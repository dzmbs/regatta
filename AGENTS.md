# regatta-cli

Zig SDK and CLI for [Pacifica](https://trade.pacifica.fi) — market data, trading, account operations, keystore management, and Solana deposits.

## Environment

- Language: Zig 0.15.2
- Build: `zig build`
- Test: `zig build test`
- Run: `zig build run -- <args>`
- Release: `./scripts/release.sh <version>`

## Architecture

Three layers:

- `src/lib/` — primitives (crypto, json, uuid)
- `src/sdk/` — Pacifica protocol client, Solana helpers, signing
- `src/cli/` — command parsing, output formatting, UX

Public package entrypoint: `src/root.zig`

## Conventions

- Pipe-aware output: styled tables on TTY, JSON when piped or `--json`
- Semantic exit codes: 0=ok, 1=error, 2=usage, 3=auth, 4=network
- Ethereum-style V3 keystore under `~/.regatta/keys/`
- No interactive prompts — designed for agent and automation use
- `--dry-run` for previewing signed requests without sending
- USD-notional order sizing (`$10`, `usd:10`) with lot/min validation

## Key environment variables

```
PACIFICA_KEY=...          # base58 Solana keypair
PACIFICA_KEY_NAME=...     # named local keystore entry
PACIFICA_PASSWORD=...     # keystore password
PACIFICA_ADDRESS=...      # default account address
PACIFICA_AGENT_WALLET=... # delegated agent wallet
PACIFICA_CHAIN=...        # mainnet or testnet
SOLANA_RPC_URL=...        # Solana RPC for deposit
```

## Required rules

- Keep changes narrowly scoped; avoid unrelated refactors.
- Run `zig build test` before any PR handoff.
- Maintain existing code style — no unnecessary abstractions.
- Do not add interactive prompts or break agent-friendliness.
- Solana deposit is mainnet-only; do not enable testnet deposits without verified constants.

## Tests and validation

```bash
zig build test
```

Fixture/parity tests live under `tests/`. CLI unit tests are inline in `src/cli/*.zig`.
