// ╔═══════════════════════════════════════════════════════════════╗
// ║  Command implementations                                      ║
// ╚═══════════════════════════════════════════════════════════════╝

const std = @import("std");
const lib = @import("lib");
const sdk = @import("sdk");
const args_mod = @import("args.zig");
const config_mod = @import("config.zig");
const keystore = @import("keystore.zig");
const output_mod = @import("output.zig");
const Client = sdk.client.Client;
const Writer = output_mod.Writer;
const Style = output_mod.Style;
const Column = output_mod.Column;
const Config = config_mod.Config;

fn doSignedPost(
    client: *Client,
    path: []const u8,
    signer: *const lib.crypto.signer.Signer,
    config: *Config,
    msg_type: []const u8,
    payload: std.json.Value,
) !sdk.client.Response {
    const ctx = try config.getSigningContext();
    return client.signedPost(path, signer, ctx.account_addr, msg_type, payload, ctx.agent_pubkey);
}

fn doSignedWs(
    allocator: std.mem.Allocator,
    signer: *const lib.crypto.signer.Signer,
    config: *Config,
    op_name: []const u8,
    msg_type: []const u8,
    payload: std.json.Value,
) !sdk.ws.ActionResult {
    var rest_client = Client.init(allocator, config.chain);
    defer rest_client.deinit();
    var ws_client = try sdk.ws.Client.init(allocator, config.chain, config.api_key);
    defer ws_client.deinit();
    const ctx = try config.getSigningContext();
    return ws_client.signedAction(&rest_client, op_name, signer, ctx.account_addr, msg_type, payload, ctx.agent_pubkey);
}

pub fn keysCmd(allocator: std.mem.Allocator, w: *Writer, a: args_mod.KeysArgs) !void {
    const password = a.password orelse std.posix.getenv("PACIFICA_PASSWORD") orelse {
        if (a.action == .ls) return keysLs(allocator, w);
        if (a.action == .rm) return keysRm(w, a.name orelse {
            try w.err("usage: regatta keys rm <name>");
            return error.MissingArgument;
        });
        if (a.action == .default) return keysDefault(w, a.name orelse {
            try w.err("usage: regatta keys default <name>");
            return error.MissingArgument;
        });
        try w.err("password required: --password <PASS> or PACIFICA_PASSWORD env");
        return error.MissingKey;
    };

    switch (a.action) {
        .ls => return keysLs(allocator, w),
        .new => {
            const name = a.name orelse {
                try w.err("usage: regatta keys new <name> --password <PASS>");
                return error.MissingArgument;
            };
            const signer = lib.crypto.signer.Signer.generate();
            const secret = signer.secretBytes64();
            const json = keystore.encrypt(allocator, secret, password) catch |e| return failFmt(w, "encrypt: {s}", .{@errorName(e)});
            defer allocator.free(json);
            keystore.save(name, json) catch |e| return failFmt(w, "save: {s}", .{@errorName(e)});
            var addr_buf: [44]u8 = undefined;
            const addr = signer.pubkeyBase58(&addr_buf);
            if (w.format == .json) {
                var buf: [256]u8 = undefined;
                const body = std.fmt.bufPrint(&buf, "{{\"status\":\"created\",\"name\":\"{s}\",\"address\":\"{s}\"}}", .{ name, addr }) catch return error.Overflow;
                try w.jsonRaw(body);
            } else {
                try w.success(name);
                try w.print("  address: {s}\n  path:    ~/.regatta/keys/{s}.json\n", .{ addr, name });
            }
        },
        .import_ => {
            const name = a.name orelse {
                try w.err("usage: regatta keys import <name> --private-key <BASE58> --password <PASS>");
                return error.MissingArgument;
            };
            const key = a.key_b58 orelse std.posix.getenv("PACIFICA_KEY") orelse {
                try w.err("provide key: --private-key <BASE58> or PACIFICA_KEY env");
                return error.MissingKey;
            };
            var decode_buf: [128]u8 = undefined;
            const decoded = lib.crypto.base58.decode(&decode_buf, key) catch {
                try w.err("invalid base58 private key");
                return error.InvalidFlag;
            };
            if (decoded.len != 64) {
                try w.err("invalid Solana keypair length");
                return error.InvalidFlag;
            }
            const signer = lib.crypto.signer.Signer.fromBytes(decoded[0..64].*) catch {
                try w.err("invalid Solana keypair");
                return error.InvalidFlag;
            };
            const json = keystore.encrypt(allocator, decoded[0..64].*, password) catch |e| return failFmt(w, "encrypt: {s}", .{@errorName(e)});
            defer allocator.free(json);
            keystore.save(name, json) catch |e| return failFmt(w, "save: {s}", .{@errorName(e)});
            var addr_buf: [44]u8 = undefined;
            const addr = signer.pubkeyBase58(&addr_buf);
            if (w.format == .json) {
                var buf: [256]u8 = undefined;
                const body = std.fmt.bufPrint(&buf, "{{\"status\":\"imported\",\"name\":\"{s}\",\"address\":\"{s}\"}}", .{ name, addr }) catch return error.Overflow;
                try w.jsonRaw(body);
            } else {
                try w.success(name);
                try w.print("  address: {s}\n  path: ~/.regatta/keys/{s}.json\n", .{ addr, name });
            }
        },
        .export_ => {
            const name = a.name orelse {
                try w.err("usage: regatta keys export <name> --password <PASS>");
                return error.MissingArgument;
            };
            const data = keystore.load(allocator, name) catch return failFmt(w, "key \"{s}\" not found", .{name});
            defer allocator.free(data);
            const secret = keystore.decrypt(allocator, data, password) catch |e| {
                if (e == error.BadPassword) {
                    try w.fail("wrong password");
                    return error.CommandFailed;
                }
                return failFmt(w, "decrypt: {s}", .{@errorName(e)});
            };
            const signer = lib.crypto.signer.Signer.fromBytes(secret) catch return fail(w, "invalid stored key");
            var key_buf: [128]u8 = undefined;
            const key_b58 = signer.secretBase58(&key_buf);
            if (w.format == .json) {
                var buf: [256]u8 = undefined;
                const body = std.fmt.bufPrint(&buf, "{{\"name\":\"{s}\",\"key\":\"{s}\"}}", .{ name, key_b58 }) catch return error.Overflow;
                try w.jsonRaw(body);
            } else {
                try w.print("{s}\n", .{key_b58});
            }
        },
        .rm => return keysRm(w, a.name orelse {
            try w.err("usage: regatta keys rm <name>");
            return error.MissingArgument;
        }),
        .default => return keysDefault(w, a.name orelse {
            try w.err("usage: regatta keys default <name>");
            return error.MissingArgument;
        }),
    }
}

fn keysLs(allocator: std.mem.Allocator, w: *Writer) !void {
    const entries = keystore.list(allocator) catch return fail(w, "failed to list keys");
    defer allocator.free(entries);
    if (entries.len == 0) {
        if (w.format == .json) return w.jsonRaw("[]");
        try w.styled(Style.muted, "  no keys. Run: regatta keys new <name> --password <PASS>\n");
        return;
    }
    if (w.format == .json) {
        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);
        try buf.append(allocator, '[');
        for (entries, 0..) |e, i| {
            if (i > 0) try buf.append(allocator, ',');
            try buf.writer(allocator).print("{{\"name\":\"{s}\",\"address\":\"{s}\",\"default\":{s}}}", .{ e.getName(), e.getAddress(), if (e.is_default) "true" else "false" });
        }
        try buf.append(allocator, ']');
        return w.jsonRaw(buf.items);
    }
    try w.heading("Keys");
    for (entries) |e| {
        const mark: []const u8 = if (e.is_default) " *" else "";
        try w.print("  {s}  {s}{s}\n", .{ e.getName(), e.getAddress(), mark });
    }
    try w.footer();
}

fn keysRm(w: *Writer, name: []const u8) !void {
    keystore.remove(name) catch return failFmt(w, "key \"{s}\" not found", .{name});
    if (w.format == .json) {
        var buf: [128]u8 = undefined;
        const body = std.fmt.bufPrint(&buf, "{{\"status\":\"removed\",\"name\":\"{s}\"}}", .{name}) catch return error.Overflow;
        try w.jsonRaw(body);
    } else {
        try w.success("removed");
        try w.print("  {s}\n", .{name});
    }
}

fn keysDefault(w: *Writer, name: []const u8) !void {
    const home = std.posix.getenv("HOME") orelse "";
    var pbuf: [576]u8 = undefined;
    const path = std.fmt.bufPrint(&pbuf, "{s}/.regatta/keys/{s}.json", .{ home, name }) catch return failFmt(w, "key \"{s}\" not found", .{name});
    std.fs.cwd().access(path, .{}) catch return failFmt(w, "key \"{s}\" not found", .{name});
    keystore.setDefault(name) catch return fail(w, "failed to set default");
    if (w.format == .json) {
        var buf: [128]u8 = undefined;
        const body = std.fmt.bufPrint(&buf, "{{\"status\":\"default\",\"name\":\"{s}\"}}", .{name}) catch return error.Overflow;
        try w.jsonRaw(body);
    } else {
        try w.success("default set");
        try w.print("  {s}\n", .{name});
    }
}

fn fail(w: *Writer, msg: []const u8) anyerror!void {
    try w.fail(msg);
    return error.CommandFailed;
}

