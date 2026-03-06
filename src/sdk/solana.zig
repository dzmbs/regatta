const std = @import("std");
const lib = @import("lib");
const Signer = lib.crypto.signer.Signer;
const base58 = lib.crypto.base58;
const Edwards25519 = std.crypto.ecc.Edwards25519;

const PROGRAM_ID = "PCFA5iYgmqK6MqPhWNKg7Yv7auX7VZ4Cx7T1eJyrAMH";
const CENTRAL_STATE = "9Gdmhq4Gv1LnNMp7aiS1HSVd7pNnXNMsbuXALCQRmGjY";
const PACIFICA_VAULT = "72R843XwZxqWhsJceARQQTTbYtWy6Zw9et2YV4FpRHTa";
const USDC_MINT = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v";
const TOKEN_PROGRAM_ID = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA";
const ASSOCIATED_TOKEN_PROGRAM_ID = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL";
const SYS_PROGRAM_ID = "11111111111111111111111111111111";
const COMPUTE_BUDGET_PROGRAM_ID = "ComputeBudget111111111111111111111111111111";
const PDA_MARKER = "ProgramDerivedAddress";
const DEFAULT_COMPUTE_UNIT_LIMIT: u32 = 200_000;
const DEFAULT_COMPUTE_UNIT_PRICE: u64 = 375_000;

pub const MIN_DEPOSIT_USDC_UNITS: u64 = 10_000_000;

const CompileMode = enum {
    // Deterministic grouped ordering; matches the current Solana Rust SDK.
    sorted,
    // First-seen grouped ordering; matches the current solana-web3.js compiler.
    insertion,
};

const AccountMeta = struct {
    pubkey: [32]u8,
    is_signer: bool,
    is_writable: bool,
};

const InstructionSpec = struct {
    program_id: [32]u8,
    accounts: []const AccountMeta,
    data: []const u8,
};

const CompiledKeyMeta = struct {
    pubkey: [32]u8,
    is_signer: bool = false,
    is_writable: bool = false,
    is_invoked: bool = false,
    first_seen: usize = 0,
};

pub const DepositResult = struct {
    signature: []u8,
    confirmation_status: ?[]u8,

    simulation_units_consumed: ?u64 = null,

    pub fn deinit(self: *DepositResult, allocator: std.mem.Allocator) void {
        allocator.free(self.signature);
        if (self.confirmation_status) |s| allocator.free(s);
    }
};

pub const DepositPreflight = struct {
    address_b58: []u8,
    ata_b58: []u8,
    sol_lamports: u64,
    usdc_units: u64,

    pub fn deinit(self: *DepositPreflight, allocator: std.mem.Allocator) void {
        allocator.free(self.address_b58);
        allocator.free(self.ata_b58);
    }
};

pub const DepositDebug = struct {
    ata_b58: []u8,
    event_authority_b58: []u8,
    tx_base64: []u8,

    pub fn deinit(self: *DepositDebug, allocator: std.mem.Allocator) void {
        allocator.free(self.ata_b58);
        allocator.free(self.event_authority_b58);
        allocator.free(self.tx_base64);
    }
};

pub fn buildDepositDebug(
    allocator: std.mem.Allocator,
    signer: *const Signer,
    blockhash_b58: []const u8,
    amount_str: []const u8,
) !DepositDebug {
    return buildDepositDebugWithMode(allocator, signer, blockhash_b58, amount_str, DEFAULT_COMPUTE_UNIT_LIMIT, DEFAULT_COMPUTE_UNIT_PRICE, .sorted);
}

fn buildDepositDebugWithCompute(
    allocator: std.mem.Allocator,
    signer: *const Signer,
    blockhash_b58: []const u8,
    amount_str: []const u8,
    compute_unit_limit: u32,
    compute_unit_price: u64,
) !DepositDebug {
    return buildDepositDebugWithMode(allocator, signer, blockhash_b58, amount_str, compute_unit_limit, compute_unit_price, .sorted);
}

fn buildDepositDebugWithMode(
    allocator: std.mem.Allocator,
    signer: *const Signer,
    blockhash_b58: []const u8,
    amount_str: []const u8,
    compute_unit_limit: u32,
    compute_unit_price: u64,
    mode: CompileMode,
) !DepositDebug {
    const amount = try parseUsdcAmount(amount_str);
    const signer_pub = signer.pubkeyBytes();
    const user_token_account = try deriveAssociatedTokenAddress(signer_pub, try decodePubkey(TOKEN_PROGRAM_ID), try decodePubkey(USDC_MINT), try decodePubkey(ASSOCIATED_TOKEN_PROGRAM_ID));
    const event_authority = try findProgramAddress(&.{"__event_authority"}, try decodePubkey(PROGRAM_ID));
    const tx_b64 = try buildSignedDepositTransactionWithMode(allocator, signer, user_token_account, event_authority, blockhash_b58, amount, compute_unit_limit, compute_unit_price, mode);

    var ata_buf: [64]u8 = undefined;
    var event_buf: [64]u8 = undefined;
    return .{
        .ata_b58 = try allocator.dupe(u8, base58.encode(&ata_buf, &user_token_account)),
        .event_authority_b58 = try allocator.dupe(u8, base58.encode(&event_buf, &event_authority)),
        .tx_base64 = tx_b64,
    };
}

