// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// Example: URI Validation Utilities
//
// This example demonstrates URI validation functions and error handling.
// Useful for validating user input, configuration values, and API parameters.
//
// Build and run:
//   zig build run-07_validation

const std = @import("std");
const uri = @import("uri");

const print = std.debug.print;

pub fn main() !void {
    // =========================================================================
    // Example 1: Basic Validation
    // =========================================================================
    print("\n=== Example 1: Basic Validation ===\n", .{});

    const test_uris = [_][]const u8{
        "https://example.com/path",
        "ftp://files.example.org/pub/file.txt",
        "/relative/path",
        "mailto:user@example.com",
        "urn:isbn:0451450523",
        "", // Empty is valid (empty reference)
    };

    for (test_uris) |test_uri| {
        const valid = uri.isValid(test_uri);
        const display = if (test_uri.len == 0) "(empty)" else test_uri;
        print("  {s:<40} valid: {}\n", .{ display, valid });
    }

    // =========================================================================
    // Example 2: Absolute vs Relative URIs
    // =========================================================================
    print("\n=== Example 2: Absolute vs Relative URIs ===\n", .{});

    const uri_examples = [_][]const u8{
        "https://example.com/path",
        "//example.com/path",
        "/path/to/resource",
        "path/to/resource",
        "?query=value",
        "#fragment",
    };

    print("{s:<35} {s:<10} {s:<10}\n", .{ "URI", "Absolute", "Relative" });
    print("{s:<35} {s:<10} {s:<10}\n", .{ "---", "--------", "--------" });

    for (uri_examples) |uri_str| {
        const is_abs = uri.isAbsolute(uri_str);
        const is_rel = uri.isRelative(uri_str);
        print("{s:<35} {:<10} {:<10}\n", .{ uri_str, is_abs, is_rel });
    }

    // =========================================================================
    // Example 3: Parse Error Handling
    // =========================================================================
    print("\n=== Example 3: Parse Error Handling ===\n", .{});
    print("Handling invalid URI input gracefully.\n\n", .{});

    const invalid_uris = [_]struct { input: []const u8, desc: []const u8 }{
        .{ .input = "http://example.com:99999/path", .desc = "Port out of range" },
        .{ .input = "http://example.com:abc/path", .desc = "Invalid port" },
        .{ .input = "http://[::1/path", .desc = "Unclosed IPv6 bracket" },
        .{ .input = "http://example.com/path%GG", .desc = "Invalid percent encoding" },
        .{ .input = "http://example.com/path with spaces", .desc = "Unencoded space (strict mode)" },
    };

    for (invalid_uris) |test_case| {
        const result = uri.parse(test_case.input);
        if (result) |_| {
            print("  {s}: OK (unexpectedly)\n", .{test_case.desc});
        } else |err| {
            print("  {s}: {}\n", .{ test_case.desc, err });
        }
    }

    // =========================================================================
    // Example 4: Validation with Options
    // =========================================================================
    print("\n=== Example 4: Validation with Parse Options ===\n", .{});

    const uri_with_space = "http://example.com/path with space";

    // Strict mode (default) - rejects spaces
    const strict_result = uri.parseWithOptions(uri_with_space, .{ .strict = true });
    if (strict_result) |_| {
        print("Strict mode: OK\n", .{});
    } else |err| {
        print("Strict mode: {}\n", .{err});
    }

    // Lenient mode - allows spaces
    const lenient_result = uri.parseWithOptions(uri_with_space, .{ .strict = false });
    if (lenient_result) |parsed| {
        print("Lenient mode: OK (path: {s})\n", .{parsed.path});
    } else |err| {
        print("Lenient mode: {}\n", .{err});
    }

    // =========================================================================
    // Example 5: Practical Validation Function
    // =========================================================================
    print("\n=== Example 5: Practical Validation Function ===\n", .{});

    const config_urls = [_][]const u8{
        "https://api.example.com/v1",
        "http://localhost:8080",
        "/api/endpoint",
        "ftp://files.example.com",
        "not a url at all",
    };

    for (config_urls) |url| {
        print("\nValidating: {s}\n", .{url});
        validateConfigUrl(url);
    }

    // =========================================================================
    // Example 6: URI Component Inspection
    // =========================================================================
    print("\n=== Example 6: URI Component Inspection ===\n", .{});

    const complex_uri = try uri.parse("https://admin:secret@api.example.com:8443/v2/users?active=true&limit=10#results");

    print("Inspecting: https://admin:secret@api.example.com:8443/v2/users?active=true&limit=10#results\n\n", .{});

    // Check each component
    print("Has scheme:    {} ({s})\n", .{ complex_uri.scheme != null, complex_uri.scheme orelse "" });
    print("Has userinfo:  {} ({s})\n", .{ complex_uri.userinfo != null, complex_uri.userinfo orelse "" });
    print("Has host:      {} ({s})\n", .{ complex_uri.host != null, complex_uri.host orelse "" });
    print("Has port:      {} ({?d})\n", .{ complex_uri.port != null, complex_uri.port });
    print("Has path:      {} ({s})\n", .{ complex_uri.path.len > 0, complex_uri.path });
    print("Has query:     {} ({s})\n", .{ complex_uri.query != null, complex_uri.query orelse "" });
    print("Has fragment:  {} ({s})\n", .{ complex_uri.fragment != null, complex_uri.fragment orelse "" });
    print("Has authority: {}\n", .{complex_uri.hasAuthority()});
    print("Is URN:        {}\n", .{complex_uri.isUrn()});

    // =========================================================================
    // Example 7: Batch Validation
    // =========================================================================
    print("\n=== Example 7: Batch Validation Summary ===\n", .{});

    const batch_urls = [_][]const u8{
        "https://example.com",
        "http://localhost:8080/api",
        "ftp://files.example.org",
        "invalid url",
        "mailto:test@example.com",
        "/relative/path",
        "urn:isbn:123456",
        "https://192.168.1.1/admin",
        "http://[::1]:3000/ipv6",
    };

    var valid_count: usize = 0;
    var absolute_count: usize = 0;
    var http_count: usize = 0;

    for (batch_urls) |url| {
        if (uri.parse(url)) |parsed| {
            valid_count += 1;
            if (parsed.isAbsolute()) {
                absolute_count += 1;
                if (parsed.scheme) |s| {
                    if (std.ascii.eqlIgnoreCase(s, "http") or std.ascii.eqlIgnoreCase(s, "https")) {
                        http_count += 1;
                    }
                }
            }
        } else |_| {}
    }

    print("Total URIs:    {d}\n", .{batch_urls.len});
    print("Valid:         {d}\n", .{valid_count});
    print("Absolute:      {d}\n", .{absolute_count});
    print("HTTP/HTTPS:    {d}\n", .{http_count});

    print("\n", .{});
}

// Example: Validate a configuration URL
fn validateConfigUrl(url: []const u8) void {
    // Check if it's valid
    const parsed = uri.parse(url) catch |err| {
        print("  Invalid URL: {}\n", .{err});
        return;
    };

    // Must be absolute
    if (!parsed.isAbsolute()) {
        print("  Error: URL must be absolute (have a scheme)\n", .{});
        return;
    }

    // Must be http or https
    if (parsed.scheme) |scheme| {
        const is_http = std.ascii.eqlIgnoreCase(scheme, "http");
        const is_https = std.ascii.eqlIgnoreCase(scheme, "https");
        if (!is_http and !is_https) {
            print("  Error: Scheme must be http or https, got: {s}\n", .{scheme});
            return;
        }
    }

    // Must have a host
    if (parsed.host == null) {
        print("  Error: URL must have a host\n", .{});
        return;
    }

    print("  Valid: scheme={s}, host={s}\n", .{
        parsed.scheme orelse "",
        parsed.host orelse "",
    });
}
