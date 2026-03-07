// ╔═══════════════════════════════════════════════════════════════╗
// ║  Argument parser — manual, zero deps, fast                    ║
// ╚═══════════════════════════════════════════════════════════════╝

const std = @import("std");

pub const Command = union(enum) {
    keys: KeysArgs,
    buy: OrderArgs,
    sell: OrderArgs,
    cancel: CancelArgs,
    edit: EditArgs,
    info: void,
    prices: void,
    book: BookArgs,
    candles: CandleArgs,
    account: AddrArg,
    positions: AddrArg,
    orders: AddrArg,
    history: HistoryArgs,
    trades: HistoryArgs,
    funding: HistoryArgs,
    balance_history: HistoryArgs,
    equity: EquityArgs,
    leverage: LeverageArgs,
    margin: MarginArgs,
    deposit: DepositArgs,
    transfer: TransferArgs,
    withdraw: WithdrawArgs,
    stop: StopArgs,
    tpsl: TpSlArgs,
    twap: TwapArgs,
    agent: AgentArgs,
    subaccount: SubaccountArgs,
    api_key: ApiKeyArgs,
    lake: LakeArgs,
    access: AccessArgs,
    stream: StreamArgs,
    batch: BatchArgs,
    help: HelpArgs,
    version: void,
};

// ── Arg structs ───────────────────────────────────────────────

pub const OrderArgs = struct {
    symbol: []const u8,
    amount: []const u8,
    price: ?[]const u8 = null,
    slippage: ?[]const u8 = null,
    reduce_only: bool = false,
    tif: []const u8 = "GTC",
    dry_run: bool = false,
};

pub const CancelArgs = struct {
    symbol: ?[]const u8 = null,
    order_id: ?[]const u8 = null,
    client_order_id: ?[]const u8 = null,
    all: bool = false,
};

pub const EditArgs = struct {
    symbol: []const u8,
    order_id: []const u8,
    price: []const u8,
    amount: []const u8,
};

pub const AddrArg = struct {
    address: ?[]const u8 = null,
};

pub const BookArgs = struct {
    symbol: []const u8,
};

pub const CandleArgs = struct {
    symbol: []const u8,
    interval: []const u8 = "1h",
    start: ?[]const u8 = null,
    end: ?[]const u8 = null,
};

pub const HistoryArgs = struct {
    address: ?[]const u8 = null,
    symbol: ?[]const u8 = null,
    limit: ?[]const u8 = null,
    cursor: ?[]const u8 = null,
};

pub const EquityArgs = struct {
    address: ?[]const u8 = null,
    range: []const u8 = "7d",
};

pub const LeverageArgs = struct {
    symbol: []const u8,
    leverage: ?[]const u8 = null,
};

pub const MarginArgs = struct {
    symbol: []const u8,
    isolated: bool = false,
};

pub const DepositArgs = struct {
    network: []const u8 = "solana",
    amount: ?[]const u8 = null,
    rpc_url: ?[]const u8 = null,
};

pub const TransferArgs = struct {
    network: []const u8 = "solana",
    asset: ?[]const u8 = null,
    amount: ?[]const u8 = null,
    to: ?[]const u8 = null,
    rpc_url: ?[]const u8 = null,
};

pub const WithdrawArgs = struct {
    amount: []const u8,
};

pub const StopArgs = struct {
    action: StopAction = .create,
    symbol: []const u8 = "",
    side: ?[]const u8 = null,
    stop_price: ?[]const u8 = null,
    limit_price: ?[]const u8 = null,
    amount: ?[]const u8 = null,
    order_id: ?[]const u8 = null,
    dry_run: bool = false,
};

pub const StopAction = enum { create, cancel };

pub const TpSlArgs = struct {
    symbol: []const u8,
    side: []const u8,
    tp: ?[]const u8 = null,
    tp_limit: ?[]const u8 = null,
    tp_amount: ?[]const u8 = null,
    sl: ?[]const u8 = null,
    sl_limit: ?[]const u8 = null,
    dry_run: bool = false,
};

pub const TwapArgs = struct {
    action: TwapAction = .create,
    symbol: []const u8 = "",
    side: ?[]const u8 = null,
    amount: ?[]const u8 = null,
    duration: ?[]const u8 = null,
    slippage: ?[]const u8 = null,
    order_id: ?[]const u8 = null,
    address: ?[]const u8 = null,
    dry_run: bool = false,
};

pub const TwapAction = enum { create, cancel, list, history };

pub const AgentArgs = struct {
    action: AgentAction = .list,
    agent_addr: ?[]const u8 = null,
    ip: ?[]const u8 = null,
    enable: ?bool = null,
};