pub fn depositPreflight(
    allocator: std.mem.Allocator,
    rpc_url: []const u8,
    signer: *const Signer,
) !DepositPreflight {
    var client = RpcClient.init(allocator, rpc_url);
    defer client.deinit();

    const signer_pub = signer.pubkeyBytes();
    var addr_buf: [64]u8 = undefined;
    const addr_b58 = try allocator.dupe(u8, base58.encode(&addr_buf, &signer_pub));
    errdefer allocator.free(addr_b58);

    const ata = try deriveAssociatedTokenAddress(signer_pub, try decodePubkey(TOKEN_PROGRAM_ID), try decodePubkey(USDC_MINT), try decodePubkey(ASSOCIATED_TOKEN_PROGRAM_ID));
    var ata_buf: [64]u8 = undefined;
    const ata_b58 = try allocator.dupe(u8, base58.encode(&ata_buf, &ata));
    errdefer allocator.free(ata_b58);

    const sol_lamports = client.getSolBalance(addr_b58) catch |e| switch (e) {
        error.ReadFailed => return error.SolBalanceReadFailed,
        else => return e,
    };
    const usdc_units = client.getTokenBalance(ata_b58) catch |e| switch (e) {
        error.ReadFailed => return error.UsdcBalanceReadFailed,
        error.AccountNotFound => 0,
        else => return e,
    };

    return .{
        .address_b58 = addr_b58,
        .ata_b58 = ata_b58,
        .sol_lamports = sol_lamports,
        .usdc_units = usdc_units,
    };
}

pub fn depositUsdc(
    allocator: std.mem.Allocator,
    rpc_url: []const u8,
    signer: *const Signer,
    amount_str: []const u8,
) !DepositResult {
    const amount = try parseUsdcAmount(amount_str);

    var client = RpcClient.init(allocator, rpc_url);
    defer client.deinit();

    const signer_pub = signer.pubkeyBytes();
    const user_token_account = try deriveAssociatedTokenAddress(signer_pub, try decodePubkey(TOKEN_PROGRAM_ID), try decodePubkey(USDC_MINT), try decodePubkey(ASSOCIATED_TOKEN_PROGRAM_ID));
    const event_authority = try findProgramAddress(&.{"__event_authority"}, try decodePubkey(PROGRAM_ID));

    const blockhash = client.getLatestBlockhash() catch |e| switch (e) {
        error.ReadFailed => return error.BlockhashReadFailed,
        else => return e,
    };
    defer allocator.free(blockhash);

    const tx_b64 = try buildSignedDepositTransaction(allocator, signer, user_token_account, event_authority, blockhash, amount);
    defer allocator.free(tx_b64);

    const simulation_units = client.simulateTransaction(tx_b64) catch |e| switch (e) {
        error.ReadFailed => return error.SimulateReadFailed,
        else => return e,
    };
    const tx_sig = client.sendTransaction(tx_b64) catch |e| switch (e) {
        error.ReadFailed => return error.SendReadFailed,
        else => return e,
    };
    errdefer allocator.free(tx_sig);

    const confirmation = client.waitForConfirmation(tx_sig) catch |e| switch (e) {
        error.ReadFailed => null,
        else => null,
    };

    return .{
        .signature = tx_sig,
        .confirmation_status = confirmation,
        .simulation_units_consumed = simulation_units,
    };
}

fn buildSignedDepositTransaction(
    allocator: std.mem.Allocator,
    signer: *const Signer,
    user_token_account: [32]u8,
    event_authority: [32]u8,
    blockhash_b58: []const u8,
    amount: u64,
) ![]u8 {
    return buildSignedDepositTransactionWithMode(allocator, signer, user_token_account, event_authority, blockhash_b58, amount, DEFAULT_COMPUTE_UNIT_LIMIT, DEFAULT_COMPUTE_UNIT_PRICE, .sorted);
}