fn failFmt(w: *Writer, comptime fmt: []const u8, a: anytype) anyerror!void {
    try w.failFmt(fmt, a);
    return error.CommandFailed;
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  1. MARKET DATA                                               ║
// ╚═══════════════════════════════════════════════════════════════╝

pub fn info(allocator: std.mem.Allocator, w: *Writer, config: Config) !void {
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var resp = try client.getMarketInfo();
    defer resp.deinit();

    if (w.format == .json) return checkJsonResponse(w, resp.body);

    try w.heading("Markets");
    try w.tableHeader(&.{
        .{ .text = "SYMBOL", .width = 10 },
        .{ .text = "TICK", .width = 10, .align_right = true },
        .{ .text = "LOT", .width = 10, .align_right = true },
        .{ .text = "MAX LEV", .width = 8, .align_right = true },
        .{ .text = "MIN ORDER", .width = 12, .align_right = true },
    });
    var result = try parseAndExtractData(w, allocator, resp.body);
    defer result.parsed.deinit();
    switch (result.data) {
        .array => |arr| {
            for (arr.items) |item| {
                const obj = switch (item) {
                    .object => |o| o,
                    else => continue,
                };
                try w.tableRow(&.{
                    .{ .text = jsonStr(obj, "symbol"), .width = 10, .color = Style.bold_cyan },
                    .{ .text = jsonStr(obj, "tick_size"), .width = 10, .align_right = true },
                    .{ .text = jsonStr(obj, "lot_size"), .width = 10, .align_right = true },
                    .{ .text = jsonStr(obj, "max_leverage"), .width = 8, .align_right = true },
                    .{ .text = jsonStr(obj, "min_order_size"), .width = 12, .align_right = true },
                });
            }
        },
        else => try w.rawJson(resp.body),
    }
    try w.footer();
}

pub fn prices(allocator: std.mem.Allocator, w: *Writer, config: Config) !void {
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var resp = try client.getPrices();
    defer resp.deinit();

    if (w.format == .json) return checkJsonResponse(w, resp.body);

    try w.heading("Prices");
    try w.tableHeader(&.{
        .{ .text = "SYMBOL", .width = 10 },
        .{ .text = "MARK", .width = 14, .align_right = true },
        .{ .text = "ORACLE", .width = 14, .align_right = true },
        .{ .text = "FUNDING", .width = 12, .align_right = true },
        .{ .text = "OI", .width = 14, .align_right = true },
        .{ .text = "VOL 24H", .width = 14, .align_right = true },
    });

    var result = try parseAndExtractData(w, allocator, resp.body);
    defer result.parsed.deinit();
    switch (result.data) {
        .array => |arr| {
            for (arr.items) |item| {
                const obj = switch (item) {
                    .object => |o| o,
                    else => continue,
                };
                try w.tableRow(&.{
                    .{ .text = jsonStr(obj, "symbol"), .width = 10, .color = Style.bold_cyan },
                    .{ .text = jsonStr(obj, "mark"), .width = 14, .align_right = true, .color = Style.bold_white },
                    .{ .text = jsonStr(obj, "oracle"), .width = 14, .align_right = true },
                    .{ .text = jsonStr(obj, "funding"), .width = 12, .align_right = true, .color = Style.yellow },
                    .{ .text = jsonStr(obj, "open_interest"), .width = 14, .align_right = true },
                    .{ .text = jsonStr(obj, "volume_24h"), .width = 14, .align_right = true },
                });
            }
        },
        else => {},
    }
    try w.footer();
}

pub fn book(allocator: std.mem.Allocator, w: *Writer, config: Config, a: args_mod.BookArgs) !void {
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var resp = try client.getOrderbook(a.symbol);
    defer resp.deinit();

    if (w.format == .json) return checkJsonResponse(w, resp.body);

    try w.heading("Orderbook");
    try w.print("  {s}\n\n", .{a.symbol});
    try w.rawJson(resp.body);
    try w.footer();
}

pub fn candles(allocator: std.mem.Allocator, w: *Writer, config: Config, a: args_mod.CandleArgs) !void {
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var resp = try client.getKline(a.symbol, a.interval, a.start, a.end);
    defer resp.deinit();

    if (w.format == .json) return checkJsonResponse(w, resp.body);
    try w.rawJson(resp.body);
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  2. ACCOUNT                                                   ║
// ╚═══════════════════════════════════════════════════════════════╝

pub fn account(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.AddrArg) !void {
    const addr = a.address orelse config.getAddress() orelse return error.MissingAddress;
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var resp = try client.getAccountInfo(addr);
    defer resp.deinit();

    if (w.format == .json) return checkJsonResponse(w, resp.body);

    try w.heading("Account");
    var result = try parseAndExtractData(w, allocator, resp.body);
    defer result.parsed.deinit();
    const obj = switch (result.data) {
        .object => |o| o,
        else => {
            try w.fail("unexpected response format");
            return error.CommandFailed;
        },
    };

    try w.kv("Address", addr);
    try w.kv("Balance", jsonStr(obj, "balance"));
    try w.kv("Equity", jsonStr(obj, "account_equity"));
    try w.kv("Available", jsonStr(obj, "available_to_spend"));
    try w.kv("Withdrawable", jsonStr(obj, "available_to_withdraw"));
    try w.kv("Margin Used", jsonStr(obj, "total_margin_used"));
    try w.kv("Fee Level", jsonStr(obj, "fee_level"));
    try w.kv("Maker Fee", jsonStr(obj, "maker_fee"));
    try w.kv("Taker Fee", jsonStr(obj, "taker_fee"));
    try w.kv("Positions", jsonStr(obj, "positions_count"));
    try w.kv("Orders", jsonStr(obj, "orders_count"));
    try w.footer();
}

pub fn positionsCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.AddrArg) !void {
    const addr = a.address orelse config.getAddress() orelse return error.MissingAddress;
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var resp = try client.getPositions(addr);
    defer resp.deinit();

    if (w.format == .json) return checkJsonResponse(w, resp.body);

    try w.heading("Positions");
    try w.tableHeader(&.{
        .{ .text = "SYMBOL", .width = 10 },
        .{ .text = "SIDE", .width = 5 },
        .{ .text = "SIZE", .width = 14, .align_right = true },
        .{ .text = "ENTRY", .width = 14, .align_right = true },
        .{ .text = "MARGIN", .width = 14, .align_right = true },
        .{ .text = "FUNDING", .width = 12, .align_right = true },
    });

    var result = try parseAndExtractData(w, allocator, resp.body);
    defer result.parsed.deinit();
    switch (result.data) {
        .array => |arr| {
            for (arr.items) |item| {
                const obj = switch (item) {
                    .object => |o| o,
                    else => continue,
                };
                const side = jsonStr(obj, "side");
                const side_color = if (std.mem.eql(u8, side, "bid")) Style.bold_green else Style.bold_red;
                try w.tableRow(&.{
                    .{ .text = jsonStr(obj, "symbol"), .width = 10, .color = Style.bold_cyan },
                    .{ .text = side, .width = 5, .color = side_color },
                    .{ .text = jsonStr(obj, "amount"), .width = 14, .align_right = true, .color = Style.bold_white },
                    .{ .text = jsonStr(obj, "entry_price"), .width = 14, .align_right = true },
                    .{ .text = jsonStr(obj, "margin"), .width = 14, .align_right = true },
                    .{ .text = jsonStr(obj, "funding"), .width = 12, .align_right = true },
                });
            }
        },
        else => {},
    }
    try w.footer();
}

pub fn ordersCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.AddrArg) !void {
    const addr = a.address orelse config.getAddress() orelse return error.MissingAddress;
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var resp = try client.getOpenOrders(addr);
    defer resp.deinit();

    if (w.format == .json) return checkJsonResponse(w, resp.body);

    try w.heading("Open Orders");
    try w.tableHeader(&.{
        .{ .text = "ID", .width = 12 },
        .{ .text = "SYMBOL", .width = 10 },
        .{ .text = "SIDE", .width = 5 },
        .{ .text = "PRICE", .width = 14, .align_right = true },
        .{ .text = "SIZE", .width = 14, .align_right = true },
        .{ .text = "FILLED", .width = 14, .align_right = true },
        .{ .text = "TYPE", .width = 10 },
    });

    var result = try parseAndExtractData(w, allocator, resp.body);
    defer result.parsed.deinit();
    switch (result.data) {
        .array => |arr| {
            for (arr.items) |item| {
                const obj = switch (item) {
                    .object => |o| o,
                    else => continue,
                };
                const side = jsonStr(obj, "side");
                const side_color = if (std.mem.eql(u8, side, "bid")) Style.bold_green else Style.bold_red;
                try w.tableRow(&.{
                    .{ .text = jsonStr(obj, "order_id"), .width = 12 },
                    .{ .text = jsonStr(obj, "symbol"), .width = 10, .color = Style.bold_cyan },
                    .{ .text = side, .width = 5, .color = side_color },
                    .{ .text = jsonStr(obj, "price"), .width = 14, .align_right = true, .color = Style.bold_white },
                    .{ .text = jsonStr(obj, "initial_amount"), .width = 14, .align_right = true },
                    .{ .text = jsonStr(obj, "filled_amount"), .width = 14, .align_right = true },
                    .{ .text = jsonStr(obj, "order_type"), .width = 10 },
                });
            }
        },
        else => {},
    }
    try w.footer();
}

pub fn historyCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.HistoryArgs) !void {
    const addr = a.address orelse config.getAddress() orelse return error.MissingAddress;
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var resp = try client.getOrderHistory(addr, a.limit, a.cursor);
    defer resp.deinit();

    if (w.format == .json) return checkJsonResponse(w, resp.body);
    _ = try parseAndExtractData(w, allocator, resp.body);
    try w.heading("Order History");
    try w.rawJson(resp.body);
    try w.footer();
}

