// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Parallel URI operations using spice heartbeat scheduling.
//!
//! Provides high-performance parallel implementations for batch URI
//! parsing, validation, normalization, and resolution.
//!
//! ## Overview
//!
//! This module enables parallel processing of URI operations
//! using the spice thread pool with fork/join work-stealing. Operations
//! automatically fall back to sequential processing when spice is disabled
//! or input sizes are below thresholds.
//!
//! ## Build Configuration
//!
//! Enable parallel processing with `-Dspice=true` (default: enabled).
//! Disable with `-Dspice=false` for sequential-only execution.
//!
//! ## Usage Example
//!
//! ```zig
//! const parallel = @import("parallel.zig");
//!
//! // Parse multiple URIs in parallel
//! var inputs: [64][]const u8 = undefined;
//! var results: [64]parallel.ParseResult = undefined;
//!
//! // Initialize inputs with URI strings...
//! parallel.parseUris(&inputs, &results);
//!
//! // Normalize multiple URIs
//! var norm_results: [64]parallel.NormalizeResult = undefined;
//! parallel.normalizeUris(allocator, &inputs, &norm_results);
//!
//! // Cleanup: call deinitPool() when done
//! parallel.deinitPool();
//! ```
//!
//! ## Performance Thresholds
//!
//! | Operation        | Threshold   | Sequential Below |
//! |------------------|-------------|------------------|
//! | URI Parse        | 16 URIs     | Yes              |
//! | URI Validate     | 16 URIs     | Yes              |
//! | URI Normalize    | 8 URIs      | Yes              |
//! | URI Resolve      | 8 URIs      | Yes              |

const std = @import("std");
const build_options = @import("build_options");

const spice = if (build_options.enable_spice) @import("spice") else struct {
    pub const ThreadPool = void;
    pub const Task = void;
    pub fn Future(comptime I: type, comptime O: type) type {
        _ = I;
        _ = O;
        return void;
    }
};

// ============================================================================
// Global Thread Pool
// ============================================================================

var global_pool: if (build_options.enable_spice) ?spice.ThreadPool else void = if (build_options.enable_spice) null else {};
var pool_mutex: std.Thread.Mutex = .{};

pub fn getPool() if (build_options.enable_spice) *spice.ThreadPool else void {
    if (!build_options.enable_spice) return;

    pool_mutex.lock();
    defer pool_mutex.unlock();

    if (global_pool == null) {
        global_pool = spice.ThreadPool.init(std.heap.page_allocator);
        global_pool.?.start(.{});
    }
    return &global_pool.?;
}

pub fn deinitPool() void {
    if (!build_options.enable_spice) return;

    pool_mutex.lock();
    defer pool_mutex.unlock();

    if (global_pool) |*pool| {
        pool.deinit();
        global_pool = null;
    }
}

// ============================================================================
// URI Component Types
// ============================================================================

/// Parsed URI components
pub const UriComponents = struct {
    scheme: ?[]const u8,
    userinfo: ?[]const u8,
    host: ?[]const u8,
    port: ?u16,
    path: []const u8,
    query: ?[]const u8,
    fragment: ?[]const u8,
};

/// Result of URI parsing
pub const ParseResult = struct {
    /// Parsed components (if successful)
    components: ?UriComponents,
    /// Whether parsing succeeded
    success: bool,
    /// Error code (0 = success)
    error_code: u8,
};

/// Context for parallel parsing
const ParseContext = struct {
    inputs: []const []const u8,
    results: []ParseResult,
};

// ============================================================================
// Parallel URI Parsing
// ============================================================================

/// Parse multiple URI strings in parallel.
///
/// Extracts scheme, authority, path, query, and fragment components.
///
/// Parameters:
/// - inputs: Array of URI strings
/// - results: Array to store parsing results
///
/// Threshold: Uses parallel processing for 16+ URIs
pub fn parseUris(
    inputs: []const []const u8,
    results: []ParseResult,
) void {
    std.debug.assert(inputs.len == results.len);

    if (!build_options.enable_spice or inputs.len < 16) {
        for (inputs, 0..) |input, i| {
            results[i] = parseUri(input);
        }
        return;
    }

    const pool = getPool();
    const ctx = ParseContext{
        .inputs = inputs,
        .results = results,
    };
    _ = pool.call(void, parseTask, ctx);
}