fn buildSignedDepositTransactionWithCompute(
    allocator: std.mem.Allocator,
    signer: *const Signer,
    user_token_account: [32]u8,
    event_authority: [32]u8,
    blockhash_b58: []const u8,
    amount: u64,
    compute_unit_limit: u32,
    compute_unit_price: u64,
) ![]u8 {
    return buildSignedDepositTransactionWithMode(allocator, signer, user_token_account, event_authority, blockhash_b58, amount, compute_unit_limit, compute_unit_price, .sorted);
}

fn buildSignedDepositTransactionWithMode(
    allocator: std.mem.Allocator,
    signer: *const Signer,
    user_token_account: [32]u8,
    event_authority: [32]u8,
    blockhash_b58: []const u8,
    amount: u64,
    compute_unit_limit: u32,
    compute_unit_price: u64,
    mode: CompileMode,
) ![]u8 {
    const signer_pub: [32]u8 = signer.pubkeyBytes();
    const central_state = try decodePubkey(CENTRAL_STATE);
    const pacifica_vault = try decodePubkey(PACIFICA_VAULT);
    const compute_budget_program = try decodePubkey(COMPUTE_BUDGET_PROGRAM_ID);
    const token_program = try decodePubkey(TOKEN_PROGRAM_ID);
    const associated_token_program = try decodePubkey(ASSOCIATED_TOKEN_PROGRAM_ID);
    const usdc_mint = try decodePubkey(USDC_MINT);
    const sys_program = try decodePubkey(SYS_PROGRAM_ID);
    const program_id = try decodePubkey(PROGRAM_ID);
    const blockhash = try decodePubkey(blockhash_b58);

    const cu_limit_data = encodeComputeUnitLimitData(compute_unit_limit);
    const cu_price_data = encodeComputeUnitPriceData(compute_unit_price);

    var deposit_data: [16]u8 = undefined;
    const disc = anchorDiscriminator("deposit");
    @memcpy(deposit_data[0..8], &disc);
    std.mem.writeInt(u64, deposit_data[8..16], amount, .little);

    const compute_accounts = [_]AccountMeta{};
    const deposit_accounts = [_]AccountMeta{
        .{ .pubkey = signer_pub, .is_signer = true, .is_writable = true },
        .{ .pubkey = user_token_account, .is_signer = false, .is_writable = true },
        .{ .pubkey = central_state, .is_signer = false, .is_writable = true },
        .{ .pubkey = pacifica_vault, .is_signer = false, .is_writable = true },
        .{ .pubkey = token_program, .is_signer = false, .is_writable = false },
        .{ .pubkey = associated_token_program, .is_signer = false, .is_writable = false },
        .{ .pubkey = usdc_mint, .is_signer = false, .is_writable = false },
        .{ .pubkey = sys_program, .is_signer = false, .is_writable = false },
        .{ .pubkey = event_authority, .is_signer = false, .is_writable = false },
        .{ .pubkey = program_id, .is_signer = false, .is_writable = false },
    };
    const instructions = [_]InstructionSpec{
        .{ .program_id = compute_budget_program, .accounts = &compute_accounts, .data = &cu_limit_data },
        .{ .program_id = compute_budget_program, .accounts = &compute_accounts, .data = &cu_price_data },
        .{ .program_id = program_id, .accounts = &deposit_accounts, .data = &deposit_data },
    };

    const msg_bytes = try compileLegacyMessage(allocator, signer_pub, &instructions, blockhash, mode);
    defer allocator.free(msg_bytes);

    const sig = signer.sign(msg_bytes);

    var tx = std.ArrayList(u8){};
    defer tx.deinit(allocator);
    try writeShortVec(&tx, allocator, 1);
    try tx.appendSlice(allocator, &sig);
    try tx.appendSlice(allocator, msg_bytes);

    const enc = std.base64.standard.Encoder;
    const out_len = enc.calcSize(tx.items.len);
    const out = try allocator.alloc(u8, out_len);
    _ = enc.encode(out, tx.items);
    return out;
}

fn pubkeyLessThan(a: [32]u8, b: [32]u8) bool {
    return std.mem.order(u8, &a, &b) == .lt;
}

fn pubkeyEql(a: [32]u8, b: [32]u8) bool {
    return std.mem.eql(u8, &a, &b);
}

fn findCompiledKeyIndex(keys: []const CompiledKeyMeta, pubkey: [32]u8) !u8 {
    for (keys, 0..) |key, i| {
        if (pubkeyEql(key.pubkey, pubkey)) return @intCast(i);
    }
    return error.UnknownInstructionKey;
}