pub fn tradesCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.HistoryArgs) !void {
    const addr = a.address orelse config.getAddress() orelse return error.MissingAddress;
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var resp = try client.getTradeHistory(addr, a.symbol, a.limit, a.cursor);
    defer resp.deinit();

    if (w.format == .json) return checkJsonResponse(w, resp.body);
    _ = try parseAndExtractData(w, allocator, resp.body);
    try w.heading("Trade History");
    try w.rawJson(resp.body);
    try w.footer();
}

pub fn fundingCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.HistoryArgs) !void {
    const addr = a.address orelse config.getAddress() orelse return error.MissingAddress;
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var resp = try client.getFundingHistory(addr, a.limit, a.cursor);
    defer resp.deinit();

    if (w.format == .json) return checkJsonResponse(w, resp.body);
    _ = try parseAndExtractData(w, allocator, resp.body);
    try w.heading("Funding History");
    try w.rawJson(resp.body);
    try w.footer();
}

pub fn balanceHistoryCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.HistoryArgs) !void {
    const addr = a.address orelse config.getAddress() orelse return error.MissingAddress;
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var resp = try client.getBalanceHistory(addr, a.limit, a.cursor);
    defer resp.deinit();

    if (w.format == .json) return checkJsonResponse(w, resp.body);
    _ = try parseAndExtractData(w, allocator, resp.body);
    try w.heading("Balance History");
    try w.rawJson(resp.body);
    try w.footer();
}

