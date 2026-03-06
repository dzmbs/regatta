const std = @import("std");
const lib = @import("lib");
const Signer = lib.crypto.signer.Signer;

const aes = std.crypto.core.aes;
const Aes128Ctx = aes.AesEncryptCtx(aes.Aes128);
const ctr = std.crypto.core.modes.ctr;

pub const KeystoreError = error{
    BadPassword,
    InvalidFormat,
    NotFound,
    AlreadyExists,
    IoError,
    PublicKeyMismatch,
    InvalidKeyLength,
} || std.crypto.pwhash.KdfError || std.mem.Allocator.Error;

pub const Entry = struct {
    name: [64]u8 = .{0} ** 64,
    name_len: u8 = 0,
    address: [44]u8 = .{0} ** 44,
    address_len: u8 = 0,
    is_default: bool = false,

    pub fn getName(self: *const Entry) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn getAddress(self: *const Entry) []const u8 {
        return self.address[0..self.address_len];
    }
};

pub fn encrypt(allocator: std.mem.Allocator, secret: [64]u8, password: []const u8) KeystoreError![]u8 {
    var salt: [32]u8 = undefined;
    var iv: [16]u8 = undefined;
    std.crypto.random.bytes(&salt);
    std.crypto.random.bytes(&iv);

    var derived: [32]u8 = undefined;
    const params = std.crypto.pwhash.scrypt.Params{ .ln = 13, .r = 8, .p = 1 };
    try std.crypto.pwhash.scrypt.kdf(allocator, &derived, password, &salt, params);

    const enc_key = derived[0..16];
    var ciphertext: [64]u8 = undefined;
    const aes_ctx = Aes128Ctx.init(enc_key.*);
    ctr(Aes128Ctx, aes_ctx, &ciphertext, &secret, iv, .big);

    var mac_input: [80]u8 = undefined;
    @memcpy(mac_input[0..16], derived[16..32]);
    @memcpy(mac_input[16..80], &ciphertext);
    var mac: [32]u8 = undefined;
    std.crypto.hash.sha3.Keccak256.hash(mac_input[0..80], &mac, .{});

    const signer = try Signer.fromBytes(secret);
    var addr_buf: [44]u8 = undefined;
    const address = signer.pubkeyBase58(&addr_buf);

    var salt_hex: [64]u8 = undefined;
    var iv_hex: [32]u8 = undefined;
    var ct_hex: [128]u8 = undefined;
    var mac_hex: [64]u8 = undefined;
    hexEncode(&salt, &salt_hex);
    hexEncode(iv[0..16], &iv_hex);
    hexEncode(&ciphertext, &ct_hex);
    hexEncode(&mac, &mac_hex);

    return std.fmt.allocPrint(allocator,
        "{{\"version\":1,\"kind\":\"solana-keypair\",\"address\":\"{s}\",\"crypto\":{{\"cipher\":\"aes-128-ctr\",\"cipherparams\":{{\"iv\":\"{s}\"}},\"ciphertext\":\"{s}\",\"kdf\":\"scrypt\",\"kdfparams\":{{\"dklen\":32,\"n\":8192,\"r\":8,\"p\":1,\"salt\":\"{s}\"}},\"mac\":\"{s}\"}}}}",
        .{ address, iv_hex, ct_hex, salt_hex, mac_hex },
    ) catch return error.OutOfMemory;
}

