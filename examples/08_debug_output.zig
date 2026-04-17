// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// Example: Debug Output Utilities
//
// This example demonstrates the debug output utilities for URI structures.
// These are useful for testing, logging, and debugging URI parsing.
//
// Build and run:
//   zig build run-08_debug_output

const std = @import("std");
const uri = @import("uri");

const print = std.debug.print;

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // =========================================================================
    // Example 1: JSON Output (Compact)
    // =========================================================================
    print("\n=== Example 1: Compact JSON Output ===\n", .{});
    print("Useful for logging and machine-readable output.\n\n", .{});

    const test_uri = try uri.parse("https://user:pass@example.com:8080/path?query=value#frag");
    const json = try uri.toJson(allocator, test_uri);
    defer allocator.free(json);

    print("Input: {s}\n", .{test_uri.raw});
    print("JSON:  {s}\n", .{json});

    // =========================================================================
    // Example 2: Pretty-Printed JSON
    // =========================================================================
    print("\n=== Example 2: Pretty-Printed JSON ===\n", .{});
    print("Readable format for debugging and documentation.\n\n", .{});

    const pretty_json = try uri.toJsonPretty(allocator, test_uri);
    defer allocator.free(pretty_json);

    print("{s}\n", .{pretty_json});

    // =========================================================================
    // Example 3: URN JSON Output
    // =========================================================================
    print("\n=== Example 3: URN JSON Output ===\n", .{});

    const urn = try uri.parse("urn:example:foo-bar?+resolver?=query#frag");
    const urn_json = try uri.toJsonPretty(allocator, urn);
    defer allocator.free(urn_json);

    print("Input: {s}\n\n", .{urn.raw});
    print("{s}\n", .{urn_json});

    // =========================================================================
    // Example 4: Debug Dump to stderr
    // =========================================================================
    print("\n=== Example 4: Debug Dump ===\n", .{});
    print("The dump() function writes to stderr for quick debugging.\n\n", .{});

    const complex_uri = try uri.parse("ftp://anonymous:guest@ftp.example.org:21/pub/files/readme.txt");

    print("Calling uri.dump() for: {s}\n", .{complex_uri.raw});
    print("--- Output on stderr: ---\n", .{});

    uri.dump(complex_uri);

    print("--- End stderr output ---\n", .{});

    // =========================================================================
    // Example 5: Comparing URIs with JSON
    // =========================================================================
    print("\n=== Example 5: Comparing URIs with JSON ===\n", .{});
    print("JSON output is deterministic - useful for testing.\n\n", .{});

    const uri1 = try uri.parse("https://example.com/path?a=1&b=2");
    const uri2 = try uri.parse("https://example.com/path?a=1&b=2");
    const uri3 = try uri.parse("https://example.com/path?b=2&a=1");

    const json1 = try uri.toJson(allocator, uri1);
    defer allocator.free(json1);
    const json2 = try uri.toJson(allocator, uri2);
    defer allocator.free(json2);
    const json3 = try uri.toJson(allocator, uri3);
    defer allocator.free(json3);

    print("URI 1: {s}\n", .{uri1.raw});
    print("URI 2: {s}\n", .{uri2.raw});
    print("URI 3: {s}\n", .{uri3.raw});
    print("\nJSON 1 == JSON 2: {}\n", .{std.mem.eql(u8, json1, json2)});
    print("JSON 1 == JSON 3: {}\n", .{std.mem.eql(u8, json1, json3)});
    print("(Note: query parameter order affects comparison)\n", .{});

    // =========================================================================
    // Example 6: Special Character Escaping in JSON
    // =========================================================================
    print("\n=== Example 6: JSON Escaping ===\n", .{});
    print("Special characters are properly escaped in JSON output.\n\n", .{});

    // Create a URI with special characters in the path
    var special_uri = uri.Uri{};
    special_uri.scheme = "https";
    special_uri.host = "example.com";
    special_uri.path = "/path/with\"quotes/and\\backslash";

    const special_json = try uri.toJson(allocator, special_uri);
    defer allocator.free(special_json);

    print("Path with special chars: {s}\n", .{special_uri.path});
    print("JSON output: {s}\n", .{special_json});

    // =========================================================================
    // Example 7: Minimal URIs
    // =========================================================================
    print("\n=== Example 7: Minimal URI JSON ===\n", .{});

    const minimal_uris = [_][]const u8{
        "",
        "/",
        "?query",
        "#fragment",
        "//host",
    };

    for (minimal_uris) |min_uri| {
        const parsed = try uri.parse(min_uri);
        const min_json = try uri.toJson(allocator, parsed);
        defer allocator.free(min_json);

        const display = if (min_uri.len == 0) "(empty)" else min_uri;
        print("  {s:<15} => {s}\n", .{ display, min_json });
    }

    // =========================================================================
    // Example 8: Using JSON for Test Assertions
    // =========================================================================
    print("\n=== Example 8: JSON for Testing ===\n", .{});
    print("Example test pattern using JSON output:\n\n", .{});

    print(
        \\```zig
        \\test "parse URI components" {{
        \\    const allocator = std.testing.allocator;
        \\    const parsed = try uri.parse("https://example.com:8080/path");
        \\    const json = try uri.toJson(allocator, parsed);
        \\    defer allocator.free(json);
        \\
        \\    try std.testing.expectEqualStrings(
        \\        "{{\"host\":\"example.com\",\"path\":\"/path\",\"port\":8080,\"scheme\":\"https\"}}",
        \\        json,
        \\    );
        \\}}
        \\```
        \\
    , .{});

    print("\n", .{});
}
