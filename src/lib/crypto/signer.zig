// ╔═══════════════════════════════════════════════════════════════╗
// ║  Ed25519 Signer — Solana keypair wrapper                      ║
// ╚═══════════════════════════════════════════════════════════════╝
//
// Pacifica uses Solana-format keypairs: 64 bytes where [0..32] = seed, [32..64] = pubkey.
// Encoded as base58.

const std = @import("std");
const Ed25519 = std.crypto.sign.Ed25519;
const base58 = @import("base58.zig");

pub const Signer = struct {
    key_pair: Ed25519.KeyPair,

    pub fn fromSeed(seed: [32]u8) !Signer {
        const key_pair = try Ed25519.KeyPair.generateDeterministic(seed);
        return .{ .key_pair = key_pair };
    }

    pub fn fromBytes(secret: [64]u8) !Signer {
        const seed: [32]u8 = secret[0..32].*;
        const expected_pub: [32]u8 = secret[32..64].*;
        const key_pair = try Ed25519.KeyPair.generateDeterministic(seed);
        if (!std.mem.eql(u8, &key_pair.public_key.toBytes(), &expected_pub)) {
            return error.PublicKeyMismatch;
        }
        return .{ .key_pair = key_pair };
    }

    /// Load from base58-encoded Solana secret key (decodes to 64 bytes).
    pub fn fromBase58(b58_secret: []const u8) !Signer {
        var decode_buf: [128]u8 = undefined;
        const decoded = try base58.decode(&decode_buf, b58_secret);
        if (decoded.len != 64) return error.InvalidKeyLength;
        return fromBytes(decoded[0..64].*);
    }

    /// Sign a message. Returns 64-byte signature.
    pub fn sign(self: *const Signer, msg: []const u8) [64]u8 {
        const sig = self.key_pair.sign(msg, null) catch unreachable;
        return sig.toBytes();
    }

    /// Public key as raw 32 bytes.
    pub fn pubkeyBytes(self: *const Signer) [32]u8 {
        return self.key_pair.public_key.toBytes();
    }

    /// Public key as base58 string (written into caller-provided buf).
    pub fn pubkeyBase58(self: *const Signer, buf: *[44]u8) []const u8 {
        const bytes = self.key_pair.public_key.toBytes();
        return base58.encode(buf, &bytes);
    }

    pub fn secretBytes64(self: *const Signer) [64]u8 {
        var out: [64]u8 = undefined;
        const seed = self.key_pair.secret_key.seed();
        const pubkey = self.key_pair.public_key.toBytes();
        @memcpy(out[0..32], &seed);
        @memcpy(out[32..64], &pubkey);
        return out;
    }

    pub fn secretBase58(self: *const Signer, buf: []u8) []const u8 {
        const secret = self.secretBytes64();
        return base58.encode(buf, &secret);
    }

    /// Generate a new random keypair.
    pub fn generate() Signer {
        const key_pair = Ed25519.KeyPair.generate();
        return .{ .key_pair = key_pair };
    }
};

// ╔═══════════════════════════════════════════════════════════════╗
// ║  Tests                                                        ║
// ╚═══════════════════════════════════════════════════════════════╝

const testing = std.testing;

test "generate → sign → verify roundtrip" {
    const signer = Signer.generate();
    const msg = "test message for signing";
    const sig_bytes = signer.sign(msg);

    const sig = Ed25519.Signature.fromBytes(sig_bytes);
    try sig.verify(msg, signer.key_pair.public_key);
}

test "pubkeyBase58 produces valid base58" {
    const signer = Signer.generate();
    var buf: [44]u8 = undefined;
    const b58 = signer.pubkeyBase58(&buf);

    var dec_buf: [64]u8 = undefined;
    const decoded = try base58.decode(&dec_buf, b58);
    try testing.expectEqual(@as(usize, 32), decoded.len);
    try testing.expectEqualSlices(u8, &signer.pubkeyBytes(), decoded);
}

test "deterministic signing — same key + message → same signature" {
    const signer = Signer.generate();
    const msg = "deterministic test";
    const sig1 = signer.sign(msg);
    const sig2 = signer.sign(msg);
    try testing.expectEqualSlices(u8, &sig1, &sig2);
}

test "fromBase58 → sign → verify" {
    const original = Signer.generate();
    const seed = original.key_pair.secret_key.seed();
    const pub_bytes = original.key_pair.public_key.toBytes();

    // Construct 64-byte Solana format
    var full_key: [64]u8 = undefined;
    @memcpy(full_key[0..32], &seed);
    @memcpy(full_key[32..64], &pub_bytes);

    // Encode as base58
    var b58_buf: [128]u8 = undefined;
    const b58 = base58.encode(&b58_buf, &full_key);

    // Reload from base58
    const restored = try Signer.fromBase58(b58);

    // Sign with both, should match
    const msg = "roundtrip test";
    const sig1 = original.sign(msg);
    const sig2 = restored.sign(msg);
    try testing.expectEqualSlices(u8, &sig1, &sig2);
}
