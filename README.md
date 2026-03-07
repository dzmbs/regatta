<p align="center">
  <img src="logo.svg" alt="regatta" height="110" />
</p>

<p align="center">
  Zig tooling for <a href="https://trade.pacifica.fi">Pacifica</a> — SDK and CLI.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-v0.0.8-blue" alt="version" />
  <img src="https://img.shields.io/badge/license-MIT-green" alt="license" />
  <img src="https://img.shields.io/badge/status-beta-orange" alt="status" />
  <img src="https://img.shields.io/badge/platform-macOS_|_Linux-blue" alt="platform" />
  <img src="https://img.shields.io/badge/zig-0.15.2-F7A41D?logo=zig&logoColor=white" alt="zig" />
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="#sdk">SDK</a> ·
  <a href="#agent-integration">Agent Integration</a>
</p>

---

## What is this

A Zig implementation of Pacifica tooling with one binary and one package:

| Artifact | Size | What it does |
|----------|------|--------------|
| `regatta` | ~0.6–0.7 MB | Pacifica CLI — market data, trading, account ops, keystore, Solana deposit |
| `regatta` Zig module | small, dependency-light | SDK surface for signing, REST requests, and Solana helpers |

Release binaries are stripped `ReleaseSmall` builds for macOS and Linux on x64/arm64.

Pipe-aware by default — pretty output on TTY, JSON when piped or with `--json`.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/dzmbs/regatta/main/install.sh | sh
```

Or download a binary manually from [Releases](../../releases/latest).

**From source** (requires [Zig 0.15.2](https://ziglang.org/download/)):

```bash
git clone https://github.com/dzmbs/regatta
cd regatta
zig build -Doptimize=ReleaseSmall
./zig-out/bin/regatta version
```

**As a Zig dependency:**

```zig
.dependencies = .{
    .regatta = .{
        .url = "git+https://github.com/dzmbs/regatta#main",
    },
},
```

---

## Quick Start

```bash
# No auth needed for public market data
regatta info
regatta prices
regatta book BTC
regatta candles BTC --interval 1h

# Create an encrypted local key
regatta keys new trading --password 'choose-a-password'
regatta keys default trading
export PACIFICA_KEY_NAME=trading
export PACIFICA_PASSWORD='choose-a-password'

# Check account
regatta account --json
regatta positions --json
regatta orders --json

# Trade
regatta buy BTC 0.001 @100000 --dry-run
regatta sell ETH 0.001 --dry-run
regatta cancel --all

# Access / onboarding helpers
regatta access status --json
regatta access claim <CODE>
regatta balance --json
regatta withdraw 10            # withdraw 10 total, receive 9 after fee
regatta deposit solana 10
regatta transfer solana sol 0.1 <ADDR>
regatta transfer solana usdc 5 <ADDR>
```

---

## SDK

```zig
const std = @import("std");
const regatta = @import("regatta");

const Signer = regatta.crypto.signer.Signer;
const Client = regatta.client.Client;
const Chain = regatta.config.Chain;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

const signer = try Signer.fromBase58("<BASE58_SOLANA_KEYPAIR>");
var addr_buf: [44]u8 = undefined;
const address = signer.pubkeyBase58(&addr_buf);

var client = Client.init(allocator, Chain.mainnet);
defer client.deinit();

const query = try std.fmt.allocPrint(allocator, "account={s}", .{address});
defer allocator.free(query);

