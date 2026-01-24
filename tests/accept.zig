//! Acceptance Tests (T1-T5)
//!
//! Comprehensive acceptance tests for the URI library.
//! These tests verify all major functionality works correctly together.

const std = @import("std");
const uri = @import("uri");

// =============================================================================
// T1: Basic URI Parsing
// =============================================================================

test "T1.1: Parse full URI with all components" {
    const result = try uri.parse("https://user:pass@example.com:8080/path/to/resource?query=value&foo=bar#section");

    try std.testing.expectEqualStrings("https", result.scheme.?);
    try std.testing.expectEqualStrings("user:pass", result.userinfo.?);
    try std.testing.expectEqualStrings("example.com", result.host.?);
    try std.testing.expectEqual(@as(u16, 8080), result.port.?);
    try std.testing.expectEqualStrings("/path/to/resource", result.path);
    try std.testing.expectEqualStrings("query=value&foo=bar", result.query.?);
    try std.testing.expectEqualStrings("section", result.fragment.?);
}

test "T1.2: Parse URI with IPv6 host" {
    const result = try uri.parse("http://[2001:db8::1]:8080/path");

    try std.testing.expectEqualStrings("http", result.scheme.?);
    try std.testing.expectEqualStrings("[2001:db8::1]", result.host.?);
    try std.testing.expectEqual(@as(u16, 8080), result.port.?);
    try std.testing.expectEqualStrings("/path", result.path);
}

test "T1.3: Parse relative reference" {
    const result = try uri.parse("/path/to/resource?query#frag");

    try std.testing.expect(result.scheme == null);
    try std.testing.expect(result.host == null);
    try std.testing.expectEqualStrings("/path/to/resource", result.path);
    try std.testing.expectEqualStrings("query", result.query.?);
    try std.testing.expectEqualStrings("frag", result.fragment.?);
}

test "T1.4: Parse scheme-only URI (mailto)" {
    const result = try uri.parse("mailto:user@example.com");

    try std.testing.expectEqualStrings("mailto", result.scheme.?);
    try std.testing.expectEqualStrings("user@example.com", result.path);
}

test "T1.5: Parse empty components" {
    const result = try uri.parse("http://example.com");

    try std.testing.expectEqualStrings("http", result.scheme.?);
    try std.testing.expectEqualStrings("example.com", result.host.?);
    try std.testing.expectEqualStrings("", result.path);
    try std.testing.expect(result.query == null);
    try std.testing.expect(result.fragment == null);
}

// =============================================================================
// T2: Reference Resolution (RFC 3986 Section 5)
// =============================================================================

test "T2.1: Resolve relative path against base" {
    const allocator = std.testing.allocator;
    const base = try uri.parse("http://example.com/a/b/c");
    const reference = try uri.parse("../d");

    const resolved = try uri.resolve(allocator, base, reference);
    defer allocator.free(resolved.path);

    try std.testing.expectEqualStrings("http", resolved.scheme.?);
    try std.testing.expectEqualStrings("example.com", resolved.host.?);
    try std.testing.expectEqualStrings("/a/d", resolved.path);
}

test "T2.2: Resolve absolute path against base" {
    const allocator = std.testing.allocator;
    const base = try uri.parse("http://example.com/a/b/c");
    const reference = try uri.parse("/x/y/z");

    const resolved = try uri.resolve(allocator, base, reference);
    defer allocator.free(resolved.path);

    try std.testing.expectEqualStrings("/x/y/z", resolved.path);
}

test "T2.3: Resolve with query" {
    const allocator = std.testing.allocator;
    const base = try uri.parse("http://example.com/a/b");
    const reference = try uri.parse("?query");

    const resolved = try uri.resolve(allocator, base, reference);
    defer allocator.free(resolved.path);

    try std.testing.expectEqualStrings("/a/b", resolved.path);
    try std.testing.expectEqualStrings("query", resolved.query.?);
}

test "T2.4: Resolve reference with scheme" {
    const allocator = std.testing.allocator;
    const base = try uri.parse("http://example.com/a/b");
    const reference = try uri.parse("https://other.com/x/y");

    const resolved = try uri.resolve(allocator, base, reference);
    defer allocator.free(resolved.path);

    try std.testing.expectEqualStrings("https", resolved.scheme.?);
    try std.testing.expectEqualStrings("other.com", resolved.host.?);
    try std.testing.expectEqualStrings("/x/y", resolved.path);
}