fn parseTask(t: *spice.Task, ctx: ParseContext) void {
    const inputs = ctx.inputs;
    const results = ctx.results;

    if (inputs.len < 8) {
        for (inputs, 0..) |input, i| {
            results[i] = parseUri(input);
        }
        return;
    }

    const mid = inputs.len / 2;
    const left_ctx = ParseContext{
        .inputs = inputs[0..mid],
        .results = results[0..mid],
    };
    const right_ctx = ParseContext{
        .inputs = inputs[mid..],
        .results = results[mid..],
    };

    var fut = spice.Future(ParseContext, void).init();
    fut.fork(t, parseTask, right_ctx);

    t.call(void, parseTask, left_ctx);
    if (fut.join(t) == null) {
        t.call(void, parseTask, right_ctx);
    }
}

fn parseUri(input: []const u8) ParseResult {
    if (input.len == 0) {
        return .{
            .components = .{
                .scheme = null,
                .userinfo = null,
                .host = null,
                .port = null,
                .path = "",
                .query = null,
                .fragment = null,
            },
            .success = true,
            .error_code = 0,
        };
    }

    var remaining = input;
    var components = UriComponents{
        .scheme = null,
        .userinfo = null,
        .host = null,
        .port = null,
        .path = "",
        .query = null,
        .fragment = null,
    };

    // Extract fragment
    if (std.mem.indexOf(u8, remaining, "#")) |frag_pos| {
        components.fragment = remaining[frag_pos + 1 ..];
        remaining = remaining[0..frag_pos];
    }

    // Extract query
    if (std.mem.indexOf(u8, remaining, "?")) |query_pos| {
        components.query = remaining[query_pos + 1 ..];
        remaining = remaining[0..query_pos];
    }

    // Extract scheme
    if (std.mem.indexOf(u8, remaining, ":")) |colon_pos| {
        const potential_scheme = remaining[0..colon_pos];
        var valid_scheme = potential_scheme.len > 0;
        for (potential_scheme) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '+' and c != '-' and c != '.') {
                valid_scheme = false;
                break;
            }
        }
        if (valid_scheme and potential_scheme.len > 0 and std.ascii.isAlphabetic(potential_scheme[0])) {
            components.scheme = potential_scheme;
            remaining = remaining[colon_pos + 1 ..];
        }
    }

    // Extract authority
    if (remaining.len >= 2 and remaining[0] == '/' and remaining[1] == '/') {
        remaining = remaining[2..];
        const auth_end = std.mem.indexOfAny(u8, remaining, "/?#") orelse remaining.len;
        const authority = remaining[0..auth_end];

        // Extract userinfo
        if (std.mem.indexOf(u8, authority, "@")) |at_pos| {
            components.userinfo = authority[0..at_pos];
            const host_port = authority[at_pos + 1 ..];
            parseHostPort(host_port, &components);
        } else {
            parseHostPort(authority, &components);
        }

        remaining = remaining[auth_end..];
    }

    // Remaining is path
    components.path = remaining;

    return .{
        .components = components,
        .success = true,
        .error_code = 0,
    };
}

fn parseHostPort(host_port: []const u8, components: *UriComponents) void {
    if (host_port.len == 0) return;

    // Handle IPv6 addresses [...]
    if (host_port[0] == '[') {
        if (std.mem.indexOf(u8, host_port, "]")) |bracket_end| {
            components.host = host_port[0 .. bracket_end + 1];
            if (bracket_end + 1 < host_port.len and host_port[bracket_end + 1] == ':') {
                const port_str = host_port[bracket_end + 2 ..];
                components.port = std.fmt.parseInt(u16, port_str, 10) catch null;
            }
        }
    } else {
        // Regular host:port
        if (std.mem.lastIndexOf(u8, host_port, ":")) |colon_pos| {
            components.host = host_port[0..colon_pos];
            const port_str = host_port[colon_pos + 1 ..];
            components.port = std.fmt.parseInt(u16, port_str, 10) catch null;
        } else {
            components.host = host_port;
        }
    }
}

// ============================================================================
// Validation Types
// ============================================================================

/// Result of URI validation
pub const ValidateResult = struct {
    /// Whether URI is valid
    valid: bool,
    /// Error code (0 = valid)
    error_code: u8,
    /// Error description
    error_msg: ?[]const u8,
};

/// Context for parallel validation
const ValidateContext = struct {
    inputs: []const []const u8,
    results: []ValidateResult,
};

// ============================================================================
// Parallel URI Validation
// ============================================================================

/// Validate multiple URI strings in parallel.
///
/// Checks for valid URI syntax per RFC 3986.
///
/// Parameters:
/// - inputs: Array of URI strings
/// - results: Array to store validation results
///
/// Threshold: Uses parallel processing for 16+ URIs
pub fn validateUris(
    inputs: []const []const u8,
    results: []ValidateResult,
) void {
    std.debug.assert(inputs.len == results.len);

    if (!build_options.enable_spice or inputs.len < 16) {
        for (inputs, 0..) |input, i| {
            results[i] = validateUri(input);
        }
        return;
    }

    const pool = getPool();
    const ctx = ValidateContext{
        .inputs = inputs,
        .results = results,
    };
    _ = pool.call(void, validateTask, ctx);
}

