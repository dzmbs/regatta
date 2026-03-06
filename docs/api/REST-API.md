# Pacifica REST API Reference

> Source: https://pacifica.gitbook.io/docs/api-documentation/api/rest-api
> Scraped: 2026-03-06

**Mainnet:** `https://api.pacifica.fi/api/v1`
**Testnet:** `https://test-api.pacifica.fi/api/v1`

All responses use JSON. All responses follow the envelope:
```json
{
  "success": true|false,
  "data": ...,
  "error": null|"string",
  "code": null|int
}
```

Paginated responses add `"next_cursor"` and `"has_more"` fields.
Some responses include `"last_order_id"` (exchange-wide nonce for event ordering).

---

## Markets (Public GET endpoints — no auth)

### GET /api/v1/info — Get Market Info
Returns exchange info for all trading pairs.

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "symbol": "ETH",
      "tick_size": "0.1",
      "min_tick": "0",
      "max_tick": "1000000",
      "lot_size": "0.0001",
      "max_leverage": 50,
      "isolated_only": false,
      "min_order_size": "10",
      "max_order_size": "5000000",
      "funding_rate": "0.0000125",
      "next_funding_rate": "0.0000125",
      "created_at": 1748881333944
    }
  ],
  "error": null,
  "code": null
}
```

### GET /api/v1/info/prices — Get Prices
Returns price info for all symbols.

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "symbol": "XPL",
      "funding": "0.00010529",
      "mark": "1.084819",
      "mid": "1.08615",
      "next_funding": "0.00011096",
      "open_interest": "3634796",
      "oracle": "1.084524",
      "timestamp": 1759222967974,
      "volume_24h": "20896698.0672",
      "yesterday_price": "1.3412"
    }
  ],
  "error": null,
  "code": null
}
```

### GET /api/v1/kline — Get Candle Data
**Params:** `symbol` (required), `interval` (required: 1m,3m,5m,15m,30m,1h,2h,4h,8h,12h,1d), `start_time` (ms, required), `end_time` (ms, optional)

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "t": 1748954160000,
      "T": 1748954220000,
      "s": "BTC",
      "i": "1m",
      "o": "105376",
      "c": "105376",
      "h": "105376",
      "l": "105376",
      "v": "0.00022",
      "n": 2
    }
  ],
  "error": null,
  "code": null
}
```

### GET /api/v1/kline/mark — Get Mark Price Candle Data
Same params and response shape as /kline but for mark prices.

### GET /api/v1/book — Get Orderbook
**Params:** `symbol` (required), `agg` (optional, default 1)

**Response:**
```json
{
  "success": true,
  "data": {
    "s": "BTC",
    "l": [
      [{"p": "106504", "a": "0.26203", "n": 1}],
      [{"p": "106559", "a": "0.26802", "n": 1}]
    ],
    "t": 1751370536325
  },
  "error": null,
  "code": null
}
```
`l[0]` = bids, `l[1]` = asks. Each level: `p`=price, `a`=amount, `n`=order count. Up to 10 levels.

### GET /api/v1/trades — Get Recent Trades
**Params:** `symbol` (required)

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "event_type": "fulfill_taker",
      "price": "104721",
      "amount": "0.0001",
      "side": "close_long",
      "cause": "normal",
      "created_at": 1765006315306
    }
  ],
  "error": null,
  "code": null,
  "last_order_id": 1557404170
}
```
- `event_type`: `fulfill_taker` or `fulfill_maker`
- `side`: `open_long`, `open_short`, `close_long`, `close_short`
- `cause`: `normal`, `market_liquidation`, `backstop_liquidation`, `settlement`