pub fn decrypt(allocator: std.mem.Allocator, json_data: []const u8, password: []const u8) KeystoreError![64]u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_data, .{}) catch return error.InvalidFormat;
    defer parsed.deinit();
    const root = parsed.value;
    const crypto = (if (root == .object) root.object.get("crypto") else null) orelse return error.InvalidFormat;

    const ct_hex = getString(crypto, "ciphertext") orelse return error.InvalidFormat;
    const mac_hex = getString(crypto, "mac") orelse return error.InvalidFormat;
    const cp = (if (crypto == .object) crypto.object.get("cipherparams") else null) orelse return error.InvalidFormat;
    const iv_hex = getString(cp, "iv") orelse return error.InvalidFormat;
    const kp = (if (crypto == .object) crypto.object.get("kdfparams") else null) orelse return error.InvalidFormat;
    const salt_hex = getString(kp, "salt") orelse return error.InvalidFormat;
    const n_val = getInt(kp, "n") orelse return error.InvalidFormat;
    const r_val = getInt(kp, "r") orelse return error.InvalidFormat;
    const p_val = getInt(kp, "p") orelse return error.InvalidFormat;

    var salt: [32]u8 = undefined;
    var iv: [16]u8 = undefined;
    var ciphertext: [64]u8 = undefined;
    var expected_mac: [32]u8 = undefined;
    try hexDecode(salt_hex, &salt);
    try hexDecode(iv_hex, &iv);
    try hexDecode(ct_hex, &ciphertext);
    try hexDecode(mac_hex, &expected_mac);

    const ln: std.math.Log2Int(u64) = std.math.log2_int(u64, @as(u64, @intCast(n_val)));
    var derived: [32]u8 = undefined;
    const params = std.crypto.pwhash.scrypt.Params{ .ln = ln, .r = @intCast(r_val), .p = @intCast(p_val) };
    try std.crypto.pwhash.scrypt.kdf(allocator, &derived, password, &salt, params);

    var mac_input: [80]u8 = undefined;
    @memcpy(mac_input[0..16], derived[16..32]);
    @memcpy(mac_input[16..80], &ciphertext);
    var actual_mac: [32]u8 = undefined;
    std.crypto.hash.sha3.Keccak256.hash(mac_input[0..80], &actual_mac, .{});
    if (!std.mem.eql(u8, &actual_mac, &expected_mac)) return error.BadPassword;

    const enc_key = derived[0..16];
    var plaintext: [64]u8 = undefined;
    const aes_ctx = Aes128Ctx.init(enc_key.*);
    ctr(Aes128Ctx, aes_ctx, &plaintext, &ciphertext, iv, .big);
    _ = try Signer.fromBytes(plaintext);
    return plaintext;
}

pub fn save(name: []const u8, data: []const u8) !void {
    _ = try keysDir();
    const home = std.posix.getenv("HOME") orelse return error.IoError;
    var path_buf: [576]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/.regatta/keys/{s}.json", .{ home, name }) catch return error.IoError;
    std.fs.cwd().access(path, .{}) catch {
        const file = std.fs.cwd().createFile(path, .{}) catch return error.IoError;
        defer file.close();
        file.writeAll(data) catch return error.IoError;
        _ = std.c.fchmod(file.handle, 0o600);
        return;
    };
    return error.AlreadyExists;
}

pub fn load(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    const home = std.posix.getenv("HOME") orelse return error.IoError;
    var path_buf: [576]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/.regatta/keys/{s}.json", .{ home, name }) catch return error.IoError;
    return std.fs.cwd().readFileAlloc(allocator, path, 16 * 1024) catch return error.NotFound;
}

pub fn list(allocator: std.mem.Allocator) ![]Entry {
    const home = std.posix.getenv("HOME") orelse return error.IoError;
    var path_buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/.regatta/keys", .{home}) catch return error.IoError;

    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return allocator.alloc(Entry, 0);
    defer dir.close();

    var entries = std.array_list.AlignedManaged(Entry, null).init(allocator);
    defer entries.deinit();
    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind != .file) continue;
        const fname = entry.name;
        if (!std.mem.endsWith(u8, fname, ".json")) continue;
        const name = fname[0 .. fname.len - 5];
        if (name.len == 0 or name.len > 63) continue;

        var e: Entry = .{};
        @memcpy(e.name[0..name.len], name);
        e.name_len = @intCast(name.len);

        const data = dir.readFileAlloc(allocator, fname, 16 * 1024) catch continue;
        defer allocator.free(data);
        const p = std.json.parseFromSlice(std.json.Value, allocator, data, .{}) catch continue;
        defer p.deinit();
        if (getString(p.value, "address")) |a| {
            const n = @min(a.len, e.address.len);
            @memcpy(e.address[0..n], a[0..n]);
            e.address_len = @intCast(n);
        }
        entries.append(e) catch continue;
    }

    var default_buf: [64]u8 = undefined;
    const default_name = getDefaultNameBuf(&default_buf);
    for (entries.items) |*e| {
        if (default_name) |dn| {
            if (std.mem.eql(u8, e.getName(), dn)) e.is_default = true;
        }
    }
    return entries.toOwnedSlice() catch return allocator.alloc(Entry, 0);
}