pub fn equityCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.EquityArgs) !void {
    const addr = a.address orelse config.getAddress() orelse return error.MissingAddress;
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var resp = try client.getEquityHistory(addr, a.range);
    defer resp.deinit();

    if (w.format == .json) return checkJsonResponse(w, resp.body);
    _ = try parseAndExtractData(w, allocator, resp.body);
    try w.heading("Equity History");
    try w.rawJson(resp.body);
    try w.footer();
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  3. TRADING                                                   ║
// ╚═══════════════════════════════════════════════════════════════╝

pub fn placeOrder(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.OrderArgs, is_buy: bool) !void {
    const signer = config.getSigner() catch return error.MissingKey;
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const side_str: []const u8 = if (is_buy) "bid" else "ask";

    if (a.price) |price| {
        var uuid_buf: [36]u8 = undefined;
        const cloid = lib.uuid.v4(&uuid_buf);

        var payload = std.json.ObjectMap.init(aa);
        try payload.put("symbol", .{ .string = a.symbol });
        try payload.put("price", .{ .string = price });
        try payload.put("amount", .{ .string = a.amount });
        try payload.put("side", .{ .string = side_str });
        try payload.put("tif", .{ .string = a.tif });
        try payload.put("reduce_only", .{ .bool = a.reduce_only });
        try payload.put("client_order_id", .{ .string = cloid });

        if (a.dry_run) {
            var signed = try sdk.signing.signRequest(aa, &signer, "create_order", .{ .object = payload }, @intCast(std.time.milliTimestamp()), 5000);
            defer signed.deinit();
            try w.print("DRY RUN — would send:\n{s}\n", .{signed.message});
            return;
        }

        if (config.use_ws) {
            var res = try doSignedWs(allocator, &signer, config, "create_order", "create_order", .{ .object = payload });
            defer res.deinit(allocator);
            if (w.format == .json) return w.rawJson(res.body);
            try handleSignedResponse(w, allocator, res.body, "order placed");
            return;
        }

        var resp = try doSignedPost(&client, "/orders/create", &signer, config, "create_order", .{ .object = payload });
        defer resp.deinit();

        if (w.format == .json) return checkJsonResponse(w, resp.body);
        try handleSignedResponse(w, allocator, resp.body, "order placed");
    } else {
        var uuid_buf: [36]u8 = undefined;
        const cloid = lib.uuid.v4(&uuid_buf);

        var payload = std.json.ObjectMap.init(aa);
        try payload.put("symbol", .{ .string = a.symbol });
        try payload.put("amount", .{ .string = a.amount });
        try payload.put("side", .{ .string = side_str });
        try payload.put("slippage_percent", .{ .string = a.slippage orelse "0.5" });
        try payload.put("reduce_only", .{ .bool = a.reduce_only });
        try payload.put("client_order_id", .{ .string = cloid });

        if (a.dry_run) {
            var signed = try sdk.signing.signRequest(aa, &signer, "create_market_order", .{ .object = payload }, @intCast(std.time.milliTimestamp()), 5000);
            defer signed.deinit();
            try w.print("DRY RUN — would send:\n{s}\n", .{signed.message});
            return;
        }

        if (config.use_ws) {
            var res = try doSignedWs(allocator, &signer, config, "create_market_order", "create_market_order", .{ .object = payload });
            defer res.deinit(allocator);
            if (w.format == .json) return w.rawJson(res.body);
            try handleSignedResponse(w, allocator, res.body, "market order placed");
            return;
        }

        var resp = try doSignedPost(&client, "/orders/create_market", &signer, config, "create_market_order", .{ .object = payload });
        defer resp.deinit();

        if (w.format == .json) return checkJsonResponse(w, resp.body);
        try handleSignedResponse(w, allocator, resp.body, "market order placed");
    }
}

pub fn cancelOrder(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.CancelArgs) !void {
    const signer = config.getSigner() catch return error.MissingKey;
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    if (a.all) {
        var payload = std.json.ObjectMap.init(aa);
        try payload.put("all_symbols", .{ .bool = a.symbol == null });
        try payload.put("exclude_reduce_only", .{ .bool = false });
        if (a.symbol) |s| try payload.put("symbol", .{ .string = s });

        if (config.use_ws) {
            var res = try doSignedWs(allocator, &signer, config, "cancel_all_orders", "cancel_all_orders", .{ .object = payload });
            defer res.deinit(allocator);
            if (w.format == .json) return w.rawJson(res.body);
            try handleSignedResponse(w, allocator, res.body, "cancelled all orders");
            return;
        }

        var resp = try doSignedPost(&client, "/orders/cancel_all", &signer, config, "cancel_all_orders", .{ .object = payload });
        defer resp.deinit();

        if (w.format == .json) return checkJsonResponse(w, resp.body);
        try handleSignedResponse(w, allocator, resp.body, "cancelled all orders");
    } else {
        const sym = a.symbol orelse return error.MissingArgument;
        if (a.order_id == null and a.client_order_id == null) return error.MissingArgument;
        if (a.order_id != null and a.client_order_id != null) return error.InvalidFlag;

        var payload = std.json.ObjectMap.init(aa);
        try payload.put("symbol", .{ .string = sym });
        if (a.order_id) |oid| {
            const id = std.fmt.parseInt(i64, oid, 10) catch return error.InvalidFlag;
            try payload.put("order_id", .{ .integer = id });
        }
        if (a.client_order_id) |cloid| {
            try payload.put("client_order_id", .{ .string = cloid });
        }

        if (config.use_ws) {
            var res = try doSignedWs(allocator, &signer, config, "cancel_order", "cancel_order", .{ .object = payload });
            defer res.deinit(allocator);
            if (w.format == .json) return w.rawJson(res.body);
            try handleSignedResponse(w, allocator, res.body, "order cancelled");
            return;
        }

        var resp = try doSignedPost(&client, "/orders/cancel", &signer, config, "cancel_order", .{ .object = payload });
        defer resp.deinit();

        if (w.format == .json) return checkJsonResponse(w, resp.body);
        try handleSignedResponse(w, allocator, resp.body, "order cancelled");
    }
}

pub fn leverageCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.LeverageArgs) !void {
    if (a.leverage) |lev| {
        const signer = config.getSigner() catch return error.MissingKey;
        var client = Client.init(allocator, config.chain);
        defer client.deinit();

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const aa = arena.allocator();

        const leverage_int = std.fmt.parseInt(i64, lev, 10) catch return error.InvalidFlag;
        var payload = std.json.ObjectMap.init(aa);
        try payload.put("symbol", .{ .string = a.symbol });
        try payload.put("leverage", .{ .integer = leverage_int });

        var resp = try doSignedPost(&client, "/account/leverage", &signer, config, "update_leverage", .{ .object = payload });
        defer resp.deinit();

        if (w.format == .json) return checkJsonResponse(w, resp.body);
        try handleSignedResponse(w, allocator, resp.body, "leverage updated");
    } else {
        const addr = config.getAddress() orelse return error.MissingAddress;
        var client = Client.init(allocator, config.chain);
        defer client.deinit();

        var resp = try client.getAccountSettings(addr);
        defer resp.deinit();

        if (w.format == .json) return checkJsonResponse(w, resp.body);
        _ = try parseAndExtractData(w, allocator, resp.body);
        try w.rawJson(resp.body);
    }
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  4. EDIT ORDER                                                ║
// ╚═══════════════════════════════════════════════════════════════╝

pub fn editOrder(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.EditArgs) !void {
    const signer = config.getSigner() catch return error.MissingKey;
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const order_id = std.fmt.parseInt(i64, a.order_id, 10) catch return error.InvalidFlag;
    var payload = std.json.ObjectMap.init(aa);
    try payload.put("symbol", .{ .string = a.symbol });
    try payload.put("order_id", .{ .integer = order_id });
    try payload.put("price", .{ .string = a.price });
    try payload.put("amount", .{ .string = a.amount });

    if (config.use_ws) {
        var res = try doSignedWs(allocator, &signer, config, "edit_order", "edit_order", .{ .object = payload });
        defer res.deinit(allocator);
        if (w.format == .json) return w.rawJson(res.body);
        try handleSignedResponse(w, allocator, res.body, "order edited");
        return;
    }

    var resp = try doSignedPost(&client, "/orders/edit", &signer, config, "edit_order", .{ .object = payload });
    defer resp.deinit();

    if (w.format == .json) return checkJsonResponse(w, resp.body);
    try handleSignedResponse(w, allocator, resp.body, "order edited");
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  5. MARGIN MODE                                               ║
// ╚═══════════════════════════════════════════════════════════════╝

pub fn marginCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.MarginArgs) !void {
    const signer = config.getSigner() catch return error.MissingKey;
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var payload = std.json.ObjectMap.init(aa);
    try payload.put("symbol", .{ .string = a.symbol });
    try payload.put("is_isolated", .{ .bool = a.isolated });

    var resp = try doSignedPost(&client, "/account/margin", &signer, config, "update_margin_mode", .{ .object = payload });
    defer resp.deinit();

    if (w.format == .json) return checkJsonResponse(w, resp.body);
    try handleSignedResponse(w, allocator, resp.body, "margin mode updated");
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  6. WITHDRAW                                                  ║
// ╚═══════════════════════════════════════════════════════════════╝

pub fn withdrawCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.WithdrawArgs) !void {
    const signer = config.getSigner() catch return error.MissingKey;
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var payload = std.json.ObjectMap.init(aa);
    try payload.put("amount", .{ .string = a.amount });

    var resp = try doSignedPost(&client, "/account/withdraw", &signer, config, "withdraw", .{ .object = payload });
    defer resp.deinit();

    if (w.format == .json) return checkJsonResponse(w, resp.body);
    try handleSignedResponse(w, allocator, resp.body, "withdrawal submitted");
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  7. STOP ORDERS                                               ║
// ╚═══════════════════════════════════════════════════════════════╝

pub fn stopCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.StopArgs) !void {
    const signer = config.getSigner() catch return error.MissingKey;
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    switch (a.action) {
        .cancel => {
            const oid = a.order_id orelse return error.MissingArgument;
            const order_id = std.fmt.parseInt(i64, oid, 10) catch return error.InvalidFlag;
            var payload = std.json.ObjectMap.init(aa);
            try payload.put("symbol", .{ .string = a.symbol });
            try payload.put("order_id", .{ .integer = order_id });

            var resp = try doSignedPost(&client, "/orders/stop/cancel", &signer, config, "cancel_stop_order", .{ .object = payload });
            defer resp.deinit();

            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try handleSignedResponse(w, allocator, resp.body, "stop order cancelled");
        },
        .create => {
            const stop_price = a.stop_price orelse return error.MissingArgument;
            const side = a.side orelse return error.MissingArgument;

            var stop_obj = std.json.ObjectMap.init(aa);
            try stop_obj.put("stop_price", .{ .string = stop_price });
            if (a.limit_price) |lp| try stop_obj.put("limit_price", .{ .string = lp });
            if (a.amount) |amt| try stop_obj.put("amount", .{ .string = amt });
            var uuid_buf: [36]u8 = undefined;
            try stop_obj.put("client_order_id", .{ .string = lib.uuid.v4(&uuid_buf) });

            var payload = std.json.ObjectMap.init(aa);
            try payload.put("symbol", .{ .string = a.symbol });
            try payload.put("side", .{ .string = mapPositionCloseSide(side) });
            try payload.put("reduce_only", .{ .bool = true });
            try payload.put("stop_order", .{ .object = stop_obj });

            if (a.dry_run) {
                var signed = try sdk.signing.signRequest(aa, &signer, "create_stop_order", .{ .object = payload }, @intCast(std.time.milliTimestamp()), 5000);
                defer signed.deinit();
                try w.print("DRY RUN — would send:\n{s}\n", .{signed.message});
                return;
            }

            var resp = try doSignedPost(&client, "/orders/stop/create", &signer, config, "create_stop_order", .{ .object = payload });
            defer resp.deinit();

            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try handleSignedResponse(w, allocator, resp.body, "stop order created");
        },
    }
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  8. TP/SL                                                     ║
// ╚═══════════════════════════════════════════════════════════════╝

pub fn tpslCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.TpSlArgs) !void {
    const signer = config.getSigner() catch return error.MissingKey;
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var payload = std.json.ObjectMap.init(aa);
    try payload.put("symbol", .{ .string = a.symbol });
    try payload.put("side", .{ .string = mapPositionCloseSide(a.side) });

    if (a.tp) |tp| {
        var tp_obj = std.json.ObjectMap.init(aa);
        try tp_obj.put("stop_price", .{ .string = tp });
        if (a.tp_limit) |tpl| try tp_obj.put("limit_price", .{ .string = tpl });
        if (a.tp_amount) |tpa| try tp_obj.put("amount", .{ .string = tpa });
        var uuid_buf: [36]u8 = undefined;
        try tp_obj.put("client_order_id", .{ .string = lib.uuid.v4(&uuid_buf) });
        try payload.put("take_profit", .{ .object = tp_obj });
    }

    if (a.sl) |sl| {
        var sl_obj = std.json.ObjectMap.init(aa);
        try sl_obj.put("stop_price", .{ .string = sl });
        if (a.sl_limit) |sll| try sl_obj.put("limit_price", .{ .string = sll });
        try payload.put("stop_loss", .{ .object = sl_obj });
    }

    if (a.dry_run) {
        var signed = try sdk.signing.signRequest(aa, &signer, "set_position_tpsl", .{ .object = payload }, @intCast(std.time.milliTimestamp()), 5000);
        defer signed.deinit();
        try w.print("DRY RUN — would send:\n{s}\n", .{signed.message});
        return;
    }

    var resp = try doSignedPost(&client, "/positions/tpsl", &signer, config, "set_position_tpsl", .{ .object = payload });
    defer resp.deinit();

    if (w.format == .json) return checkJsonResponse(w, resp.body);
    try handleSignedResponse(w, allocator, resp.body, "TP/SL set");
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  9. TWAP                                                      ║
// ╚═══════════════════════════════════════════════════════════════╝

pub fn twapCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.TwapArgs) !void {
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    switch (a.action) {
        .list => {
            const addr = a.address orelse config.getAddress() orelse return error.MissingAddress;
            var q: [128]u8 = undefined;
            var resp = try client.get("/orders/twap", std.fmt.bufPrint(&q, "account={s}", .{addr}) catch return error.UrlTooLong);
            defer resp.deinit();
            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try w.heading("TWAP Orders");
            try w.rawJson(resp.body);
            try w.footer();
        },
        .history => {
            const addr = a.address orelse config.getAddress() orelse return error.MissingAddress;
            var q: [128]u8 = undefined;
            var resp = try client.get("/orders/twap/history", std.fmt.bufPrint(&q, "account={s}", .{addr}) catch return error.UrlTooLong);
            defer resp.deinit();
            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try w.heading("TWAP History");
            try w.rawJson(resp.body);
            try w.footer();
        },
        .cancel => {
            const signer = config.getSigner() catch return error.MissingKey;
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const aa = arena.allocator();

            const oid = a.order_id orelse return error.MissingArgument;
            const order_id = std.fmt.parseInt(i64, oid, 10) catch return error.InvalidFlag;
            var payload = std.json.ObjectMap.init(aa);
            try payload.put("symbol", .{ .string = a.symbol });
            try payload.put("order_id", .{ .integer = order_id });

            var resp = try doSignedPost(&client, "/orders/twap/cancel", &signer, config, "cancel_twap_order", .{ .object = payload });
            defer resp.deinit();

            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try handleSignedResponse(w, allocator, resp.body, "TWAP order cancelled");
        },
        .create => {
            const signer = config.getSigner() catch return error.MissingKey;
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const aa = arena.allocator();

            const raw_side = a.side orelse return error.MissingArgument;
            const amount = a.amount orelse return error.MissingArgument;
            const duration = a.duration orelse return error.MissingArgument;
            const duration_secs = std.fmt.parseInt(i64, duration, 10) catch return error.InvalidFlag;

            const side = mapSide(raw_side);

            var payload = std.json.ObjectMap.init(aa);
            try payload.put("symbol", .{ .string = a.symbol });
            try payload.put("side", .{ .string = side });
            try payload.put("amount", .{ .string = amount });
            try payload.put("reduce_only", .{ .bool = false });
            try payload.put("duration_in_seconds", .{ .integer = duration_secs });
            if (a.slippage) |s| try payload.put("slippage_percent", .{ .string = s }) else try payload.put("slippage_percent", .{ .string = "0.5" });

            var uuid_buf: [36]u8 = undefined;
            try payload.put("client_order_id", .{ .string = lib.uuid.v4(&uuid_buf) });

            if (a.dry_run) {
                var signed = try sdk.signing.signRequest(aa, &signer, "create_twap_order", .{ .object = payload }, @intCast(std.time.milliTimestamp()), 5000);
                defer signed.deinit();
                try w.print("DRY RUN — would send:\n{s}\n", .{signed.message});
                return;
            }

            var resp = try doSignedPost(&client, "/orders/twap/create", &signer, config, "create_twap_order", .{ .object = payload });
            defer resp.deinit();

            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try handleSignedResponse(w, allocator, resp.body, "TWAP order created");
        },
    }
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  10. ACCESS                                                   ║
// ╚═══════════════════════════════════════════════════════════════╝

pub fn depositCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.DepositArgs) !void {
    if (!std.mem.eql(u8, a.network, "solana")) {
        try w.fail("only `deposit solana` is supported");
        return error.CommandFailed;
    }
    if (config.chain != .mainnet) {
        try w.fail("deposit is mainnet-only for now");
        return error.CommandFailed;
    }
    const amount = a.amount orelse return error.MissingArgument;
    const rpc_url = a.rpc_url orelse config.getSolanaRpcUrl();
    const amount_units = sdk.solana.parseUsdcAmount(amount) catch return error.InvalidFlag;
    if (amount_units < sdk.solana.MIN_DEPOSIT_USDC_UNITS) {
        if (w.format == .json) {
            var buf: [1024]u8 = undefined;
            const ms = w.elapsedMs();
            const body = std.fmt.bufPrint(&buf,
                "{{\"v\":1,\"status\":\"error\",\"cmd\":\"deposit\",\"error\":\"CommandFailed\",\"message\":\"minimum Pacifica deposit is 10 USDC\",\"data\":{{\"network\":\"solana\",\"requested_amount\":\"{s}\",\"minimum_amount\":\"10\",\"rpc\":\"{s}\"}},\"timing_ms\":{d}}}",
                .{ amount, rpc_url, ms }
            ) catch return error.Overflow;
            try w.rawJson(body);
            return error.CommandFailed;
        }
        try w.fail("minimum Pacifica deposit is 10 USDC");
        return error.CommandFailed;
    }

    const signer = config.getSigner() catch return error.MissingKey;

    var preflight = sdk.solana.depositPreflight(allocator, rpc_url, &signer) catch |e| {
        if (w.format == .json) {
            var buf: [1024]u8 = undefined;
            const ms = w.elapsedMs();
            const body = std.fmt.bufPrint(&buf,
                "{{\"v\":1,\"status\":\"error\",\"cmd\":\"deposit\",\"error\":\"CommandFailed\",\"message\":\"deposit preflight failed\",\"data\":{{\"reason\":\"{s}\",\"network\":\"solana\",\"requested_amount\":\"{s}\",\"rpc\":\"{s}\"}},\"timing_ms\":{d}}}",
                .{ @errorName(e), amount, rpc_url, ms }
            ) catch return error.Overflow;
            try w.rawJson(body);
            return error.CommandFailed;
        }
        return failFmt(w, "deposit preflight failed ({s})", .{@errorName(e)});
    };
    defer preflight.deinit(allocator);

    if (preflight.usdc_units < amount_units) {
        if (w.format == .json) {
            var buf: [1400]u8 = undefined;
            const ms = w.elapsedMs();
            const body = std.fmt.bufPrint(&buf,
                "{{\"v\":1,\"status\":\"error\",\"cmd\":\"deposit\",\"error\":\"CommandFailed\",\"message\":\"insufficient USDC balance for deposit amount\",\"data\":{{\"network\":\"solana\",\"requested_amount\":\"{s}\",\"requested_units\":{d},\"rpc\":\"{s}\",\"address\":\"{s}\",\"usdc_ata\":\"{s}\",\"sol_lamports\":{d},\"usdc_units\":{d}}},\"timing_ms\":{d}}}",
                .{ amount, amount_units, rpc_url, preflight.address_b58, preflight.ata_b58, preflight.sol_lamports, preflight.usdc_units, ms }
            ) catch return error.Overflow;
            try w.rawJson(body);
            return error.CommandFailed;
        }
        try w.fail("insufficient USDC balance for deposit amount");
        try w.kv("RPC", rpc_url);
        try w.kv("Address", preflight.address_b58);
        try w.kv("USDC ATA", preflight.ata_b58);
        try w.kv("Requested USDC", amount);
        return error.CommandFailed;
    }

    var result = sdk.solana.depositUsdc(allocator, rpc_url, &signer, amount) catch |e| {
        if (w.format == .json) {
            var buf: [1600]u8 = undefined;
            const ms = w.elapsedMs();
            const body = std.fmt.bufPrint(&buf,
                "{{\"v\":1,\"status\":\"error\",\"cmd\":\"deposit\",\"error\":\"CommandFailed\",\"message\":\"deposit failed\",\"data\":{{\"reason\":\"{s}\",\"network\":\"solana\",\"requested_amount\":\"{s}\",\"rpc\":\"{s}\",\"address\":\"{s}\",\"usdc_ata\":\"{s}\",\"sol_lamports\":{d},\"usdc_units\":{d}}},\"timing_ms\":{d}}}",
                .{ @errorName(e), amount, rpc_url, preflight.address_b58, preflight.ata_b58, preflight.sol_lamports, preflight.usdc_units, ms }
            ) catch return error.Overflow;
            try w.rawJson(body);
            return error.CommandFailed;
        }

        try w.failFmt("deposit failed: {s}", .{@errorName(e)});
        try w.kv("RPC", rpc_url);
        try w.kv("Address", preflight.address_b58);
        try w.kv("USDC ATA", preflight.ata_b58);
        try w.kv("Requested USDC", amount);
        var sol_buf: [64]u8 = undefined;
        const sol_str = std.fmt.bufPrint(&sol_buf, "{d}", .{preflight.sol_lamports}) catch "-";
        try w.kv("SOL lamports", sol_str);
        var usdc_buf: [64]u8 = undefined;
        const usdc_str = std.fmt.bufPrint(&usdc_buf, "{d}", .{preflight.usdc_units}) catch "-";
        try w.kv("USDC units", usdc_str);
        return error.CommandFailed;
    };
    defer result.deinit(allocator);

    if (w.format == .json) {
        var buf: [1400]u8 = undefined;
        const status = result.confirmation_status orelse "submitted";
        const body = std.fmt.bufPrint(&buf, "{{\"signature\":\"{s}\",\"confirmation_status\":\"{s}\",\"network\":\"solana\",\"amount\":\"{s}\",\"rpc\":\"{s}\",\"address\":\"{s}\",\"usdc_ata\":\"{s}\",\"sol_lamports\":{d},\"usdc_units\":{d}}}", .{ result.signature, status, amount, rpc_url, preflight.address_b58, preflight.ata_b58, preflight.sol_lamports, preflight.usdc_units }) catch return error.Overflow;
        try w.jsonRaw(body);
        return;
    }

    try w.success("deposit submitted");
    try w.kv("Amount", amount);
    try w.kv("Network", "solana");
    try w.kv("RPC", rpc_url);
    try w.kv("Address", preflight.address_b58);
    try w.kv("USDC ATA", preflight.ata_b58);
    var sol_buf: [64]u8 = undefined;
    const sol_str = std.fmt.bufPrint(&sol_buf, "{d}", .{preflight.sol_lamports}) catch "-";
    try w.kv("SOL lamports", sol_str);
    var usdc_buf: [64]u8 = undefined;
    const usdc_str = std.fmt.bufPrint(&usdc_buf, "{d}", .{preflight.usdc_units}) catch "-";
    try w.kv("USDC units", usdc_str);
    try w.kv("Signature", result.signature);
    try w.kv("Status", result.confirmation_status orelse "submitted");
    try w.footer();
}

pub fn accessCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.AccessArgs) !void {
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    switch (a.action) {
        .claim => {
            const code = a.code orelse return error.MissingArgument;
            const signer = config.getSigner() catch return error.MissingKey;
            var resp = try client.claimAccessCode(&signer, code);
            defer resp.deinit();
            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try handleSignedResponse(w, allocator, resp.body, "beta access claimed");
        },
        .status => {
            const addr = a.address orelse config.getAddress() orelse return error.MissingAddress;
            var resp = try client.getWhitelistStatus(addr);
            defer resp.deinit();
            if (w.format == .json) return checkJsonResponse(w, resp.body);

            try w.heading("Access");
            var result = try parseAndExtractData(w, allocator, resp.body);
            defer result.parsed.deinit();
            const obj = switch (result.data) {
                .object => |o| o,
                else => {
                    try w.fail("unexpected response format");
                    return error.CommandFailed;
                },
            };
            const status = if (obj.get("is_whitelisted")) |v| switch (v) {
                .bool => |b| if (b) "true" else "false",
                else => "-",
            } else "-";
            try w.kv("Address", addr);
            try w.kv("Whitelisted", status);
            try w.footer();
        },
    }
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  11. AGENT WALLETS                                            ║
// ╚═══════════════════════════════════════════════════════════════╝

pub fn agentCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.AgentArgs) !void {
    const signer = config.getSigner() catch return error.MissingKey;
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    switch (a.action) {
        .bind => {
            const addr = a.agent_addr orelse return error.MissingArgument;
            var payload = std.json.ObjectMap.init(aa);
            try payload.put("agent_wallet", .{ .string = addr });
            var resp = try doSignedPost(&client, "/agent/bind", &signer, config, "bind_agent_wallet", .{ .object = payload });
            defer resp.deinit();
            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try handleSignedResponse(w, allocator, resp.body, "agent wallet bound");
        },
        .list => {
            const payload = std.json.ObjectMap.init(aa);
            var resp = try doSignedPost(&client, "/agent/list", &signer, config, "list_agent_wallets", .{ .object = payload });
            defer resp.deinit();
            if (w.format == .json) return checkJsonResponse(w, resp.body);
            _ = try parseAndExtractData(w, allocator, resp.body);
            try w.heading("Agent Wallets");
            try w.rawJson(resp.body);
            try w.footer();
        },
        .revoke => {
            const addr = a.agent_addr orelse return error.MissingArgument;
            var payload = std.json.ObjectMap.init(aa);
            try payload.put("agent_wallet", .{ .string = addr });
            var resp = try doSignedPost(&client, "/agent/revoke", &signer, config, "revoke_agent_wallet", .{ .object = payload });
            defer resp.deinit();
            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try handleSignedResponse(w, allocator, resp.body, "agent wallet revoked");
        },
        .revoke_all => {
            const payload = std.json.ObjectMap.init(aa);
            var resp = try doSignedPost(&client, "/agent/revoke_all", &signer, config, "revoke_all_agent_wallets", .{ .object = payload });
            defer resp.deinit();
            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try handleSignedResponse(w, allocator, resp.body, "all agent wallets revoked");
        },
        .ip_list => {
            const addr = a.agent_addr orelse return error.MissingArgument;
            var payload = std.json.ObjectMap.init(aa);
            try payload.put("api_agent_key", .{ .string = addr });
            var resp = try doSignedPost(&client, "/agent/ip_whitelist/list", &signer, config, "list_agent_ip_whitelist", .{ .object = payload });
            defer resp.deinit();
            if (w.format == .json) return checkJsonResponse(w, resp.body);
            _ = try parseAndExtractData(w, allocator, resp.body);
            try w.heading("Agent IP Whitelist");
            try w.rawJson(resp.body);
            try w.footer();
        },
        .ip_add => {
            const addr = a.agent_addr orelse return error.MissingArgument;
            const ip = a.ip orelse return error.MissingArgument;
            var payload = std.json.ObjectMap.init(aa);
            try payload.put("agent_wallet", .{ .string = addr });
            try payload.put("ip_address", .{ .string = ip });
            var resp = try doSignedPost(&client, "/agent/ip_whitelist/add", &signer, config, "add_agent_whitelisted_ip", .{ .object = payload });
            defer resp.deinit();
            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try handleSignedResponse(w, allocator, resp.body, "IP added to whitelist");
        },
        .ip_remove => {
            const addr = a.agent_addr orelse return error.MissingArgument;
            const ip = a.ip orelse return error.MissingArgument;
            var payload = std.json.ObjectMap.init(aa);
            try payload.put("agent_wallet", .{ .string = addr });
            try payload.put("ip_address", .{ .string = ip });
            var resp = try doSignedPost(&client, "/agent/ip_whitelist/remove", &signer, config, "remove_agent_whitelisted_ip", .{ .object = payload });
            defer resp.deinit();
            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try handleSignedResponse(w, allocator, resp.body, "IP removed from whitelist");
        },
        .ip_toggle => {
            const addr = a.agent_addr orelse return error.MissingArgument;
            const enable = a.enable orelse return error.MissingArgument;
            var payload = std.json.ObjectMap.init(aa);
            try payload.put("agent_wallet", .{ .string = addr });
            try payload.put("enabled", .{ .bool = enable });
            var resp = try doSignedPost(&client, "/agent/ip_whitelist/toggle", &signer, config, "set_agent_ip_whitelist_enabled", .{ .object = payload });
            defer resp.deinit();
            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try handleSignedResponse(w, allocator, resp.body, "IP whitelist updated");
        },
    }
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  11. SUBACCOUNTS                                              ║
// ╚═══════════════════════════════════════════════════════════════╝

pub fn subaccountCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.SubaccountArgs) !void {
    const signer = config.getSigner() catch return error.MissingKey;
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    switch (a.action) {
        .list => {
            const payload = std.json.ObjectMap.init(aa);
            var resp = try doSignedPost(&client, "/account/subaccount/list", &signer, config, "list_subaccounts", .{ .object = payload });
            defer resp.deinit();
            if (w.format == .json) return checkJsonResponse(w, resp.body);
            _ = try parseAndExtractData(w, allocator, resp.body);
            try w.heading("Subaccounts");
            try w.rawJson(resp.body);
            try w.footer();
        },
        .create => {
            const sub_key_b58 = a.key_or_addr orelse return error.MissingArgument;
            const sub_signer = lib.crypto.signer.Signer.fromBase58(sub_key_b58) catch return error.InvalidFlag;

            const main_pub = try config.requireAddress();
            var sub_pub_buf: [44]u8 = undefined;
            const sub_pub = sub_signer.pubkeyBase58(&sub_pub_buf);

            const timestamp: u64 = @intCast(std.time.milliTimestamp());
            const expiry_window: u64 = 5000;

            var init_payload = std.json.ObjectMap.init(aa);
            try init_payload.put("account", .{ .string = main_pub });
            var init_signed = try sdk.signing.signRequest(aa, &sub_signer, "subaccount_initiate", .{ .object = init_payload }, timestamp, expiry_window);
            defer init_signed.deinit();

            var confirm_payload = std.json.ObjectMap.init(aa);
            try confirm_payload.put("signature", .{ .string = init_signed.signature() });
            var confirm_signed = try sdk.signing.signRequest(aa, &signer, "subaccount_confirm", .{ .object = confirm_payload }, timestamp, expiry_window);
            defer confirm_signed.deinit();

            var body_buf = std.ArrayList(u8){};
            defer body_buf.deinit(allocator);
            try body_buf.appendSlice(allocator, "{\"main_account\":\"");
            try body_buf.appendSlice(allocator, main_pub);
            try body_buf.appendSlice(allocator, "\",\"subaccount\":\"");
            try body_buf.appendSlice(allocator, sub_pub);
            try body_buf.appendSlice(allocator, "\",\"main_signature\":\"");
            try body_buf.appendSlice(allocator, confirm_signed.signature());
            try body_buf.appendSlice(allocator, "\",\"sub_signature\":\"");
            try body_buf.appendSlice(allocator, init_signed.signature());
            try body_buf.appendSlice(allocator, "\",\"timestamp\":");
            var ts_buf: [24]u8 = undefined;
            try body_buf.appendSlice(allocator, std.fmt.bufPrint(&ts_buf, "{d}", .{timestamp}) catch unreachable);
            try body_buf.appendSlice(allocator, ",\"expiry_window\":");
            var ew_buf: [24]u8 = undefined;
            try body_buf.appendSlice(allocator, std.fmt.bufPrint(&ew_buf, "{d}", .{expiry_window}) catch unreachable);
            try body_buf.append(allocator, '}');

            var resp = try client.post("/account/subaccount/create", body_buf.items);
            defer resp.deinit();

            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try handleSignedResponse(w, allocator, resp.body, "subaccount created");
        },
        .transfer => {
            const amount = a.amount orelse return error.MissingArgument;
            const to_addr = a.key_or_addr orelse return error.MissingArgument;
            var payload = std.json.ObjectMap.init(aa);
            try payload.put("to_account", .{ .string = to_addr });
            try payload.put("amount", .{ .string = amount });

            var resp = try doSignedPost(&client, "/account/subaccount/transfer", &signer, config, "transfer_funds", .{ .object = payload });
            defer resp.deinit();

            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try handleSignedResponse(w, allocator, resp.body, "transfer complete");
        },
    }
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  12. API KEYS                                                 ║
// ╚═══════════════════════════════════════════════════════════════╝

pub fn apiKeyCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.ApiKeyArgs) !void {
    const signer = config.getSigner() catch return error.MissingKey;
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    switch (a.action) {
        .create => {
            const payload = std.json.ObjectMap.init(aa);
            var resp = try doSignedPost(&client, "/account/api_keys/create", &signer, config, "create_api_key", .{ .object = payload });
            defer resp.deinit();
            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try handleSignedResponse(w, allocator, resp.body, "API key created");
        },
        .revoke => {
            const key = a.key orelse return error.MissingArgument;
            var payload = std.json.ObjectMap.init(aa);
            try payload.put("api_key", .{ .string = key });
            var resp = try doSignedPost(&client, "/account/api_keys/revoke", &signer, config, "revoke_api_key", .{ .object = payload });
            defer resp.deinit();
            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try handleSignedResponse(w, allocator, resp.body, "API key revoked");
        },
        .list => {
            const payload = std.json.ObjectMap.init(aa);
            var resp = try doSignedPost(&client, "/account/api_keys", &signer, config, "list_api_keys", .{ .object = payload });
            defer resp.deinit();
            if (w.format == .json) return checkJsonResponse(w, resp.body);
            _ = try parseAndExtractData(w, allocator, resp.body);
            try w.heading("API Keys");
            try w.rawJson(resp.body);
            try w.footer();
        },
    }
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  13. LAKE                                                     ║
// ╚═══════════════════════════════════════════════════════════════╝

pub fn lakeCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.LakeArgs) !void {
    const signer = config.getSigner() catch return error.MissingKey;
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    switch (a.action) {
        .create => {
            var pub_buf: [44]u8 = undefined;
            const signer_pub = signer.pubkeyBase58(&pub_buf);
            const default_manager = config.getAddress() orelse signer_pub;

            var payload = std.json.ObjectMap.init(aa);
            try payload.put("manager", .{ .string = a.manager orelse default_manager });
            if (a.nickname) |n| try payload.put("nickname", .{ .string = n });
            var resp = try doSignedPost(&client, "/lake/create", &signer, config, "create_lake", .{ .object = payload });
            defer resp.deinit();
            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try handleSignedResponse(w, allocator, resp.body, "lake created");
        },
        .deposit => {
            const addr = a.addr orelse return error.MissingArgument;
            const amount = a.amount orelse return error.MissingArgument;
            var payload = std.json.ObjectMap.init(aa);
            try payload.put("lake", .{ .string = addr });
            try payload.put("amount", .{ .string = amount });
            var resp = try doSignedPost(&client, "/lake/deposit", &signer, config, "deposit_to_lake", .{ .object = payload });
            defer resp.deinit();
            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try handleSignedResponse(w, allocator, resp.body, "deposited to lake");
        },
        .withdraw => {
            const addr = a.addr orelse return error.MissingArgument;
            const shares = a.amount orelse return error.MissingArgument;
            var payload = std.json.ObjectMap.init(aa);
            try payload.put("lake", .{ .string = addr });
            try payload.put("shares", .{ .string = shares });
            var resp = try doSignedPost(&client, "/lake/withdraw", &signer, config, "withdraw_from_lake", .{ .object = payload });
            defer resp.deinit();
            if (w.format == .json) return checkJsonResponse(w, resp.body);
            try handleSignedResponse(w, allocator, resp.body, "withdrawn from lake");
        },
    }
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  14. BATCH                                                    ║
// ╚═══════════════════════════════════════════════════════════════╝

pub fn batchCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.BatchArgs) !void {
    const signer = config.getSigner() catch return error.MissingKey;
    const ctx = try config.getSigningContext();
    var client = Client.init(allocator, config.chain);
    defer client.deinit();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const timestamp: u64 = @intCast(std.time.milliTimestamp());
    const expiry_window: u64 = 5000;

    var pub_buf: [44]u8 = undefined;
    const signer_pub = signer.pubkeyBase58(&pub_buf);
    const acct = ctx.account_addr orelse signer_pub;

    var body_buf = std.ArrayList(u8){};
    defer body_buf.deinit(allocator);

    try body_buf.appendSlice(allocator, "{\"actions\":[");

    var action_count: usize = 0;

    var i: usize = 0;
    while (i < a.count) : (i += 1) {
        const order_str = a.orders[i] orelse continue;
        if (parseBatchAction(aa, order_str, &signer, acct, ctx.agent_pubkey, timestamp, expiry_window)) |action_json| {
            if (action_count > 0) try body_buf.appendSlice(allocator, ",");
            try body_buf.appendSlice(allocator, action_json);
            action_count += 1;
        } else {
            try w.errFmt("skipping invalid batch action: {s}", .{order_str});
        }
    }

    if (a.stdin) {
        const stdin = std.fs.File.stdin();
        const stdin_data = stdin.readToEndAlloc(allocator, 64 * 1024) catch {
            try w.fail("failed to read stdin");
            return error.CommandFailed;
        };
        defer allocator.free(stdin_data);

        var lines = std.mem.splitScalar(u8, stdin_data, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            if (parseBatchAction(aa, trimmed, &signer, acct, ctx.agent_pubkey, timestamp, expiry_window)) |action_json| {
                if (action_count > 0) try body_buf.appendSlice(allocator, ",");
                try body_buf.appendSlice(allocator, action_json);
                action_count += 1;
            } else {
                try w.errFmt("skipping invalid batch action: {s}", .{trimmed});
            }
        }
    }

    try body_buf.appendSlice(allocator, "]}");

    if (action_count == 0) {
        try w.fail("no valid batch actions");
        return error.MissingArgument;
    }
    if (action_count > 10) {
        try w.fail("batch supports at most 10 actions");
        return error.CommandFailed;
    }

    if (config.use_ws) {
        var ws_client = try sdk.ws.Client.init(allocator, config.chain, config.api_key);
        defer ws_client.deinit();
        var res = try ws_client.rawAction("batch", body_buf.items);
        defer res.deinit(allocator);
        if (w.format == .json) return w.rawJson(res.body);
        try handleSignedResponse(w, allocator, res.body, "batch executed");
        return;
    }

    var resp = try client.post("/orders/batch", body_buf.items);
    defer resp.deinit();

    if (w.format == .json) return checkJsonResponse(w, resp.body);
    try handleSignedResponse(w, allocator, resp.body, "batch executed");
}

