//! RFC 3986 Test Vectors
//!
//! This file contains test vectors from RFC 3986 and additional comprehensive
//! tests for URI parsing compliance.
//!
//! Reference: https://www.rfc-editor.org/rfc/rfc3986

const std = @import("std");
const uri = @import("uri");

// =============================================================================
// RFC 3986 Section 1.1.2 - Example URIs
// =============================================================================

test "RFC 3986 Section 1.1.2 - Example URIs" {
    // ftp://ftp.is.co.za/rfc/rfc1808.txt
    {
        const parsed = try uri.parse("ftp://ftp.is.co.za/rfc/rfc1808.txt");
        try std.testing.expectEqualStrings("ftp", parsed.scheme.?);
        try std.testing.expectEqualStrings("ftp.is.co.za", parsed.host.?);
        try std.testing.expectEqualStrings("/rfc/rfc1808.txt", parsed.path);
    }

    // http://www.ietf.org/rfc/rfc2396.txt
    {
        const parsed = try uri.parse("http://www.ietf.org/rfc/rfc2396.txt");
        try std.testing.expectEqualStrings("http", parsed.scheme.?);
        try std.testing.expectEqualStrings("www.ietf.org", parsed.host.?);
        try std.testing.expectEqualStrings("/rfc/rfc2396.txt", parsed.path);
    }

    // ldap://[2001:db8::7]/c=GB?objectClass?one
    {
        const parsed = try uri.parse("ldap://[2001:db8::7]/c=GB?objectClass?one");
        try std.testing.expectEqualStrings("ldap", parsed.scheme.?);
        try std.testing.expectEqualStrings("[2001:db8::7]", parsed.host.?);
        try std.testing.expectEqualStrings("/c=GB", parsed.path);
        try std.testing.expectEqualStrings("objectClass?one", parsed.query.?);
    }

    // mailto:John.Doe@example.com
    {
        const parsed = try uri.parse("mailto:John.Doe@example.com");
        try std.testing.expectEqualStrings("mailto", parsed.scheme.?);
        try std.testing.expectEqualStrings("John.Doe@example.com", parsed.path);
    }

    // news:comp.infosystems.www.servers.unix
    {
        const parsed = try uri.parse("news:comp.infosystems.www.servers.unix");
        try std.testing.expectEqualStrings("news", parsed.scheme.?);
        try std.testing.expectEqualStrings("comp.infosystems.www.servers.unix", parsed.path);
    }

    // tel:+1-816-555-1212
    {
        const parsed = try uri.parse("tel:+1-816-555-1212");
        try std.testing.expectEqualStrings("tel", parsed.scheme.?);
        try std.testing.expectEqualStrings("+1-816-555-1212", parsed.path);
    }

    // telnet://192.0.2.16:80/
    {
        const parsed = try uri.parse("telnet://192.0.2.16:80/");
        try std.testing.expectEqualStrings("telnet", parsed.scheme.?);
        try std.testing.expectEqualStrings("192.0.2.16", parsed.host.?);
        try std.testing.expectEqual(@as(u16, 80), parsed.port.?);
        try std.testing.expectEqualStrings("/", parsed.path);
    }

    // urn:oasis:names:specification:docbook:dtd:xml:4.1.2
    {
        const parsed = try uri.parse("urn:oasis:names:specification:docbook:dtd:xml:4.1.2");
        try std.testing.expectEqualStrings("urn", parsed.scheme.?);
        try std.testing.expectEqualStrings("oasis:names:specification:docbook:dtd:xml:4.1.2", parsed.path);
    }
}

// =============================================================================
// RFC 3986 Section 3 - Syntax Components
// =============================================================================

test "RFC 3986 Section 3 - URI with all components" {
    // foo://example.com:8042/over/there?name=ferret#nose
    const parsed = try uri.parse("foo://example.com:8042/over/there?name=ferret#nose");
    try std.testing.expectEqualStrings("foo", parsed.scheme.?);
    try std.testing.expectEqualStrings("example.com", parsed.host.?);
    try std.testing.expectEqual(@as(u16, 8042), parsed.port.?);
    try std.testing.expectEqualStrings("/over/there", parsed.path);
    try std.testing.expectEqualStrings("name=ferret", parsed.query.?);
    try std.testing.expectEqualStrings("nose", parsed.fragment.?);
}

test "RFC 3986 Section 3 - URN example" {
    // urn:example:animal:ferret:nose
    const parsed = try uri.parse("urn:example:animal:ferret:nose");
    try std.testing.expectEqualStrings("urn", parsed.scheme.?);
    try std.testing.expectEqualStrings("example:animal:ferret:nose", parsed.path);
}

