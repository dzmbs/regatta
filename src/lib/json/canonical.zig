// ╔═══════════════════════════════════════════════════════════════╗
// ║  Canonical JSON — recursive key sort + compact serialize      ║
// ╚═══════════════════════════════════════════════════════════════╝
//
// Matches Python: json.dumps(sort_json_keys(data), separators=(",",":"))
// Used for Pacifica's deterministic signing scheme.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Recursively sort all object keys in a JSON value tree.
/// Returns a new Value with sorted ObjectMaps (insertion-ordered by sorted keys).
pub fn sortKeys(allocator: Allocator, value: std.json.Value) !std.json.Value {
    switch (value) {
        .object => |obj| {
            // Collect keys and sort them
            var keys = try allocator.alloc([]const u8, obj.count());
            defer allocator.free(keys);
            var i: usize = 0;
            var it = obj.iterator();
            while (it.next()) |entry| {
                keys[i] = entry.key_ptr.*;
                i += 1;
            }
            std.mem.sort([]const u8, keys, {}, stringLessThan);

            // Re-insert in sorted order
            var sorted = std.json.ObjectMap.init(allocator);
            try sorted.ensureTotalCapacity(@intCast(keys.len));
            for (keys) |key| {
                const child = obj.get(key).?;
                const sorted_child = try sortKeys(allocator, child);
                sorted.putAssumeCapacity(key, sorted_child);
            }

            return .{ .object = sorted };
        },
        .array => |arr| {
            var sorted_arr = try std.json.Array.initCapacity(allocator, arr.items.len);
            for (arr.items) |item| {
                sorted_arr.appendAssumeCapacity(try sortKeys(allocator, item));
            }
            return .{ .array = sorted_arr };
        },
        else => return value,
    }
}

/// Serialize a JSON value to compact string (no whitespace).
/// Equivalent to Python's json.dumps(x, separators=(",",":"))
pub fn compactStringify(allocator: Allocator, value: std.json.Value) ![]const u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);
    try writeValue(allocator, &buf, value);
    return buf.toOwnedSlice(allocator);
}

fn writeValue(allocator: Allocator, buf: *std.ArrayList(u8), value: std.json.Value) !void {
    switch (value) {
        .null => try buf.appendSlice(allocator, "null"),
        .bool => |b| try buf.appendSlice(allocator, if (b) "true" else "false"),
        .integer => |i| {
            var num_buf: [32]u8 = undefined;
            const s = std.fmt.bufPrint(&num_buf, "{d}", .{i}) catch unreachable;
            try buf.appendSlice(allocator, s);
        },
        .float => |f| {
            var num_buf: [64]u8 = undefined;
            const s = std.fmt.bufPrint(&num_buf, "{d}", .{f}) catch unreachable;
            try buf.appendSlice(allocator, s);
        },
        .number_string => |s| try buf.appendSlice(allocator, s),
        .string => |s| try writeJsonString(allocator, buf, s),
        .array => |arr| {
            try buf.append(allocator, '[');
            for (arr.items, 0..) |item, idx| {
                if (idx > 0) try buf.append(allocator, ',');
                try writeValue(allocator, buf, item);
            }
            try buf.append(allocator, ']');
        },
        .object => |obj| {
            try buf.append(allocator, '{');
            var first = true;
            var it = obj.iterator();
            while (it.next()) |entry| {
                if (!first) try buf.append(allocator, ',');
                first = false;
                try writeJsonString(allocator, buf, entry.key_ptr.*);
                try buf.append(allocator, ':');
                try writeValue(allocator, buf, entry.value_ptr.*);
            }
            try buf.append(allocator, '}');
        },
    }
}

fn writeJsonString(allocator: Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    try buf.append(allocator, '"');
    for (s) |c| {
        switch (c) {
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            0x08 => try buf.appendSlice(allocator, "\\b"),
            0x0C => try buf.appendSlice(allocator, "\\f"),
            else => {
                if (c < 0x20) {
                    var hex_buf: [6]u8 = undefined;
                    const hex = std.fmt.bufPrint(&hex_buf, "\\u{x:0>4}", .{c}) catch unreachable;
                    try buf.appendSlice(allocator, hex);
                } else {
                    try buf.append(allocator, c);
                }
            },
        }
    }
    try buf.append(allocator, '"');
}

fn stringLessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  Tests                                                        ║
// ╚═══════════════════════════════════════════════════════════════╝

const testing = std.testing;

test "sortKeys + compactStringify matches Python output" {
    const allocator = testing.allocator;

    const input =
        \\{"type":"create_order","timestamp":1709000000000,"expiry_window":5000,"data":{"symbol":"BTC","side":"bid","amount":"0.1","price":"100000","reduce_only":false,"tif":"GTC","client_order_id":"test-uuid"}}
    ;
    const expected =
        \\{"data":{"amount":"0.1","client_order_id":"test-uuid","price":"100000","reduce_only":false,"side":"bid","symbol":"BTC","tif":"GTC"},"expiry_window":5000,"timestamp":1709000000000,"type":"create_order"}
    ;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, input, .{});
    defer parsed.deinit();

    const sorted = try sortKeys(allocator, parsed.value);
    const result = try compactStringify(allocator, sorted);
    defer allocator.free(result);

    try testing.expectEqualStrings(expected, result);
}

test "compactStringify primitives" {
    const allocator = testing.allocator;

    {
        const result = try compactStringify(allocator, .null);
        defer allocator.free(result);
        try testing.expectEqualStrings("null", result);
    }
    {
        const result = try compactStringify(allocator, .{ .bool = true });
        defer allocator.free(result);
        try testing.expectEqualStrings("true", result);
    }
    {
        const result = try compactStringify(allocator, .{ .integer = 42 });
        defer allocator.free(result);
        try testing.expectEqualStrings("42", result);
    }
    {
        const result = try compactStringify(allocator, .{ .string = "hello\nworld" });
        defer allocator.free(result);
        try testing.expectEqualStrings("\"hello\\nworld\"", result);
    }
}

test "sortKeys nested objects" {
    const allocator = testing.allocator;

    const input =
        \\{"z":1,"a":{"c":3,"b":2}}
    ;
    const expected =
        \\{"a":{"b":2,"c":3},"z":1}
    ;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, input, .{});
    defer parsed.deinit();

    const sorted = try sortKeys(allocator, parsed.value);
    const result = try compactStringify(allocator, sorted);
    defer allocator.free(result);

    try testing.expectEqualStrings(expected, result);
}

test "sortKeys with arrays" {
    const allocator = testing.allocator;

    const input =
        \\{"b":[{"z":1,"a":2},{"y":3,"x":4}],"a":1}
    ;
    const expected =
        \\{"a":1,"b":[{"a":2,"z":1},{"x":4,"y":3}]}
    ;

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, input, .{});
    defer parsed.deinit();

    const sorted = try sortKeys(allocator, parsed.value);
    const result = try compactStringify(allocator, sorted);
    defer allocator.free(result);

    try testing.expectEqualStrings(expected, result);
}