fn collectCompiledKeys(
    allocator: std.mem.Allocator,
    payer: [32]u8,
    instructions: []const InstructionSpec,
    mode: CompileMode,
) !std.ArrayList(CompiledKeyMeta) {
    var keys = std.ArrayList(CompiledKeyMeta){};
    errdefer keys.deinit(allocator);

    try keys.append(allocator, .{ .pubkey = payer, .is_signer = true, .is_writable = true, .first_seen = 0 });
    var next_seen: usize = 1;

    for (instructions) |ix| {
        var program_idx: ?usize = null;
        for (keys.items, 0..) |key, idx| {
            if (pubkeyEql(key.pubkey, ix.program_id)) {
                program_idx = idx;
                break;
            }
        }
        if (program_idx) |idx| {
            keys.items[idx].is_invoked = true;
        } else {
            try keys.append(allocator, .{ .pubkey = ix.program_id, .is_invoked = true, .first_seen = next_seen });
            next_seen += 1;
        }

        for (ix.accounts) |acct| {
            var found: ?usize = null;
            for (keys.items, 0..) |key, idx| {
                if (pubkeyEql(key.pubkey, acct.pubkey)) {
                    found = idx;
                    break;
                }
            }
            if (found) |idx| {
                keys.items[idx].is_signer = keys.items[idx].is_signer or acct.is_signer;
                keys.items[idx].is_writable = keys.items[idx].is_writable or acct.is_writable;
            } else {
                try keys.append(allocator, .{
                    .pubkey = acct.pubkey,
                    .is_signer = acct.is_signer,
                    .is_writable = acct.is_writable,
                    .first_seen = next_seen,
                });
                next_seen += 1;
            }
        }
    }

    if (mode == .sorted) {
        std.mem.sort(CompiledKeyMeta, keys.items[1..], {}, struct {
            fn lessThan(_: void, a: CompiledKeyMeta, b: CompiledKeyMeta) bool {
                const a_bucket: u8 = (@as(u8, if (a.is_signer) 0 else 2) + @as(u8, if (a.is_writable) 0 else 1));
                const b_bucket: u8 = (@as(u8, if (b.is_signer) 0 else 2) + @as(u8, if (b.is_writable) 0 else 1));
                if (a_bucket != b_bucket) return a_bucket < b_bucket;
                return pubkeyLessThan(a.pubkey, b.pubkey);
            }
        }.lessThan);
    }

    return keys;
}

fn compileLegacyMessage(
    allocator: std.mem.Allocator,
    payer: [32]u8,
    instructions: []const InstructionSpec,
    blockhash: [32]u8,
    mode: CompileMode,
) ![]u8 {
    var keys = try collectCompiledKeys(allocator, payer, instructions, mode);
    defer keys.deinit(allocator);

    var num_required_signatures: u8 = 0;
    var num_readonly_signed_accounts: u8 = 0;
    var num_readonly_unsigned_accounts: u8 = 0;
    for (keys.items) |key| {
        if (key.is_signer) {
            num_required_signatures += 1;
            if (!key.is_writable) num_readonly_signed_accounts += 1;
        } else if (!key.is_writable) {
            num_readonly_unsigned_accounts += 1;
        }
    }

    var message = std.ArrayList(u8){};
    errdefer message.deinit(allocator);
    try message.appendSlice(allocator, &.{ num_required_signatures, num_readonly_signed_accounts, num_readonly_unsigned_accounts });
    try writeShortVec(&message, allocator, keys.items.len);
    for (keys.items) |key| try message.appendSlice(allocator, &key.pubkey);
    try message.appendSlice(allocator, &blockhash);
    try writeShortVec(&message, allocator, instructions.len);

    for (instructions) |ix| {
        try message.append(allocator, try findCompiledKeyIndex(keys.items, ix.program_id));
        try writeShortVec(&message, allocator, ix.accounts.len);
        for (ix.accounts) |acct| {
            try message.append(allocator, try findCompiledKeyIndex(keys.items, acct.pubkey));
        }
        try writeShortVec(&message, allocator, ix.data.len);
        try message.appendSlice(allocator, ix.data);
    }

    return message.toOwnedSlice(allocator);
}

fn encodeComputeUnitLimitData(units: u32) [5]u8 {
    var data: [5]u8 = undefined;
    data[0] = 2;
    std.mem.writeInt(u32, data[1..5], units, .little);
    return data;
}

fn encodeComputeUnitPriceData(micro_lamports: u64) [9]u8 {
    var data: [9]u8 = undefined;
    data[0] = 3;
    std.mem.writeInt(u64, data[1..9], micro_lamports, .little);
    return data;
}

fn anchorDiscriminator(name: []const u8) [8]u8 {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update("global:");
    h.update(name);
    var out: [32]u8 = undefined;
    h.final(&out);
    return out[0..8].*;
}

