// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// Example: Basic URI Parsing
//
// This example demonstrates how to parse URIs and access their components
// using the RFC 3986 compliant URI library.
//
// Build and run:
//   zig build run-01_basic_parsing

const std = @import("std");
const uri = @import("uri");

const print = std.debug.print;

pub fn main() !void {
    // =========================================================================
    // Example 1: Parse a full URI with all components
    // =========================================================================
    print("\n=== Example 1: Full URI with all components ===\n", .{});

    const full_uri = try uri.parse("https://user:pass@example.com:8080/path/to/resource?query=value&foo=bar#section1");

    print("Original:  {s}\n", .{full_uri.raw});
    print("Scheme:    {s}\n", .{full_uri.scheme orelse "(none)"});
    print("Userinfo:  {s}\n", .{full_uri.userinfo orelse "(none)"});
    print("Host:      {s}\n", .{full_uri.host orelse "(none)"});
    print("Port:      {?d}\n", .{full_uri.port});
    print("Path:      {s}\n", .{full_uri.path});
    print("Query:     {s}\n", .{full_uri.query orelse "(none)"});
    print("Fragment:  {s}\n", .{full_uri.fragment orelse "(none)"});

    // =========================================================================
    // Example 2: Parse a simple HTTP URL
    // =========================================================================
    print("\n=== Example 2: Simple HTTP URL ===\n", .{});

    const simple_uri = try uri.parse("https://example.com/path");

    print("Original:  {s}\n", .{simple_uri.raw});
    print("Scheme:    {s}\n", .{simple_uri.scheme orelse "(none)"});
    print("Host:      {s}\n", .{simple_uri.host orelse "(none)"});
    print("Path:      {s}\n", .{simple_uri.path});

    // Check if it's an absolute URI
    print("Is Absolute: {}\n", .{simple_uri.isAbsolute()});
    print("Has Authority: {}\n", .{simple_uri.hasAuthority()});

    // =========================================================================
    // Example 3: Parse a relative reference
    // =========================================================================
    print("\n=== Example 3: Relative Reference ===\n", .{});

    const relative_uri = try uri.parse("/path/to/resource?query#frag");

    print("Original:    {s}\n", .{relative_uri.raw});
    print("Scheme:      {s}\n", .{relative_uri.scheme orelse "(none)"});
    print("Path:        {s}\n", .{relative_uri.path});
    print("Query:       {s}\n", .{relative_uri.query orelse "(none)"});
    print("Fragment:    {s}\n", .{relative_uri.fragment orelse "(none)"});
    print("Is Relative: {}\n", .{relative_uri.isRelative()});

    // =========================================================================
    // Example 4: Parse URI with IPv6 host
    // =========================================================================
    print("\n=== Example 4: IPv6 Host ===\n", .{});

    const ipv6_uri = try uri.parse("http://[::1]:8080/api/v1");

    print("Original:  {s}\n", .{ipv6_uri.raw});
    print("Host:      {s}\n", .{ipv6_uri.host orelse "(none)"});
    print("Port:      {?d}\n", .{ipv6_uri.port});
    print("Path:      {s}\n", .{ipv6_uri.path});

    // =========================================================================
    // Example 5: Parse a mailto URI (scheme-only, no authority)
    // =========================================================================
    print("\n=== Example 5: Mailto URI ===\n", .{});

    const mailto_uri = try uri.parse("mailto:user@example.com");

    print("Original:      {s}\n", .{mailto_uri.raw});
    print("Scheme:        {s}\n", .{mailto_uri.scheme orelse "(none)"});
    print("Path:          {s}\n", .{mailto_uri.path});
    print("Has Authority: {}\n", .{mailto_uri.hasAuthority()});

    // =========================================================================
    // Example 6: Parse file URI
    // =========================================================================
    print("\n=== Example 6: File URI ===\n", .{});

    const file_uri = try uri.parse("file:///home/user/documents/file.txt");

    print("Original:  {s}\n", .{file_uri.raw});
    print("Scheme:    {s}\n", .{file_uri.scheme orelse "(none)"});
    print("Host:      {s}\n", .{file_uri.host orelse "(empty)"});
    print("Path:      {s}\n", .{file_uri.path});

    // =========================================================================
    // Example 7: Get default ports for common schemes
    // =========================================================================
    print("\n=== Example 7: Default Ports ===\n", .{});

    const schemes = [_][]const u8{ "http", "https", "ftp", "ssh", "smtp", "ws", "wss" };
    for (schemes) |scheme| {
        if (uri.defaultPort(scheme)) |port| {
            print("{s}: {d}\n", .{ scheme, port });
        }
    }

    // =========================================================================
    // Example 8: Parse empty/minimal URIs
    // =========================================================================
    print("\n=== Example 8: Minimal URIs ===\n", .{});

    // Empty URI
    const empty = try uri.parse("");
    print("Empty URI path: \"{s}\" (length: {d})\n", .{ empty.path, empty.path.len });

    // Query-only reference
    const query_only = try uri.parse("?search=term");
    print("Query-only - Path: \"{s}\", Query: {s}\n", .{ query_only.path, query_only.query orelse "(none)" });

    // Fragment-only reference
    const frag_only = try uri.parse("#section");
    print("Fragment-only - Path: \"{s}\", Fragment: {s}\n", .{ frag_only.path, frag_only.fragment orelse "(none)" });

    print("\n", .{});
}