// =============================================================================
// RFC 3986 Section 3.1 - Scheme
// =============================================================================

test "RFC 3986 Section 3.1 - Valid schemes" {
    // scheme = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )
    const valid_schemes = [_][]const u8{
        "http://example.com",
        "HTTP://example.com", // Schemes are case-insensitive
        "h123://example.com",
        "scheme+plus://example.com",
        "scheme-minus://example.com",
        "scheme.dot://example.com",
        "a://example.com", // Single letter
        "A1b2C3://example.com",
    };

    for (valid_schemes) |test_uri| {
        const parsed = try uri.parse(test_uri);
        try std.testing.expect(parsed.scheme != null);
    }
}

// =============================================================================
// RFC 3986 Section 3.2 - Authority
// =============================================================================

test "RFC 3986 Section 3.2 - Authority parsing" {
    // With userinfo
    {
        const parsed = try uri.parse("http://user@host.com/path");
        try std.testing.expectEqualStrings("user", parsed.userinfo.?);
        try std.testing.expectEqualStrings("host.com", parsed.host.?);
    }

    // With userinfo containing password
    {
        const parsed = try uri.parse("http://user:password@host.com/path");
        try std.testing.expectEqualStrings("user:password", parsed.userinfo.?);
        try std.testing.expectEqualStrings("host.com", parsed.host.?);
    }

    // Host only
    {
        const parsed = try uri.parse("http://host.com/path");
        try std.testing.expect(parsed.userinfo == null);
        try std.testing.expectEqualStrings("host.com", parsed.host.?);
    }

    // With port
    {
        const parsed = try uri.parse("http://host.com:8080/path");
        try std.testing.expectEqualStrings("host.com", parsed.host.?);
        try std.testing.expectEqual(@as(u16, 8080), parsed.port.?);
    }

    // Full authority
    {
        const parsed = try uri.parse("http://user:pass@host.com:8080/path");
        try std.testing.expectEqualStrings("user:pass", parsed.userinfo.?);
        try std.testing.expectEqualStrings("host.com", parsed.host.?);
        try std.testing.expectEqual(@as(u16, 8080), parsed.port.?);
    }
}

// =============================================================================
// RFC 3986 Section 3.2.2 - Host
// =============================================================================

test "RFC 3986 Section 3.2.2 - IPv4 hosts" {
    const ipv4_uris = [_][]const u8{
        "http://192.168.1.1/path",
        "http://10.0.0.1:8080/",
        "http://127.0.0.1/",
        "http://255.255.255.255/",
    };

    for (ipv4_uris) |test_uri| {
        const parsed = try uri.parse(test_uri);
        try std.testing.expect(parsed.host != null);
    }
}

test "RFC 3986 Section 3.2.2 - IPv6 hosts" {
    const ipv6_uris = [_]struct { input: []const u8, expected_host: []const u8 }{
        .{ .input = "http://[::1]/path", .expected_host = "[::1]" },
        .{ .input = "http://[2001:db8::1]/", .expected_host = "[2001:db8::1]" },
        .{ .input = "http://[::ffff:192.168.1.1]/", .expected_host = "[::ffff:192.168.1.1]" },
        .{ .input = "http://[fe80::1%25eth0]/", .expected_host = "[fe80::1%25eth0]" }, // Zone ID
        .{ .input = "http://[::1]:8080/path", .expected_host = "[::1]" },
    };

    for (ipv6_uris) |tc| {
        const parsed = try uri.parse(tc.input);
        try std.testing.expectEqualStrings(tc.expected_host, parsed.host.?);
    }
}

test "RFC 3986 Section 3.2.2 - Registered names" {
    const registered_names = [_][]const u8{
        "http://example.com/",
        "http://www.example.org/",
        "http://sub.domain.example.co.uk/",
        "http://localhost/",
        "http://myhost/",
    };

    for (registered_names) |test_uri| {
        const parsed = try uri.parse(test_uri);
        try std.testing.expect(parsed.host != null);
    }
}

// =============================================================================
// RFC 3986 Section 3.3 - Path
// =============================================================================

test "RFC 3986 Section 3.3 - Path variants" {
    // path-abempty (begins with "/" or is empty)
    {
        const parsed = try uri.parse("http://example.com");
        try std.testing.expectEqualStrings("", parsed.path);
    }
    {
        const parsed = try uri.parse("http://example.com/");
        try std.testing.expectEqualStrings("/", parsed.path);
    }
    {
        const parsed = try uri.parse("http://example.com/a/b/c");
        try std.testing.expectEqualStrings("/a/b/c", parsed.path);
    }

    // path-absolute (begins with "/" but not "//")
    {
        const parsed = try uri.parse("/path/to/resource");
        try std.testing.expectEqualStrings("/path/to/resource", parsed.path);
    }

    // path-rootless (begins with a segment)
    {
        const parsed = try uri.parse("mailto:user@example.com");
        try std.testing.expectEqualStrings("user@example.com", parsed.path);
    }

    // path-empty
    {
        const parsed = try uri.parse("http://example.com?query");
        try std.testing.expectEqualStrings("", parsed.path);
    }
}