fn writeShortVec(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, value: usize) !void {
    var n = value;
    while (true) {
        var b: u8 = @intCast(n & 0x7f);
        n >>= 7;
        if (n != 0) b |= 0x80;
        try buf.append(allocator, b);
        if (n == 0) break;
    }
}

fn decodePubkey(b58: []const u8) ![32]u8 {
    var buf: [64]u8 = undefined;
    const decoded = try base58.decode(&buf, b58);
    if (decoded.len != 32) return error.InvalidPubkey;
    return decoded[0..32].*;
}

fn deriveAssociatedTokenAddress(owner: [32]u8, token_program: [32]u8, mint: [32]u8, ata_program: [32]u8) ![32]u8 {
    return findProgramAddressRaw(&.{ &owner, &token_program, &mint }, ata_program);
}

fn findProgramAddress(seeds: []const []const u8, program_id: [32]u8) ![32]u8 {
    return findProgramAddressRaw(seeds, program_id);
}

fn findProgramAddressRaw(seeds: []const []const u8, program_id: [32]u8) ![32]u8 {
    var bump: i32 = 255;
    while (bump >= 0) : (bump -= 1) {
        const b: [1]u8 = .{@intCast(bump)};
        var h = std.crypto.hash.sha2.Sha256.init(.{});
        for (seeds) |seed| h.update(seed);
        h.update(&b);
        h.update(&program_id);
        h.update(PDA_MARKER);
        var out: [32]u8 = undefined;
        h.final(&out);
        if (!bytesAreCurvePoint(out)) return out;
    }
    return error.InvalidSeeds;
}

fn bytesAreCurvePoint(bytes: [32]u8) bool {
    _ = Edwards25519.fromBytes(bytes) catch return false;
    return true;
}

pub fn parseUsdcAmount(input: []const u8) !u64 {
    if (input.len == 0) return error.InvalidAmount;
    var parts = std.mem.splitScalar(u8, input, '.');
    const whole_s = parts.next().?;
    const frac_s = parts.next() orelse "";
    if (parts.next() != null) return error.InvalidAmount;
    if (frac_s.len > 6) return error.InvalidAmount;

    const whole = try std.fmt.parseUnsigned(u64, whole_s, 10);
    var frac: u64 = 0;
    if (frac_s.len > 0) {
        frac = try std.fmt.parseUnsigned(u64, frac_s, 10);
        var i: usize = frac_s.len;
        while (i < 6) : (i += 1) frac *= 10;
    }

    return try std.math.add(u64, try std.math.mul(u64, whole, 1_000_000), frac);
}