pub const AgentAction = enum { bind, list, revoke, revoke_all, ip_list, ip_add, ip_remove, ip_toggle };

pub const SubaccountArgs = struct {
    action: SubaccountAction = .list,
    key_or_addr: ?[]const u8 = null,
    amount: ?[]const u8 = null,
};

pub const SubaccountAction = enum { create, list, transfer };

pub const ApiKeyArgs = struct {
    action: ApiKeyAction = .list,
    key: ?[]const u8 = null,
};

pub const ApiKeyAction = enum { create, revoke, list };

pub const LakeArgs = struct {
    action: LakeAction = .create,
    addr: ?[]const u8 = null,
    amount: ?[]const u8 = null,
    nickname: ?[]const u8 = null,
    manager: ?[]const u8 = null,
};

pub const LakeAction = enum { create, deposit, withdraw };

pub const AccessArgs = struct {
    action: AccessAction = .status,
    code: ?[]const u8 = null,
    address: ?[]const u8 = null,
};

pub const AccessAction = enum { claim, status };

pub const StreamArgs = struct {
    kind: StreamKind = .prices,
    symbol: ?[]const u8 = null,
    address: ?[]const u8 = null,
    interval: []const u8 = "1m",
};

pub const StreamKind = enum {
    prices,
    orderbook,
    bbo,
    trades,
    candle,
    mark_price_candle,
    account_margin,
    account_leverage,
    account_info,
    account_positions,
    account_order_updates,
    account_trades,
    account_twap_orders,
    account_twap_order_updates,
};

pub const BatchArgs = struct {
    orders: [16]?[]const u8 = .{null} ** 16,
    count: usize = 0,
    stdin: bool = false,
};

pub const KeysArgs = struct {
    action: KeysAction = .ls,
    name: ?[]const u8 = null,
    key_b58: ?[]const u8 = null,
    password: ?[]const u8 = null,
};

pub const KeysAction = enum { ls, new, import_, rm, export_, default };

pub const HelpArgs = struct {
    topic: ?[]const u8 = null,
};

// ── Global flags ──────────────────────────────────────────────

pub const GlobalFlags = struct {
    chain: []const u8 = "mainnet",
    output: OutputFormat = .pretty,
    output_explicit: bool = false,
    quiet: bool = false,
    dry_run: bool = false,
    key: ?[]const u8 = null,
    key_name: ?[]const u8 = null,
    address: ?[]const u8 = null,
    agent_wallet: ?[]const u8 = null,
    ws: bool = false,
};

pub const OutputFormat = enum {
    pretty,
    json,

    pub fn fromStr(s: []const u8) ?OutputFormat {
        if (std.mem.eql(u8, s, "json")) return .json;
        if (std.mem.eql(u8, s, "pretty") or std.mem.eql(u8, s, "table")) return .pretty;
        return null;
    }
};

pub const ParseResult = struct {
    command: ?Command,
    flags: GlobalFlags,
};

pub const ParseError = error{
    MissingArgument,
    UnknownCommand,
    InvalidFlag,
};

// ── Parser ────────────────────────────────────────────────────

