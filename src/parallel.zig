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
const uri_mod = @import("uri.zig");

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

// Thread pool uses `page_allocator` for internal allocations. This is
// thread-safe by design (each allocation is a direct `mmap`/`munmap`
// syscall) and requires no additional synchronization. The tradeoff is
// higher per-allocation overhead compared to a userspace allocator such
// as `GeneralPurposeAllocator` or `smp_allocator`. For the thread pool's
// infrequent, large allocations this is acceptable; switching to a
// faster allocator would reduce syscall overhead but add complexity
// and an additional dependency.
var global_pool: if (build_options.enable_spice) ?spice.ThreadPool else void = if (build_options.enable_spice) null else {};
var pool_mutex: std.Thread.Mutex = .{};

/// Atomic flag indicating whether `global_pool` has been initialized.
/// Used as a fast-path check to avoid acquiring `pool_mutex` on every
/// call to `getPool()` after the pool is already running.
var pool_initialized: bool = false;

/// Return a pointer to the lazily-initialized global thread pool.
///
/// Uses double-checked locking so that, after the first initialization,
/// subsequent calls only perform an atomic load (no mutex acquisition).
///
/// Thread safety: safe to call concurrently from any number of threads.
pub fn getPool() if (build_options.enable_spice) *spice.ThreadPool else void {
    if (!build_options.enable_spice) return;

    // Fast path: pool already initialized -- atomic load avoids mutex.
    if (@atomicLoad(bool, &pool_initialized, .acquire)) {
        return &global_pool.?;
    }

    // Slow path: acquire the mutex and initialize if still needed.
    pool_mutex.lock();
    defer pool_mutex.unlock();

    if (global_pool == null) {
        global_pool = spice.ThreadPool.init(std.heap.page_allocator);
        global_pool.?.start(.{});
        @atomicStore(bool, &pool_initialized, true, .release);
    }
    return &global_pool.?;
}