const RpcClient = struct {
    allocator: std.mem.Allocator,
    http: std.http.Client,
    rpc_url: []const u8,

    fn init(allocator: std.mem.Allocator, rpc_url: []const u8) RpcClient {
        return .{ .allocator = allocator, .http = .{ .allocator = allocator }, .rpc_url = rpc_url };
    }

    fn deinit(self: *RpcClient) void {
        self.http.deinit();
    }

    fn post(self: *RpcClient, body: []const u8) ![]u8 {
        const uri = std.Uri.parse(self.rpc_url) catch return error.InvalidUrl;
        var req = std.http.Client.request(&self.http, .POST, uri, .{
            .extra_headers = &.{.{ .name = "Content-Type", .value = "application/json" }},
        }) catch return error.ConnectionFailed;
        defer req.deinit();

        req.transfer_encoding = .{ .content_length = body.len };
        var body_writer = req.sendBody(&.{}) catch return error.ConnectionFailed;
        body_writer.writer.writeAll(body) catch return error.ConnectionFailed;
        body_writer.end() catch return error.ConnectionFailed;
        req.connection.?.flush() catch return error.ConnectionFailed;

        var response = req.receiveHead(&.{}) catch return error.ConnectionFailed;

        const decompress_buf: []u8 = switch (response.head.content_encoding) {
            .identity => &.{},
            .deflate, .gzip => self.allocator.alloc(u8, std.compress.flate.max_window_len) catch return error.ReadFailed,
            .zstd => self.allocator.alloc(u8, std.compress.zstd.default_window_len) catch return error.ReadFailed,
            .compress => return error.ReadFailed,
        };
        defer if (response.head.content_encoding != .identity) self.allocator.free(decompress_buf);

        var transfer_buf: [64]u8 = undefined;
        var decompress: std.http.Decompress = undefined;
        var reader = response.readerDecompressing(&transfer_buf, &decompress, decompress_buf);
        return reader.allocRemaining(self.allocator, @enumFromInt(1024 * 1024)) catch return error.ReadFailed;
    }

    fn getLatestBlockhash(self: *RpcClient) ![]u8 {
        const body = try self.post("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getLatestBlockhash\",\"params\":[{\"commitment\":\"confirmed\"}]}");
        defer self.allocator.free(body);
        return extractStringField(self.allocator, body, &.{ "result", "value", "blockhash" });
    }

    fn getSolBalance(self: *RpcClient, owner_b58: []const u8) !u64 {
        var req = std.ArrayList(u8){};
        defer req.deinit(self.allocator);
        try req.appendSlice(self.allocator, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getBalance\",\"params\":[\"");
        try req.appendSlice(self.allocator, owner_b58);
        try req.appendSlice(self.allocator, "\",{\"commitment\":\"confirmed\"}]}");
        const body = try self.post(req.items);
        defer self.allocator.free(body);
        return extractU64Field(self.allocator, body, &.{ "result", "value" });
    }

    fn getTokenBalance(self: *RpcClient, token_account_b58: []const u8) !u64 {
        var req = std.ArrayList(u8){};
        defer req.deinit(self.allocator);
        try req.appendSlice(self.allocator, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getTokenAccountBalance\",\"params\":[\"");
        try req.appendSlice(self.allocator, token_account_b58);
        try req.appendSlice(self.allocator, "\",{\"commitment\":\"confirmed\"}]}");
        const body = try self.post(req.items);
        defer self.allocator.free(body);
        return extractU64Field(self.allocator, body, &.{ "result", "value", "amount" });
    }

    fn findUsdcTokenAccount(self: *RpcClient, owner_b58: []const u8) ![]u8 {
        var req = std.ArrayList(u8){};
        defer req.deinit(self.allocator);
        try req.appendSlice(self.allocator, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getTokenAccountsByOwner\",\"params\":[\"");
        try req.appendSlice(self.allocator, owner_b58);
        try req.appendSlice(self.allocator, "\",{\"mint\":\"");
        try req.appendSlice(self.allocator, USDC_MINT);
        try req.appendSlice(self.allocator, "\"},{\"encoding\":\"jsonParsed\",\"commitment\":\"confirmed\"}]}");
        const body = try self.post(req.items);
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, body, .{}) catch return error.InvalidRpcResponse;
        defer parsed.deinit();
        const root = parsed.value.object;
        if (root.get("error")) |e| return rpcErrorFromValue(e);
        const result = root.get("result") orelse return error.InvalidRpcResponse;
        const result_obj = switch (result) { .object => |o| o, else => return error.InvalidRpcResponse };
        const value = result_obj.get("value") orelse return error.InvalidRpcResponse;
        const arr = switch (value) { .array => |a| a, else => return error.InvalidRpcResponse };
        if (arr.items.len == 0) return error.MissingTokenAccount;
        const first = switch (arr.items[0]) { .object => |o| o, else => return error.InvalidRpcResponse };
        const pubkey = first.get("pubkey") orelse return error.InvalidRpcResponse;
        return switch (pubkey) { .string => |s| try self.allocator.dupe(u8, s), else => error.InvalidRpcResponse };
    }

    fn simulateTransaction(self: *RpcClient, tx_b64: []const u8) !?u64 {
        var req = std.ArrayList(u8){};
        defer req.deinit(self.allocator);
        try req.appendSlice(self.allocator, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"simulateTransaction\",\"params\":[\"");
        try req.appendSlice(self.allocator, tx_b64);
        try req.appendSlice(self.allocator, "\",{\"encoding\":\"base64\",\"sigVerify\":false,\"commitment\":\"confirmed\"}]}");
        const body = try self.post(req.items);
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, body, .{}) catch return error.InvalidRpcResponse;
        defer parsed.deinit();
        const root = parsed.value.object;
        if (root.get("error")) |e| return rpcErrorFromValue(e);
        const result = root.get("result") orelse return error.InvalidRpcResponse;
        const result_obj = switch (result) { .object => |o| o, else => return error.InvalidRpcResponse };
        if (result_obj.get("value")) |value| {
            const value_obj = switch (value) { .object => |o| o, else => return error.InvalidRpcResponse };
            if (value_obj.get("err")) |err_val| {
                if (err_val != .null) return error.SimulationFailed;
            }
            if (value_obj.get("unitsConsumed")) |u| {
                return switch (u) {
                    .integer => |i| @intCast(i),
                    else => null,
                };
            }
        }
        return null;
    }

    fn sendTransaction(self: *RpcClient, tx_b64: []const u8) ![]u8 {
        var req = std.ArrayList(u8){};
        defer req.deinit(self.allocator);
        try req.appendSlice(self.allocator, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"sendTransaction\",\"params\":[\"");
        try req.appendSlice(self.allocator, tx_b64);
        try req.appendSlice(self.allocator, "\",{\"encoding\":\"base64\",\"skipPreflight\":false,\"preflightCommitment\":\"confirmed\"}]}");
        const body = try self.post(req.items);
        defer self.allocator.free(body);
        return extractRpcResultString(self.allocator, body);
    }

    fn waitForConfirmation(self: *RpcClient, signature: []const u8) ![]u8 {
        var attempts: usize = 0;
        while (attempts < 60) : (attempts += 1) {
            var req = std.ArrayList(u8){};
            defer req.deinit(self.allocator);
            try req.appendSlice(self.allocator, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getSignatureStatuses\",\"params\":[[\"");
            try req.appendSlice(self.allocator, signature);
            try req.appendSlice(self.allocator, "\"],{\"searchTransactionHistory\":true}]}");
            const body = try self.post(req.items);
            defer self.allocator.free(body);

            const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, body, .{}) catch return error.InvalidRpcResponse;
            defer parsed.deinit();
            const root = parsed.value.object;
            if (root.get("error")) |e| return rpcErrorFromValue(e);
            const result = root.get("result") orelse return error.InvalidRpcResponse;
            const result_obj = switch (result) { .object => |o| o, else => return error.InvalidRpcResponse };
            const value = result_obj.get("value") orelse return error.InvalidRpcResponse;
            const arr = switch (value) { .array => |a| a, else => return error.InvalidRpcResponse };
            if (arr.items.len == 0 or arr.items[0] == .null) {
                std.Thread.sleep(500 * std.time.ns_per_ms);
                continue;
            }
            const status_obj = switch (arr.items[0]) { .object => |o| o, else => return error.InvalidRpcResponse };
            if (status_obj.get("err")) |err_val| {
                if (err_val != .null) return error.TransactionFailed;
            }
            if (status_obj.get("confirmationStatus")) |cs| {
                switch (cs) {
                    .string => |s| return try self.allocator.dupe(u8, s),
                    else => {},
                }
            }
            std.Thread.sleep(500 * std.time.ns_per_ms);
        }
        return error.ConfirmationTimeout;
    }
};

