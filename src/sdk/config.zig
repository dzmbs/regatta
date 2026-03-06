// ╔═══════════════════════════════════════════════════════════════╗
// ║  Chain configuration — mainnet/testnet URLs                   ║
// ╚═══════════════════════════════════════════════════════════════╝

pub const Chain = enum {
    mainnet,
    testnet,

    pub fn restUrl(self: Chain) []const u8 {
        return switch (self) {
            .mainnet => "https://api.pacifica.fi/api/v1",
            .testnet => "https://test-api.pacifica.fi/api/v1",
        };
    }

    pub fn wsUrl(self: Chain) []const u8 {
        return switch (self) {
            .mainnet => "wss://ws.pacifica.fi/ws",
            .testnet => "wss://test-ws.pacifica.fi/ws",
        };
    }
};
