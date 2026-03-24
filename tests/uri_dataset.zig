//! Extensive URI Dataset Tests
//!
//! A comprehensive collection of URIs covering all major schemes and edge cases.
//! This dataset tests the parser against real-world URIs from various domains.

const std = @import("std");
const uri = @import("uri");

// =============================================================================
// Test Case Structure
// =============================================================================

const TestCase = struct {
    input: []const u8,
    scheme: ?[]const u8 = null,
    userinfo: ?[]const u8 = null,
    host: ?[]const u8 = null,
    port: ?u16 = null,
    path: []const u8 = "",
    query: ?[]const u8 = null,
    fragment: ?[]const u8 = null,
    // For URNs
    nid: ?[]const u8 = null,
    nss: ?[]const u8 = null,
};

fn runTestCase(tc: TestCase) !void {
    const result = try uri.parse(tc.input);

    if (tc.scheme) |expected| {
        try std.testing.expectEqualStrings(expected, result.scheme.?);
    } else {
        try std.testing.expect(result.scheme == null);
    }

    if (tc.userinfo) |expected| {
        try std.testing.expectEqualStrings(expected, result.userinfo.?);
    } else {
        try std.testing.expect(result.userinfo == null);
    }

    if (tc.host) |expected| {
        try std.testing.expectEqualStrings(expected, result.host.?);
    } else {
        try std.testing.expect(result.host == null);
    }

    if (tc.port) |expected| {
        try std.testing.expectEqual(expected, result.port.?);
    } else {
        try std.testing.expect(result.port == null);
    }

    try std.testing.expectEqualStrings(tc.path, result.path);

    if (tc.query) |expected| {
        try std.testing.expectEqualStrings(expected, result.query.?);
    } else {
        try std.testing.expect(result.query == null);
    }

    if (tc.fragment) |expected| {
        try std.testing.expectEqualStrings(expected, result.fragment.?);
    } else {
        try std.testing.expect(result.fragment == null);
    }

    // URN-specific checks
    if (tc.nid) |expected_nid| {
        try std.testing.expect(result.urn != null);
        try std.testing.expectEqualStrings(expected_nid, result.urn.?.nid.?);
    }
    if (tc.nss) |expected_nss| {
        try std.testing.expect(result.urn != null);
        try std.testing.expectEqualStrings(expected_nss, result.urn.?.nss.?);
    }
}

// =============================================================================
// HTTP/HTTPS URLs
// =============================================================================

