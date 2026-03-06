# Pacifica Rate Limits

> Source: https://pacifica.gitbook.io/docs/api-documentation/api/rate-limits
> Scraped: 2026-03-06

## System
- Credit-based rate limiting with 60-second rolling window
- Credits shared across main account + all subaccounts
- Higher fee tier = higher rate limits
- HTTP 429 when credits exhausted

## REST Response Headers
```
ratelimit: "credits";r=1200;t=32
ratelimit-policy: "credits";q=1250;w=60
```
- `r` = remaining credits (×10 for fractional support)
- `q` = quota (×10)
- `t` = seconds until oldest credit expires
- `w` = window size (60s)

## WebSocket
- Max 300 concurrent connections per IP
- Max 20 subscriptions per channel per connection
- Rate limit info in `"rl"` field of action responses

## API Config Keys
- Created via `/api/v1/account/api_keys/create`
- Max 5 per account
- Format: `{8_char_prefix}_{base58_encoded_uuid}`
- Usage: `PF-API-KEY` header in REST, `extra_headers` in WS connection
- Allows provisioned higher limits for verified users

## Error Codes
- 400: Bad Request
- 403: Forbidden (geo-restricted)
- 422: Business Logic Error
- 429: Rate Limit Exceeded
- 500: Internal Server Error

### Business Logic Errors (422)
- POSITION_TPSL_LIMIT_EXCEEDED
- UNAUTHORIZED_REQUEST_CODE
- (and others — see docs for full list)

## Market Symbols
- CASE SENSITIVE: `BTC` ✓, `btc` ✗, `Btc` ✗
- Lowercase prefix exception: `kBONK`, `kPEPE`

## Tick and Lot Size
- `price` must be multiple of `tick_size`
- `amount` must be multiple of `lot_size`
- Invalid rounding returns Status 500
- Use `/api/v1/info` to get exact tick/lot sizes per market

## Last Order ID
- Exchange-wide nonce in trading responses
- Sequential, not subject to clock drift
- Use to order events across different endpoints