pub fn parse(allocator: std.mem.Allocator) ParseError!ParseResult {
    var args_iter = std.process.argsWithAllocator(allocator) catch return .{ .command = .{ .help = .{} }, .flags = .{} };
    defer args_iter.deinit();

    _ = args_iter.next();

    var flags = GlobalFlags{};
    var positionals: [16][]const u8 = undefined;
    var pos_count: usize = 0;

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--chain")) {
            flags.chain = args_iter.next() orelse return error.MissingArgument;
        } else if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            const val = args_iter.next() orelse return error.MissingArgument;
            flags.output = OutputFormat.fromStr(val) orelse return error.InvalidFlag;
            flags.output_explicit = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            flags.output = .json;
            flags.output_explicit = true;
        } else if (std.mem.eql(u8, arg, "--quiet") or std.mem.eql(u8, arg, "-q")) {
            flags.quiet = true;
        } else if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "-n")) {
            flags.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--key") or std.mem.eql(u8, arg, "-k")) {
            flags.key = args_iter.next() orelse return error.MissingArgument;
        } else if (std.mem.eql(u8, arg, "--key-name")) {
            flags.key_name = args_iter.next() orelse return error.MissingArgument;
        } else if (std.mem.eql(u8, arg, "--address") or std.mem.eql(u8, arg, "-a")) {
            flags.address = args_iter.next() orelse return error.MissingArgument;
        } else if (std.mem.eql(u8, arg, "--agent-wallet")) {
            flags.agent_wallet = args_iter.next() orelse return error.MissingArgument;
        } else if (std.mem.eql(u8, arg, "--ws")) {
            flags.ws = true;
        } else {
            if (pos_count < positionals.len) {
                positionals[pos_count] = arg;
                pos_count += 1;
            }
        }
    }

    if (pos_count == 0) return .{ .command = .{ .help = .{} }, .flags = flags };

    const cmd_str = positionals[0];
    const rest = positionals[1..pos_count];

    const command: Command = if (std.mem.eql(u8, cmd_str, "keys") or std.mem.eql(u8, cmd_str, "key"))
        .{ .keys = parseKeys(rest) }
    else if (std.mem.eql(u8, cmd_str, "buy") or std.mem.eql(u8, cmd_str, "long"))
        .{ .buy = parseOrder(rest, flags.dry_run) orelse return error.MissingArgument }
    else if (std.mem.eql(u8, cmd_str, "sell") or std.mem.eql(u8, cmd_str, "short"))
        .{ .sell = parseOrder(rest, flags.dry_run) orelse return error.MissingArgument }
    else if (std.mem.eql(u8, cmd_str, "cancel"))
        .{ .cancel = parseCancel(rest) }
    else if (std.mem.eql(u8, cmd_str, "edit") or std.mem.eql(u8, cmd_str, "modify"))
        .{ .edit = parseEdit(rest) orelse return error.MissingArgument }
    else if (std.mem.eql(u8, cmd_str, "info"))
        .{ .info = {} }
    else if (std.mem.eql(u8, cmd_str, "prices") or std.mem.eql(u8, cmd_str, "mids"))
        .{ .prices = {} }
    else if (std.mem.eql(u8, cmd_str, "book") or std.mem.eql(u8, cmd_str, "ob"))
        .{ .book = parseBook(rest) orelse return error.MissingArgument }
    else if (std.mem.eql(u8, cmd_str, "candles") or std.mem.eql(u8, cmd_str, "kline"))
        .{ .candles = parseCandles(rest) orelse return error.MissingArgument }
    else if (std.mem.eql(u8, cmd_str, "account") or std.mem.eql(u8, cmd_str, "acc"))
        .{ .account = parseAddr(rest) }
    else if (std.mem.eql(u8, cmd_str, "positions") or std.mem.eql(u8, cmd_str, "pos"))
        .{ .positions = parseAddr(rest) }
    else if (std.mem.eql(u8, cmd_str, "orders") or std.mem.eql(u8, cmd_str, "ord"))
        .{ .orders = parseAddr(rest) }
    else if (std.mem.eql(u8, cmd_str, "history"))
        .{ .history = parseHistory(rest) }
    else if (std.mem.eql(u8, cmd_str, "trades") or std.mem.eql(u8, cmd_str, "fills"))
        .{ .trades = parseHistory(rest) }
    else if (std.mem.eql(u8, cmd_str, "funding"))
        .{ .funding = parseHistory(rest) }
    else if (std.mem.eql(u8, cmd_str, "balance-history"))
        .{ .balance_history = parseHistory(rest) }
    else if (std.mem.eql(u8, cmd_str, "equity") or std.mem.eql(u8, cmd_str, "portfolio"))
        .{ .equity = parseEquity(rest) }
    else if (std.mem.eql(u8, cmd_str, "leverage") or std.mem.eql(u8, cmd_str, "lev"))
        .{ .leverage = parseLeverage(rest) orelse return error.MissingArgument }
    else if (std.mem.eql(u8, cmd_str, "margin"))
        .{ .margin = parseMargin(rest) orelse return error.MissingArgument }
    else if (std.mem.eql(u8, cmd_str, "deposit"))
        .{ .deposit = parseDeposit(rest) orelse return error.MissingArgument }
    else if (std.mem.eql(u8, cmd_str, "transfer"))
        .{ .transfer = parseTransfer(rest) orelse return error.MissingArgument }
    else if (std.mem.eql(u8, cmd_str, "withdraw"))
        .{ .withdraw = .{ .amount = if (rest.len > 0) rest[0] else return error.MissingArgument } }
    else if (std.mem.eql(u8, cmd_str, "stop"))
        .{ .stop = parseStop(rest, flags.dry_run) }
    else if (std.mem.eql(u8, cmd_str, "tpsl"))
        .{ .tpsl = parseTpSl(rest, flags.dry_run) orelse return error.MissingArgument }
    else if (std.mem.eql(u8, cmd_str, "twap"))
        .{ .twap = parseTwap(rest, flags.dry_run) }
    else if (std.mem.eql(u8, cmd_str, "agent"))
        .{ .agent = parseAgent(rest) }
    else if (std.mem.eql(u8, cmd_str, "subaccount") or std.mem.eql(u8, cmd_str, "sub"))
        .{ .subaccount = parseSubaccount(rest) }
    else if (std.mem.eql(u8, cmd_str, "api-key"))
        .{ .api_key = parseApiKey(rest) }
    else if (std.mem.eql(u8, cmd_str, "lake"))
        .{ .lake = parseLake(rest) }
    else if (std.mem.eql(u8, cmd_str, "access"))
        .{ .access = parseAccess(rest) }
    else if (std.mem.eql(u8, cmd_str, "stream"))
        .{ .stream = parseStream(rest) }
    else if (std.mem.eql(u8, cmd_str, "batch"))
        .{ .batch = parseBatch(rest) }
    else if (std.mem.eql(u8, cmd_str, "help") or std.mem.eql(u8, cmd_str, "--help") or std.mem.eql(u8, cmd_str, "-h"))
        .{ .help = .{ .topic = if (rest.len > 0) rest[0] else null } }
    else if (std.mem.eql(u8, cmd_str, "version") or std.mem.eql(u8, cmd_str, "--version") or std.mem.eql(u8, cmd_str, "-V"))
        .{ .version = {} }
    else
        return error.UnknownCommand;

    return .{ .command = command, .flags = flags };
}

