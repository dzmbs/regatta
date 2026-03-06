// ╔═══════════════════════════════════════════════════════════════╗
// ║  Pacifica Signing — canonical JSON + Ed25519 + base58         ║
// ╚═══════════════════════════════════════════════════════════════╝
//
// 1. Build envelope: { "type": msg_type, "timestamp": ts, "expiry_window": ew, "data": payload }
// 2. Sort all keys recursively
// 3. Compact JSON serialize (no whitespace)
// 4. Sign UTF-8 bytes with Ed25519
// 5. Base58-encode the 64-byte signature

const std = @import("std");
const Allocator = std.mem.Allocator;
const lib = @import("lib");
const Signer = lib.crypto.signer.Signer;
const base58 = lib.crypto.base58;
const canonical = lib.json;

pub const SignedRequest = struct {
    /// The compact sorted JSON message that was signed.
    message: []const u8,
    /// Base58-encoded Ed25519 signature (in struct-owned buffer).
    sig_buf: [128]u8 = undefined,
    sig_len: usize = 0,
    /// Allocator used for message.
    allocator: Allocator,

    pub fn signature(self: *const SignedRequest) []const u8 {
        return self.sig_buf[0..self.sig_len];
    }

    pub fn deinit(self: *SignedRequest) void {
        self.allocator.free(self.message);
    }
};

/// Sign a Pacifica API request.
pub fn signRequest(
    allocator: Allocator,
    signer: *const Signer,
    msg_type: []const u8,
    payload: std.json.Value,
    timestamp: u64,
    expiry_window: u64,
) !SignedRequest {
    // Use an arena for all intermediate JSON structures
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // Build the envelope: { type, timestamp, expiry_window, data: payload }
    var envelope = std.json.ObjectMap.init(arena_alloc);
    try envelope.put("type", .{ .string = msg_type });
    try envelope.put("timestamp", .{ .integer = @intCast(timestamp) });
    try envelope.put("expiry_window", .{ .integer = @intCast(expiry_window) });
    try envelope.put("data", payload);

    // Sort keys recursively
    const sorted = try canonical.sortKeys(arena_alloc, .{ .object = envelope });

    // Compact serialize (allocate with the real allocator since we return this)
    const message = try canonical.compactStringify(allocator, sorted);
    errdefer allocator.free(message);

    // Sign the UTF-8 bytes
    const sig_bytes = signer.sign(message);

    // Base58-encode the signature into the result's own buffer
    var result = SignedRequest{
        .message = message,
        .allocator = allocator,
    };
    const sig_b58 = base58.encode(&result.sig_buf, &sig_bytes);
    result.sig_len = sig_b58.len;

    return result;
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  Tests                                                        ║
// ╚═══════════════════════════════════════════════════════════════╝

const testing = std.testing;
const Ed25519 = std.crypto.sign.Ed25519;

test "signRequest produces valid signature" {
    const allocator = testing.allocator;
    const signer = Signer.generate();

    // Build a simple payload
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var payload = std.json.ObjectMap.init(arena_alloc);
    try payload.put("symbol", .{ .string = "BTC" });
    try payload.put("amount", .{ .string = "0.1" });

    var result = try signRequest(
        allocator,
        &signer,
        "create_order",
        .{ .object = payload },
        1709000000000,
        5000,
    );
    defer result.deinit();

    // Verify the message contains expected fields
    try testing.expect(std.mem.indexOf(u8, result.message, "\"type\":\"create_order\"") != null);
    try testing.expect(std.mem.indexOf(u8, result.message, "\"timestamp\":1709000000000") != null);
    try testing.expect(std.mem.indexOf(u8, result.message, "\"expiry_window\":5000") != null);

    // Verify the signature is valid base58 and decodes to 64 bytes
    var sig_dec_buf: [128]u8 = undefined;
    const sig_bytes = try base58.decode(&sig_dec_buf, result.signature());
    try testing.expectEqual(@as(usize, 64), sig_bytes.len);

    // Verify the signature against the message
    const sig = Ed25519.Signature.fromBytes(sig_bytes[0..64].*);
    try sig.verify(result.message, signer.key_pair.public_key);
}

test "signRequest message is deterministic" {
    const allocator = testing.allocator;
    const signer = Signer.generate();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var payload = std.json.ObjectMap.init(arena_alloc);
    try payload.put("symbol", .{ .string = "BTC" });

    var r1 = try signRequest(allocator, &signer, "test", .{ .object = payload }, 1000, 5000);
    defer r1.deinit();

    var r2 = try signRequest(allocator, &signer, "test", .{ .object = payload }, 1000, 5000);
    defer r2.deinit();

    try testing.expectEqualStrings(r1.message, r2.message);
    try testing.expectEqualStrings(r1.signature(), r2.signature());
}
