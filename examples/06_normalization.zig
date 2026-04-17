// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// Example: URI Normalization (RFC 3986 Section 6)
//
// This example demonstrates URI normalization, which converts URIs
// to a canonical form for reliable comparison and deduplication.
//
// Normalization includes:
// - Case normalization (scheme and host to lowercase)
// - Percent-encoding normalization
// - Path segment normalization (remove dot segments)
//
// Build and run:
//   zig build run-06_normalization

const std = @import("std");
const uri = @import("uri");

const print = std.debug.print;

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // =========================================================================
    // Example 1: Case Normalization
    // =========================================================================
    print("\n=== Example 1: Case Normalization ===\n", .{});
    print("Schemes and hosts are case-insensitive and normalized to lowercase.\n\n", .{});

    const mixed_case = try uri.parse("HTTPS://EXAMPLE.COM/Path");
    var normalized1 = try uri.normalize(allocator, mixed_case);
    defer normalized1.deinit(allocator);

    print("Original: {s}\n", .{mixed_case.raw});
    print("Scheme:   {s} => {s}\n", .{ mixed_case.scheme orelse "", normalized1.scheme orelse "" });
    print("Host:     {s} => {s}\n", .{ mixed_case.host orelse "", normalized1.host orelse "" });
    print("Path:     {s} (unchanged - paths are case-sensitive)\n", .{normalized1.path});

    // =========================================================================
    // Example 2: Path Dot Segment Removal
    // =========================================================================
    print("\n=== Example 2: Path Dot Segment Removal ===\n", .{});
    print("The . and .. segments are resolved to produce a clean path.\n\n", .{});

    const dot_segments = [_][]const u8{
        "/a/b/c/./../../g",
        "/a/b/../../../c",
        "/a/./b/./c",
        "/../a",
        "/a/b/c/../d",
    };

    for (dot_segments) |path| {
        const result = try uri.uri.removeDotSegments(allocator, path);
        defer allocator.free(result);
        print("  {s:<25} => {s}\n", .{ path, result });
    }

    // =========================================================================
    // Example 3: Full URI Normalization
    // =========================================================================
    print("\n=== Example 3: Full URI Normalization ===\n", .{});

    const uris_to_normalize = [_][]const u8{
        "HTTP://Example.COM/a/b/../c",
        "https://EXAMPLE.com:443/path/./to/../resource",
        "FTP://ftp.EXAMPLE.org/pub/./files/../docs",
    };

    for (uris_to_normalize) |uri_str| {
        const parsed = try uri.parse(uri_str);
        var normalized = try uri.normalize(allocator, parsed);
        defer normalized.deinit(allocator);

        var buf: std.Io.Writer.Allocating = .init(allocator);
        defer buf.deinit();
        try normalized.format(&buf.writer);

        print("\nOriginal:   {s}\n", .{uri_str});
        print("Normalized: {s}\n", .{buf.writer.buffered()});
    }

    // =========================================================================
    // Example 4: Why Normalization Matters
    // =========================================================================
    print("\n=== Example 4: Why Normalization Matters ===\n", .{});
    print("These URIs all refer to the same resource:\n\n", .{});

    const equivalent_uris = [_][]const u8{
        "https://example.com/path",
        "HTTPS://EXAMPLE.COM/path",
        "https://Example.Com/path",
        "https://example.com/a/../path",
        "https://example.com/./path",
    };

    for (equivalent_uris) |uri_str| {
        const parsed = try uri.parse(uri_str);
        var normalized = try uri.normalize(allocator, parsed);
        defer normalized.deinit(allocator);

        var buf: std.Io.Writer.Allocating = .init(allocator);
        defer buf.deinit();
        try normalized.format(&buf.writer);

        print("  {s:<40} => {s}\n", .{ uri_str, buf.writer.buffered() });
    }

    print("\nAfter normalization, they can be reliably compared.\n", .{});

    // =========================================================================
    // Example 5: Normalization for Caching
    // =========================================================================
    print("\n=== Example 5: Normalization for Caching ===\n", .{});
    print("Use normalized URIs as cache keys to avoid duplicates.\n\n", .{});

    // Simulated cache using normalized URIs as keys
    var cache = std.StringHashMap([]const u8).init(allocator);
    defer {
        var it = cache.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        cache.deinit();
    }

    const requests = [_][]const u8{
        "HTTPS://API.EXAMPLE.COM/users",
        "https://api.example.com/users",
        "https://API.example.com/./users",
    };

    for (requests) |request| {
        const parsed = try uri.parse(request);
        var normalized = try uri.normalize(allocator, parsed);

        var buf: std.Io.Writer.Allocating = .init(allocator);
        try normalized.format(&buf.writer);
        const normalized_key = try buf.toOwnedSlice();

        // Clean up the normalized URI struct (we only need the string)
        normalized.deinit(allocator);

        if (cache.contains(normalized_key)) {
            print("  Cache HIT:  {s}\n", .{request});
            print("              (normalized: {s})\n", .{normalized_key});
            allocator.free(normalized_key);
        } else {
            print("  Cache MISS: {s}\n", .{request});
            print("              (normalized: {s})\n", .{normalized_key});
            try cache.put(normalized_key, "cached data");
        }
    }

    // =========================================================================
    // Example 6: Default Port Normalization
    // =========================================================================
    print("\n=== Example 6: Default Port Handling ===\n", .{});
    print("Standard ports for common schemes:\n\n", .{});

    const schemes_with_ports = [_]struct { scheme: []const u8, port: u16 }{
        .{ .scheme = "http", .port = 80 },
        .{ .scheme = "https", .port = 443 },
        .{ .scheme = "ftp", .port = 21 },
        .{ .scheme = "ssh", .port = 22 },
    };

    for (schemes_with_ports) |sp| {
        const default = uri.defaultPort(sp.scheme);
        print("  {s}: default port {d}\n", .{ sp.scheme, default orelse 0 });
    }

    print("\nNote: Explicit default ports (e.g., :80 for http) can be omitted.\n", .{});
    print("Both 'http://example.com' and 'http://example.com:80' are equivalent.\n", .{});

    print("\n", .{});
}
