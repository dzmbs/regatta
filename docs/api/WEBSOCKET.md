# Pacifica WebSocket API Reference

> Source: https://pacifica.gitbook.io/docs/api-documentation/api/websocket
> Scraped: 2026-03-06

**Mainnet:** `wss://ws.pacifica.fi/ws`
**Testnet:** `wss://test-ws.pacifica.fi/ws`

## Connection Management

- Connection closed if no message for 60 seconds
- Connection closed after 24 hours alive
- Heartbeat: send `{"method":"ping"}`, receive `{"method":"pong"}`
- Max 300 concurrent connections per IP
- Max 20 subscriptions per channel per connection
- API Config Key: add `extra_headers={"PF-API-KEY": "your_key"}` to connection

## Subscribe / Unsubscribe

```json
{ "method": "subscribe", "params": { "source": "...", ... } }
{ "method": "unsubscribe", "params": { "source": "...", ... } }
```

---

## Subscription Channels

### prices
```json
{ "method": "subscribe", "params": { "source": "prices" } }
```
Streams all symbol prices. No account needed.

### orderbook
```json
{ "method": "subscribe", "params": { "source": "orderbook", "symbol": "BTC" } }
```

### bbo (Best Bid Offer)
```json
{ "method": "subscribe", "params": { "source": "bbo", "symbol": "BTC" } }
```

### trades
```json
{ "method": "subscribe", "params": { "source": "trades", "symbol": "BTC" } }
```

### candle
```json
{ "method": "subscribe", "params": { "source": "candle", "symbol": "BTC", "interval": "1m" } }
```

### mark_price_candle
```json
{ "method": "subscribe", "params": { "source": "mark_price_candle", "symbol": "BTC", "interval": "1m" } }
```

### account_margin
```json
{ "method": "subscribe", "params": { "source": "account_margin", "account": "..." } }
```

### account_leverage
```json
{ "method": "subscribe", "params": { "source": "account_leverage", "account": "..." } }
```

### account_info
```json
{ "method": "subscribe", "params": { "source": "account_info", "account": "..." } }
```

### account_positions
```json
{ "method": "subscribe", "params": { "source": "account_positions", "account": "..." } }
```

### account_order_updates
```json
{ "method": "subscribe", "params": { "source": "account_order_updates", "account": "..." } }
```

### account_trades
```json
{ "method": "subscribe", "params": { "source": "account_trades", "account": "..." } }
```

### account_twap_orders (from python-sdk)
```json
{ "method": "subscribe", "params": { "source": "account_twap_orders", "account": "..." } }
```

### account_twap_order_updates (from python-sdk)
```json
{ "method": "subscribe", "params": { "source": "account_twap_order_updates", "account": "..." } }
```

---

## Trading Operations via WebSocket

All WS trading operations use this envelope:
```json
{
  "id": "unique-request-id",
  "params": {
    "<operation_name>": {
      ...signed_request_payload...
    }
  }
}
```

The signed request payload is identical to the REST body (same signing, same fields).

### create_market_order
```json
{
  "id": "uuid",
  "params": {
    "create_market_order": {
      "account": "...",
      "signature": "...",
      "timestamp": ...,
      "expiry_window": 5000,
      "symbol": "BTC",
      "amount": "0.1",
      "side": "bid",
      "slippage_percent": "0.5",
      "reduce_only": false,
      "client_order_id": "..."
    }
  }
}
```

### create_order (limit)
```json
{
  "id": "uuid",
  "params": {
    "create_order": {
      "account": "...",
      "signature": "...",
      "timestamp": ...,
      "expiry_window": 5000,
      "symbol": "BTC",
      "price": "100000",
      "amount": "0.1",
      "side": "bid",
      "tif": "GTC",
      "reduce_only": false,
      "client_order_id": "..."
    }
  }
}
```

### edit_order
```json
{
  "id": "uuid",
  "params": {
    "edit_order": {
      "account": "...",
      "signature": "...",
      "timestamp": ...,
      "expiry_window": 5000,
      "symbol": "BTC",
      "price": "90000",
      "amount": "0.5",
      "order_id": 123456789
    }
  }
}
```

### cancel_order
```json
{
  "id": "uuid",
  "params": {
    "cancel_order": {
      "account": "...",
      "signature": "...",
      "timestamp": ...,
      "expiry_window": 5000,
      "symbol": "BTC",
      "order_id": 42069
    }
  }
}
```

### cancel_all_orders
```json
{
  "id": "uuid",
  "params": {
    "cancel_all_orders": {
      "account": "...",
      "signature": "...",
      "timestamp": ...,
      "expiry_window": 5000,
      "all_symbols": true,
      "exclude_reduce_only": false
    }
  }
}
```

### batch_order
```json
{
  "id": "uuid",
  "params": {
    "batch": {
      "actions": [
        { "type": "Create", "data": { ...create_order_request... } },
        { "type": "Cancel", "data": { ...cancel_order_request... } }
      ]
    }
  }
}
```

## WS Response Rate Limit Info
Action responses include `"rl"` field:
```json
{ "rl": { "r": 1200, "q": 1250, "t": 32 } }
```
- `r` = remaining credits (×10)
- `q` = quota (×10)
- `t` = time until reset