/// Tear down the global thread pool and release its resources.
///
/// **Lifecycle constraint:** This function must NOT be called while any
/// parallel operations (e.g., `parseUris`, `validateUris`, `normalizeUris`)
/// are still in flight. Callers must ensure that every batch operation has
/// returned before calling `deinitPool()`. Violating this invariant causes
/// undefined behavior (use-after-free on the pool).
///
/// After `deinitPool()` returns, a subsequent call to `getPool()` will
/// transparently re-initialize a fresh pool.
pub fn deinitPool() void {
    if (!build_options.enable_spice) return;

    pool_mutex.lock();
    defer pool_mutex.unlock();

    if (global_pool) |*pool| {
        @atomicStore(bool, &pool_initialized, false, .release);
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
    /// Error message (null on success)
    error_msg: ?[]const u8,
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

/// Parse a single URI by delegating to the core uri.zig parser.
fn parseUri(input: []const u8) ParseResult {
    const parsed = uri_mod.parse(input) catch |err| {
        return .{
            .components = null,
            .success = false,
            .error_msg = parseErrorMessage(err),
        };
    };

    return .{
        .components = .{
            .scheme = parsed.scheme,
            .userinfo = parsed.userinfo,
            .host = parsed.host,
            .port = parsed.port,
            .path = parsed.path,
            .query = parsed.query,
            .fragment = parsed.fragment,
        },
        .success = true,
        .error_msg = null,
    };
}

/// Convert a ParseError to a human-readable error message.
fn parseErrorMessage(err: uri_mod.ParseError) []const u8 {
    return switch (err) {
        error.InvalidCharacter => "Invalid character in URI",
        error.InvalidPercentEncoding => "Invalid percent encoding",
        error.InvalidScheme => "Invalid scheme",
        error.InvalidPort => "Invalid port number",
        error.PortOutOfRange => "Port number out of range (0-65535)",
        error.InvalidHost => "Invalid host format",
        error.UnclosedIPv6Bracket => "Unclosed bracket in IPv6 address",
        error.OutOfMemory => "Out of memory",
        error.InputTooLong => "Input exceeds maximum allowed length",
    };
}

// ============================================================================
// Validation Types
// ============================================================================

/// Result of URI validation
pub const ValidateResult = struct {
    /// Whether URI is valid
    valid: bool,
    /// Error description (null when valid)
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

/// Validate a single URI by delegating to the core uri.zig parser.
fn validateUri(input: []const u8) ValidateResult {
    _ = uri_mod.parse(input) catch |err| {
        return .{
            .valid = false,
            .error_msg = parseErrorMessage(err),
        };
    };

    return .{ .valid = true, .error_msg = null };
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
    /// Error message (null on success)
    error_msg: ?[]const u8,
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
/// normalize percent-encoding, remove dot segments.
///
/// Parameters:
/// - allocator: Memory allocator for normalized strings.
///   **Thread-safety requirement:** When spice is enabled and the input
///   length meets the parallel threshold (>= 8), this allocator is used
///   concurrently from multiple worker threads. It **must** be thread-safe.
///   Suitable allocators include `std.heap.page_allocator` and
///   `std.heap.GeneralPurposeAllocator` (thread-safe by default). An
///   allocator that is NOT thread-safe (e.g., a bare `ArenaAllocator` or
///   `FixedBufferAllocator`) will cause data races.
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

/// Normalize a single URI by delegating to the core uri.zig parser and normalizer.
fn normalizeUri(allocator: std.mem.Allocator, input: []const u8) NormalizeResult {
    const parsed = uri_mod.parse(input) catch |err| {
        return .{
            .normalized = null,
            .success = false,
            .error_msg = parseErrorMessage(err),
        };
    };

    var normalized = uri_mod.normalize(allocator, parsed) catch |err| {
        return .{
            .normalized = null,
            .success = false,
            .error_msg = switch (err) {
                error.OutOfMemory => "Out of memory",
                else => parseErrorMessage(err),
            },
        };
    };
    defer normalized.deinit(allocator);

    // Serialize the normalized URI to a string
    var buf = std.array_list.Managed(u8).init(allocator);

    // Estimate output size from URI components to avoid reallocation
    const estimated = (if (normalized.scheme) |s| s.len + 1 else @as(usize, 0)) +
        (if (normalized.host != null) @as(usize, 2) else @as(usize, 0)) +
        (if (normalized.userinfo) |ui| ui.len + 1 else @as(usize, 0)) +
        (if (normalized.host) |h| h.len else @as(usize, 0)) +
        (if (normalized.raw_port) |rp| rp.len + 1 else @as(usize, 0)) +
        normalized.path.len +
        (if (normalized.query) |q| q.len + 1 else @as(usize, 0)) +
        (if (normalized.fragment) |f| f.len + 1 else @as(usize, 0));
    buf.ensureTotalCapacity(estimated) catch {
        buf.deinit();
        return .{ .normalized = null, .success = false, .error_msg = "Out of memory" };
    };

    normalized.format(buf.writer()) catch {
        buf.deinit();
        return .{
            .normalized = null,
            .success = false,
            .error_msg = "Out of memory",
        };
    };

    const slice = buf.toOwnedSlice() catch {
        buf.deinit();
        return .{
            .normalized = null,
            .success = false,
            .error_msg = "Out of memory",
        };
    };
    return .{
        .normalized = slice,
        .success = true,
        .error_msg = null,
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

test "parse uri - error has descriptive message" {
    const inputs = [_][]const u8{"http://example.com/%GG"};
    var results: [1]ParseResult = undefined;

    parseUris(&inputs, &results);

    try std.testing.expect(!results[0].success);
    try std.testing.expect(results[0].error_msg != null);
    try std.testing.expectEqualStrings("Invalid percent encoding", results[0].error_msg.?);
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
    try std.testing.expect(results[0].error_msg != null);
    try std.testing.expectEqualStrings("Invalid percent encoding", results[0].error_msg.?);
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
    // RFC 3986 Section 6.2.3: default port 80 is removed for http scheme
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