### GET /api/v1/funding_rate/history — Get Historical Funding
**Params:** `symbol` (required), `limit` (default 100, max 4000), `cursor` (optional)

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "oracle_price": "117170.410304",
      "bid_impact_price": "117126",
      "ask_impact_price": "117142",
      "funding_rate": "0.0000125",
      "next_funding_rate": "0.0000125",
      "created_at": 1753806934249
    }
  ],
  "next_cursor": "11114Lz77",
  "has_more": true
}
```

---

## Account (GET endpoints — no auth, uses account query param)

### GET /api/v1/account — Get Account Info
**Params:** `account` (required — wallet address)

**Response:**
```json
{
  "success": true,
  "data": {
    "balance": "2000.000000",
    "fee_level": 0,
    "maker_fee": "0.00015",
    "taker_fee": "0.0004",
    "account_equity": "2150.250000",
    "available_to_spend": "1800.750000",
    "available_to_withdraw": "1500.850000",
    "pending_balance": "0.000000",
    "total_margin_used": "349.500000",
    "cross_mmr": "420.690000",
    "positions_count": 2,
    "orders_count": 3,
    "stop_orders_count": 1,
    "updated_at": 1716200000000,
    "use_ltp_for_stop_orders": false
  },
  "error": null,
  "code": null
}
```

### GET /api/v1/account/settings — Get Account Settings
**Params:** `account` (required)

Returns only markets where settings differ from defaults (cross margin, max leverage).

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "symbol": "WLFI",
      "isolated": false,
      "leverage": 5,
      "created_at": 1758085929703,
      "updated_at": 1758086074002
    }
  ],
  "error": null,
  "code": null
}
```

### GET /api/v1/positions — Get Positions
**Params:** `account` (required)

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "symbol": "AAVE",
      "side": "ask",
      "amount": "223.72",
      "entry_price": "279.283134",
      "margin": "0",
      "funding": "13.159593",
      "isolated": false,
      "created_at": 1754928414996,
      "updated_at": 1759223365538
    }
  ],
  "error": null,
  "code": null,
  "last_order_id": 1557431179
}
```

### GET /api/v1/trades/history — Get Trade History
**Params:** `account` (required), `symbol` (optional), `start_time` (optional), `limit` (default 100), `cursor` (optional)

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "history_id": 19329801,
      "order_id": 315293920,
      "client_order_id": "acf...",
      "symbol": "LDO",
      "amount": "0.1",
      "price": "1.1904",
      "entry_price": "1.176247",
      "fee": "0",
      "pnl": "-0.001415",
      "event_type": "fulfill_maker",
      "side": "close_short",
      "created_at": 1759215599188,
      "cause": "normal"
    }
  ],
  "next_cursor": "11111Z5RK",
  "has_more": true
}
```

### GET /api/v1/funding/history — Get Funding History
**Params:** `account` (required), `limit` (optional), `cursor` (optional)

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "history_id": 2287920,
      "symbol": "PUMP",
      "side": "ask",
      "amount": "39033804",
      "payout": "2.617479",
      "rate": "0.0000125",
      "created_at": 1759222804122
    }
  ],
  "next_cursor": "11114Lz77",
  "has_more": true
}
```

### GET /api/v1/portfolio — Get Account Equity History
**Params:** `account` (required), `time_range` (1d,7d,14d,30d,all), `start_time` (optional), `limit` (default 100)

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "account_equity": "61046.308885",
      "pnl": "9297.553505",
      "timestamp": 1761177600000
    }
  ],
  "error": null,
  "code": null
}
```

### GET /api/v1/account/balance/history — Get Balance History
**Params:** `account` (required), `limit` (optional), `cursor` (optional)

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "amount": "100.000000",
      "balance": "1200.000000",
      "pending_balance": "0.000000",
      "event_type": "deposit",
      "created_at": 1716200000000
    }
  ],
  "next_cursor": "11114Lz77",
  "has_more": true
}
```
Event types: `deposit`, `deposit_release`, `withdrawal`, `trade`, `market_liquidation`, `backstop_liquidation`, `adl`, `transfer`, `payout`

---

## Account (POST — Signed)

### POST /api/v1/account/leverage — Update Leverage
**Sign type:** `update_leverage`

**Request:**
```json
{
  "account": "42trU9A5...",
  "signature": "5j1Vy9Uq...",
  "timestamp": 1716200000000,
  "expiry_window": 5000,
  "symbol": "BTC",
  "leverage": 42
}
```

### POST /api/v1/account/margin — Update Margin Mode
**Sign type:** `update_margin_mode`

**Request:**
```json
{
  "account": "42trU9A5...",
  "signature": "...",
  "timestamp": 1716200000000,
  "expiry_window": 5000,
  "symbol": "BTC",
  "is_isolated": false
}
```

### POST /api/v1/account/withdraw — Request Withdrawal
**Sign type:** `withdraw`

**Request:**
```json
{
  "account": "42trU9A5...",
  "signature": "...",
  "timestamp": 1716200000000,
  "amount": "100.50",
  "expiry_window": 30000
}
```

---

## Orders (GET — no auth)

### GET /api/v1/orders — Get Open Orders
**Params:** `account` (required)

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "order_id": 315979358,
      "client_order_id": "add9a4b5-c7f7-4124-b57f-86982d86d479",
      "symbol": "ASTER",
      "side": "ask",
      "price": "1.836",
      "initial_amount": "85.33",
      "filled_amount": "0",
      "cancelled_amount": "0",
      "stop_price": null,
      "order_type": "limit",
      "stop_parent_order_id": null,
      "reduce_only": false,
      "created_at": 1759224706737,
      "updated_at": 1759224706737
    }
  ],
  "error": null,
  "code": null,
  "last_order_id": 1557370337
}
```
`order_type` values: `limit`, `market`, `stop_limit`, `stop_market`, `take_profit_limit`, `stop_loss_limit`, `take_profit_market`, `stop_loss_market`

