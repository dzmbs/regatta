// ╔═══════════════════════════════════════════════════════════════╗
// ║  Config loader — flags > env > .env > defaults                ║
// ╚═══════════════════════════════════════════════════════════════╝

const std = @import("std");
const lib = @import("lib");
const sdk = @import("sdk");
const args_mod = @import("args.zig");
const keystore = @import("keystore.zig");
const Signer = lib.crypto.signer.Signer;
const Chain = sdk.config.Chain;

pub const Config = struct {
    key_b58: ?[]const u8 = null,
    key_name: ?[]const u8 = null,
    password: ?[]const u8 = null,
    address: ?[]const u8 = null,
    chain: Chain = .mainnet,
    agent_wallet: ?[]const u8 = null,
    solana_rpc_url: ?[]const u8 = null,
    env_buf: ?[]u8 = null,
    key_alloc: ?[]u8 = null,
    allocator: std.mem.Allocator,
    derived_addr: [44]u8 = undefined,
    derived_agent: [44]u8 = undefined,

    pub fn deinit(self: *Config) void {
        if (self.key_alloc) |buf| {
            @memset(buf, 0);
            self.allocator.free(buf);
        }
        if (self.env_buf) |buf| self.allocator.free(buf);
    }

    pub fn getSigner(self: *const Config) !Signer {
        const key = self.key_b58 orelse return error.MissingKey;
        return Signer.fromBase58(key);
    }

    pub fn getAddress(self: *Config) ?[]const u8 {
        if (self.address) |a| return a;
        if (self.agent_wallet != null) return null;
        if (self.key_b58) |key| {
            const signer = Signer.fromBase58(key) catch return null;
            var buf: [44]u8 = undefined;
            const addr = signer.pubkeyBase58(&buf);
            @memcpy(self.derived_addr[0..addr.len], addr);
            self.address = self.derived_addr[0..addr.len];
            return self.address;
        }
        return null;
    }

    pub fn getAgentPubkey(self: *Config) ?[]const u8 {
        if (self.agent_wallet) |aw| return aw;
        if (self.key_b58) |key| {
            const signer = Signer.fromBase58(key) catch return null;
            var buf: [44]u8 = undefined;
            const pubkey = signer.pubkeyBase58(&buf);
            @memcpy(self.derived_agent[0..pubkey.len], pubkey);
            return self.derived_agent[0..pubkey.len];
        }
        return null;
    }

    pub fn getSigningContext(self: *Config) !struct { account_addr: ?[]const u8, agent_pubkey: ?[]const u8 } {
        if (self.agent_wallet != null) {
            const addr = self.getAddress() orelse return error.MissingAddress;
            const agent_pub = self.getAgentPubkey() orelse return error.MissingKey;
            return .{ .account_addr = addr, .agent_pubkey = agent_pub };
        }
        return .{ .account_addr = null, .agent_pubkey = null };
    }

    pub fn requireAddress(self: *Config) ![]const u8 {
        return self.getAddress() orelse return error.MissingAddress;
    }

    pub fn getSolanaRpcUrl(self: *const Config) []const u8 {
        return self.solana_rpc_url orelse "https://api.mainnet-beta.solana.com";
    }
};

