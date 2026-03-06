// ╔═══════════════════════════════════════════════════════════════╗
// ║  UUID v4 — random UUID for client_order_id                    ║
// ╚═══════════════════════════════════════════════════════════════╝

const std = @import("std");

/// Generate a UUID v4 string into the provided 36-byte buffer.
/// Format: xxxxxxxx-xxxx-4xxx-Nxxx-xxxxxxxxxxxx (N = 8|9|a|b)
pub fn v4(buf: *[36]u8) []const u8 {
    var bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&bytes);

    // Set version 4: byte 6 → 0100xxxx
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    // Set variant 1: byte 8 → 10xxxxxx
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    const hex = "0123456789abcdef";
    var pos: usize = 0;

    const groups = [_]struct { start: usize, len: usize }{
        .{ .start = 0, .len = 4 },  // 8 hex chars
        .{ .start = 4, .len = 2 },  // 4 hex chars
        .{ .start = 6, .len = 2 },  // 4 hex chars
        .{ .start = 8, .len = 2 },  // 4 hex chars
        .{ .start = 10, .len = 6 }, // 12 hex chars
    };

    inline for (groups, 0..) |g, gi| {
        if (gi > 0) {
            buf[pos] = '-';
            pos += 1;
        }
        for (g.start..g.start + g.len) |i| {
            buf[pos] = hex[bytes[i] >> 4];
            buf[pos + 1] = hex[bytes[i] & 0x0F];
            pos += 2;
        }
    }

    return buf[0..36];
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  Tests                                                        ║
// ╚═══════════════════════════════════════════════════════════════╝

const testing = std.testing;

test "v4 format" {
    var buf: [36]u8 = undefined;
    const uuid = v4(&buf);

    try testing.expectEqual(@as(usize, 36), uuid.len);
    // Check dashes at positions 8, 13, 18, 23
    try testing.expectEqual(@as(u8, '-'), uuid[8]);
    try testing.expectEqual(@as(u8, '-'), uuid[13]);
    try testing.expectEqual(@as(u8, '-'), uuid[18]);
    try testing.expectEqual(@as(u8, '-'), uuid[23]);
    // Check version nibble (position 14 = '4')
    try testing.expectEqual(@as(u8, '4'), uuid[14]);
    // Check variant nibble (position 19 = '8', '9', 'a', or 'b')
    const variant = uuid[19];
    try testing.expect(variant == '8' or variant == '9' or variant == 'a' or variant == 'b');
}

test "v4 uniqueness" {
    var buf1: [36]u8 = undefined;
    var buf2: [36]u8 = undefined;
    const uuid1 = v4(&buf1);
    const uuid2 = v4(&buf2);
    try testing.expect(!std.mem.eql(u8, uuid1, uuid2));
}