// ── Sub-parsers ───────────────────────────────────────────────

fn parseOrder(args: []const []const u8, global_dry_run: bool) ?OrderArgs {
    if (args.len < 2) return null;
    var result = OrderArgs{ .symbol = args[0], .amount = args[1], .dry_run = global_dry_run };
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (a.len > 0 and a[0] == '@') {
            result.price = a[1..];
        } else if (std.mem.eql(u8, a, "--reduce-only")) {
            result.reduce_only = true;
        } else if (std.mem.eql(u8, a, "--tif") and i + 1 < args.len) {
            i += 1;
            result.tif = args[i];
        } else if (std.mem.eql(u8, a, "--slippage") and i + 1 < args.len) {
            i += 1;
            result.slippage = args[i];
        } else if (std.mem.eql(u8, a, "--dry-run") or std.mem.eql(u8, a, "-n")) {
            result.dry_run = true;
        } else if (!std.mem.startsWith(u8, a, "--")) {
            result.price = a;
        }
    }
    return result;
}

fn parseCancel(args: []const []const u8) CancelArgs {
    var result = CancelArgs{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--all")) {
            result.all = true;
        } else if (std.mem.eql(u8, a, "--cloid") and i + 1 < args.len) {
            i += 1;
            result.client_order_id = args[i];
        } else if (std.mem.eql(u8, a, "--symbol") and i + 1 < args.len) {
            i += 1;
            result.symbol = args[i];
        } else if (result.symbol == null) {
            result.symbol = a;
        } else {
            result.order_id = a;
        }
    }
    return result;
}

fn parseEdit(args: []const []const u8) ?EditArgs {
    if (args.len < 4) return null;
    var price = args[2];
    if (price.len > 0 and price[0] == '@') price = price[1..];
    return .{ .symbol = args[0], .order_id = args[1], .price = price, .amount = args[3] };
}

fn parseAddr(args: []const []const u8) AddrArg {
    return .{ .address = if (args.len > 0) args[0] else null };
}

fn parseBook(args: []const []const u8) ?BookArgs {
    if (args.len < 1) return null;
    return .{ .symbol = args[0] };
}

fn parseCandles(args: []const []const u8) ?CandleArgs {
    if (args.len < 1) return null;
    var result = CandleArgs{ .symbol = args[0] };
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--interval") and i + 1 < args.len) {
            i += 1;
            result.interval = args[i];
        } else if (std.mem.eql(u8, args[i], "--start") and i + 1 < args.len) {
            i += 1;
            result.start = args[i];
        } else if (std.mem.eql(u8, args[i], "--end") and i + 1 < args.len) {
            i += 1;
            result.end = args[i];
        }
    }
    return result;
}

fn parseHistory(args: []const []const u8) HistoryArgs {
    var result = HistoryArgs{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--symbol") and i + 1 < args.len) {
            i += 1;
            result.symbol = args[i];
        } else if (std.mem.eql(u8, args[i], "--limit") and i + 1 < args.len) {
            i += 1;
            result.limit = args[i];
        } else if (std.mem.eql(u8, args[i], "--cursor") and i + 1 < args.len) {
            i += 1;
            result.cursor = args[i];
        } else if (result.address == null) {
            result.address = args[i];
        }
    }
    return result;
}

fn parseEquity(args: []const []const u8) EquityArgs {
    var result = EquityArgs{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--range") and i + 1 < args.len) {
            i += 1;
            result.range = args[i];
        } else if (result.address == null) {
            result.address = args[i];
        }
    }
    return result;
}