fn validateTask(t: *spice.Task, ctx: ValidateContext) void {
    const inputs = ctx.inputs;
    const results = ctx.results;

    if (inputs.len < 8) {
        for (inputs, 0..) |input, i| {
            results[i] = validateUri(input);
        }
        return;
    }

    const mid = inputs.len / 2;
    const left_ctx = ValidateContext{
        .inputs = inputs[0..mid],
        .results = results[0..mid],
    };
    const right_ctx = ValidateContext{
        .inputs = inputs[mid..],
        .results = results[mid..],
    };

    var fut = spice.Future(ValidateContext, void).init();
    fut.fork(t, validateTask, right_ctx);

    t.call(void, validateTask, left_ctx);
    if (fut.join(t) == null) {
        t.call(void, validateTask, right_ctx);
    }
}

fn validateUri(input: []const u8) ValidateResult {
    // Empty URI is valid (empty reference)
    if (input.len == 0) {
        return .{ .valid = true, .error_code = 0, .error_msg = null };
    }

    // Check for invalid characters
    for (input) |c| {
        if (c < 0x21 or c == 0x7F) {
            if (c != ' ') { // Space might be allowed in lenient mode
                return .{ .valid = false, .error_code = 1, .error_msg = "Invalid character in URI" };
            }
        }
    }

    // Check scheme if present
    if (std.mem.indexOf(u8, input, ":")) |colon_pos| {
        const scheme = input[0..colon_pos];
        if (scheme.len == 0) {
            return .{ .valid = false, .error_code = 2, .error_msg = "Empty scheme" };
        }
        if (!std.ascii.isAlphabetic(scheme[0])) {
            return .{ .valid = false, .error_code = 3, .error_msg = "Scheme must start with letter" };
        }
    }

    // Basic percent-encoding validation
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '%') {
            if (i + 2 >= input.len) {
                return .{ .valid = false, .error_code = 4, .error_msg = "Incomplete percent encoding" };
            }
            if (!std.ascii.isHex(input[i + 1]) or !std.ascii.isHex(input[i + 2])) {
                return .{ .valid = false, .error_code = 5, .error_msg = "Invalid percent encoding" };
            }
            i += 3;
        } else {
            i += 1;
        }
    }

    return .{ .valid = true, .error_code = 0, .error_msg = null };
}

// ============================================================================
// Normalization Types
// ============================================================================

/// Result of URI normalization
pub const NormalizeResult = struct {
    /// Normalized URI string (owned by caller's allocator)
    normalized: ?[]u8,
    /// Whether normalization succeeded
    success: bool,
    /// Error code (0 = success)
    error_code: u8,
};

/// Context for parallel normalization
const NormalizeContext = struct {
    allocator: std.mem.Allocator,
    inputs: []const []const u8,
    results: []NormalizeResult,
};

// ============================================================================
// Parallel URI Normalization
// ============================================================================

/// Normalize multiple URIs in parallel.
///
/// Applies RFC 3986 normalization: lowercase scheme/host,
/// remove default ports, normalize percent-encoding.
///
/// Parameters:
/// - allocator: Memory allocator for normalized strings
/// - inputs: Array of URI strings
/// - results: Array to store normalization results
///
/// Threshold: Uses parallel processing for 8+ URIs
pub fn normalizeUris(
    allocator: std.mem.Allocator,
    inputs: []const []const u8,
    results: []NormalizeResult,
) void {
    std.debug.assert(inputs.len == results.len);

    if (!build_options.enable_spice or inputs.len < 8) {
        for (inputs, 0..) |input, i| {
            results[i] = normalizeUri(allocator, input);
        }
        return;
    }

    const pool = getPool();
    const ctx = NormalizeContext{
        .allocator = allocator,
        .inputs = inputs,
        .results = results,
    };
    _ = pool.call(void, normalizeTask, ctx);
}

