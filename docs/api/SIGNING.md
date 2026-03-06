# Pacifica Signing Protocol

> Source: https://pacifica.gitbook.io/docs/api-documentation/api/signing/implementation
> Scraped: 2026-03-06

All POST requests require Ed25519 signatures. GET requests and WS subscriptions do NOT.

## Steps

### 1. Load Key
Solana-style Ed25519 keypair from base58-encoded 64-byte secret key.
Public key = last 32 bytes (or derive from first 32).

### 2. Define Operation Type + Payload
Each endpoint has a specific `type` string used in signing:

| type | endpoint |
|------|----------|
| `create_order` | `/api/v1/orders/create` |
| `create_market_order` | `/api/v1/orders/create_market` |
| `edit_order` | `/api/v1/orders/edit` |
| `cancel_order` | `/api/v1/orders/cancel` |
| `cancel_all_orders` | `/api/v1/orders/cancel_all` |
| `create_stop_order` | `/api/v1/orders/stop/create` |
| `cancel_stop_order` | `/api/v1/orders/stop/cancel` |
| `set_position_tpsl` | `/api/v1/positions/tpsl` |
| `create_twap_order` | `/api/v1/orders/twap/create` |
| `cancel_twap_order` | `/api/v1/orders/twap/cancel` |
| `update_leverage` | `/api/v1/account/leverage` |
| `update_margin_mode` | `/api/v1/account/margin` |
| `withdraw` | `/api/v1/account/withdraw` |
| `bind_agent_wallet` | `/api/v1/agent/bind` |
| `list_agent_wallets` | `/api/v1/agent/list` |
| `revoke_agent_wallet` | `/api/v1/agent/revoke` |
| `revoke_all_agent_wallets` | `/api/v1/agent/revoke_all` |
| `list_agent_ip_whitelist` | `/api/v1/agent/ip_whitelist/list` |
| `add_agent_whitelisted_ip` | `/api/v1/agent/ip_whitelist/add` |
| `remove_agent_whitelisted_ip` | `/api/v1/agent/ip_whitelist/remove` |
| `set_agent_ip_whitelist_enabled` | `/api/v1/agent/ip_whitelist/toggle` |
| `subaccount_initiate` | `/api/v1/account/subaccount/create` (sub signs) |
| `subaccount_confirm` | `/api/v1/account/subaccount/create` (main signs) |
| `transfer_funds` | `/api/v1/account/subaccount/transfer` |
| `list_subaccounts` | `/api/v1/account/subaccount/list` |
| `create_api_key` | `/api/v1/account/api_keys/create` |
| `revoke_api_key` | `/api/v1/account/api_keys/revoke` |
| `list_api_keys` | `/api/v1/account/api_keys` |
| `create_lake` | `/api/v1/lake/create` |
| `deposit_to_lake` | `/api/v1/lake/deposit` |
| `withdraw_from_lake` | `/api/v1/lake/withdraw` |

### 3. Create Signature Header
```python
signature_header = {
    "timestamp": int(time.time() * 1_000),  # ms
    "expiry_window": 5_000,  # ms, optional, default 30000
    "type": "create_order",
}
```

### 4. Combine Header + Payload Under "data" Key
```python
data_to_sign = {
    **signature_header,
    "data": operation_payload,
}
```

### 5. Recursively Sort All JSON Keys (alphabetically, all levels)
```python
def sort_json_keys(value):
    if isinstance(value, dict):
        return {k: sort_json_keys(v) for k, v in sorted(value.items())}
    elif isinstance(value, list):
        return [sort_json_keys(item) for item in value]
    return value
```

### 6. Create Compact JSON String
```python
compact_json = json.dumps(sorted_message, separators=(",", ":"))
```

**Example output:**
```
{"data":{"amount":"0.1","client_order_id":"12345678-1234-1234-1234-123456789abc","price":"100000","reduce_only":false,"side":"bid","symbol":"BTC","tif":"GTC"},"expiry_window":5000,"timestamp":1748970123456,"type":"create_order"}
```

### 7. Sign UTF-8 Bytes with Ed25519
```python
message_bytes = compact_json.encode("utf-8")
signature = keypair.sign_message(message_bytes)
signature_b58 = base58.b58encode(bytes(signature)).decode("ascii")
```

### 8. Build Final Request
```python
request = {
    "account": public_key,
    "agent_wallet": None,  # or agent pubkey if using agent wallet
    "signature": signature_b58,
    "timestamp": timestamp,
    "expiry_window": expiry_window,
    **operation_payload,  # flatten data fields into top-level
}
```

**Important:** The request body flattens data fields to top level. The `"data"` wrapper is ONLY used during signing, not in the actual HTTP request.

## Agent Wallet Signing
When using an agent wallet:
- Sign with the agent wallet's private key (not main account)
- Include `"agent_wallet": agent_public_key` in request
- Include `"account": main_account_public_key` in request

## Batch Orders
Batch orders are NOT signed as a whole. Each action within the batch is signed independently with its own operation type.

## Key Format
Solana keypair: 64-byte secret key, base58 encoded.
- First 32 bytes = private key seed
- Last 32 bytes = public key
- `Keypair.from_base58_string(PRIVATE_KEY)` in Python solders library
