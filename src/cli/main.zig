// ╔═══════════════════════════════════════════════════════════════╗
// ║  regatta — Pacifica DEX CLI                                   ║
// ╚═══════════════════════════════════════════════════════════════╝

const std = @import("std");
const args_mod = @import("args.zig");
const config_mod = @import("config.zig");
const output_mod = @import("output.zig");
const commands = @import("commands.zig");

const Style = output_mod.Style;
const VERSION = "0.0.2";

const EXIT_OK: u8 = 0;
const EXIT_ERROR: u8 = 1;
const EXIT_USAGE: u8 = 2;
const EXIT_AUTH: u8 = 3;
const EXIT_NETWORK: u8 = 4;

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const result = args_mod.parse(allocator) catch |e| {
        const wants_json = blk: {
            if (!std.posix.isatty(std.fs.File.stdout().handle)) break :blk true;
            var raw = std.process.argsWithAllocator(allocator) catch break :blk false;
            defer raw.deinit();
            while (raw.next()) |a| {
                if (std.mem.eql(u8, a, "--json")) break :blk true;
            }
            break :blk false;
        };
        if (wants_json) {
            var w = output_mod.Writer.init(.json);
            w.cmd = "unknown";
            w.start_ns = std.time.nanoTimestamp();
            const name = @errorName(e);
            var buf: [512]u8 = undefined;
            const s = std.fmt.bufPrint(&buf,
                \\{{"v":1,"status":"error","cmd":"unknown","error":"{s}","message":"","hint":"run `regatta help` for usage","timing_ms":0}}
            , .{name}) catch "";
            w.rawJson(s) catch {};
        } else {
            var w = output_mod.Writer.init(.pretty);
            switch (e) {
                error.MissingArgument => w.err("missing required argument. Run `regatta help` for usage.") catch {},
                error.UnknownCommand => w.err("unknown command. Run `regatta help` for usage.") catch {},
                error.InvalidFlag => w.err("invalid flag value. Run `regatta help` for usage.") catch {},
            }
        }
        std.process.exit(EXIT_USAGE);
    };

    const flags = result.flags;

    var config = config_mod.load(allocator, flags);
    defer config.deinit();

    var w = output_mod.Writer.initAuto(flags.output, flags.output_explicit);
    w.quiet = flags.quiet;

    const cmd = result.command orelse {
        printHelp(&w) catch {};
        return;
    };

    const cmd_name: []const u8 = switch (cmd) {
        .balance_history => "balance-history",
        .api_key => "api-key",
        else => @tagName(cmd),
    };
    if (w.format == .json) {
        w.cmd = cmd_name;
        w.start_ns = std.time.nanoTimestamp();
    }

    switch (cmd) {
        .help => |a| {
            if (a.topic) |t| {
                printTopicHelp(&w, t) catch {};
            } else {
                printHelp(&w) catch {};
            }
        },
        .version => printVersion(&w) catch {},
        .keys => |a| commands.keysCmd(allocator, &w, a) catch |e| exit(&w, cmd_name, e),
        .info => commands.info(allocator, &w, config) catch |e| exit(&w, cmd_name, e),
        .prices => commands.prices(allocator, &w, config) catch |e| exit(&w, cmd_name, e),
        .book => |a| commands.book(allocator, &w, config, a) catch |e| exit(&w, cmd_name, e),
        .candles => |a| commands.candles(allocator, &w, config, a) catch |e| exit(&w, cmd_name, e),
        .account => |a| commands.account(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .positions => |a| commands.positionsCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .orders => |a| commands.ordersCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .history => |a| commands.historyCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .trades => |a| commands.tradesCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .funding => |a| commands.fundingCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .balance_history => |a| commands.balanceHistoryCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .equity => |a| commands.equityCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .buy => |a| commands.placeOrder(allocator, &w, &config, a, true) catch |e| exit(&w, cmd_name, e),
        .sell => |a| commands.placeOrder(allocator, &w, &config, a, false) catch |e| exit(&w, cmd_name, e),
        .cancel => |a| commands.cancelOrder(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .leverage => |a| commands.leverageCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .edit => |a| commands.editOrder(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .margin => |a| commands.marginCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .deposit => |a| commands.depositCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .withdraw => |a| commands.withdrawCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .stop => |a| commands.stopCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .tpsl => |a| commands.tpslCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .twap => |a| commands.twapCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .agent => |a| commands.agentCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .subaccount => |a| commands.subaccountCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .api_key => |a| commands.apiKeyCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .lake => |a| commands.lakeCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .access => |a| commands.accessCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .stream => |a| commands.streamCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
        .batch => |a| commands.batchCmd(allocator, &w, &config, a) catch |e| exit(&w, cmd_name, e),
    }
}

fn exit(w: *output_mod.Writer, cmd: []const u8, e: anyerror) void {
    const code: u8 = switch (e) {
        error.MissingKey, error.MissingAddress => EXIT_AUTH,
        error.MissingArgument, error.InvalidFlag => EXIT_USAGE,
        error.ConnectionFailed, error.ConnectionRefused, error.BrokenPipe => EXIT_NETWORK,
        error.CommandFailed => EXIT_ERROR,
        else => EXIT_ERROR,
    };

    if (e == error.CommandFailed) {
        std.process.exit(code);
    }

    if (w.format == .json) {
        var buf: [2048]u8 = undefined;
        const name = @errorName(e);
        const hint: []const u8 = switch (e) {
            error.MissingKey => "set PACIFICA_KEY env var or pass --key",
            error.MissingAddress => "set PACIFICA_ADDRESS env var or pass --address",
            error.MissingArgument => "run `regatta help` for usage",
            error.ConnectionFailed => "check network / API endpoint",
            else => "",
        };
        var msg_buf: [1024]u8 = undefined;
        const msg = jsonEscape(w.exitMessage() orelse "", &msg_buf);
        const ms = w.elapsedMs();
        const s = std.fmt.bufPrint(&buf,
            \\{{"v":1,"status":"error","cmd":"{s}","error":"{s}","message":"{s}","hint":"{s}","timing_ms":{d}}}
        , .{ cmd, name, msg, hint, ms }) catch return;
        w.rawJson(s) catch {};
    } else {
        w.errFmt("{s}: {s}", .{ cmd, @errorName(e) }) catch {};
    }

    std.process.exit(code);
}

fn jsonEscape(input: []const u8, buf: []u8) []const u8 {
    var i: usize = 0;
    for (input) |c| {
        switch (c) {
            '"' => {
                if (i + 2 > buf.len) break;
                buf[i] = '\\';
                buf[i + 1] = '"';
                i += 2;
            },
            '\\' => {
                if (i + 2 > buf.len) break;
                buf[i] = '\\';
                buf[i + 1] = '\\';
                i += 2;
            },
            '\n' => {
                if (i + 2 > buf.len) break;
                buf[i] = '\\';
                buf[i + 1] = 'n';
                i += 2;
            },
            '\r' => {
                if (i + 2 > buf.len) break;
                buf[i] = '\\';
                buf[i + 1] = 'r';
                i += 2;
            },
            '\t' => {
                if (i + 2 > buf.len) break;
                buf[i] = '\\';
                buf[i + 1] = 't';
                i += 2;
            },
            else => {
                if (c < 0x20) {
                    if (i + 6 > buf.len) break;
                    const hex = "0123456789abcdef";
                    buf[i] = '\\';
                    buf[i + 1] = 'u';
                    buf[i + 2] = '0';
                    buf[i + 3] = '0';
                    buf[i + 4] = hex[c >> 4];
                    buf[i + 5] = hex[c & 0xf];
                    i += 6;
                } else {
                    if (i >= buf.len) break;
                    buf[i] = c;
                    i += 1;
                }
            },
        }
    }
    return buf[0..i];
}

fn printVersion(w: *output_mod.Writer) !void {
    if (w.format == .json) {
        try w.jsonRaw("{\"version\":\"" ++ VERSION ++ "\"}");
    } else {
        try w.print("regatta {s}\n", .{VERSION});
    }
}

fn printHelp(w: *output_mod.Writer) !void {
    try w.styled(Style.bold_cyan,
        \\
        \\  \xe2\x96\x88\xe2\x96\x88\xe2\x96\x88\xe2\x96\x88\xe2\x96\x88
        \\  \xe2\x96\x88\xe2\x96\x84\xe2\x96\x84\xe2\x96\x84\xe2\x96\x88
        \\  \xe2\x96\x88  \xe2\x96\x88\xe2\x96\x84
        \\
    );
    try w.print("  Pacifica DEX CLI v{s}\n\n", .{VERSION});

    try w.styled(Style.bold_white, "USAGE\n");
    try w.print("  regatta <command> [args] [flags]\n\n", .{});

    try w.styled(Style.bold_white, "MARKET DATA\n");
    try w.print(
        \\  info                             All market specs (tick/lot size, leverage)
        \\  prices                           All prices (mark, oracle, funding, OI)
        \\  book <SYMBOL>                    Orderbook (10 levels)
        \\  candles <SYMBOL> [--interval 1h] Candle data
        \\
        \\
    , .{});

    try w.styled(Style.bold_white, "ACCOUNT\n");
    try w.print(
        \\  account [ADDR]                   Balance, equity, fees
        \\  positions [ADDR]                 Open positions
        \\  orders [ADDR]                    Open orders
        \\  history [ADDR]                   Order history
        \\  trades [ADDR]                    Trade history
        \\  funding [ADDR]                   Funding history
        \\  balance-history [ADDR]           Balance events
        \\  equity [ADDR] [--range 7d]       Equity over time
        \\
        \\
    , .{});

    try w.styled(Style.bold_white, "TRADING\n");
    try w.print(
        \\  buy <SYM> <AMT> [@PRICE]         Limit (with @) or market buy
        \\  sell <SYM> <AMT> [@PRICE]         Limit (with @) or market sell
        \\  cancel <SYM> [ORDER_ID]           Cancel order
        \\  cancel --all [--symbol SYM]       Cancel all orders
        \\  edit <SYM> <OID> <PRICE> <AMT>    Edit existing order
        \\  leverage <SYM> [N]                Query or set leverage
        \\  margin <SYM> --isolated|--cross   Set margin mode
        \\  deposit solana <AMOUNT> [--rpc URL]
        \\  stop <SYM> --side long --stop-price P [--limit-price P]
        \\  tpsl <SYM> <SIDE> --tp P --sl P   Set TP/SL on position
        \\
        \\
    , .{});

    try w.styled(Style.bold_white, "TRADING FLAGS\n");
    try w.print(
        \\  --reduce-only             Reduce-only order
        \\  --tif <GTC|IOC|ALO|TOB>   Time-in-force (default: GTC)
        \\  --slippage <PCT>          Max slippage for market orders
        \\  --dry-run, -n             Preview signed request without sending
        \\
        \\
    , .{});

    try w.styled(Style.bold_white, "TWAP\n");
    try w.print(
        \\  twap <SYM> buy|sell <AMT> --duration <SECS> --slippage <PCT>
        \\  twap cancel <SYM> <OID>
        \\  twap list [ADDR]
        \\  twap history [ADDR]
        \\
        \\
    , .{});

    try w.styled(Style.bold_white, "STREAMING\n");
    try w.print(
        \\  stream prices                    All prices
        \\  stream book <SYMBOL>             Orderbook updates
        \\  stream bbo <SYMBOL>              Best bid / offer updates
        \\  stream trades <SYMBOL>           Public trade feed
        \\  stream candle <SYM> --interval 1m
        \\  stream mark-candle <SYM> --interval 1m
        \\  stream margin [ADDR]             Account margin updates
        \\  stream leverage [ADDR]           Account leverage updates
        \\  stream account [ADDR]            Account info updates
        \\  stream positions [ADDR]          Position updates
        \\  stream orders [ADDR]             Order updates
        \\  stream account-trades [ADDR]     Account trade updates
        \\  stream twap [ADDR]               TWAP snapshots
        \\  stream twap-updates [ADDR]       TWAP order updates
        \\
        \\
    , .{});

    try w.styled(Style.bold_white, "AGENT WALLETS\n");
    try w.print(
        \\  agent bind <ADDR>                Bind agent wallet
        \\  agent list                       List agent wallets
        \\  agent revoke <ADDR>              Revoke agent
        \\  agent revoke-all                 Revoke all agents
        \\  agent ip-list <AGENT>            List IP whitelist
        \\  agent ip-add <AGENT> <IP>        Add whitelisted IP
        \\  agent ip-remove <AGENT> <IP>     Remove whitelisted IP
        \\  agent ip-toggle <AGENT> --enable|--disable
        \\
        \\
    , .{});

    try w.styled(Style.bold_white, "KEYS\n");
    try w.print(
        \\  keys ls                         List encrypted local keys
        \\  keys new <NAME>                 Generate new encrypted key
        \\  keys import <NAME>              Import base58 Solana keypair
        \\  keys export <NAME>              Export decrypted base58 keypair
        \\  keys rm <NAME>                  Remove key
        \\  keys default <NAME>             Set default key
        \\
        \\
    , .{});

    try w.styled(Style.bold_white, "ACCOUNT MANAGEMENT\n");
    try w.print(
        \\  access claim <CODE>              Claim beta access code
        \\  access status [ADDR]             Check beta access status
        \\  subaccount create <KEY>          Create subaccount
        \\  subaccount list                  List subaccounts
        \\  subaccount transfer <AMT> --to <ADDR>
        \\  withdraw <AMOUNT>                Withdraw funds
        \\  api-key create                   Create API key
        \\  api-key revoke <KEY>             Revoke API key
        \\  api-key list                     List API keys
        \\  lake create [--nickname NAME]    Create lake
        \\  lake deposit <ADDR> <AMT>        Deposit to lake
        \\  lake withdraw <ADDR> <SHARES>    Withdraw from lake
        \\
        \\
    , .{});

    try w.styled(Style.bold_white, "BATCH\n");
    try w.print(
        \\  batch "buy BTC 0.1 @100000" "sell ETH 1.0"
        \\  batch --stdin                    Read from stdin
        \\
        \\
    , .{});

    try w.styled(Style.bold_white, "GLOBAL FLAGS\n");
    try w.print(
        \\  --json                    Force JSON output
        \\  --quiet, -q               Minimal output
        \\  --chain testnet           Use testnet
        \\  --dry-run, -n             Preview without sending
        \\  --key <BASE58>            Private key (prefer keystore/env)
        \\  --key-name <NAME>         Use named keystore key
        \\  --address <BASE58>        Account address
        \\  --agent-wallet <ADDR>     Sign as agent wallet
        \\  --ws                      Use WebSocket transport where supported
        \\
        \\
    , .{});

    try w.styled(Style.bold_white, "ENVIRONMENT\n");
    try w.print(
        \\  PACIFICA_KEY              Solana keypair (base58)
        \\  PACIFICA_KEY_NAME         Named keystore key
        \\  PACIFICA_PASSWORD         Keystore password
        \\  PACIFICA_API_KEY          Optional WebSocket API header
        \\  PACIFICA_ADDRESS          Default account address
        \\  PACIFICA_CHAIN            Default chain (mainnet|testnet)
        \\  SOLANA_RPC_URL            Solana RPC for on-chain deposit
        \\  NO_COLOR                  Disable colored output
        \\
        \\
    , .{});

    try w.styled(Style.bold_white, "EXIT CODES\n");
    try w.print(
        \\  0  Success
        \\  1  Error
        \\  2  Usage error (bad args)
        \\  3  Auth error (missing key/address)
        \\  4  Network error (retryable)
        \\
        \\
    , .{});

    try w.styled(Style.bold_white, "EXAMPLES\n");
    try w.print(
        \\  regatta prices                              All prices
        \\  regatta buy BTC 0.1 @100000                 Limit buy
        \\  regatta sell ETH 1.0                        Market sell
        \\  regatta deposit solana 100                  Deposit 100 USDC on Solana
        \\  regatta cancel BTC --all                    Cancel all BTC orders
        \\  regatta positions --json | jq '.data'       Pipe to jq
        \\  regatta buy BTC 0.1 @95000 --dry-run        Preview order
        \\  regatta stream prices                       Real-time prices
        \\
        \\
    , .{});

    try w.styled(Style.muted, "  Aliases: long=buy short=sell pos=positions ord=orders acc=account\n");
    try w.styled(Style.muted, "  Auto-JSON when piped: regatta prices | jq\n\n");
}

fn printTopicHelp(w: *output_mod.Writer, topic: []const u8) !void {
    if (std.mem.eql(u8, topic, "keys") or std.mem.eql(u8, topic, "key")) {
        try w.print(
            \\USAGE
            \\  regatta keys ls
            \\  regatta keys new <NAME> --password <PASS>
            \\  regatta keys import <NAME> --private-key <BASE58> --password <PASS>
            \\  regatta keys export <NAME> --password <PASS>
            \\  regatta keys rm <NAME>
            \\  regatta keys default <NAME>
            \\
            \\ENV
            \\  PACIFICA_KEY_NAME   Use named keystore entry for normal commands
            \\  PACIFICA_PASSWORD   Password used to decrypt the keystore
            \\
            \\NOTES
            \\  Keystores are stored under ~/.regatta/keys/
            \\  Raw --key / PACIFICA_KEY still work, but keystore is preferred for local use.
            \\
        , .{});
    } else if (std.mem.eql(u8, topic, "buy") or std.mem.eql(u8, topic, "sell")) {
        try w.print(
            \\USAGE
            \\  regatta buy <SYMBOL> <AMOUNT> [@PRICE]
            \\  regatta sell <SYMBOL> <AMOUNT> [@PRICE]
            \\
            \\  With @PRICE: limit order. Without: market order.
            \\
            \\FLAGS
            \\  --reduce-only     Reduce-only order
            \\  --tif <GTC|IOC|ALO|TOB>  Time-in-force
            \\  --slippage <PCT>  Max slippage (market orders)
            \\  --dry-run, -n     Preview without sending
            \\
            \\EXAMPLES
            \\  regatta buy BTC 0.1 @100000    Limit buy 0.1 BTC at $100k
            \\  regatta sell ETH 1.0           Market sell 1 ETH
            \\  regatta buy BTC 0.5 --dry-run  Preview market buy
            \\
        , .{});
    } else {
        try w.print("No help available for '{s}'. Run `regatta help` for all commands.\n", .{topic});
    }
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  Tests                                                        ║
// ╚═══════════════════════════════════════════════════════════════╝

test "jsonEscape: special characters in error messages" {
    var buf: [256]u8 = undefined;
    // Quotes and backslashes must be escaped for valid JSON
    try std.testing.expectEqualStrings("\\\"hi\\\"", jsonEscape("\"hi\"", &buf));
    try std.testing.expectEqualStrings("a\\\\b", jsonEscape("a\\b", &buf));
    // Whitespace control chars → escape sequences
    try std.testing.expectEqualStrings("a\\nb\\rc\\td", jsonEscape("a\nb\rc\td", &buf));
    // Low control chars → \u00XX
    try std.testing.expectEqualStrings("a\\u0001b", jsonEscape("a\x01b", &buf));
}