// =============================================================================
// RFC 3986 Section 3.4 - Query
// =============================================================================

test "RFC 3986 Section 3.4 - Query component" {
    {
        const parsed = try uri.parse("http://example.com?query");
        try std.testing.expectEqualStrings("query", parsed.query.?);
    }
    {
        const parsed = try uri.parse("http://example.com?key=value");
        try std.testing.expectEqualStrings("key=value", parsed.query.?);
    }
    {
        const parsed = try uri.parse("http://example.com?key1=value1&key2=value2");
        try std.testing.expectEqualStrings("key1=value1&key2=value2", parsed.query.?);
    }
    {
        const parsed = try uri.parse("http://example.com?");
        try std.testing.expectEqualStrings("", parsed.query.?);
    }
}

// =============================================================================
// RFC 3986 Section 3.5 - Fragment
// =============================================================================

test "RFC 3986 Section 3.5 - Fragment component" {
    {
        const parsed = try uri.parse("http://example.com#fragment");
        try std.testing.expectEqualStrings("fragment", parsed.fragment.?);
    }
    {
        const parsed = try uri.parse("http://example.com/path#section1");
        try std.testing.expectEqualStrings("section1", parsed.fragment.?);
    }
    {
        const parsed = try uri.parse("http://example.com?query#frag");
        try std.testing.expectEqualStrings("frag", parsed.fragment.?);
    }
    {
        const parsed = try uri.parse("http://example.com#");
        try std.testing.expectEqualStrings("", parsed.fragment.?);
    }
}

// =============================================================================
// RFC 3986 Section 5.4 - Reference Resolution Examples
// =============================================================================

test "RFC 3986 Section 5.4.1 - Normal examples" {
    const allocator = std.testing.allocator;

    // Base URI: "http://a/b/c/d;p?q"
    const base = try uri.parse("http://a/b/c/d;p?q");

    const test_cases = [_]struct { reference: []const u8, expected_path: []const u8 }{
        // Normal examples
        .{ .reference = "g:h", .expected_path = "h" }, // Different scheme
        .{ .reference = "g", .expected_path = "/b/c/g" },
        .{ .reference = "./g", .expected_path = "/b/c/g" },
        .{ .reference = "g/", .expected_path = "/b/c/g/" },
        .{ .reference = "/g", .expected_path = "/g" },
        .{ .reference = "//g", .expected_path = "" }, // Authority change
        .{ .reference = "?y", .expected_path = "/b/c/d;p" },
        .{ .reference = "g?y", .expected_path = "/b/c/g" },
        .{ .reference = "#s", .expected_path = "/b/c/d;p" },
        .{ .reference = "g#s", .expected_path = "/b/c/g" },
        .{ .reference = "g?y#s", .expected_path = "/b/c/g" },
        .{ .reference = ";x", .expected_path = "/b/c/;x" },
        .{ .reference = "g;x", .expected_path = "/b/c/g;x" },
        .{ .reference = "g;x?y#s", .expected_path = "/b/c/g;x" },
        .{ .reference = "", .expected_path = "/b/c/d;p" },
        .{ .reference = ".", .expected_path = "/b/c/" },
        .{ .reference = "./", .expected_path = "/b/c/" },
        .{ .reference = "..", .expected_path = "/b/" },
        .{ .reference = "../", .expected_path = "/b/" },
        .{ .reference = "../g", .expected_path = "/b/g" },
        .{ .reference = "../..", .expected_path = "/" },
        .{ .reference = "../../", .expected_path = "/" },
        .{ .reference = "../../g", .expected_path = "/g" },
    };

    for (test_cases) |tc| {
        const ref = try uri.parse(tc.reference);
        const resolved = try uri.resolve(allocator, base, ref);
        defer allocator.free(resolved.path);
        try std.testing.expectEqualStrings(tc.expected_path, resolved.path);
    }
}

