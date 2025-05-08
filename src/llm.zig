const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ChatPayload = struct {
    model: []const u8,
    messages: []Message,
    max_tokens: ?u32,
    temperature: ?f32
};

pub const Message = struct {
    role: []const u8,
    content: []const u8,

    pub fn system(content: []const u8) Message {
        return .{ .role = Role.system, .content = content };
    }

    pub fn user(content: []const u8) Message {
        return .{ .role = Role.user, .content = content };
    }
};

pub const Role = struct {
    pub const system = "system";
    pub const user = "user";
    pub const assistant = "assistant";
};

pub const ChatResponse = struct {
    id: []const u8,
    object: []const u8,
    created: u64,
    model: []const u8,
    choices: []Choice,
    usage: Usage,
};

pub const Choice = struct {
    index: usize,
    finish_reason: ?[]const u8,
    message: struct {
        role: []const u8,
        content: []const u8,
    },
};

pub const Usage = struct {
    prompt_tokens: u64,
    completion_tokens: ?u64,
    total_tokens: u64,
};

const OpenAIError = error{
    BadRequest,
    Unauthorized,
    Forbidden,
    NotFound,
    TooManyRequests,
    InternalServerError,
    ServiceUnavailable,
    GatewayTimeout,
    Unknown,
};

fn getError(status: std.http.Status) OpenAIError {
    const result = switch (status) {
        .bad_request => OpenAIError.BadRequest,
        .unauthorized => OpenAIError.Unauthorized,
        .forbidden => OpenAIError.Forbidden,
        .not_found => OpenAIError.NotFound,
        .too_many_requests => OpenAIError.TooManyRequests,
        .internal_server_error => OpenAIError.InternalServerError,
        .service_unavailable => OpenAIError.ServiceUnavailable,
        .gateway_timeout => OpenAIError.GatewayTimeout,
        else => OpenAIError.Unknown,
    };
    return result;
}

pub const Client = struct {
    base_url: []const u8 = "https://api.openai.com/v1",
    api_key: []const u8,
    allocator: Allocator,
    http_client: std.http.Client,

    pub fn init(allocator: Allocator, api_key: ?[]const u8) !Client {
        var env = try std.process.getEnvMap(allocator);
        defer env.deinit();

        const _api_key = api_key
            orelse env.get("OPENAI_API_KEY")
            orelse return error.MissingAPIKey;
        const openai_api_key = try allocator.dupe(u8, _api_key);

        var http_client = std.http.Client{ .allocator = allocator };
        http_client.initDefaultProxies(allocator) catch |err| {
            http_client.deinit();
            return err;
        };

        return Client{
            .allocator = allocator,
            .api_key = openai_api_key,
            .http_client = http_client,
        };
    }

    pub fn chat(self: *Client, payload: ChatPayload, verbose: bool) !std.json.Parsed(ChatResponse) {
        const options = .{
            .model = payload.model,
            .messages = payload.messages,
            .max_tokens = payload.max_tokens,
            .temperature = payload.temperature,
        };
        const body = try std.json.stringifyAlloc(self.allocator, options, .{ .whitespace = .indent_2 });
        defer self.allocator.free(body);

        var req = try self.makeCall("/chat/completions", body, verbose);
        defer req.deinit();

        if (req.response.status != .ok) {
            const err = getError(req.response.status);
            req.deinit();
            return err;
        }

        const response = try req.reader().readAllAlloc(self.allocator, 1024 * 8);
        defer self.allocator.free(response);

        const parsed = try std.json.parseFromSlice(ChatResponse, self.allocator, response, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        });

        return parsed;
    }

    fn makeCall(self: *Client, endpoint: []const u8, body: []const u8, _: bool) !std.http.Client.Request {
        const headers = try get_headers(self.allocator, self.api_key);
        defer self.allocator.free(headers.authorization.override);

        var buf: [16 * 1024]u8 = undefined;

        const path = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base_url, endpoint });
        defer self.allocator.free(path);
        const uri = try std.Uri.parse(path);

        var req = try self.http_client.open(.POST, uri, .{ .headers = headers, .server_header_buffer = &buf });
        errdefer req.deinit();

        req.transfer_encoding = .{ .content_length = body.len };

        try req.send();
        try req.writeAll(body);
        try req.finish();
        try req.wait();

        return req;
    }

    fn get_headers(allocator: Allocator, api_key: []const u8) !std.http.Client.Request.Headers {
        const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key});
        const headers = std.http.Client.Request.Headers{
            .content_type = .{ .override = "application/json" },
            .authorization = .{ .override = auth_header },
        };
        return headers;
    }

    pub fn deinit(self: *Client) void {
        self.allocator.free(self.api_key);
        self.http_client.deinit();
    }
};
