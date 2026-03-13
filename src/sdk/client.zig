// ╔═══════════════════════════════════════════════════════════════╗
// ║  REST Client — typed HTTP for Pacifica API                    ║
// ╚═══════════════════════════════════════════════════════════════╝

const std = @import("std");
const http = std.http;
const Allocator = std.mem.Allocator;
const lib = @import("lib");
const config_mod = @import("config.zig");
const signing_mod = @import("signing.zig");
const Signer = lib.crypto.signer.Signer;
const Chain = config_mod.Chain;

pub const Response = struct {
    body: []const u8,
    status: http.Status,
    allocator: Allocator,

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.body);
    }
};

pub const Client = struct {
    allocator: Allocator,
    http: http.Client,
    chain: Chain,

    pub fn init(allocator: Allocator, chain: Chain) Client {
        return .{
            .allocator = allocator,
            .http = http.Client{ .allocator = allocator },
            .chain = chain,
        };
    }

    pub fn deinit(self: *Client) void {
        self.http.deinit();
    }

    // ── Raw HTTP ──────────────────────────────────────────────

    pub fn get(self: *Client, path: []const u8, query: ?[]const u8) !Response {
        var url_buf: [1024]u8 = undefined;
        const base = self.chain.restUrl();
        const url = if (query) |q|
            std.fmt.bufPrint(&url_buf, "{s}{s}?{s}", .{ base, path, q }) catch return error.UrlTooLong
        else
            std.fmt.bufPrint(&url_buf, "{s}{s}", .{ base, path }) catch return error.UrlTooLong;

        return self.doFetch(url, null);
    }

    pub fn post(self: *Client, path: []const u8, body: []const u8) !Response {
        var url_buf: [512]u8 = undefined;
        const url = std.fmt.bufPrint(&url_buf, "{s}{s}", .{ self.chain.restUrl(), path }) catch return error.UrlTooLong;

        return self.doFetch(url, body);
    }

    fn doFetch(self: *Client, url: []const u8, payload: ?[]const u8) !Response {
        const uri = std.Uri.parse(url) catch return error.InvalidUrl;
        const method: http.Method = if (payload != null) .POST else .GET;

        const extra_headers: []const http.Header = if (payload != null)
            &.{.{ .name = "Content-Type", .value = "application/json" }}
        else
            &.{};

        var req = http.Client.request(&self.http, method, uri, .{
            .extra_headers = extra_headers,
        }) catch return error.ConnectionFailed;
        defer req.deinit();

        if (payload) |p| {
            req.transfer_encoding = .{ .content_length = p.len };
            var body_writer = req.sendBody(&.{}) catch return error.ConnectionFailed;
            body_writer.writer.writeAll(p) catch return error.ConnectionFailed;
            body_writer.end() catch return error.ConnectionFailed;
            req.connection.?.flush() catch return error.ConnectionFailed;
        } else {
            req.sendBodiless() catch return error.ConnectionFailed;
        }

        var response = req.receiveHead(&.{}) catch return error.ConnectionFailed;

        // Handle gzip/deflate/zstd decompression
        const decompress_buf: []u8 = switch (response.head.content_encoding) {
            .identity => &.{},
            .deflate, .gzip => self.allocator.alloc(u8, std.compress.flate.max_window_len) catch return error.ReadFailed,
            .zstd => self.allocator.alloc(u8, std.compress.zstd.default_window_len) catch return error.ReadFailed,
            .compress => return error.ReadFailed,
        };
        defer if (response.head.content_encoding != .identity) self.allocator.free(decompress_buf);

        var transfer_buf: [64]u8 = undefined;
        var decompress: http.Decompress = undefined;
        var reader = response.readerDecompressing(&transfer_buf, &decompress, decompress_buf);
        const body = reader.allocRemaining(self.allocator, @enumFromInt(4 * 1024 * 1024)) catch return error.ReadFailed;

        return .{
            .body = body,
            .status = response.head.status,
            .allocator = self.allocator,
        };
    }

    // ── Signed POST ───────────────────────────────────────────

    pub fn rawSignedPost(
        self: *Client,
        path: []const u8,
        body: []const u8,
    ) !Response {
        return self.post(path, body);
    }

    pub fn buildSignedBody(
        self: *Client,
        signer: *const Signer,
        account_addr: ?[]const u8,
        msg_type: []const u8,
        payload: std.json.Value,
        agent_pubkey: ?[]const u8,
    ) ![]u8 {
        const timestamp: u64 = @intCast(std.time.milliTimestamp());
        const expiry_window: u64 = 5000;

        var signed = try signing_mod.signRequest(
            self.allocator,
            signer,
            msg_type,
            payload,
            timestamp,
            expiry_window,
        );
        defer signed.deinit();

        var pub_buf: [44]u8 = undefined;
        const signer_pub = signer.pubkeyBase58(&pub_buf);
        const acct = account_addr orelse signer_pub;
        var body_buf = std.ArrayList(u8){};
        defer body_buf.deinit(self.allocator);

        try body_buf.appendSlice(self.allocator, "{\"account\":\"");
        try body_buf.appendSlice(self.allocator, acct);
        try body_buf.appendSlice(self.allocator, "\",\"signature\":\"");
        try body_buf.appendSlice(self.allocator, signed.signature());
        try body_buf.appendSlice(self.allocator, "\",\"timestamp\":");
        var ts_buf: [24]u8 = undefined;
        const ts_str = std.fmt.bufPrint(&ts_buf, "{d}", .{timestamp}) catch unreachable;
        try body_buf.appendSlice(self.allocator, ts_str);
        try body_buf.appendSlice(self.allocator, ",\"expiry_window\":");
        var ew_buf: [24]u8 = undefined;
        const ew_str = std.fmt.bufPrint(&ew_buf, "{d}", .{expiry_window}) catch unreachable;
        try body_buf.appendSlice(self.allocator, ew_str);

        if (agent_pubkey) |aw| {
            try body_buf.appendSlice(self.allocator, ",\"agent_wallet\":\"");
            try body_buf.appendSlice(self.allocator, aw);
            try body_buf.appendSlice(self.allocator, "\"");
        }

        switch (payload) {
            .object => |obj| {
                var it = obj.iterator();
                while (it.next()) |entry| {
                    try body_buf.appendSlice(self.allocator, ",\"");
                    try body_buf.appendSlice(self.allocator, entry.key_ptr.*);
                    try body_buf.appendSlice(self.allocator, "\":");
                    const val_str = try lib.json.compactStringify(self.allocator, entry.value_ptr.*);
                    defer self.allocator.free(val_str);
                    try body_buf.appendSlice(self.allocator, val_str);
                }
            },
            else => {},
        }

        try body_buf.append(self.allocator, '}');
        return body_buf.toOwnedSlice(self.allocator);
    }

    pub fn signedPost(
        self: *Client,
        path: []const u8,
        signer: *const Signer,
        account_addr: ?[]const u8,
        msg_type: []const u8,
        payload: std.json.Value,
        agent_pubkey: ?[]const u8,
    ) !Response {
        const body = try self.buildSignedBody(signer, account_addr, msg_type, payload, agent_pubkey);
        defer self.allocator.free(body);
        return self.post(path, body);
    }

    pub fn claimAccessCode(
        self: *Client,
        signer: *const Signer,
        code: []const u8,
    ) !Response {
        const timestamp: u64 = @intCast(std.time.milliTimestamp());
        const expiry_window: u64 = 300000;

        var payload_arena = std.heap.ArenaAllocator.init(self.allocator);
        defer payload_arena.deinit();
        const aa = payload_arena.allocator();

        var payload = std.json.ObjectMap.init(aa);
        try payload.put("code", .{ .string = code });

        var signed = try signing_mod.signRequest(
            self.allocator,
            signer,
            "claim_access_code",
            .{ .object = payload },
            timestamp,
            expiry_window,
        );
        defer signed.deinit();

        var pub_buf: [44]u8 = undefined;
        const acct = signer.pubkeyBase58(&pub_buf);

        var body_buf = std.ArrayList(u8){};
        defer body_buf.deinit(self.allocator);

        try body_buf.appendSlice(self.allocator, "{\"account\":\"");
        try body_buf.appendSlice(self.allocator, acct);
        try body_buf.appendSlice(self.allocator, "\",\"code\":\"");
        try body_buf.appendSlice(self.allocator, code);
        try body_buf.appendSlice(self.allocator, "\",\"expiry_window\":");
        var ew_buf: [24]u8 = undefined;
        try body_buf.appendSlice(self.allocator, std.fmt.bufPrint(&ew_buf, "{d}", .{expiry_window}) catch unreachable);
        try body_buf.appendSlice(self.allocator, ",\"signature\":{\"type\":\"raw\",\"value\":\"");
        try body_buf.appendSlice(self.allocator, signed.signature());
        try body_buf.appendSlice(self.allocator, "\"},\"timestamp\":");
        var ts_buf: [24]u8 = undefined;
        try body_buf.appendSlice(self.allocator, std.fmt.bufPrint(&ts_buf, "{d}", .{timestamp}) catch unreachable);
        try body_buf.append(self.allocator, '}');

        return self.post("/whitelist/claim", body_buf.items);
    }

    // ── Public GET endpoints ──────────────────────────────────

    pub fn getMarketInfo(self: *Client) !Response {
        return self.get("/info", null);
    }

    pub fn getPrices(self: *Client) !Response {
        return self.get("/info/prices", null);
    }

    pub fn getOrderbook(self: *Client, symbol: []const u8) !Response {
        var q: [128]u8 = undefined;
        return self.get("/book", std.fmt.bufPrint(&q, "symbol={s}", .{symbol}) catch return error.UrlTooLong);
    }

    pub fn getKline(self: *Client, symbol: []const u8, interval: []const u8, start: ?[]const u8, end: ?[]const u8) !Response {
        var q: [256]u8 = undefined;
        var len: usize = 0;
        len += (std.fmt.bufPrint(q[len..], "symbol={s}&interval={s}", .{ symbol, interval }) catch return error.UrlTooLong).len;
        if (start) |s| {
            len += (std.fmt.bufPrint(q[len..], "&start_time={s}", .{s}) catch return error.UrlTooLong).len;
        } else {
            // Default to 24h ago
            const now: u64 = @intCast(std.time.milliTimestamp());
            const day_ago = now - 86400_000;
            len += (std.fmt.bufPrint(q[len..], "&start_time={d}", .{day_ago}) catch return error.UrlTooLong).len;
        }
        if (end) |e| len += (std.fmt.bufPrint(q[len..], "&end_time={s}", .{e}) catch return error.UrlTooLong).len;
        return self.get("/kline", q[0..len]);
    }

    // ── Account GET endpoints ─────────────────────────────────

    fn accountQuery(q: *[128]u8, account: []const u8) []const u8 {
        return std.fmt.bufPrint(q, "account={s}", .{account}) catch "account=";
    }

    pub fn getWhitelistStatus(self: *Client, account: []const u8) !Response {
        var q: [128]u8 = undefined;
        return self.get("/whitelist/status", accountQuery(&q, account));
    }

    pub fn getAccountInfo(self: *Client, account: []const u8) !Response {
        var q: [128]u8 = undefined;
        return self.get("/account", accountQuery(&q, account));
    }

    pub fn getAccountSettings(self: *Client, account: []const u8) !Response {
        var q: [128]u8 = undefined;
        return self.get("/account/settings", accountQuery(&q, account));
    }

    pub fn getPositions(self: *Client, account: []const u8) !Response {
        var q: [128]u8 = undefined;
        return self.get("/positions", accountQuery(&q, account));
    }

    pub fn getOpenOrders(self: *Client, account: []const u8) !Response {
        var q: [128]u8 = undefined;
        return self.get("/orders", accountQuery(&q, account));
    }

    pub fn getOrderHistory(self: *Client, account: []const u8, limit: ?[]const u8, cursor: ?[]const u8) !Response {
        var q: [256]u8 = undefined;
        var len: usize = 0;
        len += (std.fmt.bufPrint(q[len..], "account={s}", .{account}) catch return error.UrlTooLong).len;
        if (limit) |l| len += (std.fmt.bufPrint(q[len..], "&limit={s}", .{l}) catch return error.UrlTooLong).len;
        if (cursor) |c| len += (std.fmt.bufPrint(q[len..], "&cursor={s}", .{c}) catch return error.UrlTooLong).len;
        return self.get("/orders/history", q[0..len]);
    }

    pub fn getTradeHistory(self: *Client, account: []const u8, symbol: ?[]const u8, limit: ?[]const u8, cursor: ?[]const u8) !Response {
        var q: [256]u8 = undefined;
        var len: usize = 0;
        len += (std.fmt.bufPrint(q[len..], "account={s}", .{account}) catch return error.UrlTooLong).len;
        if (symbol) |s| len += (std.fmt.bufPrint(q[len..], "&symbol={s}", .{s}) catch return error.UrlTooLong).len;
        if (limit) |l| len += (std.fmt.bufPrint(q[len..], "&limit={s}", .{l}) catch return error.UrlTooLong).len;
        if (cursor) |c| len += (std.fmt.bufPrint(q[len..], "&cursor={s}", .{c}) catch return error.UrlTooLong).len;
        return self.get("/trades/history", q[0..len]);
    }

    pub fn getFundingHistory(self: *Client, account: []const u8, limit: ?[]const u8, cursor: ?[]const u8) !Response {
        var q: [256]u8 = undefined;
        var len: usize = 0;
        len += (std.fmt.bufPrint(q[len..], "account={s}", .{account}) catch return error.UrlTooLong).len;
        if (limit) |l| len += (std.fmt.bufPrint(q[len..], "&limit={s}", .{l}) catch return error.UrlTooLong).len;
        if (cursor) |c| len += (std.fmt.bufPrint(q[len..], "&cursor={s}", .{c}) catch return error.UrlTooLong).len;
        return self.get("/funding/history", q[0..len]);
    }

    pub fn getEquityHistory(self: *Client, account: []const u8, time_range: []const u8) !Response {
        var q: [256]u8 = undefined;
        const qs = std.fmt.bufPrint(&q, "account={s}&time_range={s}", .{ account, time_range }) catch return error.UrlTooLong;
        return self.get("/portfolio", qs);
    }

    pub fn getBalanceHistory(self: *Client, account: []const u8, limit: ?[]const u8, cursor: ?[]const u8) !Response {
        var q: [256]u8 = undefined;
        var len: usize = 0;
        len += (std.fmt.bufPrint(q[len..], "account={s}", .{account}) catch return error.UrlTooLong).len;
        if (limit) |l| len += (std.fmt.bufPrint(q[len..], "&limit={s}", .{l}) catch return error.UrlTooLong).len;
        if (cursor) |c| len += (std.fmt.bufPrint(q[len..], "&cursor={s}", .{c}) catch return error.UrlTooLong).len;
        return self.get("/account/balance/history", q[0..len]);
    }

    // ── Builder endpoints ─────────────────────────────────────

    pub fn getBuilderApprovals(self: *Client, account: []const u8) !Response {
        var q: [128]u8 = undefined;
        return self.get("/account/builder_codes/approvals", accountQuery(&q, account));
    }

    pub fn getBuilderOverview(self: *Client, account: []const u8) !Response {
        var q: [128]u8 = undefined;
        return self.get("/builder/overview", accountQuery(&q, account));
    }
};