fn parseBatchAction(
    aa: std.mem.Allocator,
    order_str: []const u8,
    signer: *const lib.crypto.signer.Signer,
    acct: []const u8,
    agent_pubkey: ?[]const u8,
    timestamp: u64,
    expiry_window: u64,
) ?[]const u8 {
    var parts: [8][]const u8 = undefined;
    var count: usize = 0;
    var it = std.mem.splitScalar(u8, order_str, ' ');
    while (it.next()) |part| {
        if (part.len == 0) continue;
        if (count >= 8) break;
        parts[count] = part;
        count += 1;
    }
    if (count < 2) return null;

    const action = parts[0];
    if (std.mem.eql(u8, action, "buy") or std.mem.eql(u8, action, "sell")) {
        if (count < 4) return null;
        const symbol = parts[1];
        const amount = parts[2];
        const side: []const u8 = if (std.mem.eql(u8, action, "buy")) "bid" else "ask";

        var raw_price = parts[3];
        if (raw_price.len > 0 and raw_price[0] == '@') raw_price = raw_price[1..];

        return buildBatchCreate(aa, signer, acct, agent_pubkey, timestamp, expiry_window, symbol, amount, side, raw_price);
    } else if (std.mem.eql(u8, action, "cancel")) {
        if (count < 3) return null;
        return buildBatchCancel(aa, signer, acct, agent_pubkey, timestamp, expiry_window, parts[1], parts[2]);
    }
    return null;
}

