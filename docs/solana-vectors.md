# Solana deposit fixture notes

`testdata/solana_deposit_vectors.json` is a checked-in parity fixture used by `src/sdk/solana.zig` tests.

It was generated once from two local reference implementations:
- Solana Rust SDK transaction builder
- `solana-web3.js`

Why keep the fixture but not the generators?
- `regatta` is a Zig project
- normal build/test should stay lean and self-contained
- users cloning the repo should not need local Rust/Node reference SDK checkouts just to run tests
- the generators were intentionally removed after the fixture was locked in

What the fixture covers:
- deterministic seeds
- multiple blockhashes
- multiple USDC amounts
- multiple compute-budget profiles
- exact transaction bytes for both internal ordering policies:
  - `sorted` → matches current Solana Rust SDK behavior
  - `insertion` → matches current `solana-web3.js` behavior

The fixture exists to preserve a high-confidence regression net without dragging cross-language tooling into the public API or normal developer workflow.