fn parseLeverage(args: []const []const u8) ?LeverageArgs {
    if (args.len < 1) return null;
    var result = LeverageArgs{ .symbol = args[0] };
    if (args.len >= 2 and !std.mem.startsWith(u8, args[1], "--")) result.leverage = args[1];
    return result;
}

fn parseMargin(args: []const []const u8) ?MarginArgs {
    if (args.len < 1) return null;
    var result = MarginArgs{ .symbol = args[0] };
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--isolated")) result.isolated = true;
        if (std.mem.eql(u8, args[i], "--cross")) result.isolated = false;
    }
    return result;
}

fn parseDeposit(args: []const []const u8) ?DepositArgs {
    if (args.len < 2) return null;
    var result = DepositArgs{ .network = args[0], .amount = args[1] };
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--rpc") and i + 1 < args.len) {
            i += 1;
            result.rpc_url = args[i];
        }
    }
    return result;
}

fn parseTransfer(args: []const []const u8) ?TransferArgs {
    if (args.len < 4) return null;
    var result = TransferArgs{
        .network = args[0],
        .asset = args[1],
        .amount = args[2],
        .to = args[3],
    };
    var i: usize = 4;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--rpc") and i + 1 < args.len) {
            i += 1;
            result.rpc_url = args[i];
        }
    }
    return result;
}

fn parseStop(args: []const []const u8, global_dry_run: bool) StopArgs {
    var result = StopArgs{ .dry_run = global_dry_run };
    if (args.len > 0 and std.mem.eql(u8, args[0], "cancel")) {
        result.action = .cancel;
        if (args.len > 1) result.symbol = args[1];
        if (args.len > 2) result.order_id = args[2];
        return result;
    }
    if (args.len > 0) result.symbol = args[0];
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--side") and i + 1 < args.len) {
            i += 1;
            result.side = args[i];
        } else if (std.mem.eql(u8, args[i], "--stop-price") and i + 1 < args.len) {
            i += 1;
            result.stop_price = args[i];
        } else if (std.mem.eql(u8, args[i], "--limit-price") and i + 1 < args.len) {
            i += 1;
            result.limit_price = args[i];
        } else if (std.mem.eql(u8, args[i], "--amount") and i + 1 < args.len) {
            i += 1;
            result.amount = args[i];
        } else if (std.mem.eql(u8, args[i], "--dry-run")) {
            result.dry_run = true;
        }
    }
    return result;
}

fn parseTpSl(args: []const []const u8, global_dry_run: bool) ?TpSlArgs {
    if (args.len < 1) return null;
    var result = TpSlArgs{ .symbol = args[0], .side = if (args.len > 1) args[1] else "bid", .dry_run = global_dry_run };
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--tp") and i + 1 < args.len) {
            i += 1;
            result.tp = args[i];
        } else if (std.mem.eql(u8, args[i], "--tp-limit") and i + 1 < args.len) {
            i += 1;
            result.tp_limit = args[i];
        } else if (std.mem.eql(u8, args[i], "--tp-amount") and i + 1 < args.len) {
            i += 1;
            result.tp_amount = args[i];
        } else if (std.mem.eql(u8, args[i], "--sl") and i + 1 < args.len) {
            i += 1;
            result.sl = args[i];
        } else if (std.mem.eql(u8, args[i], "--sl-limit") and i + 1 < args.len) {
            i += 1;
            result.sl_limit = args[i];
        } else if (std.mem.eql(u8, args[i], "--dry-run")) {
            result.dry_run = true;
        }
    }
    return result;
}

fn parseTwap(args: []const []const u8, global_dry_run: bool) TwapArgs {
    var result = TwapArgs{ .dry_run = global_dry_run };
    if (args.len == 0) return result;
    if (std.mem.eql(u8, args[0], "cancel")) {
        result.action = .cancel;
        if (args.len > 1) result.symbol = args[1];
        if (args.len > 2) result.order_id = args[2];
        return result;
    }
    if (std.mem.eql(u8, args[0], "list")) {
        result.action = .list;
        if (args.len > 1) result.address = args[1];
        return result;
    }
    if (std.mem.eql(u8, args[0], "history")) {
        result.action = .history;
        if (args.len > 1) result.address = args[1];
        return result;
    }
    result.action = .create;
    result.symbol = args[0];
    if (args.len > 1) result.side = args[1];
    if (args.len > 2) result.amount = args[2];
    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--duration") and i + 1 < args.len) {
            i += 1;
            result.duration = args[i];
        } else if (std.mem.eql(u8, args[i], "--slippage") and i + 1 < args.len) {
            i += 1;
            result.slippage = args[i];
        } else if (std.mem.eql(u8, args[i], "--dry-run")) {
            result.dry_run = true;
        }
    }
    return result;
}