fn buildBatchCreate(
    aa: std.mem.Allocator,
    signer: *const lib.crypto.signer.Signer,
    acct: []const u8,
    agent_pubkey: ?[]const u8,
    timestamp: u64,
    expiry_window: u64,
    symbol: []const u8,
    amount: []const u8,
    side: []const u8,
    price: []const u8,
) ?[]const u8 {
    var payload = std.json.ObjectMap.init(aa);
    payload.put("symbol", .{ .string = symbol }) catch return null;
    payload.put("price", .{ .string = price }) catch return null;
    payload.put("amount", .{ .string = amount }) catch return null;
    payload.put("side", .{ .string = side }) catch return null;
    payload.put("tif", .{ .string = "GTC" }) catch return null;
    payload.put("reduce_only", .{ .bool = false }) catch return null;
    var uuid_buf: [36]u8 = undefined;
    payload.put("client_order_id", .{ .string = lib.uuid.v4(&uuid_buf) }) catch return null;

    var signed = sdk.signing.signRequest(aa, signer, "create_order", .{ .object = payload }, timestamp, expiry_window) catch return null;
    defer signed.deinit();

    return buildBatchBody(aa, "Create", acct, agent_pubkey, signed.signature(), timestamp, expiry_window, payload);
}

fn buildBatchCancel(
    aa: std.mem.Allocator,
    signer: *const lib.crypto.signer.Signer,
    acct: []const u8,
    agent_pubkey: ?[]const u8,
    timestamp: u64,
    expiry_window: u64,
    symbol: []const u8,
    order_id_str: []const u8,
) ?[]const u8 {
    const order_id = std.fmt.parseInt(i64, order_id_str, 10) catch return null;

    var payload = std.json.ObjectMap.init(aa);
    payload.put("symbol", .{ .string = symbol }) catch return null;
    payload.put("order_id", .{ .integer = order_id }) catch return null;

    var signed = sdk.signing.signRequest(aa, signer, "cancel_order", .{ .object = payload }, timestamp, expiry_window) catch return null;
    defer signed.deinit();

    return buildBatchBody(aa, "Cancel", acct, agent_pubkey, signed.signature(), timestamp, expiry_window, payload);
}