pub fn load(allocator: std.mem.Allocator, flags: args_mod.GlobalFlags) Config {
    var config = Config{ .allocator = allocator };

    // Load .env or ~/.regatta/config (lowest priority)
    loadEnvFile(allocator, &config);

    // Environment variables
    if (getEnv("PACIFICA_KEY")) |v| config.key_b58 = v;
    if (getEnv("PACIFICA_KEY_NAME")) |v| config.key_name = v;
    if (getEnv("PACIFICA_PASSWORD")) |v| config.password = v;
    if (getEnv("PACIFICA_ADDRESS")) |v| config.address = v;
    if (getEnv("PACIFICA_CHAIN")) |v| {
        if (std.mem.eql(u8, v, "testnet")) config.chain = .testnet;
    }
    if (getEnv("PACIFICA_AGENT_WALLET")) |v| config.agent_wallet = v;
    if (getEnv("SOLANA_RPC_URL")) |v| config.solana_rpc_url = v;

    // CLI flags override everything
    if (flags.key) |k| config.key_b58 = k;
    if (flags.key_name) |kn| config.key_name = kn;
    if (flags.address) |a| config.address = a;
    if (std.mem.eql(u8, flags.chain, "testnet")) config.chain = .testnet;
    if (flags.agent_wallet) |aw| config.agent_wallet = aw;

    if (config.key_b58 == null) {
        const key_name = config.key_name orelse blk: {
            var dbuf: [64]u8 = undefined;
            break :blk keystore.getDefaultNameBuf(&dbuf);
        };
        if (key_name) |name| {
            const password = config.password;
            if (password) |pw| {
                const data = keystore.load(allocator, name) catch null;
                if (data) |ks_data| {
                    const secret = keystore.decrypt(allocator, ks_data, pw) catch null;
                    allocator.free(ks_data);
                    if (secret) |sk| {
                        const signer = Signer.fromBytes(sk) catch null;
                        if (signer) |s| {
                            const out = allocator.alloc(u8, 128) catch null;
                            if (out) |buf| {
                                const b58 = s.secretBase58(buf);
                                const dup = allocator.dupe(u8, b58) catch null;
                                @memset(buf, 0);
                                allocator.free(buf);
                                if (dup) |d| {
                                    config.key_b58 = d;
                                    config.key_alloc = d;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    return config;
}

fn getEnv(name: []const u8) ?[]const u8 {
    const v = std.posix.getenv(name) orelse return null;
    return if (v.len == 0) null else v;
}

fn loadEnvFile(allocator: std.mem.Allocator, config: *Config) void {
    const buf = std.fs.cwd().readFileAlloc(allocator, ".env", 64 * 1024) catch {
        const home = std.posix.getenv("HOME") orelse return;
        var path_buf: [512]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/.regatta/config", .{home}) catch return;
        const buf2 = std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024) catch return;
        config.env_buf = buf2;
        parseEnvBuf(buf2, config);
        return;
    };
    config.env_buf = buf;
    parseEnvBuf(buf, config);
}

fn parseEnvBuf(buf: []const u8, config: *Config) void {
    var it = std.mem.splitScalar(u8, buf, '\n');
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (parseEnvLine(trimmed, "PACIFICA_KEY=")) |v| {
            if (config.key_b58 == null) config.key_b58 = v;
        } else if (parseEnvLine(trimmed, "PACIFICA_KEY_NAME=")) |v| {
            if (config.key_name == null) config.key_name = v;
        } else if (parseEnvLine(trimmed, "PACIFICA_PASSWORD=")) |v| {
            if (config.password == null) config.password = v;
        } else if (parseEnvLine(trimmed, "PACIFICA_ADDRESS=")) |v| {
            if (config.address == null) config.address = v;
        } else if (parseEnvLine(trimmed, "PACIFICA_CHAIN=")) |v| {
            if (std.mem.eql(u8, v, "testnet")) config.chain = .testnet;
        } else if (parseEnvLine(trimmed, "PACIFICA_AGENT_WALLET=")) |v| {
            if (config.agent_wallet == null) config.agent_wallet = v;
        } else if (parseEnvLine(trimmed, "PACIFICA_KEY_NAME=")) |v| {
            _ = v;
        } else if (parseEnvLine(trimmed, "PACIFICA_PASSWORD=")) |v| {
            _ = v;
        } else if (parseEnvLine(trimmed, "SOLANA_RPC_URL=")) |v| {
            if (config.solana_rpc_url == null) config.solana_rpc_url = v;
        }
    }
}

fn parseEnvLine(line: []const u8, prefix: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    var value = line[prefix.len..];
    value = std.mem.trim(u8, value, " \t\"'");
    if (value.len == 0) return null;
    return value;
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  Tests                                                        ║
// ╚═══════════════════════════════════════════════════════════════╝

const TEST_KEY = "1GMkH3brNXiNNs1tiFZHu4yZSRrzJwxi5wB9bHFtMikjwpAW9DMZzU2Pqakc5it8X3N5vPmqdN7KF4CCUpmKhq";
const TEST_PUBKEY = "FAe4sisG95oZ42w7buUn5qEE4TAnfTTFPiguZUHmhiF";

test "getAddress: agent mode must not derive from key (requires explicit --address)" {
    // This was a real bug — without this guard, agent mode would sign as the agent key's pubkey
    // instead of the main account, sending funds to the wrong address
    var c = Config{ .allocator = std.testing.allocator, .key_b58 = TEST_KEY, .agent_wallet = "AgentPub" };
    try std.testing.expect(c.getAddress() == null);
}

test "getAddress: explicit address overrides key derivation" {
    var c = Config{ .allocator = std.testing.allocator, .key_b58 = TEST_KEY, .address = "Explicit" };
    try std.testing.expectEqualStrings("Explicit", c.getAddress().?);
}

test "getSigningContext: agent mode requires --address" {
    // Agent wallet set but no address → must error, not silently derive wrong account
    var c = Config{ .allocator = std.testing.allocator, .key_b58 = TEST_KEY, .agent_wallet = "AgentPub" };
    try std.testing.expectError(error.MissingAddress, c.getSigningContext());
}

test "getSigningContext: agent mode resolves all three fields" {
    var c = Config{ .allocator = std.testing.allocator, .key_b58 = TEST_KEY, .agent_wallet = "AgentPub", .address = "MainAcct" };
    const ctx = try c.getSigningContext();
    try std.testing.expectEqualStrings("MainAcct", ctx.account_addr.?);
    try std.testing.expectEqualStrings("AgentPub", ctx.agent_pubkey.?);
}

test "getSigningContext: direct mode has no agent fields" {
    var c = Config{ .allocator = std.testing.allocator, .key_b58 = TEST_KEY };
    const ctx = try c.getSigningContext();
    try std.testing.expect(ctx.account_addr == null);
    try std.testing.expect(ctx.agent_pubkey == null);
}

test "parseEnvBuf: quote stripping (common .env foot-gun)" {
    // Users copy-paste keys with quotes from examples — must strip or signing breaks
    var c = Config{ .allocator = std.testing.allocator };
    parseEnvBuf("PACIFICA_KEY=\"quotedkey\"\nPACIFICA_ADDRESS='single'\n", &c);
    try std.testing.expectEqualStrings("quotedkey", c.key_b58.?);
    try std.testing.expectEqualStrings("single", c.address.?);
}

test "parseEnvBuf: flags > env > .env precedence" {
    // CLI flags already set must not be overwritten by .env file
    var c = Config{ .allocator = std.testing.allocator, .key_b58 = "from_flag" };
    parseEnvBuf("PACIFICA_KEY=from_file\n", &c);
    try std.testing.expectEqualStrings("from_flag", c.key_b58.?);
}