test "RFC 3986 Section 5.4.2 - Abnormal examples" {
    const allocator = std.testing.allocator;

    // Base URI: "http://a/b/c/d;p?q"
    const base = try uri.parse("http://a/b/c/d;p?q");

    const test_cases = [_]struct { reference: []const u8, expected_path: []const u8 }{
        // Abnormal examples - going above root
        .{ .reference = "../../../g", .expected_path = "/g" },
        .{ .reference = "../../../../g", .expected_path = "/g" },
        // Abnormal examples - removing dot segments
        .{ .reference = "/./g", .expected_path = "/g" },
        .{ .reference = "/../g", .expected_path = "/g" },
        .{ .reference = "g.", .expected_path = "/b/c/g." },
        .{ .reference = ".g", .expected_path = "/b/c/.g" },
        .{ .reference = "g..", .expected_path = "/b/c/g.." },
        .{ .reference = "..g", .expected_path = "/b/c/..g" },
    };

    for (test_cases) |tc| {
        const ref = try uri.parse(tc.reference);
        const resolved = try uri.resolve(allocator, base, ref);
        defer allocator.free(resolved.path);
        try std.testing.expectEqualStrings(tc.expected_path, resolved.path);
    }
}

// =============================================================================
// Additional Comprehensive Tests
// =============================================================================

test "Edge case - empty components" {
    // Empty query
    {
        const parsed = try uri.parse("http://example.com?");
        try std.testing.expectEqualStrings("", parsed.query.?);
    }
    // Empty fragment
    {
        const parsed = try uri.parse("http://example.com#");
        try std.testing.expectEqualStrings("", parsed.fragment.?);
    }
    // Empty path with query
    {
        const parsed = try uri.parse("http://example.com?query");
        try std.testing.expectEqualStrings("", parsed.path);
    }
}

test "Edge case - special characters in query and fragment" {
    // These characters are allowed in query/fragment without encoding
    {
        const parsed = try uri.parse("http://example.com?a=b&c=d");
        try std.testing.expectEqualStrings("a=b&c=d", parsed.query.?);
    }
    {
        const parsed = try uri.parse("http://example.com#section/subsection");
        try std.testing.expectEqualStrings("section/subsection", parsed.fragment.?);
    }
}

test "Edge case - multiple colons in path" {
    const parsed = try uri.parse("urn:isbn:0451450523");
    try std.testing.expectEqualStrings("urn", parsed.scheme.?);
    try std.testing.expectEqualStrings("isbn:0451450523", parsed.path);
}

test "Common web URIs" {
    // HTTPS with path and query
    {
        const parsed = try uri.parse("https://www.example.com/search?q=zig+language");
        try std.testing.expectEqualStrings("https", parsed.scheme.?);
        try std.testing.expectEqualStrings("www.example.com", parsed.host.?);
        try std.testing.expectEqualStrings("/search", parsed.path);
        try std.testing.expectEqualStrings("q=zig+language", parsed.query.?);
    }

    // File URI (host is empty string for file:///)
    {
        const parsed = try uri.parse("file:///home/user/document.txt");
        try std.testing.expectEqualStrings("file", parsed.scheme.?);
        // file:/// has empty authority, so host may be null or empty
        // depending on implementation
        try std.testing.expectEqualStrings("/home/user/document.txt", parsed.path);
    }

    // Data URI
    {
        const parsed = try uri.parse("data:text/plain;base64,SGVsbG8gV29ybGQh");
        try std.testing.expectEqualStrings("data", parsed.scheme.?);
        try std.testing.expectEqualStrings("text/plain;base64,SGVsbG8gV29ybGQh", parsed.path);
    }
}

test "Port boundary values" {
    // Minimum port
    {
        const parsed = try uri.parse("http://example.com:0/");
        try std.testing.expectEqual(@as(u16, 0), parsed.port.?);
    }
    // Maximum port
    {
        const parsed = try uri.parse("http://example.com:65535/");
        try std.testing.expectEqual(@as(u16, 65535), parsed.port.?);
    }
    // Common ports
    {
        const parsed = try uri.parse("http://example.com:80/");
        try std.testing.expectEqual(@as(u16, 80), parsed.port.?);
    }
    {
        const parsed = try uri.parse("https://example.com:443/");
        try std.testing.expectEqual(@as(u16, 443), parsed.port.?);
    }
}

test "Uri.format reconstructs URI correctly" {
    const test_uris = [_][]const u8{
        "http://example.com",
        "http://example.com/",
        "http://example.com/path",
        "http://example.com/path?query",
        "http://example.com/path?query#frag",
        "http://user@example.com/",
        "http://user:pass@example.com/",
        "http://example.com:8080/",
        "https://user:pass@example.com:8080/path/to/resource?key=value#section",
    };

    var buf: [512]u8 = undefined;
    for (test_uris) |test_uri| {
        const parsed = try uri.parse(test_uri);
        const formatted = try std.fmt.bufPrint(&buf, "{f}", .{parsed});
        try std.testing.expectEqualStrings(test_uri, formatted);
    }
}
