// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// Example: URI Reference Resolution (RFC 3986 Section 5)
//
// This example demonstrates how to resolve relative URI references
// against a base URI according to RFC 3986.
//
// The resolution algorithm handles:
// - Relative paths (../sibling, ./current, subdir/file)
// - Absolute paths (/from/root)
// - Query-only references (?newquery)
// - Fragment-only references (#section)
// - Full URIs with schemes
//
// Build and run:
//   zig build run-02_uri_resolution

const std = @import("std");
const uri = @import("uri");

const print = std.debug.print;

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // =========================================================================
    // RFC 3986 Section 5.4 Reference Resolution Examples
    // Base URI: http://a/b/c/d;p?q
    // =========================================================================
    print("\n=== RFC 3986 Section 5.4 Reference Resolution Examples ===\n", .{});
    print("Base URI: http://a/b/c/d;p?q\n\n", .{});

    const base = try uri.parse("http://a/b/c/d;p?q");

    // Test cases from RFC 3986 Section 5.4
    const test_cases = [_]struct { reference: []const u8, expected: []const u8 }{
        // Normal Examples (5.4.1)
        .{ .reference = "g:h", .expected = "g:h" },
        .{ .reference = "g", .expected = "http://a/b/c/g" },
        .{ .reference = "./g", .expected = "http://a/b/c/g" },
        .{ .reference = "g/", .expected = "http://a/b/c/g/" },
        .{ .reference = "/g", .expected = "http://a/g" },
        .{ .reference = "//g", .expected = "http://g" },
        .{ .reference = "?y", .expected = "http://a/b/c/d;p?y" },
        .{ .reference = "g?y", .expected = "http://a/b/c/g?y" },
        .{ .reference = "#s", .expected = "http://a/b/c/d;p?q#s" },
        .{ .reference = "g#s", .expected = "http://a/b/c/g#s" },
        .{ .reference = "g?y#s", .expected = "http://a/b/c/g?y#s" },
        .{ .reference = ";x", .expected = "http://a/b/c/;x" },
        .{ .reference = "g;x", .expected = "http://a/b/c/g;x" },
        .{ .reference = "g;x?y#s", .expected = "http://a/b/c/g;x?y#s" },
        .{ .reference = "", .expected = "http://a/b/c/d;p?q" },
        .{ .reference = ".", .expected = "http://a/b/c/" },
        .{ .reference = "./", .expected = "http://a/b/c/" },
        .{ .reference = "..", .expected = "http://a/b/" },
        .{ .reference = "../", .expected = "http://a/b/" },
        .{ .reference = "../g", .expected = "http://a/b/g" },
        .{ .reference = "../..", .expected = "http://a/" },
        .{ .reference = "../../", .expected = "http://a/" },
        .{ .reference = "../../g", .expected = "http://a/g" },
    };

    for (test_cases) |tc| {
        const ref = try uri.parse(tc.reference);
        var resolved = try uri.resolve(allocator, base, ref);
        defer resolved.deinit(allocator);

        // Format the resolved URI to a string for display
        var result_buf: std.Io.Writer.Allocating = .init(allocator);
        defer result_buf.deinit();
        try resolved.format(&result_buf.writer);

        const ref_display = if (tc.reference.len == 0) "(empty)" else tc.reference;
        print("  \"{s:<12}\" => {s}\n", .{ ref_display, result_buf.writer.buffered() });
    }

    // =========================================================================
    // Practical Example: Resolving links on a webpage
    // =========================================================================
    print("\n=== Practical Example: Resolving Links ===\n", .{});
    print("Base: https://example.com/docs/api/v2/users.html\n\n", .{});

    const page_base = try uri.parse("https://example.com/docs/api/v2/users.html");

    const links = [_][]const u8{
        "../v1/users.html", // Link to older API version
        "groups.html", // Sibling page
        "/images/logo.png", // Absolute path from root
        "?page=2", // Pagination
        "#create-user", // Anchor link
        "//cdn.example.com/lib.js", // Protocol-relative URL
    };

    for (links) |link| {
        const ref = try uri.parse(link);
        var resolved = try uri.resolve(allocator, page_base, ref);
        defer resolved.deinit(allocator);

        var result_buf: std.Io.Writer.Allocating = .init(allocator);
        defer result_buf.deinit();
        try resolved.format(&result_buf.writer);

        print("  Link: \"{s}\"\n  Resolved: {s}\n\n", .{ link, result_buf.writer.buffered() });
    }

    // =========================================================================
    // Example: Building API endpoint URLs
    // =========================================================================
    print("=== Building API Endpoint URLs ===\n", .{});
    print("Base: https://api.service.com/v1/\n\n", .{});

    const api_base = try uri.parse("https://api.service.com/v1/");

    const endpoints = [_][]const u8{
        "users", // /v1/users
        "users/123", // /v1/users/123
        "users/123/posts", // /v1/users/123/posts
        "../v2/users", // /v2/users
    };

    for (endpoints) |endpoint| {
        const ref = try uri.parse(endpoint);
        var resolved = try uri.resolve(allocator, api_base, ref);
        defer resolved.deinit(allocator);

        var result_buf: std.Io.Writer.Allocating = .init(allocator);
        defer result_buf.deinit();
        try resolved.format(&result_buf.writer);

        print("  Endpoint: \"{s}\" => {s}\n", .{ endpoint, result_buf.writer.buffered() });
    }

    print("\n", .{});
}