fn extractRpcResultString(allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return error.InvalidRpcResponse;
    defer parsed.deinit();
    const root = parsed.value.object;
    if (root.get("error")) |e| return rpcErrorFromValue(e);
    const result = root.get("result") orelse return error.InvalidRpcResponse;
    return switch (result) {
        .string => |s| try allocator.dupe(u8, s),
        else => error.InvalidRpcResponse,
    };
}

fn extractStringField(allocator: std.mem.Allocator, body: []const u8, path: []const []const u8) ![]u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return error.InvalidRpcResponse;
    defer parsed.deinit();
    var cur = parsed.value;
    for (path) |part| {
        const obj = switch (cur) { .object => |o| o, else => return error.InvalidRpcResponse };
        if (obj.get("error")) |e| return rpcErrorFromValue(e);
        cur = obj.get(part) orelse return error.InvalidRpcResponse;
    }
    return switch (cur) {
        .string => |s| try allocator.dupe(u8, s),
        else => error.InvalidRpcResponse,
    };
}

fn extractU64Field(allocator: std.mem.Allocator, body: []const u8, path: []const []const u8) !u64 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return error.InvalidRpcResponse;
    defer parsed.deinit();
    var cur = parsed.value;
    for (path) |part| {
        const obj = switch (cur) { .object => |o| o, else => return error.InvalidRpcResponse };
        if (obj.get("error")) |e| {
            if (isAccountNotFoundError(e)) return error.AccountNotFound;
            return rpcErrorFromValue(e);
        }
        cur = obj.get(part) orelse return error.InvalidRpcResponse;
    }
    return switch (cur) {
        .integer => |i| @intCast(i),
        .string => |s| std.fmt.parseUnsigned(u64, s, 10) catch error.InvalidRpcResponse,
        else => error.InvalidRpcResponse,
    };
}

fn isAccountNotFoundError(value: std.json.Value) bool {
    switch (value) {
        .object => |obj| {
            if (obj.get("message")) |m| {
                return switch (m) {
                    .string => |s| std.mem.indexOf(u8, s, "could not find account") != null,
                    else => false,
                };
            }
        },
        else => {},
    }
    return false;
}

fn rpcErrorFromValue(value: std.json.Value) anyerror {
    switch (value) {
        .object => |obj| {
            if (obj.get("message")) |m| {
                if (m == .string) return error.RpcRequestFailed;
            }
        },
        else => {},
    }
    return error.RpcRequestFailed;
}

