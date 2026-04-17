// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// Example: Percent-Encoding and Decoding (RFC 3986 Section 2.1)
//
// This example demonstrates percent-encoding and decoding of URI components.
// Different URI components have different allowed characters, so encoding
// is context-sensitive.
//
// Build and run:
//   zig build run-03_percent_encoding

const std = @import("std");
const uri = @import("uri");

const print = std.debug.print;

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // =========================================================================
    // Example 1: Basic encoding and decoding
    // =========================================================================
    print("\n=== Example 1: Basic Encoding/Decoding ===\n", .{});

    const original = "hello world!";
    const encoded = try uri.percentEncode(allocator, original, .path);
    defer allocator.free(encoded);

    print("Original: \"{s}\"\n", .{original});
    print("Encoded:  \"{s}\"\n", .{encoded});

    const decoded = try uri.percentDecode(allocator, encoded);
    defer allocator.free(decoded);
    print("Decoded:  \"{s}\"\n", .{decoded});

    // =========================================================================
    // Example 2: Component-specific encoding
    // =========================================================================
    print("\n=== Example 2: Component-Specific Encoding ===\n", .{});
    print("Different components allow different characters.\n\n", .{});

    const test_string = "user@host:8080/path?q=v#frag";

    // Encode for different components
    const components = [_]struct { comp: uri.Component, name: []const u8 }{
        .{ .comp = .path, .name = "path" },
        .{ .comp = .query, .name = "query" },
        .{ .comp = .fragment, .name = "fragment" },
        .{ .comp = .userinfo, .name = "userinfo" },
        .{ .comp = .host, .name = "host" },
    };

    print("Input: \"{s}\"\n\n", .{test_string});

    for (components) |c| {
        const result = try uri.percentEncode(allocator, test_string, c.comp);
        defer allocator.free(result);
        print("As {s:<10}: {s}\n", .{ c.name, result });
    }

    // =========================================================================
    // Example 3: Encoding special characters
    // =========================================================================
    print("\n=== Example 3: Special Characters ===\n", .{});

    const special_chars = [_]struct { char: []const u8, desc: []const u8 }{
        .{ .char = " ", .desc = "space" },
        .{ .char = "&", .desc = "ampersand" },
        .{ .char = "=", .desc = "equals" },
        .{ .char = "?", .desc = "question mark" },
        .{ .char = "#", .desc = "hash" },
        .{ .char = "/", .desc = "slash" },
        .{ .char = "@", .desc = "at sign" },
        .{ .char = ":", .desc = "colon" },
        .{ .char = "+", .desc = "plus" },
        .{ .char = "%", .desc = "percent" },
    };

    print("Character encoding in path component:\n", .{});
    for (special_chars) |sc| {
        const result = try uri.percentEncode(allocator, sc.char, .path);
        defer allocator.free(result);
        print("  '{s}' ({s:<14}) => \"{s}\"\n", .{ sc.char, sc.desc, result });
    }

    // =========================================================================
    // Example 4: Decoding percent-encoded strings
    // =========================================================================
    print("\n=== Example 4: Decoding Examples ===\n", .{});

    const encoded_strings = [_][]const u8{
        "hello%20world",
        "100%25%20complete",
        "caf%C3%A9", // UTF-8 encoded 'cafe' with accent
        "%2Fpath%2Fto%2Ffile",
        "key%3Dvalue%26foo%3Dbar",
    };

    for (encoded_strings) |enc| {
        const dec = try uri.percentDecode(allocator, enc);
        defer allocator.free(dec);
        print("  \"{s}\" => \"{s}\"\n", .{ enc, dec });
    }

    // =========================================================================
    // Example 5: Building a URL with encoded parameters
    // =========================================================================
    print("\n=== Example 5: Building URL with Encoded Parameters ===\n", .{});

    // Simulate building a search URL with user input
    const base_url = "https://example.com/search";
    const search_term = "zig programming & memory safety";
    const category = "languages/systems";

    const encoded_term = try uri.percentEncode(allocator, search_term, .query);
    defer allocator.free(encoded_term);

    const encoded_category = try uri.percentEncode(allocator, category, .query);
    defer allocator.free(encoded_category);

    print("Base URL: {s}\n", .{base_url});
    print("Search term: \"{s}\"\n", .{search_term});
    print("Category: \"{s}\"\n", .{category});
    print("Full URL: {s}?q={s}&cat={s}\n", .{ base_url, encoded_term, encoded_category });

    // =========================================================================
    // Example 6: Handling already-encoded strings
    // =========================================================================
    print("\n=== Example 6: Double-Encoding Prevention ===\n", .{});

    // When you encode an already-encoded string, the % gets encoded too
    const already_encoded = "hello%20world";
    const double_encoded = try uri.percentEncode(allocator, already_encoded, .path);
    defer allocator.free(double_encoded);

    print("Original (already encoded): \"{s}\"\n", .{already_encoded});
    print("Double-encoded (incorrect): \"{s}\"\n", .{double_encoded});
    print("Note: Be careful not to encode already-encoded strings!\n", .{});

    // =========================================================================
    // Example 7: Unreserved characters (RFC 3986)
    // =========================================================================
    print("\n=== Example 7: Unreserved Characters ===\n", .{});
    print("These characters never need encoding:\n", .{});
    print("ALPHA / DIGIT / \"-\" / \".\" / \"_\" / \"~\"\n\n", .{});

    const unreserved_test = "ABCxyz-._~0123456789";
    const unreserved_encoded = try uri.percentEncode(allocator, unreserved_test, .path);
    defer allocator.free(unreserved_encoded);

    print("Input:   \"{s}\"\n", .{unreserved_test});
    print("Encoded: \"{s}\"\n", .{unreserved_encoded});
    print("(Unreserved characters pass through unchanged)\n", .{});

    print("\n", .{});
}