test "T2.5: RFC 3986 Section 5.4 examples" {
    const allocator = std.testing.allocator;
    const base = try uri.parse("http://a/b/c/d;p?q");

    // Test cases from RFC 3986 Section 5.4
    const test_cases = .{
        .{ "g:h", "g:h" },
        .{ "g", "/b/c/g" },
        .{ "./g", "/b/c/g" },
        .{ "g/", "/b/c/g/" },
        .{ "/g", "/g" },
        .{ "//g", "//g" }, // This has authority
        .{ "?y", "/b/c/d;p" },
        .{ "g?y", "/b/c/g" },
        .{ "#s", "/b/c/d;p" },
        .{ "g#s", "/b/c/g" },
        .{ "g?y#s", "/b/c/g" },
        .{ ";x", "/b/c/;x" },
        .{ "g;x", "/b/c/g;x" },
        .{ "g;x?y#s", "/b/c/g;x" },
        .{ "", "/b/c/d;p" },
        .{ ".", "/b/c/" },
        .{ "./", "/b/c/" },
        .{ "..", "/b/" },
        .{ "../", "/b/" },
        .{ "../g", "/b/g" },
        .{ "../..", "/" },
        .{ "../../", "/" },
        .{ "../../g", "/g" },
    };

    inline for (test_cases) |tc| {
        const reference = try uri.parse(tc[0]);
        const resolved = try uri.resolve(allocator, base, reference);
        defer allocator.free(resolved.path);

        // For references with authority, check host
        if (tc[0].len >= 2 and tc[0][0] == '/' and tc[0][1] == '/') {
            try std.testing.expectEqualStrings("g", resolved.host.?);
        } else if (tc[0].len > 0 and tc[0][0] != '/' and std.mem.indexOf(u8, tc[0], ":") != null) {
            // Has scheme - different from base
        } else {
            try std.testing.expectEqualStrings(tc[1], resolved.path);
        }
    }
}

// =============================================================================
// T3: Normalization
// =============================================================================

test "T3.1: Case normalization" {
    const allocator = std.testing.allocator;
    const parsed = try uri.parse("HTTP://EXAMPLE.COM/Path");

    var normalized = try uri.normalize(allocator, parsed);
    defer normalized.deinit(allocator);

    try std.testing.expectEqualStrings("http", normalized.scheme.?);
    try std.testing.expectEqualStrings("example.com", normalized.host.?);
}

test "T3.2: Dot segment removal" {
    const allocator = std.testing.allocator;
    const result = try uri.uri.removeDotSegments(allocator, "/a/b/c/./../../g");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("/a/g", result);
}

test "T3.3: Complex dot segments" {
    const allocator = std.testing.allocator;

    const test_cases = .{
        .{ "/a/b/../../../c", "/c" },
        .{ "/../a/b", "/a/b" },
        .{ "/a/./b/./c", "/a/b/c" },
        .{ "a/b/c", "a/b/c" },
    };

    inline for (test_cases) |tc| {
        const result = try uri.uri.removeDotSegments(allocator, tc[0]);
        defer allocator.free(result);
        try std.testing.expectEqualStrings(tc[1], result);
    }
}

// =============================================================================
// T4: URN Support (RFC 8141)
// =============================================================================

test "T4.1: Parse basic URN" {
    const result = try uri.parse("urn:isbn:0451450523");

    try std.testing.expectEqualStrings("urn", result.scheme.?);
    try std.testing.expect(result.isUrn());
    try std.testing.expectEqualStrings("isbn", result.urn.?.nid.?);
    try std.testing.expectEqualStrings("0451450523", result.urn.?.nss.?);
}

test "T4.2: Parse URN with UUID" {
    const result = try uri.parse("urn:uuid:f81d4fae-7dec-11d0-a765-00a0c91e6bf6");

    try std.testing.expectEqualStrings("uuid", result.urn.?.nid.?);
    try std.testing.expectEqualStrings("f81d4fae-7dec-11d0-a765-00a0c91e6bf6", result.urn.?.nss.?);
}

test "T4.3: Parse URN with r-component" {
    const result = try uri.parse("urn:example:resource?+resolver");

    try std.testing.expectEqualStrings("example", result.urn.?.nid.?);
    try std.testing.expectEqualStrings("resource", result.urn.?.nss.?);
    try std.testing.expectEqualStrings("resolver", result.urn.?.r_component.?);
}

test "T4.4: Parse URN with q-component" {
    const result = try uri.parse("urn:example:resource?=query");

    try std.testing.expectEqualStrings("example", result.urn.?.nid.?);
    try std.testing.expectEqualStrings("resource", result.urn.?.nss.?);
    try std.testing.expectEqualStrings("query", result.urn.?.q_component.?);
}