fn buildBatchBody(
    aa: std.mem.Allocator,
    action_type: []const u8,
    acct: []const u8,
    agent_pubkey: ?[]const u8,
    sig: []const u8,
    timestamp: u64,
    expiry_window: u64,
    payload: std.json.ObjectMap,
) ?[]const u8 {
    var buf = std.ArrayList(u8){};
    buf.appendSlice(aa, "{\"type\":\"") catch return null;
    buf.appendSlice(aa, action_type) catch return null;
    buf.appendSlice(aa, "\",\"data\":{\"account\":\"") catch return null;
    buf.appendSlice(aa, acct) catch return null;
    buf.appendSlice(aa, "\",\"signature\":\"") catch return null;
    buf.appendSlice(aa, sig) catch return null;
    buf.appendSlice(aa, "\",\"timestamp\":") catch return null;
    var ts_buf: [24]u8 = undefined;
    buf.appendSlice(aa, std.fmt.bufPrint(&ts_buf, "{d}", .{timestamp}) catch return null) catch return null;
    buf.appendSlice(aa, ",\"expiry_window\":") catch return null;
    var ew_buf: [24]u8 = undefined;
    buf.appendSlice(aa, std.fmt.bufPrint(&ew_buf, "{d}", .{expiry_window}) catch return null) catch return null;

    if (agent_pubkey) |aw| {
        buf.appendSlice(aa, ",\"agent_wallet\":\"") catch return null;
        buf.appendSlice(aa, aw) catch return null;
        buf.appendSlice(aa, "\"") catch return null;
    }

    var pit = payload.iterator();
    while (pit.next()) |entry| {
        buf.appendSlice(aa, ",\"") catch return null;
        buf.appendSlice(aa, entry.key_ptr.*) catch return null;
        buf.appendSlice(aa, "\":") catch return null;
        const val_str = lib.json.compactStringify(aa, entry.value_ptr.*) catch return null;
        defer aa.free(val_str);
        buf.appendSlice(aa, val_str) catch return null;
    }
    buf.appendSlice(aa, "}}") catch return null;
    return buf.items;
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  15. STREAMING                                                ║
// ╚═══════════════════════════════════════════════════════════════╝

pub fn streamCmd(allocator: std.mem.Allocator, w: *Writer, config: *Config, a: args_mod.StreamArgs) !void {
    var ws_client = sdk.ws.Client.init(allocator, config.chain, config.api_key) catch |e| return failFmt(w, "ws connect: {s}", .{@errorName(e)});
    defer ws_client.deinit();

    const params = try streamParams(allocator, config, a);
    defer allocator.free(params);

    ws_client.subscribe(params) catch |e| return failFmt(w, "ws subscribe: {s}", .{@errorName(e)});

    var last_ping_ms: i64 = std.time.milliTimestamp();
    while (true) {
        const maybe_text = ws_client.nextText() catch |e| switch (e) {
            error.Closed => return,
            else => return failFmt(w, "ws read: {s}", .{@errorName(e)}),
        };
        if (maybe_text) |text| {
            defer allocator.free(text);
            if (w.format == .json) {
                try w.rawJson(text);
            } else if (std.mem.indexOf(u8, text, "\"channel\":\"subscribe\"") != null) {
                try w.styled(Style.muted, text);
                try w.print("\n", .{});
            } else {
                try w.print("{s}\n", .{text});
            }
            last_ping_ms = std.time.milliTimestamp();
        } else {
            const now = std.time.milliTimestamp();
            if (now - last_ping_ms >= 30_000) {
                ws_client.sendPing() catch |e| return failFmt(w, "ws ping: {s}", .{@errorName(e)});
                last_ping_ms = now;
            }
        }
    }
}

fn streamParams(allocator: std.mem.Allocator, config: *Config, a: args_mod.StreamArgs) ![]u8 {
    return switch (a.kind) {
        .prices => allocator.dupe(u8, "{\"source\":\"prices\"}"),
        .orderbook => std.fmt.allocPrint(allocator, "{{\"source\":\"orderbook\",\"symbol\":\"{s}\"}}", .{a.symbol orelse return error.MissingArgument}),
        .bbo => std.fmt.allocPrint(allocator, "{{\"source\":\"bbo\",\"symbol\":\"{s}\"}}", .{a.symbol orelse return error.MissingArgument}),
        .trades => std.fmt.allocPrint(allocator, "{{\"source\":\"trades\",\"symbol\":\"{s}\"}}", .{a.symbol orelse return error.MissingArgument}),
        .candle => std.fmt.allocPrint(allocator, "{{\"source\":\"candle\",\"symbol\":\"{s}\",\"interval\":\"{s}\"}}", .{ a.symbol orelse return error.MissingArgument, a.interval }),
        .mark_price_candle => std.fmt.allocPrint(allocator, "{{\"source\":\"mark_price_candle\",\"symbol\":\"{s}\",\"interval\":\"{s}\"}}", .{ a.symbol orelse return error.MissingArgument, a.interval }),
        .account_margin => std.fmt.allocPrint(allocator, "{{\"source\":\"account_margin\",\"account\":\"{s}\"}}", .{a.address orelse try config.requireAddress()}),
        .account_leverage => std.fmt.allocPrint(allocator, "{{\"source\":\"account_leverage\",\"account\":\"{s}\"}}", .{a.address orelse try config.requireAddress()}),
        .account_info => std.fmt.allocPrint(allocator, "{{\"source\":\"account_info\",\"account\":\"{s}\"}}", .{a.address orelse try config.requireAddress()}),
        .account_positions => std.fmt.allocPrint(allocator, "{{\"source\":\"account_positions\",\"account\":\"{s}\"}}", .{a.address orelse try config.requireAddress()}),
        .account_order_updates => std.fmt.allocPrint(allocator, "{{\"source\":\"account_order_updates\",\"account\":\"{s}\"}}", .{a.address orelse try config.requireAddress()}),
        .account_trades => std.fmt.allocPrint(allocator, "{{\"source\":\"account_trades\",\"account\":\"{s}\"}}", .{a.address orelse try config.requireAddress()}),
        .account_twap_orders => std.fmt.allocPrint(allocator, "{{\"source\":\"account_twap_orders\",\"account\":\"{s}\"}}", .{a.address orelse try config.requireAddress()}),
        .account_twap_order_updates => std.fmt.allocPrint(allocator, "{{\"source\":\"account_twap_order_updates\",\"account\":\"{s}\"}}", .{a.address orelse try config.requireAddress()}),
    };
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  Helpers                                                      ║
// ╚═══════════════════════════════════════════════════════════════╝

fn handleSignedResponse(w: *Writer, allocator: std.mem.Allocator, body: []const u8, success_msg: []const u8) !void {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        try w.fail("invalid JSON response");
        return error.CommandFailed;
    };
    defer parsed.deinit();
    if (isSuccess(parsed.value)) {
        try w.success(success_msg);
    } else {
        try w.fail(extractError(parsed.value));
        return error.CommandFailed;
    }
}

fn checkJsonResponse(w: *Writer, body: []const u8) !void {
    try w.jsonResponse(body);
    if (!output_mod.bodyIsSuccess(body)) return error.CommandFailed;
}

fn parseAndExtractData(w: *Writer, allocator: std.mem.Allocator, body: []const u8) !struct { parsed: std.json.Parsed(std.json.Value), data: std.json.Value } {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        try w.fail("invalid JSON response");
        return error.CommandFailed;
    };
    if (extractData(parsed.value)) |data| {
        return .{ .parsed = parsed, .data = data };
    }
    const err_msg = extractError(parsed.value);
    try w.fail(err_msg);
    parsed.deinit();
    return error.CommandFailed;
}