pub fn remove(name: []const u8) !void {
    const home = std.posix.getenv("HOME") orelse return error.IoError;
    var path_buf: [576]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/.regatta/keys/{s}.json", .{ home, name }) catch return error.IoError;
    std.fs.cwd().deleteFile(path) catch return error.NotFound;
}

pub fn setDefault(name: []const u8) !void {
    const home = std.posix.getenv("HOME") orelse return error.IoError;
    var path_buf: [576]u8 = undefined;
    std.fs.cwd().makePath(std.fmt.bufPrint(&path_buf, "{s}/.regatta", .{home}) catch return error.IoError) catch {};
    const path = std.fmt.bufPrint(&path_buf, "{s}/.regatta/default", .{home}) catch return error.IoError;
    const file = std.fs.cwd().createFile(path, .{}) catch return error.IoError;
    defer file.close();
    file.writeAll(name) catch return error.IoError;
}

pub fn getDefaultNameBuf(buf: []u8) ?[]const u8 {
    const home = std.posix.getenv("HOME") orelse return null;
    var path_buf: [576]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/.regatta/default", .{home}) catch return null;
    const file = std.fs.cwd().openFile(path, .{}) catch return null;
    defer file.close();
    const n = file.readAll(buf) catch return null;
    const trimmed = std.mem.trim(u8, buf[0..n], " \t\r\n");
    if (trimmed.len == 0) return null;
    return trimmed;
}

fn keysDir() ![512]u8 {
    const home = std.posix.getenv("HOME") orelse return error.IoError;
    var buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "{s}/.regatta/keys", .{home}) catch return error.IoError;
    std.fs.cwd().makePath(path) catch {};
    return buf;
}

fn getString(val: std.json.Value, key: []const u8) ?[]const u8 {
    if (val != .object) return null;
    const v = val.object.get(key) orelse return null;
    if (v != .string) return null;
    return v.string;
}

fn getInt(val: std.json.Value, key: []const u8) ?u64 {
    if (val != .object) return null;
    const v = val.object.get(key) orelse return null;
    return switch (v) {
        .integer => @intCast(v.integer),
        .float => @intFromFloat(v.float),
        else => null,
    };
}

fn hexEncode(src: []const u8, dst: []u8) void {
    const chars = "0123456789abcdef";
    for (src, 0..) |b, i| {
        dst[i * 2] = chars[b >> 4];
        dst[i * 2 + 1] = chars[b & 0xf];
    }
}

fn hexDecode(src: []const u8, dst: []u8) !void {
    if (src.len != dst.len * 2) return error.InvalidFormat;
    for (dst, 0..) |*b, i| {
        b.* = (try hexVal(src[i * 2])) << 4 | try hexVal(src[i * 2 + 1]);
    }
}

fn hexVal(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => error.InvalidFormat,
    };
}

test "keystore encrypt/decrypt roundtrip" {
    const signer = Signer.generate();
    const secret = signer.secretBytes64();
    const json = try encrypt(std.testing.allocator, secret, "pass123");
    defer std.testing.allocator.free(json);
    const out = try decrypt(std.testing.allocator, json, "pass123");
    try std.testing.expectEqualSlices(u8, &secret, &out);
}