### GET /api/v1/orders/history — Get Order History
**Params:** `account` (required), `limit` (default 100), `cursor` (optional)

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "order_id": 315992721,
      "client_order_id": "ade",
      "symbol": "XPL",
      "side": "ask",
      "initial_price": "1.0865",
      "average_filled_price": "0",
      "amount": "984",
      "filled_amount": "0",
      "order_status": "open",
      "order_type": "limit",
      "stop_price": null,
      "stop_parent_order_id": null,
      "reduce_only": false,
      "reason": null,
      "created_at": 1759224893638,
      "updated_at": 1759224893638
    }
  ],
  "next_cursor": "1111Hyd74",
  "has_more": true
}
```
`order_status`: `open`, `partially_filled`, `filled`, `cancelled`, `rejected`
`reason` (on cancel/reject): `cancel`, `force_cancel`, `expired`, `post_only_rejected`, `self_trade_prevented`

### GET /api/v1/orders/history_by_id — Get Order History By ID
**Params:** `order_id` (required)

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "history_id": 641452639,
      "order_id": 315992721,
      "client_order_id": "ade1aa6...",
      "symbol": "XPL",
      "side": "ask",
      "price": "1.0865",
      "initial_amount": "984",
      "filled_amount": "0",
      "cancelled_amount": "984",
      "event_type": "cancel",
      "order_type": "limit",
      "order_status": "cancelled",
      "stop_price": null,
      "stop_parent_order_id": null,
      "reduce_only": false,
      "created_at": 1759224895038
    }
  ],
  "error": null,
  "code": null
}
```
`event_type` values: `make`, `stop_created`, `twap_created`, `fulfill_market`, `fulfill_limit`, `adjust`, `stop_parent_order_filled`, `stop_triggered`, `stop_upgrade`, `twap_triggered`, `cancel`, `force_cancel`, `expired`, `post_only_rejected`, `self_trade_prevented`

### GET /api/v1/orders/twap — Get Open TWAP Orders
**Params:** `account` (required)

### GET /api/v1/orders/twap/history — Get TWAP History
**Params:** `account` (required)

### GET /api/v1/orders/twap/history_by_id — Get TWAP History By ID
**Params:** `order_id` (required)

---

## Orders (POST — Signed)

### POST /api/v1/orders/create — Create Limit Order
**Sign type:** `create_order`

**Request:**
```json
{
  "account": "42trU9A5...",
  "signature": "5j1Vy9Uq",
  "timestamp": 1716200000000,
  "expiry_window": 5000,
  "symbol": "BTC",
  "price": "50000",
  "amount": "0.1",
  "side": "bid",
  "tif": "GTC",
  "reduce_only": false,
  "client_order_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "take_profit": {
    "stop_price": "55000",
    "limit_price": "54950",
    "client_order_id": "e36ac10b-..."
  },
  "stop_loss": {
    "stop_price": "48000",
    "limit_price": "47950",
    "client_order_id": "d25ac10b-..."
  },
  "agent_wallet": null
}
```
TIF values: `GTC`, `IOC`, `ALO` (Post Only), `TOB` (Top of Book)

**Success response:** `{ "success": true, "data": { "order_id": 12345 }, "error": null, "code": null }`

Note: GTC and IOC orders subject to ~200ms speed bump.

### POST /api/v1/orders/create_market — Create Market Order
**Sign type:** `create_market_order`

