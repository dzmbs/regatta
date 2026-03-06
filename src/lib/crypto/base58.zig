// ╔═══════════════════════════════════════════════════════════════╗
// ║  Base58 — Bitcoin/Solana alphabet                             ║
// ╚═══════════════════════════════════════════════════════════════╝
//
// Encode/decode with alphabet: 123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz
// Stack buffers only, no allocator needed.

const alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

/// Reverse lookup: ASCII byte → alphabet index (255 = invalid)
const decode_table: [256]u8 = blk: {
    var table: [256]u8 = .{255} ** 256;
    for (alphabet, 0..) |c, i| {
        table[c] = @intCast(i);
    }
    break :blk table;
};

/// Encode bytes to base58 into caller-provided buffer.
/// Returns the slice of `dest` that was written.
pub fn encode(dest: []u8, source: []const u8) []const u8 {
    if (source.len == 0) return dest[0..0];

    // Count leading zeros
    var leading_zeros: usize = 0;
    for (source) |b| {
        if (b != 0) break;
        leading_zeros += 1;
    }

    // Work buffer: big-endian base58 digits (most significant first after reversal)
    // Max expansion: ceil(source.len * 138 / 100) + 1
    var buf: [512]u8 = undefined;
    var buf_len: usize = 0;

    // For each input byte, multiply the existing big number by 256 and add the byte
    for (source) |byte| {
        var carry: u32 = byte;
        var i: usize = 0;
        while (i < buf_len) : (i += 1) {
            carry += @as(u32, buf[i]) * 256;
            buf[i] = @intCast(carry % 58);
            carry /= 58;
        }
        while (carry > 0) {
            buf[buf_len] = @intCast(carry % 58);
            carry /= 58;
            buf_len += 1;
        }
    }

    // Leading zeros → '1' characters
    var pos: usize = 0;
    for (0..leading_zeros) |_| {
        dest[pos] = '1';
        pos += 1;
    }

    // Reverse the digits and map to alphabet
    var i: usize = buf_len;
    while (i > 0) {
        i -= 1;
        dest[pos] = alphabet[buf[i]];
        pos += 1;
    }

    return dest[0..pos];
}

/// Decode base58 string to bytes into caller-provided buffer.
/// Returns the slice of `dest` that was written.
pub fn decode(dest: []u8, source: []const u8) ![]const u8 {
    if (source.len == 0) return dest[0..0];

    // Count leading '1's (= leading zero bytes)
    var leading_ones: usize = 0;
    for (source) |c| {
        if (c != '1') break;
        leading_ones += 1;
    }

    // Work buffer for base-256 digits
    var buf: [512]u8 = undefined;
    var buf_len: usize = 0;

    for (source) |c| {
        const val = decode_table[c];
        if (val == 255) return error.InvalidBase58Character;

        var carry: u32 = val;
        var i: usize = 0;
        while (i < buf_len) : (i += 1) {
            carry += @as(u32, buf[i]) * 58;
            buf[i] = @intCast(carry & 0xFF);
            carry >>= 8;
        }
        while (carry > 0) {
            buf[buf_len] = @intCast(carry & 0xFF);
            carry >>= 8;
            buf_len += 1;
        }
    }

    // Write leading zero bytes
    var pos: usize = 0;
    for (0..leading_ones) |_| {
        dest[pos] = 0;
        pos += 1;
    }

    // Reverse the base-256 digits
    var i: usize = buf_len;
    while (i > 0) {
        i -= 1;
        dest[pos] = buf[i];
        pos += 1;
    }

    return dest[0..pos];
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  Tests                                                        ║
// ╚═══════════════════════════════════════════════════════════════╝

const testing = @import("std").testing;

test "encode 'Hello'" {
    var buf: [64]u8 = undefined;
    const result = encode(&buf, "Hello");
    try testing.expectEqualStrings("9Ajdvzr", result);
}

test "encode 32 zero bytes" {
    var buf: [64]u8 = undefined;
    const zeros = [_]u8{0} ** 32;
    const result = encode(&buf, &zeros);
    try testing.expectEqualStrings("11111111111111111111111111111111", result);
    try testing.expectEqual(@as(usize, 32), result.len);
}

test "decode '9Ajdvzr' → 'Hello'" {
    var buf: [64]u8 = undefined;
    const result = try decode(&buf, "9Ajdvzr");
    try testing.expectEqualStrings("Hello", result);
}

test "decode 32 ones → 32 zero bytes" {
    var buf: [64]u8 = undefined;
    const result = try decode(&buf, "11111111111111111111111111111111");
    try testing.expectEqual(@as(usize, 32), result.len);
    for (result) |b| try testing.expectEqual(@as(u8, 0), b);
}

test "roundtrip random-ish data" {
    const data = [_]u8{ 0, 0, 1, 2, 3, 255, 128, 64, 32, 16, 8, 4, 2, 1, 0 };
    var enc_buf: [128]u8 = undefined;
    var dec_buf: [128]u8 = undefined;
    const encoded = encode(&enc_buf, &data);
    const decoded = try decode(&dec_buf, encoded);
    try testing.expectEqualSlices(u8, &data, decoded);
}

test "invalid character" {
    var buf: [64]u8 = undefined;
    try testing.expectError(error.InvalidBase58Character, decode(&buf, "0OIl"));
}

test "encode/decode Solana-sized key (32 bytes)" {
    // A typical Solana pubkey-sized payload
    const data = [_]u8{
        0x0a, 0x1b, 0x2c, 0x3d, 0x4e, 0x5f, 0x60, 0x71,
        0x82, 0x93, 0xa4, 0xb5, 0xc6, 0xd7, 0xe8, 0xf9,
        0x01, 0x12, 0x23, 0x34, 0x45, 0x56, 0x67, 0x78,
        0x89, 0x9a, 0xab, 0xbc, 0xcd, 0xde, 0xef, 0xff,
    };
    var enc_buf: [128]u8 = undefined;
    var dec_buf: [128]u8 = undefined;
    const encoded = encode(&enc_buf, &data);
    const decoded = try decode(&dec_buf, encoded);
    try testing.expectEqualSlices(u8, &data, decoded);
}