fn parseAgent(args: []const []const u8) AgentArgs {
    var result = AgentArgs{};
    if (args.len == 0) return result;
    if (std.mem.eql(u8, args[0], "bind")) {
        result.action = .bind;
        if (args.len > 1) result.agent_addr = args[1];
    } else if (std.mem.eql(u8, args[0], "list")) {
        result.action = .list;
    } else if (std.mem.eql(u8, args[0], "revoke")) {
        result.action = .revoke;
        if (args.len > 1) result.agent_addr = args[1];
    } else if (std.mem.eql(u8, args[0], "revoke-all")) {
        result.action = .revoke_all;
    } else if (std.mem.eql(u8, args[0], "ip-list")) {
        result.action = .ip_list;
        if (args.len > 1) result.agent_addr = args[1];
    } else if (std.mem.eql(u8, args[0], "ip-add")) {
        result.action = .ip_add;
        if (args.len > 1) result.agent_addr = args[1];
        if (args.len > 2) result.ip = args[2];
    } else if (std.mem.eql(u8, args[0], "ip-remove")) {
        result.action = .ip_remove;
        if (args.len > 1) result.agent_addr = args[1];
        if (args.len > 2) result.ip = args[2];
    } else if (std.mem.eql(u8, args[0], "ip-toggle")) {
        result.action = .ip_toggle;
        if (args.len > 1) result.agent_addr = args[1];
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--enable")) result.enable = true;
            if (std.mem.eql(u8, args[i], "--disable")) result.enable = false;
        }
    }
    return result;
}

fn parseSubaccount(args: []const []const u8) SubaccountArgs {
    var result = SubaccountArgs{};
    if (args.len == 0) return result;
    if (std.mem.eql(u8, args[0], "create")) {
        result.action = .create;
        if (args.len > 1) result.key_or_addr = args[1];
    } else if (std.mem.eql(u8, args[0], "list") or std.mem.eql(u8, args[0], "ls")) {
        result.action = .list;
    } else if (std.mem.eql(u8, args[0], "transfer")) {
        result.action = .transfer;
        if (args.len > 1) result.amount = args[1];
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--to") and i + 1 < args.len) {
                i += 1;
                result.key_or_addr = args[i];
            }
        }
    }
    return result;
}

fn parseApiKey(args: []const []const u8) ApiKeyArgs {
    var result = ApiKeyArgs{};
    if (args.len == 0) return result;
    if (std.mem.eql(u8, args[0], "create")) {
        result.action = .create;
    } else if (std.mem.eql(u8, args[0], "revoke")) {
        result.action = .revoke;
        if (args.len > 1) result.key = args[1];
    } else if (std.mem.eql(u8, args[0], "list") or std.mem.eql(u8, args[0], "ls")) {
        result.action = .list;
    }
    return result;
}

fn parseLake(args: []const []const u8) LakeArgs {
    var result = LakeArgs{};
    if (args.len == 0) return result;
    if (std.mem.eql(u8, args[0], "create")) {
        result.action = .create;
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--nickname") and i + 1 < args.len) {
                i += 1;
                result.nickname = args[i];
            } else if (std.mem.eql(u8, args[i], "--manager") and i + 1 < args.len) {
                i += 1;
                result.manager = args[i];
            }
        }
    } else if (std.mem.eql(u8, args[0], "deposit")) {
        result.action = .deposit;
        if (args.len > 1) result.addr = args[1];
        if (args.len > 2) result.amount = args[2];
    } else if (std.mem.eql(u8, args[0], "withdraw")) {
        result.action = .withdraw;
        if (args.len > 1) result.addr = args[1];
        if (args.len > 2) result.amount = args[2];
    }
    return result;
}

fn parseAccess(args: []const []const u8) AccessArgs {
    var result = AccessArgs{};
    if (args.len == 0) return result;
    if (std.mem.eql(u8, args[0], "claim")) {
        result.action = .claim;
        if (args.len > 1) result.code = args[1];
    } else if (std.mem.eql(u8, args[0], "status")) {
        result.action = .status;
        if (args.len > 1) result.address = args[1];
    } else {
        result.action = .claim;
        result.code = args[0];
    }
    return result;
}