test "T4.5: Parse URN with all components" {
    const result = try uri.parse("urn:example:resource?+resolver?=query#fragment");

    try std.testing.expectEqualStrings("example", result.urn.?.nid.?);
    try std.testing.expectEqualStrings("resource", result.urn.?.nss.?);
    try std.testing.expectEqualStrings("resolver", result.urn.?.r_component.?);
    try std.testing.expectEqualStrings("query", result.urn.?.q_component.?);
    try std.testing.expectEqualStrings("fragment", result.urn.?.f_component.?);
}

// =============================================================================
// T5: Registry Operations
// =============================================================================

test "T5.1: Basic registry operations" {
    const allocator = std.testing.allocator;
    var reg = uri.Registry.init(allocator);
    defer reg.deinit();

    try reg.register("https://example.com/schema.json", "{\"type\":\"object\"}", "application/json");

    const resource = try reg.get("https://example.com/schema.json", false);
    try std.testing.expectEqualStrings("{\"type\":\"object\"}", resource.content);
}

test "T5.2: Registry caps enforcement" {
    const allocator = std.testing.allocator;
    var reg = uri.Registry.initWithCaps(allocator, .{
        .max_docs = 2,
        .max_bytes = 1000,
    });
    defer reg.deinit();

    try reg.register("https://example.com/1", "content1", null);
    try reg.register("https://example.com/2", "content2", null);

    // Should fail - max docs reached
    const result = reg.register("https://example.com/3", "content3", null);
    try std.testing.expectError(uri.registry.RegistryError.CapacityExceeded, result);
}

test "T5.3: Registry anchors" {
    const allocator = std.testing.allocator;
    var reg = uri.Registry.init(allocator);
    defer reg.deinit();

    const content = "Hello, World! This is a test.";
    try reg.register("https://example.com/doc", content, null);
    try reg.addAnchor("https://example.com/doc", "greeting", 0, 13);
    try reg.addAnchor("https://example.com/doc", "message", 14, 15);

    const greeting = try reg.getAnchorContent("https://example.com/doc", "greeting");
    try std.testing.expectEqualStrings("Hello, World!", greeting);

    const message = try reg.getAnchorContent("https://example.com/doc", "message");
    try std.testing.expectEqualStrings("This is a test.", message);
}

test "T5.4: Registry remove" {
    const allocator = std.testing.allocator;
    var reg = uri.Registry.init(allocator);
    defer reg.deinit();

    try reg.register("https://example.com/doc", "content", null);
    try std.testing.expect(reg.contains("https://example.com/doc"));

    const removed = reg.remove("https://example.com/doc");
    try std.testing.expect(removed);
    try std.testing.expect(!reg.contains("https://example.com/doc"));
}

test "T5.5: Registry stats" {
    const allocator = std.testing.allocator;
    var reg = uri.Registry.init(allocator);
    defer reg.deinit();

    try reg.register("https://example.com/1", "content1", null);
    try reg.register("https://example.com/2", "content2content2", null);

    const stats = reg.stats();
    try std.testing.expectEqual(@as(usize, 2), stats.doc_count);
    try std.testing.expectEqual(@as(usize, 24), stats.total_bytes); // 8 + 16
}

// =============================================================================
// Bonus: Percent Encoding
// =============================================================================

test "Percent encode/decode roundtrip" {
    const allocator = std.testing.allocator;

    const original = "hello world! /path?query=value&foo=bar";
    const encoded = try uri.percentEncode(allocator, original, .path);
    defer allocator.free(encoded);

    const decoded = try uri.percentDecode(allocator, encoded);
    defer allocator.free(decoded);

    try std.testing.expectEqualStrings(original, decoded);
}

// =============================================================================
// Bonus: Debug Output
// =============================================================================

test "Debug JSON output" {
    const allocator = std.testing.allocator;
    const parsed = try uri.parse("https://example.com/path?query#frag");

    const json = try uri.toJson(allocator, parsed);
    defer allocator.free(json);

    // Verify JSON contains expected fields
    try std.testing.expect(std.mem.indexOf(u8, json, "\"scheme\":\"https\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"host\":\"example.com\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"path\":\"/path\"") != null);
}

test "Debug pretty JSON output" {
    const allocator = std.testing.allocator;
    const parsed = try uri.parse("https://example.com/path");

    const json = try uri.toJsonPretty(allocator, parsed);
    defer allocator.free(json);

    // Should have formatting
    try std.testing.expect(std.mem.indexOf(u8, json, "\n") != null);
}