**Request:**
```json
{
  "account": "42trU9A5...",
  "signature": "...",
  "timestamp": 1716200000000,
  "expiry_window": 5000,
  "symbol": "BTC",
  "amount": "0.1",
  "side": "bid",
  "slippage_percent": "0.5",
  "reduce_only": false,
  "client_order_id": "f47ac10b-...",
  "take_profit": { ... },
  "stop_loss": { ... },
  "agent_wallet": null
}
```
Note: ~200ms speed bump applies.

### POST /api/v1/orders/edit — Edit Order
**Sign type:** `edit_order`

**Request:**
```json
{
  "account": "42trU9A5...",
  "signature": "...",
  "timestamp": 1716200000000,
  "expiry_window": 5000,
  "symbol": "BTC",
  "price": "90000",
  "amount": "0.5",
  "order_id": 123456789
}
```
Note: Must provide `order_id` OR `client_order_id` (not both). Edit cancels original, creates new ALO order with new `order_id`. Not subject to speed bump.

### POST /api/v1/orders/cancel — Cancel Order
**Sign type:** `cancel_order`

**Request:**
```json
{
  "account": "42trU9A5...",
  "signature": "...",
  "timestamp": 1716200000000,
  "expiry_window": 5000,
  "symbol": "BTC",
  "order_id": 123
}
```
Can also use `client_order_id` instead. Not subject to speed bump.

### POST /api/v1/orders/cancel_all — Cancel All Orders
**Sign type:** `cancel_all_orders`

**Request:**
```json
{
  "account": "42trU9A5...",
  "signature": "...",
  "timestamp": 1716200000000,
  "expiry_window": 5000,
  "all_symbols": true,
  "exclude_reduce_only": false,
  "symbol": "BTC"
}
```
`symbol` required if `all_symbols` is false.

**Response:** `{ "success": true, "data": { "cancelled_count": 5 }, ... }`

### POST /api/v1/orders/stop/create — Create Stop Order
**Sign type:** `create_stop_order`

**Request:**
```json
{
  "account": "42trU9A5...",
  "signature": "...",
  "timestamp": 1716200000000,
  "expiry_window": 5000,
  "symbol": "BTC",
  "side": "long",
  "reduce_only": true,
  "stop_order": {
    "stop_price": "48000",
    "limit_price": "47950",
    "amount": "0.1",
    "client_order_id": "d25ac10b-..."
  }
}
```

### POST /api/v1/orders/stop/cancel — Cancel Stop Order
**Sign type:** `cancel_stop_order`

**Request:**
```json
{
  "account": "42trU9A5...",
  "signature": "...",
  "timestamp": 1716200000000,
  "expiry_window": 5000,
  "symbol": "BTC",
  "order_id": 123
}
```

### POST /api/v1/positions/tpsl — Set Position TP/SL
**Sign type:** `set_position_tpsl`

**Request:**
```json
{
  "account": "42trU9A5...",
  "signature": "...",
  "timestamp": 1716200000000,
  "expiry_window": 5000,
  "symbol": "BTC",
  "side": "ask",
  "take_profit": {
    "stop_price": "120000",
    "limit_price": "120300",
    "amount": "0.1",
    "client_order_id": "..."
  },
  "stop_loss": {
    "stop_price": "99800"
  }
}
```

### POST /api/v1/orders/batch — Batch Orders
Max 10 actions. Each action signed independently. Actions: `Create` or `Cancel`.

**Request:**
```json
{
  "actions": [
    { "type": "Create", "data": { ...create_order_request... } },
    { "type": "Cancel", "data": { ...cancel_order_request... } }
  ]
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "results": [
      { "success": true, "order_id": 470506, "error": null },
      { "success": true }
    ]
  },
  "error": null,
  "code": null
}
```

### POST /api/v1/orders/twap/create — Create TWAP Order
**Sign type:** `create_twap_order`

**Request:**
```json
{
  "account": "...",
  "signature": "...",
  "timestamp": ...,
  "expiry_window": 5000,
  "symbol": "BTC",
  "reduce_only": false,
  "amount": "1",
  "side": "bid",
  "slippage_percent": "0.5",
  "duration_in_seconds": 180,
  "client_order_id": "..."
}
```