fn extractData(value: std.json.Value) ?std.json.Value {
    switch (value) {
        .object => |obj| {
            if (obj.get("success")) |s| {
                switch (s) {
                    .bool => |b| if (!b) return null,
                    else => {},
                }
            }
            if (obj.get("data")) |d| return d;
        },
        else => {},
    }
    return null;
}

fn isSuccess(value: std.json.Value) bool {
    switch (value) {
        .object => |obj| {
            if (obj.get("success")) |s| {
                return switch (s) {
                    .bool => |b| b,
                    else => false,
                };
            }
            if (obj.get("code")) |c| {
                return switch (c) {
                    .integer => |ii| ii >= 200 and ii < 300,
                    else => false,
                };
            }
        },
        else => {},
    }
    return false;
}

fn extractError(value: std.json.Value) []const u8 {
    switch (value) {
        .object => |obj| {
            if (obj.get("error")) |e| {
                return switch (e) {
                    .string => |s| s,
                    else => "unknown error",
                };
            }
            if (obj.get("message")) |m| {
                return switch (m) {
                    .string => |s| s,
                    else => "request failed",
                };
            }
            if (obj.get("code")) |c| {
                return switch (c) {
                    .integer => |ii| if (ii >= 200 and ii < 300) "" else "request failed",
                    else => "request failed",
                };
            }
        },
        else => {},
    }
    return "request failed";
}

fn jsonStr(obj: std.json.ObjectMap, key: []const u8) []const u8 {
    if (obj.get(key)) |val| {
        return switch (val) {
            .string => |s| s,
            .integer => |ii| blk: {
                const S = struct {
                    var bufs: [16][24]u8 = undefined;
                    var idx: usize = 0;
                };
                const buf = &S.bufs[S.idx % 16];
                S.idx +%= 1;
                break :blk std.fmt.bufPrint(buf, "{d}", .{ii}) catch "-";
            },
            .float => |f| blk: {
                const S = struct {
                    var bufs: [16][32]u8 = undefined;
                    var idx: usize = 0;
                };
                const buf = &S.bufs[S.idx % 16];
                S.idx +%= 1;
                break :blk std.fmt.bufPrint(buf, "{d}", .{f}) catch "-";
            },
            .bool => |b| if (b) "true" else "false",
            .null => "-",
            else => "-",
        };
    }
    return "-";
}

fn mapSide(raw: []const u8) []const u8 {
    if (std.mem.eql(u8, raw, "buy") or std.mem.eql(u8, raw, "long")) return "bid";
    if (std.mem.eql(u8, raw, "sell") or std.mem.eql(u8, raw, "short")) return "ask";
    return raw;
}

fn mapPositionCloseSide(raw: []const u8) []const u8 {
    if (std.mem.eql(u8, raw, "long") or std.mem.eql(u8, raw, "buy")) return "ask";
    if (std.mem.eql(u8, raw, "short") or std.mem.eql(u8, raw, "sell")) return "bid";
    return raw;
}

// ╔═══════════════════════════════════════════════════════════════╗
// ║  Tests                                                        ║
// ╚═══════════════════════════════════════════════════════════════╝

test "mapSide: entry-side aliases map to Pacifica API values" {
    try std.testing.expectEqualStrings("bid", mapSide("buy"));
    try std.testing.expectEqualStrings("ask", mapSide("sell"));
    try std.testing.expectEqualStrings("bid", mapSide("long"));
    try std.testing.expectEqualStrings("ask", mapSide("short"));
}

test "mapPositionCloseSide: position aliases map to opposite closing side" {
    try std.testing.expectEqualStrings("ask", mapPositionCloseSide("long"));
    try std.testing.expectEqualStrings("bid", mapPositionCloseSide("short"));
    try std.testing.expectEqualStrings("ask", mapPositionCloseSide("buy"));
    try std.testing.expectEqualStrings("bid", mapPositionCloseSide("sell"));
}

test "jsonStr: renders actual numbers not type names" {
    // This was a real bug — jsonStr was printing "int"/"float" instead of the value
    var map = std.json.ObjectMap.init(std.testing.allocator);
    defer map.deinit();
    try map.put("n", .{ .integer = 42 });
    try map.put("neg", .{ .integer = -100 });
    try map.put("t", .{ .bool = true });

    try std.testing.expectEqualStrings("42", jsonStr(map, "n"));
    try std.testing.expectEqualStrings("-100", jsonStr(map, "neg"));
    try std.testing.expectEqualStrings("true", jsonStr(map, "t"));
    try std.testing.expectEqualStrings("-", jsonStr(map, "missing"));
}

test "extractData: gates on success field (controls exit code)" {
    // success:true → return data; success:false → null → error exit
    const ok = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"success":true,"data":[1,2]}
    , .{});
    defer ok.deinit();
    try std.testing.expect(extractData(ok.value) != null);

    const fail_body = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"success":false,"error":"bad"}
    , .{});
    defer fail_body.deinit();
    try std.testing.expect(extractData(fail_body.value) == null);
}

test "extractError: pulls error message from Pacifica envelope" {
    const p = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"success":false,"error":"insufficient balance"}
    , .{});
    defer p.deinit();
    try std.testing.expectEqualStrings("insufficient balance", extractError(p.value));
}