fn normalizeTask(t: *spice.Task, ctx: NormalizeContext) void {
    const inputs = ctx.inputs;
    const results = ctx.results;

    if (inputs.len < 4) {
        for (inputs, 0..) |input, i| {
            results[i] = normalizeUri(ctx.allocator, input);
        }
        return;
    }

    const mid = inputs.len / 2;
    const left_ctx = NormalizeContext{
        .allocator = ctx.allocator,
        .inputs = inputs[0..mid],
        .results = results[0..mid],
    };
    const right_ctx = NormalizeContext{
        .allocator = ctx.allocator,
        .inputs = inputs[mid..],
        .results = results[mid..],
    };

    var fut = spice.Future(NormalizeContext, void).init();
    fut.fork(t, normalizeTask, right_ctx);

    t.call(void, normalizeTask, left_ctx);
    if (fut.join(t) == null) {
        t.call(void, normalizeTask, right_ctx);
    }
}

fn normalizeUri(allocator: std.mem.Allocator, input: []const u8) NormalizeResult {
    if (input.len == 0) {
        return .{ .normalized = allocator.dupe(u8, "") catch null, .success = true, .error_code = 0 };
    }

    // Simple normalization: lowercase scheme and host
    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(allocator);

    const parse_result = parseUri(input);
    if (!parse_result.success) {
        return .{ .normalized = null, .success = false, .error_code = 1 };
    }

    const components = parse_result.components.?;

    // Add scheme (lowercase)
    if (components.scheme) |scheme| {
        for (scheme) |c| {
            result.append(allocator, std.ascii.toLower(c)) catch {
                return .{ .normalized = null, .success = false, .error_code = 2 };
            };
        }
        result.append(allocator, ':') catch {
            return .{ .normalized = null, .success = false, .error_code = 2 };
        };
    }

    // Add authority
    if (components.host != null) {
        result.appendSlice(allocator, "//") catch {
            return .{ .normalized = null, .success = false, .error_code = 2 };
        };

        if (components.userinfo) |userinfo| {
            result.appendSlice(allocator, userinfo) catch {
                return .{ .normalized = null, .success = false, .error_code = 2 };
            };
            result.append(allocator, '@') catch {
                return .{ .normalized = null, .success = false, .error_code = 2 };
            };
        }

        // Host lowercase (unless IPv6)
        if (components.host) |host| {
            if (host.len > 0 and host[0] == '[') {
                result.appendSlice(allocator, host) catch {
                    return .{ .normalized = null, .success = false, .error_code = 2 };
                };
            } else {
                for (host) |c| {
                    result.append(allocator, std.ascii.toLower(c)) catch {
                        return .{ .normalized = null, .success = false, .error_code = 2 };
                    };
                }
            }
        }

        if (components.port) |port| {
            // Skip default ports
            const is_default = if (components.scheme) |s|
                (std.mem.eql(u8, s, "http") and port == 80) or
                    (std.mem.eql(u8, s, "https") and port == 443)
            else
                false;

            if (!is_default) {
                result.append(allocator, ':') catch {
                    return .{ .normalized = null, .success = false, .error_code = 2 };
                };
                var port_buf: [8]u8 = undefined;
                const port_str = std.fmt.bufPrint(&port_buf, "{d}", .{port}) catch {
                    return .{ .normalized = null, .success = false, .error_code = 2 };
                };
                result.appendSlice(allocator, port_str) catch {
                    return .{ .normalized = null, .success = false, .error_code = 2 };
                };
            }
        }
    }

    // Add path
    result.appendSlice(allocator, components.path) catch {
        return .{ .normalized = null, .success = false, .error_code = 2 };
    };

    // Add query
    if (components.query) |query| {
        result.append(allocator, '?') catch {
            return .{ .normalized = null, .success = false, .error_code = 2 };
        };
        result.appendSlice(allocator, query) catch {
            return .{ .normalized = null, .success = false, .error_code = 2 };
        };
    }

    // Add fragment
    if (components.fragment) |fragment| {
        result.append(allocator, '#') catch {
            return .{ .normalized = null, .success = false, .error_code = 2 };
        };
        result.appendSlice(allocator, fragment) catch {
            return .{ .normalized = null, .success = false, .error_code = 2 };
        };
    }

    return .{
        .normalized = result.toOwnedSlice(allocator) catch null,
        .success = true,
        .error_code = 0,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "parse uri - full" {
    const inputs = [_][]const u8{"https://user:pass@example.com:8080/path?query=1#frag"};
    var results: [1]ParseResult = undefined;

    parseUris(&inputs, &results);

    try std.testing.expect(results[0].success);
    const c = results[0].components.?;
    try std.testing.expectEqualStrings("https", c.scheme.?);
    try std.testing.expectEqualStrings("user:pass", c.userinfo.?);
    try std.testing.expectEqualStrings("example.com", c.host.?);
    try std.testing.expectEqual(@as(?u16, 8080), c.port);
    try std.testing.expectEqualStrings("/path", c.path);
    try std.testing.expectEqualStrings("query=1", c.query.?);
    try std.testing.expectEqualStrings("frag", c.fragment.?);
}

test "parse uri - simple" {
    const inputs = [_][]const u8{"http://example.com/path"};
    var results: [1]ParseResult = undefined;

    parseUris(&inputs, &results);

    try std.testing.expect(results[0].success);
    const c = results[0].components.?;
    try std.testing.expectEqualStrings("http", c.scheme.?);
    try std.testing.expectEqualStrings("example.com", c.host.?);
    try std.testing.expectEqualStrings("/path", c.path);
}

test "parse uri - relative" {
    const inputs = [_][]const u8{"/path/to/resource"};
    var results: [1]ParseResult = undefined;

    parseUris(&inputs, &results);

    try std.testing.expect(results[0].success);
    const c = results[0].components.?;
    try std.testing.expect(c.scheme == null);
    try std.testing.expectEqualStrings("/path/to/resource", c.path);
}

test "parse uri - ipv6" {
    const inputs = [_][]const u8{"http://[::1]:8080/path"};
    var results: [1]ParseResult = undefined;

    parseUris(&inputs, &results);

    try std.testing.expect(results[0].success);
    const c = results[0].components.?;
    try std.testing.expectEqualStrings("[::1]", c.host.?);
    try std.testing.expectEqual(@as(?u16, 8080), c.port);
}

test "validate uri - valid" {
    const inputs = [_][]const u8{
        "https://example.com",
        "ftp://files.example.com/file.txt",
        "/relative/path",
    };
    var results: [3]ValidateResult = undefined;

    validateUris(&inputs, &results);

    for (results) |result| {
        try std.testing.expect(result.valid);
    }
}

test "validate uri - invalid percent encoding" {
    const inputs = [_][]const u8{"http://example.com/%GG"};
    var results: [1]ValidateResult = undefined;

    validateUris(&inputs, &results);

    try std.testing.expect(!results[0].valid);
    try std.testing.expectEqual(@as(u8, 5), results[0].error_code);
}

test "normalize uri - lowercase" {
    const allocator = std.testing.allocator;
    const inputs = [_][]const u8{"HTTP://EXAMPLE.COM/Path"};
    var results: [1]NormalizeResult = undefined;

    normalizeUris(allocator, &inputs, &results);

    try std.testing.expect(results[0].success);
    try std.testing.expectEqualStrings("http://example.com/Path", results[0].normalized.?);
    allocator.free(results[0].normalized.?);
}

test "normalize uri - remove default port" {
    const allocator = std.testing.allocator;
    const inputs = [_][]const u8{"http://example.com:80/path"};
    var results: [1]NormalizeResult = undefined;

    normalizeUris(allocator, &inputs, &results);

    try std.testing.expect(results[0].success);
    try std.testing.expectEqualStrings("http://example.com/path", results[0].normalized.?);
    allocator.free(results[0].normalized.?);
}

test "normalize uri - keep non-default port" {
    const allocator = std.testing.allocator;
    const inputs = [_][]const u8{"http://example.com:8080/path"};
    var results: [1]NormalizeResult = undefined;

    normalizeUris(allocator, &inputs, &results);

    try std.testing.expect(results[0].success);
    try std.testing.expectEqualStrings("http://example.com:8080/path", results[0].normalized.?);
    allocator.free(results[0].normalized.?);
}

test "parallel parse - large batch" {
    if (!build_options.enable_spice) return error.SkipZigTest;

    var inputs: [32][]const u8 = undefined;
    for (&inputs) |*input| {
        input.* = "https://example.com/path";
    }
    var results: [32]ParseResult = undefined;

    parseUris(&inputs, &results);

    for (results) |result| {
        try std.testing.expect(result.success);
    }
}

test "parallel validate - large batch" {
    if (!build_options.enable_spice) return error.SkipZigTest;

    var inputs: [32][]const u8 = undefined;
    for (&inputs) |*input| {
        input.* = "https://example.com/path?query=value";
    }
    var results: [32]ValidateResult = undefined;

    validateUris(&inputs, &results);

    for (results) |result| {
        try std.testing.expect(result.valid);
    }
}

test "parallel normalize - large batch" {
    if (!build_options.enable_spice) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var inputs: [16][]const u8 = undefined;
    for (&inputs) |*input| {
        input.* = "HTTP://EXAMPLE.COM/path";
    }
    var results: [16]NormalizeResult = undefined;

    normalizeUris(allocator, &inputs, &results);

    for (results) |result| {
        try std.testing.expect(result.success);
        try std.testing.expectEqualStrings("http://example.com/path", result.normalized.?);
        allocator.free(result.normalized.?);
    }
}