test "HTTP URLs - Basic" {
    const cases = [_]TestCase{
        .{ .input = "http://example.com", .scheme = "http", .host = "example.com", .path = "" },
        .{ .input = "http://example.com/", .scheme = "http", .host = "example.com", .path = "/" },
        .{ .input = "http://example.com/path", .scheme = "http", .host = "example.com", .path = "/path" },
        .{ .input = "http://example.com/path/", .scheme = "http", .host = "example.com", .path = "/path/" },
        .{ .input = "http://example.com:80", .scheme = "http", .host = "example.com", .port = 80, .path = "" },
        .{ .input = "http://example.com:8080", .scheme = "http", .host = "example.com", .port = 8080, .path = "" },
        .{ .input = "http://example.com:8080/", .scheme = "http", .host = "example.com", .port = 8080, .path = "/" },
        .{ .input = "http://www.example.com", .scheme = "http", .host = "www.example.com", .path = "" },
        .{ .input = "http://subdomain.example.com", .scheme = "http", .host = "subdomain.example.com", .path = "" },
        .{ .input = "http://deep.subdomain.example.com", .scheme = "http", .host = "deep.subdomain.example.com", .path = "" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "HTTPS URLs - Basic" {
    const cases = [_]TestCase{
        .{ .input = "https://example.com", .scheme = "https", .host = "example.com", .path = "" },
        .{ .input = "https://example.com/", .scheme = "https", .host = "example.com", .path = "/" },
        .{ .input = "https://example.com:443", .scheme = "https", .host = "example.com", .port = 443, .path = "" },
        .{ .input = "https://example.com:8443", .scheme = "https", .host = "example.com", .port = 8443, .path = "" },
        .{ .input = "https://secure.example.com", .scheme = "https", .host = "secure.example.com", .path = "" },
        .{ .input = "https://api.example.com/v1", .scheme = "https", .host = "api.example.com", .path = "/v1" },
        .{ .input = "https://api.example.com/v1/", .scheme = "https", .host = "api.example.com", .path = "/v1/" },
        .{ .input = "https://cdn.example.com/assets", .scheme = "https", .host = "cdn.example.com", .path = "/assets" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "HTTP URLs - With Authentication" {
    const cases = [_]TestCase{
        .{ .input = "http://user@example.com", .scheme = "http", .userinfo = "user", .host = "example.com", .path = "" },
        .{ .input = "http://user:pass@example.com", .scheme = "http", .userinfo = "user:pass", .host = "example.com", .path = "" },
        .{ .input = "http://user:pass@example.com:8080", .scheme = "http", .userinfo = "user:pass", .host = "example.com", .port = 8080, .path = "" },
        .{ .input = "http://user:pass@example.com/path", .scheme = "http", .userinfo = "user:pass", .host = "example.com", .path = "/path" },
        .{ .input = "http://admin:secret@localhost:3000", .scheme = "http", .userinfo = "admin:secret", .host = "localhost", .port = 3000, .path = "" },
        .{ .input = "https://api_key:@api.example.com", .scheme = "https", .userinfo = "api_key:", .host = "api.example.com", .path = "" },
        .{ .input = "http://user%40domain:pass%23word@example.com", .scheme = "http", .userinfo = "user%40domain:pass%23word", .host = "example.com", .path = "" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "HTTP URLs - With Query Strings" {
    const cases = [_]TestCase{
        .{ .input = "http://example.com?query", .scheme = "http", .host = "example.com", .path = "", .query = "query" },
        .{ .input = "http://example.com/?query", .scheme = "http", .host = "example.com", .path = "/", .query = "query" },
        .{ .input = "http://example.com?key=value", .scheme = "http", .host = "example.com", .path = "", .query = "key=value" },
        .{ .input = "http://example.com?key=value&foo=bar", .scheme = "http", .host = "example.com", .path = "", .query = "key=value&foo=bar" },
        .{ .input = "http://example.com/path?key=value", .scheme = "http", .host = "example.com", .path = "/path", .query = "key=value" },
        .{ .input = "http://example.com/search?q=hello+world", .scheme = "http", .host = "example.com", .path = "/search", .query = "q=hello+world" },
        .{ .input = "http://example.com/search?q=hello%20world", .scheme = "http", .host = "example.com", .path = "/search", .query = "q=hello%20world" },
        .{ .input = "http://example.com?a=1&b=2&c=3&d=4&e=5", .scheme = "http", .host = "example.com", .path = "", .query = "a=1&b=2&c=3&d=4&e=5" },
        .{ .input = "http://example.com?array[]=1&array[]=2", .scheme = "http", .host = "example.com", .path = "", .query = "array[]=1&array[]=2" },
        .{ .input = "http://example.com?filter[name]=john&filter[age]=30", .scheme = "http", .host = "example.com", .path = "", .query = "filter[name]=john&filter[age]=30" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "HTTP URLs - With Fragments" {
    const cases = [_]TestCase{
        .{ .input = "http://example.com#section", .scheme = "http", .host = "example.com", .path = "", .fragment = "section" },
        .{ .input = "http://example.com/#section", .scheme = "http", .host = "example.com", .path = "/", .fragment = "section" },
        .{ .input = "http://example.com/page#top", .scheme = "http", .host = "example.com", .path = "/page", .fragment = "top" },
        .{ .input = "http://example.com/page#section-1", .scheme = "http", .host = "example.com", .path = "/page", .fragment = "section-1" },
        .{ .input = "http://example.com/page#section_2", .scheme = "http", .host = "example.com", .path = "/page", .fragment = "section_2" },
        .{ .input = "http://example.com?query#fragment", .scheme = "http", .host = "example.com", .path = "", .query = "query", .fragment = "fragment" },
        .{ .input = "http://example.com/path?key=value#section", .scheme = "http", .host = "example.com", .path = "/path", .query = "key=value", .fragment = "section" },
        .{ .input = "http://example.com#", .scheme = "http", .host = "example.com", .path = "", .fragment = "" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "HTTP URLs - Complex Paths" {
    const cases = [_]TestCase{
        .{ .input = "http://example.com/a/b/c/d/e", .scheme = "http", .host = "example.com", .path = "/a/b/c/d/e" },
        .{ .input = "http://example.com/path/to/resource.html", .scheme = "http", .host = "example.com", .path = "/path/to/resource.html" },
        .{ .input = "http://example.com/path/to/resource.json", .scheme = "http", .host = "example.com", .path = "/path/to/resource.json" },
        .{ .input = "http://example.com/api/v1/users/123", .scheme = "http", .host = "example.com", .path = "/api/v1/users/123" },
        .{ .input = "http://example.com/api/v2/users/456/posts/789", .scheme = "http", .host = "example.com", .path = "/api/v2/users/456/posts/789" },
        .{ .input = "http://example.com/~user/file.txt", .scheme = "http", .host = "example.com", .path = "/~user/file.txt" },
        .{ .input = "http://example.com/path%20with%20spaces", .scheme = "http", .host = "example.com", .path = "/path%20with%20spaces" },
        .{ .input = "http://example.com/path/with/trailing/slash/", .scheme = "http", .host = "example.com", .path = "/path/with/trailing/slash/" },
        .{ .input = "http://example.com/CamelCase/Path", .scheme = "http", .host = "example.com", .path = "/CamelCase/Path" },
        .{ .input = "http://example.com/kebab-case/path", .scheme = "http", .host = "example.com", .path = "/kebab-case/path" },
        .{ .input = "http://example.com/snake_case/path", .scheme = "http", .host = "example.com", .path = "/snake_case/path" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "HTTP URLs - Real World Examples" {
    const cases = [_]TestCase{
        // GitHub
        .{ .input = "https://github.com/ziglang/zig", .scheme = "https", .host = "github.com", .path = "/ziglang/zig" },
        .{ .input = "https://github.com/ziglang/zig/issues/1234", .scheme = "https", .host = "github.com", .path = "/ziglang/zig/issues/1234" },
        .{ .input = "https://raw.githubusercontent.com/user/repo/main/file.txt", .scheme = "https", .host = "raw.githubusercontent.com", .path = "/user/repo/main/file.txt" },
        .{ .input = "https://api.github.com/repos/owner/repo/commits?per_page=100", .scheme = "https", .host = "api.github.com", .path = "/repos/owner/repo/commits", .query = "per_page=100" },

        // Google
        .{ .input = "https://www.google.com/search?q=zig+programming", .scheme = "https", .host = "www.google.com", .path = "/search", .query = "q=zig+programming" },
        .{ .input = "https://maps.google.com/maps?q=New+York", .scheme = "https", .host = "maps.google.com", .path = "/maps", .query = "q=New+York" },
        .{ .input = "https://drive.google.com/file/d/abc123/view", .scheme = "https", .host = "drive.google.com", .path = "/file/d/abc123/view" },

        // AWS
        .{ .input = "https://s3.amazonaws.com/bucket/key", .scheme = "https", .host = "s3.amazonaws.com", .path = "/bucket/key" },
        .{ .input = "https://bucket.s3.us-west-2.amazonaws.com/key", .scheme = "https", .host = "bucket.s3.us-west-2.amazonaws.com", .path = "/key" },
        .{ .input = "https://sqs.us-east-1.amazonaws.com/123456789/queue-name", .scheme = "https", .host = "sqs.us-east-1.amazonaws.com", .path = "/123456789/queue-name" },

        // CDNs
        .{ .input = "https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.0/jquery.min.js", .scheme = "https", .host = "cdnjs.cloudflare.com", .path = "/ajax/libs/jquery/3.6.0/jquery.min.js" },
        .{ .input = "https://unpkg.com/react@18/umd/react.production.min.js", .scheme = "https", .host = "unpkg.com", .path = "/react@18/umd/react.production.min.js" },

        // APIs
        .{ .input = "https://api.stripe.com/v1/charges", .scheme = "https", .host = "api.stripe.com", .path = "/v1/charges" },
        .{ .input = "https://api.twilio.com/2010-04-01/Accounts/AC123/Messages.json", .scheme = "https", .host = "api.twilio.com", .path = "/2010-04-01/Accounts/AC123/Messages.json" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// IPv4 Addresses
// =============================================================================

test "IPv4 URLs" {
    const cases = [_]TestCase{
        .{ .input = "http://127.0.0.1", .scheme = "http", .host = "127.0.0.1", .path = "" },
        .{ .input = "http://127.0.0.1/", .scheme = "http", .host = "127.0.0.1", .path = "/" },
        .{ .input = "http://127.0.0.1:8080", .scheme = "http", .host = "127.0.0.1", .port = 8080, .path = "" },
        .{ .input = "http://127.0.0.1:8080/path", .scheme = "http", .host = "127.0.0.1", .port = 8080, .path = "/path" },
        .{ .input = "http://192.168.1.1", .scheme = "http", .host = "192.168.1.1", .path = "" },
        .{ .input = "http://192.168.1.1:3000", .scheme = "http", .host = "192.168.1.1", .port = 3000, .path = "" },
        .{ .input = "http://10.0.0.1", .scheme = "http", .host = "10.0.0.1", .path = "" },
        .{ .input = "http://172.16.0.1", .scheme = "http", .host = "172.16.0.1", .path = "" },
        .{ .input = "http://0.0.0.0:8080", .scheme = "http", .host = "0.0.0.0", .port = 8080, .path = "" },
        .{ .input = "http://255.255.255.255", .scheme = "http", .host = "255.255.255.255", .path = "" },
        .{ .input = "http://1.2.3.4:5678/path?query#frag", .scheme = "http", .host = "1.2.3.4", .port = 5678, .path = "/path", .query = "query", .fragment = "frag" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// IPv6 Addresses
// =============================================================================

test "IPv6 URLs" {
    const cases = [_]TestCase{
        .{ .input = "http://[::1]", .scheme = "http", .host = "[::1]", .path = "" },
        .{ .input = "http://[::1]/", .scheme = "http", .host = "[::1]", .path = "/" },
        .{ .input = "http://[::1]:8080", .scheme = "http", .host = "[::1]", .port = 8080, .path = "" },
        .{ .input = "http://[::1]:8080/path", .scheme = "http", .host = "[::1]", .port = 8080, .path = "/path" },
        .{ .input = "http://[::ffff:127.0.0.1]", .scheme = "http", .host = "[::ffff:127.0.0.1]", .path = "" },
        .{ .input = "http://[2001:db8::1]", .scheme = "http", .host = "[2001:db8::1]", .path = "" },
        .{ .input = "http://[2001:db8::1]:8080", .scheme = "http", .host = "[2001:db8::1]", .port = 8080, .path = "" },
        .{ .input = "http://[2001:db8:85a3::8a2e:370:7334]", .scheme = "http", .host = "[2001:db8:85a3::8a2e:370:7334]", .path = "" },
        .{ .input = "http://[fe80::1%25eth0]", .scheme = "http", .host = "[fe80::1%25eth0]", .path = "" },
        .{ .input = "http://[::]:8080", .scheme = "http", .host = "[::]", .port = 8080, .path = "" },
        .{ .input = "http://[0:0:0:0:0:0:0:1]", .scheme = "http", .host = "[0:0:0:0:0:0:0:1]", .path = "" },
        .{ .input = "https://[2607:f8b0:4004:800::200e]", .scheme = "https", .host = "[2607:f8b0:4004:800::200e]", .path = "" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// Localhost and Special Hosts
// =============================================================================

test "Localhost URLs" {
    const cases = [_]TestCase{
        .{ .input = "http://localhost", .scheme = "http", .host = "localhost", .path = "" },
        .{ .input = "http://localhost/", .scheme = "http", .host = "localhost", .path = "/" },
        .{ .input = "http://localhost:3000", .scheme = "http", .host = "localhost", .port = 3000, .path = "" },
        .{ .input = "http://localhost:8080/api", .scheme = "http", .host = "localhost", .port = 8080, .path = "/api" },
        .{ .input = "http://LOCALHOST", .scheme = "http", .host = "LOCALHOST", .path = "" },
        .{ .input = "http://LocalHost:8080", .scheme = "http", .host = "LocalHost", .port = 8080, .path = "" },
        .{ .input = "http://localhost.localdomain", .scheme = "http", .host = "localhost.localdomain", .path = "" },
        .{ .input = "http://local", .scheme = "http", .host = "local", .path = "" },
        .{ .input = "http://host.local", .scheme = "http", .host = "host.local", .path = "" },
        .{ .input = "http://myapp.localhost:3000", .scheme = "http", .host = "myapp.localhost", .port = 3000, .path = "" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// File URLs
// =============================================================================

test "File URLs - Unix Paths" {
    const cases = [_]TestCase{
        .{ .input = "file:///", .scheme = "file", .path = "/" },
        .{ .input = "file:///home", .scheme = "file", .path = "/home" },
        .{ .input = "file:///home/user", .scheme = "file", .path = "/home/user" },
        .{ .input = "file:///home/user/file.txt", .scheme = "file", .path = "/home/user/file.txt" },
        .{ .input = "file:///home/user/Documents/report.pdf", .scheme = "file", .path = "/home/user/Documents/report.pdf" },
        .{ .input = "file:///tmp/test", .scheme = "file", .path = "/tmp/test" },
        .{ .input = "file:///var/log/syslog", .scheme = "file", .path = "/var/log/syslog" },
        .{ .input = "file:///etc/passwd", .scheme = "file", .path = "/etc/passwd" },
        .{ .input = "file:///usr/local/bin/program", .scheme = "file", .path = "/usr/local/bin/program" },
        .{ .input = "file:///opt/app/config.json", .scheme = "file", .path = "/opt/app/config.json" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "File URLs - Windows Paths" {
    const cases = [_]TestCase{
        .{ .input = "file:///C:", .scheme = "file", .path = "/C:" },
        .{ .input = "file:///C:/", .scheme = "file", .path = "/C:/" },
        .{ .input = "file:///C:/Users", .scheme = "file", .path = "/C:/Users" },
        .{ .input = "file:///C:/Users/John", .scheme = "file", .path = "/C:/Users/John" },
        .{ .input = "file:///C:/Users/John/Documents/file.txt", .scheme = "file", .path = "/C:/Users/John/Documents/file.txt" },
        .{ .input = "file:///D:/Projects/src/main.zig", .scheme = "file", .path = "/D:/Projects/src/main.zig" },
        .{ .input = "file:///C:/Program%20Files/App/app.exe", .scheme = "file", .path = "/C:/Program%20Files/App/app.exe" },
        .{ .input = "file:///C:/Windows/System32/cmd.exe", .scheme = "file", .path = "/C:/Windows/System32/cmd.exe" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "File URLs - Network Paths (UNC)" {
    const cases = [_]TestCase{
        .{ .input = "file://server/share", .scheme = "file", .host = "server", .path = "/share" },
        .{ .input = "file://server/share/", .scheme = "file", .host = "server", .path = "/share/" },
        .{ .input = "file://server/share/path/to/file.txt", .scheme = "file", .host = "server", .path = "/share/path/to/file.txt" },
        .{ .input = "file://fileserver/data/reports/2024/q1.xlsx", .scheme = "file", .host = "fileserver", .path = "/data/reports/2024/q1.xlsx" },
        .{ .input = "file://nas/backup/daily", .scheme = "file", .host = "nas", .path = "/backup/daily" },
        .{ .input = "file://192.168.1.100/shared", .scheme = "file", .host = "192.168.1.100", .path = "/shared" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// Database URIs
// =============================================================================

test "PostgreSQL URIs" {
    const cases = [_]TestCase{
        .{ .input = "postgresql://localhost", .scheme = "postgresql", .host = "localhost", .path = "" },
        .{ .input = "postgresql://localhost/mydb", .scheme = "postgresql", .host = "localhost", .path = "/mydb" },
        .{ .input = "postgresql://localhost:5432/mydb", .scheme = "postgresql", .host = "localhost", .port = 5432, .path = "/mydb" },
        .{ .input = "postgresql://user@localhost/mydb", .scheme = "postgresql", .userinfo = "user", .host = "localhost", .path = "/mydb" },
        .{ .input = "postgresql://user:password@localhost/mydb", .scheme = "postgresql", .userinfo = "user:password", .host = "localhost", .path = "/mydb" },
        .{ .input = "postgresql://user:password@localhost:5432/mydb", .scheme = "postgresql", .userinfo = "user:password", .host = "localhost", .port = 5432, .path = "/mydb" },
        .{ .input = "postgres://user:pass@host/db", .scheme = "postgres", .userinfo = "user:pass", .host = "host", .path = "/db" },
        .{ .input = "postgresql://user:pass@host:5432/db?sslmode=require", .scheme = "postgresql", .userinfo = "user:pass", .host = "host", .port = 5432, .path = "/db", .query = "sslmode=require" },
        .{ .input = "postgresql://user:pass@host/db?connect_timeout=10&application_name=myapp", .scheme = "postgresql", .userinfo = "user:pass", .host = "host", .path = "/db", .query = "connect_timeout=10&application_name=myapp" },
        .{ .input = "postgresql://admin:secret%40123@db.example.com:5432/production", .scheme = "postgresql", .userinfo = "admin:secret%40123", .host = "db.example.com", .port = 5432, .path = "/production" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "MySQL URIs" {
    const cases = [_]TestCase{
        .{ .input = "mysql://localhost", .scheme = "mysql", .host = "localhost", .path = "" },
        .{ .input = "mysql://localhost/mydb", .scheme = "mysql", .host = "localhost", .path = "/mydb" },
        .{ .input = "mysql://localhost:3306/mydb", .scheme = "mysql", .host = "localhost", .port = 3306, .path = "/mydb" },
        .{ .input = "mysql://root@localhost/mydb", .scheme = "mysql", .userinfo = "root", .host = "localhost", .path = "/mydb" },
        .{ .input = "mysql://root:password@localhost/mydb", .scheme = "mysql", .userinfo = "root:password", .host = "localhost", .path = "/mydb" },
        .{ .input = "mysql://root:password@localhost:3306/mydb", .scheme = "mysql", .userinfo = "root:password", .host = "localhost", .port = 3306, .path = "/mydb" },
        .{ .input = "mysql://user:pass@db.example.com/app?charset=utf8mb4", .scheme = "mysql", .userinfo = "user:pass", .host = "db.example.com", .path = "/app", .query = "charset=utf8mb4" },
        .{ .input = "mariadb://user:pass@localhost:3306/db", .scheme = "mariadb", .userinfo = "user:pass", .host = "localhost", .port = 3306, .path = "/db" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "MongoDB URIs" {
    const cases = [_]TestCase{
        .{ .input = "mongodb://localhost", .scheme = "mongodb", .host = "localhost", .path = "" },
        .{ .input = "mongodb://localhost/mydb", .scheme = "mongodb", .host = "localhost", .path = "/mydb" },
        .{ .input = "mongodb://localhost:27017", .scheme = "mongodb", .host = "localhost", .port = 27017, .path = "" },
        .{ .input = "mongodb://localhost:27017/mydb", .scheme = "mongodb", .host = "localhost", .port = 27017, .path = "/mydb" },
        .{ .input = "mongodb://user:pass@localhost/mydb", .scheme = "mongodb", .userinfo = "user:pass", .host = "localhost", .path = "/mydb" },
        .{ .input = "mongodb://user:pass@localhost:27017/mydb", .scheme = "mongodb", .userinfo = "user:pass", .host = "localhost", .port = 27017, .path = "/mydb" },
        .{ .input = "mongodb+srv://user:pass@cluster.mongodb.net/mydb", .scheme = "mongodb+srv", .userinfo = "user:pass", .host = "cluster.mongodb.net", .path = "/mydb" },
        .{ .input = "mongodb://user:pass@host/db?authSource=admin", .scheme = "mongodb", .userinfo = "user:pass", .host = "host", .path = "/db", .query = "authSource=admin" },
        .{ .input = "mongodb://user:pass@host/db?retryWrites=true&w=majority", .scheme = "mongodb", .userinfo = "user:pass", .host = "host", .path = "/db", .query = "retryWrites=true&w=majority" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "Redis URIs" {
    const cases = [_]TestCase{
        .{ .input = "redis://localhost", .scheme = "redis", .host = "localhost", .path = "" },
        .{ .input = "redis://localhost:6379", .scheme = "redis", .host = "localhost", .port = 6379, .path = "" },
        .{ .input = "redis://localhost/0", .scheme = "redis", .host = "localhost", .path = "/0" },
        .{ .input = "redis://localhost:6379/0", .scheme = "redis", .host = "localhost", .port = 6379, .path = "/0" },
        .{ .input = "redis://:password@localhost", .scheme = "redis", .userinfo = ":password", .host = "localhost", .path = "" },
        .{ .input = "redis://:password@localhost:6379/0", .scheme = "redis", .userinfo = ":password", .host = "localhost", .port = 6379, .path = "/0" },
        .{ .input = "redis://user:pass@localhost:6379/0", .scheme = "redis", .userinfo = "user:pass", .host = "localhost", .port = 6379, .path = "/0" },
        .{ .input = "rediss://localhost:6379", .scheme = "rediss", .host = "localhost", .port = 6379, .path = "" },
        .{ .input = "redis://localhost:6379/1?timeout=5", .scheme = "redis", .host = "localhost", .port = 6379, .path = "/1", .query = "timeout=5" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "SQLite URIs" {
    const cases = [_]TestCase{
        .{ .input = "sqlite:///path/to/database.db", .scheme = "sqlite", .path = "/path/to/database.db" },
        .{ .input = "sqlite:///home/user/data.sqlite", .scheme = "sqlite", .path = "/home/user/data.sqlite" },
        .{ .input = "sqlite:///:memory:", .scheme = "sqlite", .path = "/:memory:" },
        .{ .input = "sqlite:///C:/Users/data/app.db", .scheme = "sqlite", .path = "/C:/Users/data/app.db" },
        .{ .input = "sqlite:///tmp/test.db?mode=rwc", .scheme = "sqlite", .path = "/tmp/test.db", .query = "mode=rwc" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "Other Database URIs" {
    const cases = [_]TestCase{
        // Microsoft SQL Server
        .{ .input = "mssql://user:pass@localhost/mydb", .scheme = "mssql", .userinfo = "user:pass", .host = "localhost", .path = "/mydb" },
        .{ .input = "sqlserver://user:pass@localhost:1433/mydb", .scheme = "sqlserver", .userinfo = "user:pass", .host = "localhost", .port = 1433, .path = "/mydb" },

        // Oracle
        .{ .input = "oracle://user:pass@localhost:1521/ORCL", .scheme = "oracle", .userinfo = "user:pass", .host = "localhost", .port = 1521, .path = "/ORCL" },

        // CockroachDB
        .{ .input = "cockroachdb://user:pass@localhost:26257/mydb", .scheme = "cockroachdb", .userinfo = "user:pass", .host = "localhost", .port = 26257, .path = "/mydb" },

        // Cassandra
        .{ .input = "cassandra://localhost:9042/keyspace", .scheme = "cassandra", .host = "localhost", .port = 9042, .path = "/keyspace" },

        // ClickHouse
        .{ .input = "clickhouse://default:@localhost:8123/default", .scheme = "clickhouse", .userinfo = "default:", .host = "localhost", .port = 8123, .path = "/default" },

        // InfluxDB
        .{ .input = "influxdb://localhost:8086/mydb", .scheme = "influxdb", .host = "localhost", .port = 8086, .path = "/mydb" },

        // Elasticsearch
        .{ .input = "elasticsearch://localhost:9200", .scheme = "elasticsearch", .host = "localhost", .port = 9200, .path = "" },

        // Neo4j
        .{ .input = "neo4j://localhost:7687", .scheme = "neo4j", .host = "localhost", .port = 7687, .path = "" },
        .{ .input = "bolt://localhost:7687", .scheme = "bolt", .host = "localhost", .port = 7687, .path = "" },

        // Memcached
        .{ .input = "memcached://localhost:11211", .scheme = "memcached", .host = "localhost", .port = 11211, .path = "" },

        // RabbitMQ
        .{ .input = "amqp://guest:guest@localhost:5672/vhost", .scheme = "amqp", .userinfo = "guest:guest", .host = "localhost", .port = 5672, .path = "/vhost" },
        .{ .input = "amqps://user:pass@mq.example.com:5671/", .scheme = "amqps", .userinfo = "user:pass", .host = "mq.example.com", .port = 5671, .path = "/" },

        // Kafka
        .{ .input = "kafka://localhost:9092", .scheme = "kafka", .host = "localhost", .port = 9092, .path = "" },

        // etcd
        .{ .input = "etcd://localhost:2379", .scheme = "etcd", .host = "localhost", .port = 2379, .path = "" },

        // Consul
        .{ .input = "consul://localhost:8500", .scheme = "consul", .host = "localhost", .port = 8500, .path = "" },

        // ZooKeeper
        .{ .input = "zookeeper://localhost:2181/path", .scheme = "zookeeper", .host = "localhost", .port = 2181, .path = "/path" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// FTP/SFTP/SSH URLs
// =============================================================================

test "FTP URLs" {
    const cases = [_]TestCase{
        .{ .input = "ftp://ftp.example.com", .scheme = "ftp", .host = "ftp.example.com", .path = "" },
        .{ .input = "ftp://ftp.example.com/", .scheme = "ftp", .host = "ftp.example.com", .path = "/" },
        .{ .input = "ftp://ftp.example.com/pub", .scheme = "ftp", .host = "ftp.example.com", .path = "/pub" },
        .{ .input = "ftp://ftp.example.com/pub/file.tar.gz", .scheme = "ftp", .host = "ftp.example.com", .path = "/pub/file.tar.gz" },
        .{ .input = "ftp://anonymous@ftp.example.com", .scheme = "ftp", .userinfo = "anonymous", .host = "ftp.example.com", .path = "" },
        .{ .input = "ftp://anonymous:email@ftp.example.com", .scheme = "ftp", .userinfo = "anonymous:email", .host = "ftp.example.com", .path = "" },
        .{ .input = "ftp://user:pass@ftp.example.com:21/path", .scheme = "ftp", .userinfo = "user:pass", .host = "ftp.example.com", .port = 21, .path = "/path" },
        .{ .input = "ftps://secure.example.com/data", .scheme = "ftps", .host = "secure.example.com", .path = "/data" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "SFTP URLs" {
    const cases = [_]TestCase{
        .{ .input = "sftp://example.com", .scheme = "sftp", .host = "example.com", .path = "" },
        .{ .input = "sftp://example.com/path", .scheme = "sftp", .host = "example.com", .path = "/path" },
        .{ .input = "sftp://user@example.com/path", .scheme = "sftp", .userinfo = "user", .host = "example.com", .path = "/path" },
        .{ .input = "sftp://user:pass@example.com:22/home/user/file", .scheme = "sftp", .userinfo = "user:pass", .host = "example.com", .port = 22, .path = "/home/user/file" },
        .{ .input = "sftp://deploy@server.example.com/var/www/html", .scheme = "sftp", .userinfo = "deploy", .host = "server.example.com", .path = "/var/www/html" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "SSH URLs" {
    const cases = [_]TestCase{
        .{ .input = "ssh://example.com", .scheme = "ssh", .host = "example.com", .path = "" },
        .{ .input = "ssh://user@example.com", .scheme = "ssh", .userinfo = "user", .host = "example.com", .path = "" },
        .{ .input = "ssh://user@example.com:22", .scheme = "ssh", .userinfo = "user", .host = "example.com", .port = 22, .path = "" },
        .{ .input = "ssh://git@github.com/user/repo.git", .scheme = "ssh", .userinfo = "git", .host = "github.com", .path = "/user/repo.git" },
        .{ .input = "ssh://root@192.168.1.1:2222", .scheme = "ssh", .userinfo = "root", .host = "192.168.1.1", .port = 2222, .path = "" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// Git URLs
// =============================================================================

test "Git URLs" {
    const cases = [_]TestCase{
        .{ .input = "git://github.com/user/repo.git", .scheme = "git", .host = "github.com", .path = "/user/repo.git" },
        .{ .input = "git://git.example.com/project.git", .scheme = "git", .host = "git.example.com", .path = "/project.git" },
        .{ .input = "git+https://github.com/user/repo.git", .scheme = "git+https", .host = "github.com", .path = "/user/repo.git" },
        .{ .input = "git+ssh://git@github.com/user/repo.git", .scheme = "git+ssh", .userinfo = "git", .host = "github.com", .path = "/user/repo.git" },
        .{ .input = "https://github.com/user/repo.git", .scheme = "https", .host = "github.com", .path = "/user/repo.git" },
        .{ .input = "https://gitlab.com/group/project.git", .scheme = "https", .host = "gitlab.com", .path = "/group/project.git" },
        .{ .input = "https://bitbucket.org/user/repo.git", .scheme = "https", .host = "bitbucket.org", .path = "/user/repo.git" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// WebSocket URLs
// =============================================================================

test "WebSocket URLs" {
    const cases = [_]TestCase{
        .{ .input = "ws://example.com", .scheme = "ws", .host = "example.com", .path = "" },
        .{ .input = "ws://example.com/", .scheme = "ws", .host = "example.com", .path = "/" },
        .{ .input = "ws://example.com/socket", .scheme = "ws", .host = "example.com", .path = "/socket" },
        .{ .input = "ws://example.com:8080/socket", .scheme = "ws", .host = "example.com", .port = 8080, .path = "/socket" },
        .{ .input = "wss://example.com/socket", .scheme = "wss", .host = "example.com", .path = "/socket" },
        .{ .input = "wss://example.com:443/socket", .scheme = "wss", .host = "example.com", .port = 443, .path = "/socket" },
        .{ .input = "ws://localhost:3000/ws", .scheme = "ws", .host = "localhost", .port = 3000, .path = "/ws" },
        .{ .input = "wss://api.example.com/v1/stream", .scheme = "wss", .host = "api.example.com", .path = "/v1/stream" },
        .{ .input = "ws://example.com/socket?token=abc123", .scheme = "ws", .host = "example.com", .path = "/socket", .query = "token=abc123" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// Mailto URLs
// =============================================================================

test "Mailto URLs" {
    const cases = [_]TestCase{
        .{ .input = "mailto:user@example.com", .scheme = "mailto", .path = "user@example.com" },
        .{ .input = "mailto:john.doe@example.com", .scheme = "mailto", .path = "john.doe@example.com" },
        .{ .input = "mailto:user+tag@example.com", .scheme = "mailto", .path = "user+tag@example.com" },
        .{ .input = "mailto:user@example.com?subject=Hello", .scheme = "mailto", .path = "user@example.com", .query = "subject=Hello" },
        .{ .input = "mailto:user@example.com?subject=Hello&body=World", .scheme = "mailto", .path = "user@example.com", .query = "subject=Hello&body=World" },
        .{ .input = "mailto:user@example.com?cc=other@example.com", .scheme = "mailto", .path = "user@example.com", .query = "cc=other@example.com" },
        .{ .input = "mailto:user@example.com?cc=a@b.com&bcc=c@d.com", .scheme = "mailto", .path = "user@example.com", .query = "cc=a@b.com&bcc=c@d.com" },
        .{ .input = "mailto:support@company.com?subject=Bug%20Report", .scheme = "mailto", .path = "support@company.com", .query = "subject=Bug%20Report" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// Tel URLs
// =============================================================================

test "Tel URLs" {
    const cases = [_]TestCase{
        .{ .input = "tel:+1-800-555-1234", .scheme = "tel", .path = "+1-800-555-1234" },
        .{ .input = "tel:+1234567890", .scheme = "tel", .path = "+1234567890" },
        .{ .input = "tel:555-1234", .scheme = "tel", .path = "555-1234" },
        .{ .input = "tel:+44-20-7946-0958", .scheme = "tel", .path = "+44-20-7946-0958" },
        .{ .input = "tel:+1-650-253-0000", .scheme = "tel", .path = "+1-650-253-0000" },
        .{ .input = "tel:*67555-1234", .scheme = "tel", .path = "*67555-1234" },
        .{ .input = "tel:+1-800-CALL-NOW", .scheme = "tel", .path = "+1-800-CALL-NOW" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// Data URLs
// =============================================================================

test "Data URLs" {
    const cases = [_]TestCase{
        .{ .input = "data:,Hello%2C%20World!", .scheme = "data", .path = ",Hello%2C%20World!" },
        .{ .input = "data:text/plain,Hello", .scheme = "data", .path = "text/plain,Hello" },
        .{ .input = "data:text/plain;charset=utf-8,Hello", .scheme = "data", .path = "text/plain;charset=utf-8,Hello" },
        .{ .input = "data:text/html,%3Ch1%3EHello%3C/h1%3E", .scheme = "data", .path = "text/html,%3Ch1%3EHello%3C/h1%3E" },
        .{ .input = "data:image/png;base64,iVBORw0KGgo=", .scheme = "data", .path = "image/png;base64,iVBORw0KGgo=" },
        .{ .input = "data:application/json,%7B%22key%22:%22value%22%7D", .scheme = "data", .path = "application/json,%7B%22key%22:%22value%22%7D" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// URNs (Uniform Resource Names)
// =============================================================================

test "URNs - ISBN" {
    const cases = [_]TestCase{
        .{ .input = "urn:isbn:0451450523", .scheme = "urn", .path = "isbn:0451450523", .nid = "isbn", .nss = "0451450523" },
        .{ .input = "urn:isbn:0-486-27557-4", .scheme = "urn", .path = "isbn:0-486-27557-4", .nid = "isbn", .nss = "0-486-27557-4" },
        .{ .input = "urn:isbn:978-3-16-148410-0", .scheme = "urn", .path = "isbn:978-3-16-148410-0", .nid = "isbn", .nss = "978-3-16-148410-0" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "URNs - UUID" {
    const cases = [_]TestCase{
        .{ .input = "urn:uuid:f81d4fae-7dec-11d0-a765-00a0c91e6bf6", .scheme = "urn", .path = "uuid:f81d4fae-7dec-11d0-a765-00a0c91e6bf6", .nid = "uuid", .nss = "f81d4fae-7dec-11d0-a765-00a0c91e6bf6" },
        .{ .input = "urn:uuid:550e8400-e29b-41d4-a716-446655440000", .scheme = "urn", .path = "uuid:550e8400-e29b-41d4-a716-446655440000", .nid = "uuid", .nss = "550e8400-e29b-41d4-a716-446655440000" },
        .{ .input = "urn:uuid:6ba7b810-9dad-11d1-80b4-00c04fd430c8", .scheme = "urn", .path = "uuid:6ba7b810-9dad-11d1-80b4-00c04fd430c8", .nid = "uuid", .nss = "6ba7b810-9dad-11d1-80b4-00c04fd430c8" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "URNs - IETF" {
    const cases = [_]TestCase{
        .{ .input = "urn:ietf:rfc:3986", .scheme = "urn", .path = "ietf:rfc:3986", .nid = "ietf", .nss = "rfc:3986" },
        .{ .input = "urn:ietf:rfc:2141", .scheme = "urn", .path = "ietf:rfc:2141", .nid = "ietf", .nss = "rfc:2141" },
        .{ .input = "urn:ietf:params:xml:ns:caldav", .scheme = "urn", .path = "ietf:params:xml:ns:caldav", .nid = "ietf", .nss = "params:xml:ns:caldav" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "URNs - OID" {
    const cases = [_]TestCase{
        .{ .input = "urn:oid:2.16.840.1.113883.3.1", .scheme = "urn", .path = "oid:2.16.840.1.113883.3.1", .nid = "oid", .nss = "2.16.840.1.113883.3.1" },
        .{ .input = "urn:oid:1.3.6.1.4.1", .scheme = "urn", .path = "oid:1.3.6.1.4.1", .nid = "oid", .nss = "1.3.6.1.4.1" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "URNs - Other Namespaces" {
    const cases = [_]TestCase{
        // Amazon Resource Names
        .{ .input = "urn:aws:s3:::my-bucket", .scheme = "urn", .path = "aws:s3:::my-bucket", .nid = "aws", .nss = "s3:::my-bucket" },
        .{ .input = "urn:aws:iam::123456789:user/johndoe", .scheme = "urn", .path = "aws:iam::123456789:user/johndoe", .nid = "aws", .nss = "iam::123456789:user/johndoe" },

        // OASIS
        .{ .input = "urn:oasis:names:tc:SAML:2.0:assertion", .scheme = "urn", .path = "oasis:names:tc:SAML:2.0:assertion", .nid = "oasis", .nss = "names:tc:SAML:2.0:assertion" },

        // HL7 (Healthcare)
        .{ .input = "urn:hl7-org:v3", .scheme = "urn", .path = "hl7-org:v3", .nid = "hl7-org", .nss = "v3" },

        // Example namespace
        .{ .input = "urn:example:animal:ferret:nose", .scheme = "urn", .path = "example:animal:ferret:nose", .nid = "example", .nss = "animal:ferret:nose" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// Magnet URLs (P2P)
// =============================================================================

test "Magnet URLs" {
    const cases = [_]TestCase{
        .{ .input = "magnet:?xt=urn:btih:c12fe1c06bba254a9dc9f519b335aa7c1367a88a", .scheme = "magnet", .path = "", .query = "xt=urn:btih:c12fe1c06bba254a9dc9f519b335aa7c1367a88a" },
        .{ .input = "magnet:?xt=urn:btih:abc123&dn=Example+File", .scheme = "magnet", .path = "", .query = "xt=urn:btih:abc123&dn=Example+File" },
        .{ .input = "magnet:?xt=urn:sha1:YNCKHTQCWBTRNJIV4WNAE52SJUQCZO5C", .scheme = "magnet", .path = "", .query = "xt=urn:sha1:YNCKHTQCWBTRNJIV4WNAE52SJUQCZO5C" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// Custom/Application Schemes
// =============================================================================

test "Custom Application Schemes" {
    const cases = [_]TestCase{
        // Slack
        .{ .input = "slack://channel?team=T123&id=C456", .scheme = "slack", .host = "channel", .path = "", .query = "team=T123&id=C456" },

        // Spotify
        .{ .input = "spotify:track:4iV5W9uYEdYUVa79Axb7Rh", .scheme = "spotify", .path = "track:4iV5W9uYEdYUVa79Axb7Rh" },
        .{ .input = "spotify:album:0sNOF9WDwhWunNAHPD3Baj", .scheme = "spotify", .path = "album:0sNOF9WDwhWunNAHPD3Baj" },
        .{ .input = "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M", .scheme = "spotify", .path = "playlist:37i9dQZF1DXcBWIGoYBM5M" },

        // VS Code
        .{ .input = "vscode://file/path/to/file.txt", .scheme = "vscode", .host = "file", .path = "/path/to/file.txt" },
        .{ .input = "vscode://vscode.git/clone?url=https://github.com/user/repo", .scheme = "vscode", .host = "vscode.git", .path = "/clone", .query = "url=https://github.com/user/repo" },

        // Zoom
        .{ .input = "zoommtg://zoom.us/join?confno=123456789", .scheme = "zoommtg", .host = "zoom.us", .path = "/join", .query = "confno=123456789" },

        // Discord
        .{ .input = "discord://discordapp.com/users/123456789", .scheme = "discord", .host = "discordapp.com", .path = "/users/123456789" },

        // Steam
        .{ .input = "steam://run/440", .scheme = "steam", .host = "run", .path = "/440" },
        .{ .input = "steam://connect/192.168.1.1:27015", .scheme = "steam", .host = "connect", .path = "/192.168.1.1:27015" },

        // Apple
        .{ .input = "itms-apps://apps.apple.com/app/id123456789", .scheme = "itms-apps", .host = "apps.apple.com", .path = "/app/id123456789" },
        .{ .input = "maps://maps.apple.com/?q=New+York", .scheme = "maps", .host = "maps.apple.com", .path = "/", .query = "q=New+York" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// LDAP URLs
// =============================================================================

test "LDAP URLs" {
    const cases = [_]TestCase{
        .{ .input = "ldap://ldap.example.com", .scheme = "ldap", .host = "ldap.example.com", .path = "" },
        .{ .input = "ldap://ldap.example.com/", .scheme = "ldap", .host = "ldap.example.com", .path = "/" },
        .{ .input = "ldap://ldap.example.com/dc=example,dc=com", .scheme = "ldap", .host = "ldap.example.com", .path = "/dc=example,dc=com" },
        .{ .input = "ldap://ldap.example.com:389/dc=example,dc=com", .scheme = "ldap", .host = "ldap.example.com", .port = 389, .path = "/dc=example,dc=com" },
        .{ .input = "ldaps://ldap.example.com/dc=example,dc=com", .scheme = "ldaps", .host = "ldap.example.com", .path = "/dc=example,dc=com" },
        .{ .input = "ldap://ldap.example.com/ou=users,dc=example,dc=com?cn,mail", .scheme = "ldap", .host = "ldap.example.com", .path = "/ou=users,dc=example,dc=com", .query = "cn,mail" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// S3 URLs
// =============================================================================

test "S3 URLs" {
    const cases = [_]TestCase{
        .{ .input = "s3://bucket-name", .scheme = "s3", .host = "bucket-name", .path = "" },
        .{ .input = "s3://bucket-name/", .scheme = "s3", .host = "bucket-name", .path = "/" },
        .{ .input = "s3://bucket-name/key", .scheme = "s3", .host = "bucket-name", .path = "/key" },
        .{ .input = "s3://bucket-name/path/to/object", .scheme = "s3", .host = "bucket-name", .path = "/path/to/object" },
        .{ .input = "s3://my-bucket/data/2024/01/file.csv", .scheme = "s3", .host = "my-bucket", .path = "/data/2024/01/file.csv" },
        .{ .input = "s3://bucket/key?versionId=abc123", .scheme = "s3", .host = "bucket", .path = "/key", .query = "versionId=abc123" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// Docker Registry URLs
// =============================================================================

test "Docker Registry URLs" {
    // Note: docker:// URLs with tags in path work, but host:tag without path would be parsed as port
    const cases = [_]TestCase{
        .{ .input = "docker://ubuntu", .scheme = "docker", .host = "ubuntu", .path = "" },
        .{ .input = "docker://registry.example.com/myimage", .scheme = "docker", .host = "registry.example.com", .path = "/myimage" },
        .{ .input = "docker://registry.example.com/myimage:latest", .scheme = "docker", .host = "registry.example.com", .path = "/myimage:latest" },
        .{ .input = "docker://gcr.io/project/image:tag", .scheme = "docker", .host = "gcr.io", .path = "/project/image:tag" },
        .{ .input = "docker://quay.io/user/image:v1.0", .scheme = "docker", .host = "quay.io", .path = "/user/image:v1.0" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// Kubernetes Resource URLs
// =============================================================================

test "Kubernetes Resource URLs" {
    const cases = [_]TestCase{
        .{ .input = "k8s://api/v1/namespaces/default/pods", .scheme = "k8s", .host = "api", .path = "/v1/namespaces/default/pods" },
        .{ .input = "k8s://apis/apps/v1/deployments", .scheme = "k8s", .host = "apis", .path = "/apps/v1/deployments" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// News/NNTP URLs
// =============================================================================

test "News URLs" {
    const cases = [_]TestCase{
        .{ .input = "news:comp.lang.zig", .scheme = "news", .path = "comp.lang.zig" },
        .{ .input = "news:alt.test", .scheme = "news", .path = "alt.test" },
        .{ .input = "nntp://news.example.com/comp.lang.zig", .scheme = "nntp", .host = "news.example.com", .path = "/comp.lang.zig" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// Gopher URLs
// =============================================================================

test "Gopher URLs" {
    const cases = [_]TestCase{
        .{ .input = "gopher://gopher.example.com", .scheme = "gopher", .host = "gopher.example.com", .path = "" },
        .{ .input = "gopher://gopher.example.com/", .scheme = "gopher", .host = "gopher.example.com", .path = "/" },
        .{ .input = "gopher://gopher.example.com/1/path", .scheme = "gopher", .host = "gopher.example.com", .path = "/1/path" },
        .{ .input = "gopher://gopher.example.com:70/", .scheme = "gopher", .host = "gopher.example.com", .port = 70, .path = "/" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// IRC URLs
// =============================================================================

test "IRC URLs" {
    const cases = [_]TestCase{
        .{ .input = "irc://irc.example.com", .scheme = "irc", .host = "irc.example.com", .path = "" },
        .{ .input = "irc://irc.example.com/channel", .scheme = "irc", .host = "irc.example.com", .path = "/channel" },
        .{ .input = "irc://irc.example.com:6667/channel", .scheme = "irc", .host = "irc.example.com", .port = 6667, .path = "/channel" },
        .{ .input = "ircs://irc.example.com/channel", .scheme = "ircs", .host = "irc.example.com", .path = "/channel" },
        .{ .input = "irc://nick@irc.example.com/channel", .scheme = "irc", .userinfo = "nick", .host = "irc.example.com", .path = "/channel" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// SIP URLs (VoIP)
// =============================================================================

test "SIP URLs" {
    // Note: sip: without // is parsed as scheme:path, not scheme://authority
    const cases = [_]TestCase{
        .{ .input = "sip:user@example.com", .scheme = "sip", .path = "user@example.com" },
        .{ .input = "sip://user@example.com", .scheme = "sip", .userinfo = "user", .host = "example.com", .path = "" },
        .{ .input = "sip://user:password@example.com", .scheme = "sip", .userinfo = "user:password", .host = "example.com", .path = "" },
        .{ .input = "sip://user@example.com:5060", .scheme = "sip", .userinfo = "user", .host = "example.com", .port = 5060, .path = "" },
        .{ .input = "sips://user@example.com", .scheme = "sips", .userinfo = "user", .host = "example.com", .path = "" },
        .{ .input = "sip://+1-800-555-1234@gateway.example.com", .scheme = "sip", .userinfo = "+1-800-555-1234", .host = "gateway.example.com", .path = "" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// XMPP/Jabber URLs
// =============================================================================

test "XMPP URLs" {
    const cases = [_]TestCase{
        .{ .input = "xmpp:user@example.com", .scheme = "xmpp", .path = "user@example.com" },
        .{ .input = "xmpp:user@example.com?message", .scheme = "xmpp", .path = "user@example.com", .query = "message" },
        .{ .input = "xmpp:user@example.com?message;body=Hello", .scheme = "xmpp", .path = "user@example.com", .query = "message;body=Hello" },
        .{ .input = "xmpp://example.com/user@example.com", .scheme = "xmpp", .host = "example.com", .path = "/user@example.com" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// RTP/RTSP URLs (Streaming)
// =============================================================================

test "Streaming URLs" {
    const cases = [_]TestCase{
        // RTSP
        .{ .input = "rtsp://server.example.com/stream", .scheme = "rtsp", .host = "server.example.com", .path = "/stream" },
        .{ .input = "rtsp://server.example.com:554/stream", .scheme = "rtsp", .host = "server.example.com", .port = 554, .path = "/stream" },
        .{ .input = "rtsp://user:pass@server.example.com/live", .scheme = "rtsp", .userinfo = "user:pass", .host = "server.example.com", .path = "/live" },
        .{ .input = "rtsps://server.example.com/secure", .scheme = "rtsps", .host = "server.example.com", .path = "/secure" },

        // RTMP
        .{ .input = "rtmp://server.example.com/live", .scheme = "rtmp", .host = "server.example.com", .path = "/live" },
        .{ .input = "rtmp://server.example.com:1935/live/stream", .scheme = "rtmp", .host = "server.example.com", .port = 1935, .path = "/live/stream" },
        .{ .input = "rtmps://server.example.com/live", .scheme = "rtmps", .host = "server.example.com", .path = "/live" },

        // HLS
        .{ .input = "https://stream.example.com/hls/playlist.m3u8", .scheme = "https", .host = "stream.example.com", .path = "/hls/playlist.m3u8" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// Relative References
// =============================================================================

test "Relative References - Path Only" {
    const cases = [_]TestCase{
        .{ .input = "path", .path = "path" },
        .{ .input = "path/to/resource", .path = "path/to/resource" },
        .{ .input = "/path", .path = "/path" },
        .{ .input = "/path/to/resource", .path = "/path/to/resource" },
        .{ .input = "/path/to/resource.html", .path = "/path/to/resource.html" },
        .{ .input = "./relative", .path = "./relative" },
        .{ .input = "../parent", .path = "../parent" },
        .{ .input = "../../grandparent", .path = "../../grandparent" },
        .{ .input = "./path/./to/../resource", .path = "./path/./to/../resource" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "Relative References - With Query and Fragment" {
    const cases = [_]TestCase{
        .{ .input = "?query", .path = "", .query = "query" },
        .{ .input = "?key=value", .path = "", .query = "key=value" },
        .{ .input = "#fragment", .path = "", .fragment = "fragment" },
        .{ .input = "#section-1", .path = "", .fragment = "section-1" },
        .{ .input = "?query#fragment", .path = "", .query = "query", .fragment = "fragment" },
        .{ .input = "path?query", .path = "path", .query = "query" },
        .{ .input = "path#fragment", .path = "path", .fragment = "fragment" },
        .{ .input = "path?query#fragment", .path = "path", .query = "query", .fragment = "fragment" },
        .{ .input = "/path?query#fragment", .path = "/path", .query = "query", .fragment = "fragment" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// Edge Cases and Special Characters
// =============================================================================

test "Edge Cases - Empty Components" {
    const cases = [_]TestCase{
        .{ .input = "", .path = "" },
        .{ .input = "//host", .host = "host", .path = "" },
        .{ .input = "//host/", .host = "host", .path = "/" },
        .{ .input = "//host:8080", .host = "host", .port = 8080, .path = "" },
        // scheme:// with empty host - parser returns null host, not empty string
        .{ .input = "scheme:///path", .scheme = "scheme", .path = "/path" },
        .{ .input = "scheme://@host", .scheme = "scheme", .userinfo = "", .host = "host", .path = "" },
        .{ .input = "scheme://:@host", .scheme = "scheme", .userinfo = ":", .host = "host", .path = "" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "Edge Cases - Percent Encoding in Path" {
    const cases = [_]TestCase{
        .{ .input = "http://example.com/path%20with%20spaces", .scheme = "http", .host = "example.com", .path = "/path%20with%20spaces" },
        .{ .input = "http://example.com/path%2Fwith%2Fslashes", .scheme = "http", .host = "example.com", .path = "/path%2Fwith%2Fslashes" },
        .{ .input = "http://example.com/%E4%B8%AD%E6%96%87", .scheme = "http", .host = "example.com", .path = "/%E4%B8%AD%E6%96%87" },
        .{ .input = "http://example.com/caf%C3%A9", .scheme = "http", .host = "example.com", .path = "/caf%C3%A9" },
        .{ .input = "http://example.com/%00%01%02", .scheme = "http", .host = "example.com", .path = "/%00%01%02" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "Edge Cases - Special Characters in Query" {
    const cases = [_]TestCase{
        .{ .input = "http://example.com?a=1&b=2", .scheme = "http", .host = "example.com", .path = "", .query = "a=1&b=2" },
        .{ .input = "http://example.com?key=value%26more", .scheme = "http", .host = "example.com", .path = "", .query = "key=value%26more" },
        .{ .input = "http://example.com?q=hello+world", .scheme = "http", .host = "example.com", .path = "", .query = "q=hello+world" },
        .{ .input = "http://example.com?q=a%3Db", .scheme = "http", .host = "example.com", .path = "", .query = "q=a%3Db" },
        .{ .input = "http://example.com?q=%22quoted%22", .scheme = "http", .host = "example.com", .path = "", .query = "q=%22quoted%22" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "Edge Cases - Long URIs" {
    const cases = [_]TestCase{
        .{
            .input = "http://example.com/a/very/long/path/that/goes/on/and/on/and/on/forever/and/ever/until/it/finally/ends",
            .scheme = "http",
            .host = "example.com",
            .path = "/a/very/long/path/that/goes/on/and/on/and/on/forever/and/ever/until/it/finally/ends",
        },
        .{
            .input = "http://example.com?a=1&b=2&c=3&d=4&e=5&f=6&g=7&h=8&i=9&j=10&k=11&l=12&m=13&n=14&o=15",
            .scheme = "http",
            .host = "example.com",
            .path = "",
            .query = "a=1&b=2&c=3&d=4&e=5&f=6&g=7&h=8&i=9&j=10&k=11&l=12&m=13&n=14&o=15",
        },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "Edge Cases - Unusual but Valid" {
    const cases = [_]TestCase{
        // Scheme with plus, minus, dot
        .{ .input = "coap+tcp://example.com", .scheme = "coap+tcp", .host = "example.com", .path = "" },
        .{ .input = "svn+ssh://example.com", .scheme = "svn+ssh", .host = "example.com", .path = "" },
        .{ .input = "h2c://example.com", .scheme = "h2c", .host = "example.com", .path = "" },

        // Numeric TLDs (not real but valid syntax)
        .{ .input = "http://example.123", .scheme = "http", .host = "example.123", .path = "" },

        // Single character components
        .{ .input = "x://a", .scheme = "x", .host = "a", .path = "" },
        .{ .input = "http://a/b?c#d", .scheme = "http", .host = "a", .path = "/b", .query = "c", .fragment = "d" },

        // Numbers in scheme (after first char)
        .{ .input = "h323://example.com", .scheme = "h323", .host = "example.com", .path = "" },
        .{ .input = "sip2://example.com", .scheme = "sip2", .host = "example.com", .path = "" },
    };
    for (cases) |tc| try runTestCase(tc);
}

test "Edge Cases - Ports" {
    const cases = [_]TestCase{
        .{ .input = "http://example.com:0", .scheme = "http", .host = "example.com", .port = 0, .path = "" },
        .{ .input = "http://example.com:1", .scheme = "http", .host = "example.com", .port = 1, .path = "" },
        .{ .input = "http://example.com:65535", .scheme = "http", .host = "example.com", .port = 65535, .path = "" },
        .{ .input = "http://example.com:80/", .scheme = "http", .host = "example.com", .port = 80, .path = "/" },
        .{ .input = "https://example.com:443/", .scheme = "https", .host = "example.com", .port = 443, .path = "/" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// Container/Orchestration URLs
// =============================================================================

test "Container URLs" {
    const cases = [_]TestCase{
        // Podman
        .{ .input = "podman://localhost/containers/abc123", .scheme = "podman", .host = "localhost", .path = "/containers/abc123" },

        // Containerd
        .{ .input = "containerd://default/mycontainer", .scheme = "containerd", .host = "default", .path = "/mycontainer" },

        // OCI Registry
        .{ .input = "oci://ghcr.io/user/image:tag", .scheme = "oci", .host = "ghcr.io", .path = "/user/image:tag" },
        .{ .input = "oci://quay.io/user/image@sha256:abc123", .scheme = "oci", .host = "quay.io", .path = "/user/image@sha256:abc123" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// Cloud Provider URLs
// =============================================================================

test "Cloud Provider URLs" {
    const cases = [_]TestCase{
        // Google Cloud
        .{ .input = "gs://bucket-name/path/to/object", .scheme = "gs", .host = "bucket-name", .path = "/path/to/object" },
        .{ .input = "gcr://gcr.io/project/image", .scheme = "gcr", .host = "gcr.io", .path = "/project/image" },

        // Azure
        .{ .input = "azblob://container/blob", .scheme = "azblob", .host = "container", .path = "/blob" },
        .{ .input = "az://subscription/resourcegroup", .scheme = "az", .host = "subscription", .path = "/resourcegroup" },

        // DigitalOcean
        .{ .input = "do://spaces/bucket/key", .scheme = "do", .host = "spaces", .path = "/bucket/key" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// Version Control URLs
// =============================================================================

test "Version Control URLs" {
    const cases = [_]TestCase{
        // Mercurial
        .{ .input = "hg://hg.example.com/repo", .scheme = "hg", .host = "hg.example.com", .path = "/repo" },
        .{ .input = "hg+https://hg.example.com/repo", .scheme = "hg+https", .host = "hg.example.com", .path = "/repo" },

        // Subversion
        .{ .input = "svn://svn.example.com/repo/trunk", .scheme = "svn", .host = "svn.example.com", .path = "/repo/trunk" },
        .{ .input = "svn+ssh://user@svn.example.com/repo", .scheme = "svn+ssh", .userinfo = "user", .host = "svn.example.com", .path = "/repo" },

        // CVS
        .{ .input = "cvs://cvs.example.com/cvsroot/module", .scheme = "cvs", .host = "cvs.example.com", .path = "/cvsroot/module" },

        // Perforce
        .{ .input = "p4://perforce.example.com:1666/depot/path", .scheme = "p4", .host = "perforce.example.com", .port = 1666, .path = "/depot/path" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// API Gateway URLs
// =============================================================================

test "API Gateway URLs" {
    const cases = [_]TestCase{
        // AWS API Gateway
        .{ .input = "https://abc123.execute-api.us-east-1.amazonaws.com/prod/users", .scheme = "https", .host = "abc123.execute-api.us-east-1.amazonaws.com", .path = "/prod/users" },

        // Azure API Management
        .{ .input = "https://myapi.azure-api.net/v1/users", .scheme = "https", .host = "myapi.azure-api.net", .path = "/v1/users" },

        // Google Cloud Endpoints
        .{ .input = "https://myproject.appspot.com/api/v1/items", .scheme = "https", .host = "myproject.appspot.com", .path = "/api/v1/items" },
    };
    for (cases) |tc| try runTestCase(tc);
}

// =============================================================================
// Test Statistics
// =============================================================================

test "Dataset Statistics" {
    // This test just prints statistics about the dataset
    // The actual test coverage is in all the other tests
    std.debug.print("\n=== URI Dataset Test Statistics ===\n", .{});
    std.debug.print("Test categories covered:\n", .{});
    std.debug.print("  - HTTP/HTTPS URLs (basic, auth, query, fragment, paths)\n", .{});
    std.debug.print("  - IPv4 and IPv6 addresses\n", .{});
    std.debug.print("  - Localhost and special hosts\n", .{});
    std.debug.print("  - File URLs (Unix, Windows, UNC)\n", .{});
    std.debug.print("  - Database URIs (PostgreSQL, MySQL, MongoDB, Redis, SQLite, etc.)\n", .{});
    std.debug.print("  - FTP/SFTP/SSH URLs\n", .{});
    std.debug.print("  - Git URLs\n", .{});
    std.debug.print("  - WebSocket URLs\n", .{});
    std.debug.print("  - Mailto URLs\n", .{});
    std.debug.print("  - Tel URLs\n", .{});
    std.debug.print("  - Data URLs\n", .{});
    std.debug.print("  - URNs (ISBN, UUID, IETF, OID, etc.)\n", .{});
    std.debug.print("  - Magnet URLs\n", .{});
    std.debug.print("  - Custom application schemes\n", .{});
    std.debug.print("  - LDAP URLs\n", .{});
    std.debug.print("  - S3 URLs\n", .{});
    std.debug.print("  - Docker Registry URLs\n", .{});
    std.debug.print("  - Kubernetes Resource URLs\n", .{});
    std.debug.print("  - News/NNTP URLs\n", .{});
    std.debug.print("  - Gopher URLs\n", .{});
    std.debug.print("  - IRC URLs\n", .{});
    std.debug.print("  - SIP URLs\n", .{});
    std.debug.print("  - XMPP URLs\n", .{});
    std.debug.print("  - Streaming URLs (RTSP, RTMP)\n", .{});
    std.debug.print("  - Relative references\n", .{});
    std.debug.print("  - Edge cases and special characters\n", .{});
    std.debug.print("  - Container URLs\n", .{});
    std.debug.print("  - Cloud Provider URLs\n", .{});
    std.debug.print("  - Version Control URLs\n", .{});
    std.debug.print("  - API Gateway URLs\n", .{});
    std.debug.print("===================================\n", .{});
}