fn parseStream(args: []const []const u8) StreamArgs {
    var result = StreamArgs{};
    if (args.len == 0) return result;

    const kind = args[0];
    if (std.mem.eql(u8, kind, "prices") or std.mem.eql(u8, kind, "price")) {
        result.kind = .prices;
    } else if (std.mem.eql(u8, kind, "book") or std.mem.eql(u8, kind, "orderbook") or std.mem.eql(u8, kind, "ob")) {
        result.kind = .orderbook;
    } else if (std.mem.eql(u8, kind, "bbo")) {
        result.kind = .bbo;
    } else if (std.mem.eql(u8, kind, "trades") or std.mem.eql(u8, kind, "trade")) {
        result.kind = .trades;
    } else if (std.mem.eql(u8, kind, "candle") or std.mem.eql(u8, kind, "candles")) {
        result.kind = .candle;
    } else if (std.mem.eql(u8, kind, "mark-candle") or std.mem.eql(u8, kind, "mark-price-candle")) {
        result.kind = .mark_price_candle;
    } else if (std.mem.eql(u8, kind, "margin")) {
        result.kind = .account_margin;
    } else if (std.mem.eql(u8, kind, "leverage")) {
        result.kind = .account_leverage;
    } else if (std.mem.eql(u8, kind, "account") or std.mem.eql(u8, kind, "info")) {
        result.kind = .account_info;
    } else if (std.mem.eql(u8, kind, "positions") or std.mem.eql(u8, kind, "pos")) {
        result.kind = .account_positions;
    } else if (std.mem.eql(u8, kind, "orders") or std.mem.eql(u8, kind, "ord")) {
        result.kind = .account_order_updates;
    } else if (std.mem.eql(u8, kind, "account-trades")) {
        result.kind = .account_trades;
    } else if (std.mem.eql(u8, kind, "twap")) {
        result.kind = .account_twap_orders;
    } else if (std.mem.eql(u8, kind, "twap-updates")) {
        result.kind = .account_twap_order_updates;
    }

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--interval") and i + 1 < args.len) {
            i += 1;
            result.interval = args[i];
        } else if (!std.mem.startsWith(u8, a, "--")) {
            switch (result.kind) {
                .orderbook, .bbo, .trades, .candle, .mark_price_candle => {
                    if (result.symbol == null) result.symbol = a;
                },
                else => {
                    if (result.address == null) result.address = a;
                },
            }
        }
    }
    return result;
}

fn parseKeys(args: []const []const u8) KeysArgs {
    var result = KeysArgs{};
    if (args.len == 0) return result;

    const action = args[0];
    if (std.mem.eql(u8, action, "new")) {
        result.action = .new;
    } else if (std.mem.eql(u8, action, "import")) {
        result.action = .import_;
    } else if (std.mem.eql(u8, action, "rm") or std.mem.eql(u8, action, "remove")) {
        result.action = .rm;
    } else if (std.mem.eql(u8, action, "export")) {
        result.action = .export_;
    } else if (std.mem.eql(u8, action, "default") or std.mem.eql(u8, action, "use")) {
        result.action = .default;
    } else if (std.mem.eql(u8, action, "ls") or std.mem.eql(u8, action, "list")) {
        result.action = .ls;
    } else {
        result.name = action;
        return result;
    }

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--password") and i + 1 < args.len) {
            i += 1;
            result.password = args[i];
        } else if ((std.mem.eql(u8, a, "--private-key") or std.mem.eql(u8, a, "--pk")) and i + 1 < args.len) {
            i += 1;
            result.key_b58 = args[i];
        } else if (!std.mem.startsWith(u8, a, "--")) {
            result.name = a;
        }
    }
    return result;
}

