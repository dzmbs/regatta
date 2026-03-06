const std = @import("std");
const websocket = @import("websocket");
const config_mod = @import("config.zig");
const client_mod = @import("client.zig");
const lib = @import("lib");

const Chain = config_mod.Chain;
const Signer = lib.crypto.signer.Signer;

pub const ActionResult = struct {
    id: []u8,
    body: []u8,

    pub fn deinit(self: *ActionResult, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.body);
    }
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    inner: websocket.Client,

    pub fn init(allocator: std.mem.Allocator, chain: Chain, api_key: ?[]const u8) !Client {
        const spec = try parseWsSpec(chain.wsUrl());
        var inner = try websocket.Client.init(allocator, .{
            .host = spec.host,
            .port = spec.port,
            .tls = spec.tls,
            .max_size = 4 * 1024 * 1024,
            .buffer_size = 16 * 1024,
        });
        errdefer inner.deinit();

        const headers = if (api_key) |k|
            try std.fmt.allocPrint(allocator, "Host: {s}\r\nUser-Agent: regatta\r\nPF-API-KEY: {s}\r\n", .{ spec.host, k })
        else
            try std.fmt.allocPrint(allocator, "Host: {s}\r\nUser-Agent: regatta\r\n", .{spec.host});
        defer allocator.free(headers);

        try inner.handshake(spec.path, .{ .headers = headers });
        try inner.readTimeout(1000);
        return .{ .allocator = allocator, .inner = inner };
    }

    pub fn deinit(self: *Client) void {
        self.inner.deinit();
    }

    pub fn subscribe(self: *Client, params_json: []const u8) !void {
        const msg = try std.fmt.allocPrint(self.allocator, "{{\"method\":\"subscribe\",\"params\":{s}}}", .{params_json});
        defer self.allocator.free(msg);
        try self.sendText(msg);
    }

    pub fn unsubscribe(self: *Client, params_json: []const u8) !void {
        const msg = try std.fmt.allocPrint(self.allocator, "{{\"method\":\"unsubscribe\",\"params\":{s}}}", .{params_json});
        defer self.allocator.free(msg);
        try self.sendText(msg);
    }

    pub fn sendPing(self: *Client) !void {
        try self.sendText("{\"method\":\"ping\"}");
    }

    pub fn sendText(self: *Client, text: []const u8) !void {
        const buf = try self.allocator.dupe(u8, text);
        defer self.allocator.free(buf);
        try self.inner.writeText(buf);
    }

    pub fn nextText(self: *Client) !?[]u8 {
        while (true) {
            const msg = try self.inner.read() orelse return null;
            defer self.inner.done(msg);
            switch (msg.type) {
                .text => return try self.allocator.dupe(u8, msg.data),
                else => {},
            }
        }
    }

    pub fn waitForAction(self: *Client, request_id: []const u8, timeout_ms: u32) !ActionResult {
        const start = std.time.milliTimestamp();
        while (true) {
            if (@as(u64, @intCast(std.time.milliTimestamp() - start)) > timeout_ms) {
                return error.Timeout;
            }
            if (try self.nextText()) |text| {
                errdefer self.allocator.free(text);
                if (std.mem.indexOf(u8, text, "\"id\":\"") != null and std.mem.indexOf(u8, text, request_id) != null) {
                    return .{
                        .id = try self.allocator.dupe(u8, request_id),
                        .body = text,
                    };
                }
                self.allocator.free(text);
            }
        }
    }

    pub fn rawAction(self: *Client, op_name: []const u8, body_json: []const u8) !ActionResult {
        var id_buf: [36]u8 = undefined;
        const request_id = lib.uuid.v4(&id_buf);
        const msg = try std.fmt.allocPrint(self.allocator, "{{\"id\":\"{s}\",\"params\":{{\"{s}\":{s}}}}}", .{ request_id, op_name, body_json });
        defer self.allocator.free(msg);
        try self.sendText(msg);
        return self.waitForAction(request_id, 10_000);
    }

    pub fn signedAction(
        self: *Client,
        rest_client: *client_mod.Client,
        op_name: []const u8,
        signer: *const Signer,
        account_addr: ?[]const u8,
        msg_type: []const u8,
        payload: std.json.Value,
        agent_pubkey: ?[]const u8,
    ) !ActionResult {
        const body = try rest_client.buildSignedBody(signer, account_addr, msg_type, payload, agent_pubkey);
        defer self.allocator.free(body);
        return self.rawAction(op_name, body);
    }
};

fn parseWsSpec(url: []const u8) !struct { tls: bool, host: []const u8, port: u16, path: []const u8 } {
    const tls_enabled = if (std.mem.startsWith(u8, url, "wss://")) true else if (std.mem.startsWith(u8, url, "ws://")) false else return error.InvalidUrl;
    const offset: usize = if (tls_enabled) 6 else 5;
    const rest = url[offset..];
    const slash = std.mem.indexOfScalar(u8, rest, '/') orelse rest.len;
    const host_port = rest[0..slash];
    const path = if (slash < rest.len) rest[slash..] else "/";

    const colon = std.mem.lastIndexOfScalar(u8, host_port, ':');
    if (colon) |idx| {
        const host = host_port[0..idx];
        const port = std.fmt.parseInt(u16, host_port[idx + 1 ..], 10) catch return error.InvalidUrl;
        return .{ .tls = tls_enabled, .host = host, .port = port, .path = path };
    }

    return .{ .tls = tls_enabled, .host = host_port, .port = if (tls_enabled) 443 else 80, .path = path };
}

test "parseWsSpec mainnet" {
    const s = try parseWsSpec("wss://ws.pacifica.fi/ws");
    try std.testing.expect(s.tls);
    try std.testing.expectEqual(@as(u16, 443), s.port);
    try std.testing.expectEqualStrings("ws.pacifica.fi", s.host);
    try std.testing.expectEqualStrings("/ws", s.path);
}