var res = try client.get("/account", query);
defer res.deinit();
```

Public package entrypoint:
- `src/root.zig`

Convenience exports include:
- `regatta.crypto`
- `regatta.json`
- `regatta.uuid`
- `regatta.signing`
- `regatta.config`
- `regatta.client`
- `regatta.solana`

---

## CLI Commands

<details>
<summary><strong>Market Data</strong> (no auth)</summary>

| Command | Description |
|---------|-------------|
| `regatta info` | Exchange metadata and configuration |
| `regatta prices` | All market prices |
| `regatta book <SYM>` | Order book |
| `regatta candles <SYM> --interval 1h` | Candle history |

</details>

<details>
<summary><strong>Trading</strong></summary>

| Command | Description |
|---------|-------------|
| `regatta buy <SYM> <AMT> [@PRICE]` | Limit or market buy |
| `regatta sell <SYM> <AMT> [@PRICE]` | Limit or market sell |
| `regatta cancel <SYM> [ORDER_ID]` | Cancel order |
| `regatta cancel --all [--symbol SYM]` | Cancel all orders |
| `regatta edit <SYM> <OID> <PRICE> <AMT>` | Edit existing order |
| `regatta leverage <SYM> [N]` | Query or set leverage |
| `regatta margin <SYM> --isolated\|--cross` | Set margin mode |
| `regatta stop <SYM> --side long --stop-price P [--limit-price P]` | Place stop order |
| `regatta tpsl <SYM> <SIDE> --tp P --sl P` | Place take-profit / stop-loss |
| `regatta twap <SYM> buy\|sell <AMT> --duration <SECS> --slippage <PCT>` | TWAP execution |
| `regatta deposit solana <AMOUNT> [--rpc URL]` | Deposit USDC on Solana (minimum 10 USDC) |
| `regatta transfer solana sol <AMOUNT> <TO> [--rpc URL]` | Send SOL on Solana |
| `regatta transfer solana usdc <AMOUNT> <TO> [--rpc URL]` | Send USDC on Solana (creates recipient ATA if needed) |
| `regatta balance [solana|pacifica]` | Show Solana wallet and/or Pacifica balances |
| `regatta withdraw <AMOUNT>` | Withdraw gross amount; 1 USDC fee is deducted from that amount |

**Flags:** `--reduce-only`, `--tif GTC|IOC|ALO|TOB`, `--slippage <PCT>`, `--dry-run`

</details>

<details>
<summary><strong>Account</strong></summary>

| Command | Description |
|---------|-------------|
| `regatta account [ADDR]` | Account info (friendly zero-state for uninitialized accounts) |
| `regatta positions [ADDR]` | Open positions |
| `regatta orders [ADDR]` | Open orders |
| `regatta history [ADDR]` | Order history |
| `regatta trades [ADDR]` | Trade history |
| `regatta funding [ADDR]` | Funding history |
| `regatta balance-history [ADDR]` | Balance events |
| `regatta equity [ADDR]` | Equity over time |
| `regatta access status [ADDR]` | Beta access status |
| `regatta access claim <CODE>` | Claim beta access |

</details>

<details>
<summary><strong>Keys</strong></summary>

```bash
regatta keys ls
regatta keys new <NAME> --password <PASS>
regatta keys import <NAME> --private-key <BASE58> --password <PASS>
regatta keys export <NAME> --password <PASS>
regatta keys rm <NAME>
regatta keys default <NAME>
```

Keystores are stored under `~/.regatta/keys/`.

</details>

<details>
<summary><strong>Global Flags & Environment</strong></summary>

```
--json                  JSON output (auto when piped)
--quiet, -q             Minimal output
--chain testnet         Use testnet where supported
--dry-run, -n           Preview without sending
--key-name <NAME>       Select keystore key
--key <BASE58>          Raw Solana keypair
--address <BASE58>      Explicit account address
--agent-wallet <ADDR>   Delegated agent wallet
```

```bash
PACIFICA_KEY=...          # base58 Solana keypair
PACIFICA_KEY_NAME=...     # named local keystore entry
PACIFICA_PASSWORD=...     # keystore password
PACIFICA_ADDRESS=...      # default account address
PACIFICA_AGENT_WALLET=... # delegated agent wallet
PACIFICA_CHAIN=...        # mainnet or testnet
SOLANA_RPC_URL=...        # Solana RPC for deposit
```

Exit codes: `0` success, `1` error, `2` usage, `3` auth, `4` network

</details>

---

## Agent Integration

Built for automation and AI agents:

- JSON when piped, `--json` always available
- semantic exit codes (`0/1/2/3/4`)
- `--dry-run` for signed request previewing
- `--quiet` for concise values
- `batch --stdin` support
- no interactive prompts
- no fake `status: ok` wrapper over Pacifica API results

```bash
regatta prices --json
regatta account --json
printf '%s\n' 'buy BTC 0.001 @10000' | regatta batch --stdin --dry-run --json
```

---

## Solana Deposit

Current on-chain deposit support is:
- Solana
- USDC
- mainnet only

Deposit building is fixture-tested against locked reference vectors and verified against observed Pacifica mainnet transaction data.

Release parity coverage includes:
- associated token account derivation
- Pacifica event authority PDA derivation
- exact legacy transaction serialization parity for both supported internal ordering modes

Why mainnet only?
- the current builder uses verified mainnet Pacifica program constants
- `regatta` explicitly blocks deposit on `--chain testnet`
- testnet support should only be enabled once reliable Pacifica testnet Solana constants exist

---

## Architecture

`regatta` is organized in three layers:

- `src/lib/` — primitives
- `src/sdk/` — Pacifica protocol + Solana helpers
- `src/cli/` — command parsing and UX

Public package entrypoint:
- `src/root.zig`

Project layout:

```text
build.zig
build.zig.zon
README.md
LICENSE
logo.svg
install.sh
scripts/
src/
  cli/
  lib/
  sdk/
docs/
  api/
tests/
  fixtures/
```

---

## Release

GitHub Releases are built automatically by Actions when you push a tag like `v0.0.8`.

Manual local build remains available:

```bash
./scripts/release.sh 0.0.8
```

This produces:
- `dist/0.0.8/regatta-darwin-arm64`
- `dist/0.0.8/regatta-darwin-x64`
- `dist/0.0.8/regatta-linux-arm64`
- `dist/0.0.8/regatta-linux-x64`
- `dist/0.0.8/SHA256SUMS`

Current `0.0.8` binary sizes from local release builds:
- macOS arm64: ~678 KB
- macOS x64: ~711 KB
- Linux arm64: ~560 KB
- Linux x64: ~651 KB

---

## Credits

- Pacifica docs and API surface
- Pacifica Python examples for request-shape verification
- Solana Rust SDK and `solana-web3.js` used to validate deposit serialization parity