fn parseBatch(a: []const []const u8) BatchArgs {
    var result = BatchArgs{};
    for (a) |arg| {
        if (std.mem.eql(u8, arg, "--stdin")) {
            result.stdin = true;
        } else if (result.count < 16) {
            result.orders[result.count] = arg;
            result.count += 1;
        }
    }
    return result;
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  Tests                                                        ║
// ╚═══════════════════════════════════════════════════════════════╝

test "parseOrder: limit with @ prefix strips the @" {
    const r = parseOrder(&.{ "BTC", "0.1", "@100000" }, false).?;
    try std.testing.expectEqualStrings("100000", r.price.?);
    try std.testing.expectEqualStrings("GTC", r.tif);
}

test "parseOrder: all flags parsed correctly" {
    const r = parseOrder(&.{ "SOL", "10", "@200", "--reduce-only", "--tif", "IOC", "--slippage", "1.5", "--dry-run" }, false).?;
    try std.testing.expect(r.reduce_only);
    try std.testing.expectEqualStrings("IOC", r.tif);
    try std.testing.expectEqualStrings("1.5", r.slippage.?);
    try std.testing.expect(r.dry_run);
}

test "parseOrder: missing amount rejects cleanly" {
    try std.testing.expect(parseOrder(&.{"BTC"}, false) == null);
}

test "parseCancel: --cloid vs order_id are mutually exclusive paths" {
    const c1 = parseCancel(&.{ "BTC", "--cloid", "abc-123" });
    try std.testing.expectEqualStrings("abc-123", c1.client_order_id.?);
    try std.testing.expect(c1.order_id == null);
    const c2 = parseCancel(&.{ "BTC", "42069" });
    try std.testing.expectEqualStrings("42069", c2.order_id.?);
    try std.testing.expect(c2.client_order_id == null);
}

test "parseEdit: @ stripped from price" {
    const r = parseEdit(&.{ "BTC", "123", "@100000", "0.5" }).?;
    try std.testing.expectEqualStrings("100000", r.price);
}

test "parseDeposit: network amount and rpc" {
    const r = parseDeposit(&.{ "solana", "100", "--rpc", "https://rpc.example" }).?;
    try std.testing.expectEqualStrings("solana", r.network);
    try std.testing.expectEqualStrings("100", r.amount.?);
    try std.testing.expectEqualStrings("https://rpc.example", r.rpc_url.?);
}

test "parseStop: create vs cancel action dispatch" {
    const create = parseStop(&.{ "BTC", "--side", "long", "--stop-price", "48000", "--limit-price", "47950", "--amount", "0.1" }, false);
    try std.testing.expect(create.action == .create);
    try std.testing.expectEqualStrings("48000", create.stop_price.?);
    try std.testing.expectEqualStrings("47950", create.limit_price.?);
    try std.testing.expectEqualStrings("0.1", create.amount.?);

    const cancel = parseStop(&.{ "cancel", "BTC", "42069" }, false);
    try std.testing.expect(cancel.action == .cancel);
}

test "parseTpSl: all nested fields for protocol-correct body" {
    const r = parseTpSl(&.{ "BTC", "ask", "--tp", "120000", "--tp-limit", "120300", "--tp-amount", "0.5", "--sl", "99800", "--sl-limit", "99700" }, false).?;
    try std.testing.expectEqualStrings("120000", r.tp.?);
    try std.testing.expectEqualStrings("120300", r.tp_limit.?);
    try std.testing.expectEqualStrings("0.5", r.tp_amount.?);
    try std.testing.expectEqualStrings("99800", r.sl.?);
    try std.testing.expectEqualStrings("99700", r.sl_limit.?);
}

test "parseTwap: three action variants" {
    const create = parseTwap(&.{ "BTC", "buy", "1.0", "--duration", "300", "--slippage", "0.5" }, false);
    try std.testing.expect(create.action == .create);
    try std.testing.expectEqualStrings("300", create.duration.?);
    try std.testing.expectEqualStrings("0.5", create.slippage.?);

    try std.testing.expect(parseTwap(&.{ "cancel", "BTC", "42069" }, false).action == .cancel);
    try std.testing.expect(parseTwap(&.{ "list", "Addr" }, false).action == .list);
}

test "parseAgent: ip-toggle enable/disable flag" {
    try std.testing.expect(parseAgent(&.{ "ip-toggle", "A", "--enable" }).enable.?);
    try std.testing.expect(!parseAgent(&.{ "ip-toggle", "A", "--disable" }).enable.?);
}

test "parseSubaccount: transfer parses --to destination" {
    const r = parseSubaccount(&.{ "transfer", "100.5", "--to", "Dest" });
    try std.testing.expect(r.action == .transfer);
    try std.testing.expectEqualStrings("100.5", r.amount.?);
    try std.testing.expectEqualStrings("Dest", r.key_or_addr.?);
}

test "parseLake: create with --nickname and --manager" {
    const r = parseLake(&.{ "create", "--nickname", "Moraine", "--manager", "Mgr" });
    try std.testing.expect(r.action == .create);
    try std.testing.expectEqualStrings("Moraine", r.nickname.?);
    try std.testing.expectEqualStrings("Mgr", r.manager.?);
}

test "parseAccess: claim and status variants" {
    const claim = parseAccess(&.{ "claim", "CODE123" });
    try std.testing.expect(claim.action == .claim);
    try std.testing.expectEqualStrings("CODE123", claim.code.?);

    const shorthand = parseAccess(&.{"CODE456"});
    try std.testing.expect(shorthand.action == .claim);
    try std.testing.expectEqualStrings("CODE456", shorthand.code.?);

    const status = parseAccess(&.{ "status", "Addr" });
    try std.testing.expect(status.action == .status);
    try std.testing.expectEqualStrings("Addr", status.address.?);
}

test "parseBatch: --stdin vs inline orders" {
    const stdin = parseBatch(&.{"--stdin"});
    try std.testing.expect(stdin.stdin);
    try std.testing.expectEqual(@as(usize, 0), stdin.count);

    const inline_ = parseBatch(&.{ "buy BTC 0.1", "cancel BTC 1" });
    try std.testing.expect(!inline_.stdin);
    try std.testing.expectEqual(@as(usize, 2), inline_.count);
}