### POST /api/v1/orders/twap/cancel — Cancel TWAP Order
**Sign type:** `cancel_twap_order`

---

## Subaccounts (POST — Signed)

### POST /api/v1/account/subaccount/create — Create Subaccount
Cross-signature scheme: sub signs main pubkey, main signs sub's signature.

**Sign types:** `subaccount_initiate` (sub signs), `subaccount_confirm` (main signs)

**Request:**
```json
{
  "main_account": "42trU9A5...",
  "subaccount": "69trU9A5...",
  "main_signature": "5j1Vy9Uq...",
  "sub_signature": "4k2Wx8Zq...",
  "timestamp": 1716200000000,
  "expiry_window": 5000
}
```

**Response:** `{ "success": true, "data": null, "error": null, "code": null }`

### POST /api/v1/account/subaccount/list — List Subaccounts
**Sign type:** `list_subaccounts`

**Response:**
```json
{
  "success": true,
  "data": {
    "subaccounts": [
      {
        "address": "69txU9As...",
        "balance": "1000.50",
        "pending_balance": "0.00",
        "fee_level": 1,
        "fee_mode": "auto",
        "use_ltp_for_stop_orders": false,
        "created_at": 1716200000000
      }
    ]
  },
  "error": null,
  "code": null
}
```

### POST /api/v1/account/subaccount/transfer — Transfer Funds
**Sign type:** `transfer_funds`

**Request:**
```json
{
  "account": "AwX6321...",
  "signature": "...",
  "timestamp": 1749228826313,
  "expiry_window": 5000,
  "to_account": "CRTxBM...",
  "amount": "420.69"
}
```

---

## Agent Wallet (POST — Signed)

### POST /api/v1/agent/bind — Bind Agent Wallet
**Sign type:** `bind_agent_wallet`
**Payload:** `{ "agent_wallet": "..." }`

### POST /api/v1/agent/list — List Agent Wallets
**Sign type:** `list_agent_wallets`
**Payload:** `{}`

### POST /api/v1/agent/revoke — Revoke Agent Wallet
**Sign type:** `revoke_agent_wallet`
**Payload:** `{ "agent_wallet": "..." }`

### POST /api/v1/agent/revoke_all — Revoke All Agent Wallets
**Sign type:** `revoke_all_agent_wallets`
**Payload:** `{}`

### POST /api/v1/agent/ip_whitelist/list — List IP Whitelist
**Sign type:** `list_agent_ip_whitelist`
**Payload:** `{ "api_agent_key": "..." }`

### POST /api/v1/agent/ip_whitelist/add — Add IP to Whitelist
**Sign type:** `add_agent_whitelisted_ip`
**Payload:** `{ "agent_wallet": "...", "ip_address": "..." }`

### POST /api/v1/agent/ip_whitelist/remove — Remove IP from Whitelist
**Sign type:** `remove_agent_whitelisted_ip`
**Payload:** `{ "agent_wallet": "...", "ip_address": "..." }`

### POST /api/v1/agent/ip_whitelist/toggle — Toggle IP Whitelist
**Sign type:** `set_agent_ip_whitelist_enabled`
**Payload:** `{ "agent_wallet": "...", "enabled": true|false }`

---

## API Config Keys (POST — Signed)

### POST /api/v1/account/api_keys/create — Create API Key
**Sign type:** `create_api_key`
**Payload:** `{}`
**Response:** `{ "data": { "api_key": "AbCdEfGh_2mT8x..." } }`

### POST /api/v1/account/api_keys/revoke — Revoke API Key
**Sign type:** `revoke_api_key`
**Payload:** `{ "api_key": "..." }`

### POST /api/v1/account/api_keys — List API Keys
**Sign type:** `list_api_keys`
**Payload:** `{}`

Usage: Add `PF-API-KEY` header to REST/WS requests.

---

## Lake (POST — Signed)

### POST /api/v1/lake/create — Create Lake
**Sign type:** `create_lake`
**Payload:** `{ "manager": "...", "nickname": "..." }`

### POST /api/v1/lake/deposit — Deposit to Lake
**Sign type:** `deposit_to_lake`
**Payload:** `{ "lake": "...", "amount": "100000" }`

### POST /api/v1/lake/withdraw — Withdraw from Lake
**Sign type:** `withdraw_from_lake`
**Payload:** `{ "lake": "...", "shares": "100" }`