test "parseUsdcAmount whole and fractional" {
    try std.testing.expectEqual(@as(u64, 100_000000), try parseUsdcAmount("100"));
    try std.testing.expectEqual(@as(u64, 1_500000), try parseUsdcAmount("1.5"));
    try std.testing.expectEqual(@as(u64, 1), try parseUsdcAmount("0.000001"));
}

test "anchorDiscriminator deposit is stable width" {
    const disc = anchorDiscriminator("deposit");
    try std.testing.expectEqual(@as(usize, 8), disc.len);
}

test "deriveAssociatedTokenAddress matches observed deposit tx" {
    const owner = try decodePubkey("DsxuzibwdScs9XDb2hPWVKrSUaRwFYwkkXJzbYonWW8q");
    const ata = try deriveAssociatedTokenAddress(owner, try decodePubkey(TOKEN_PROGRAM_ID), try decodePubkey(USDC_MINT), try decodePubkey(ASSOCIATED_TOKEN_PROGRAM_ID));
    var buf: [64]u8 = undefined;
    const ata_b58 = base58.encode(&buf, &ata);
    try std.testing.expectEqualStrings("BYwTwfHykAQ26k2pSXbMSV7awK8tH59foGvxDtEYTZuQ", ata_b58);
}

test "event authority PDA matches observed deposit tx" {
    const event_authority = try findProgramAddress(&.{"__event_authority"}, try decodePubkey(PROGRAM_ID));
    var buf: [64]u8 = undefined;
    const event_b58 = base58.encode(&buf, &event_authority);
    try std.testing.expectEqualStrings("2cPFdP7ADcdQE2rG9BqASYAVosZv3PX5yCyTdYCfGq8V", event_b58);
}

test "compute budget encoding matches Solana Rust/web3.js vectors" {
    try std.testing.expectEqualSlices(u8, &.{ 2, 1, 1, 0, 0 }, &encodeComputeUnitLimitData(257));
    try std.testing.expectEqualSlices(u8, &.{ 3, 255, 255, 255, 255, 255, 255, 255, 255 }, &encodeComputeUnitPriceData(std.math.maxInt(u64)));
    try std.testing.expectEqualSlices(u8, &.{ 2, 0x50, 0xC3, 0x00, 0x00 }, &encodeComputeUnitLimitData(50_000));
    try std.testing.expectEqualSlices(u8, &.{ 3, 0xA0, 0x86, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00 }, &encodeComputeUnitPriceData(100_000));
}

fn signerFromSeedHex(seed_hex: []const u8) !Signer {
    var seed: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&seed, seed_hex);
    return try Signer.fromSeed(seed);
}

test "buildDepositDebug matches generated sorted and insertion vector matrix" {
    const Vector = struct {
        id: []const u8,
        seed_hex: []const u8,
        blockhash: []const u8,
        amount: []const u8,
        compute_unit_limit: u32,
        compute_unit_price: u64,
        ata: []const u8,
        event_authority: []const u8,
        rust_tx_base64: []const u8,
        web3_tx_base64: []const u8,
    };

    // Maintainer note: this checked-in fixture was generated once from local
    // reference implementations (Solana Rust SDK + solana-web3.js) to lock in
    // exact parity for both ordering policies without keeping those toolchains
    // or generator scripts in the normal Zig project surface.
    const fixture = @embedFile("../../tests/fixtures/solana_deposit_vectors.json");
    const parsed = try std.json.parseFromSlice([]const Vector, std.testing.allocator, fixture, .{});
    defer parsed.deinit();

    for (parsed.value) |vector| {
        var signer = try signerFromSeedHex(vector.seed_hex);

        var rust_debug = try buildDepositDebugWithMode(std.testing.allocator, &signer, vector.blockhash, vector.amount, vector.compute_unit_limit, vector.compute_unit_price, .sorted);
        defer rust_debug.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings(vector.ata, rust_debug.ata_b58);
        try std.testing.expectEqualStrings(vector.event_authority, rust_debug.event_authority_b58);
        try std.testing.expectEqualStrings(vector.sorted_tx_base64, rust_debug.tx_base64);

        var web3_debug = try buildDepositDebugWithMode(std.testing.allocator, &signer, vector.blockhash, vector.amount, vector.compute_unit_limit, vector.compute_unit_price, .insertion);
        defer web3_debug.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings(vector.ata, web3_debug.ata_b58);
        try std.testing.expectEqualStrings(vector.event_authority, web3_debug.event_authority_b58);
        try std.testing.expectEqualStrings(vector.insertion_tx_base64, web3_debug.tx_base64);
    }
}
