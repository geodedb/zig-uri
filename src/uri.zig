// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! URI Parser - RFC 3986 Compliant Implementation
//!
//! This module implements URI parsing according to RFC 3986:
//! "Uniform Resource Identifier (URI): Generic Syntax"
//!
//! ## Grammar (RFC 3986 Appendix A)
//!
//! ```
//! URI           = scheme ":" hier-part [ "?" query ] [ "#" fragment ]
//! hier-part     = "//" authority path-abempty
//!               / path-absolute
//!               / path-rootless
//!               / path-empty
//! authority     = [ userinfo "@" ] host [ ":" port ]
//! ```

const std = @import("std");
const mem = std.mem;
const ascii = std.ascii;
const Allocator = std.mem.Allocator;

/// URI parsing error types.
pub const ParseError = error{
    /// Invalid character in URI
    InvalidCharacter,
    /// Invalid percent-encoded sequence
    InvalidPercentEncoding,
    /// Invalid scheme (must start with letter)
    InvalidScheme,
    /// Invalid port number
    InvalidPort,
    /// Port number out of range (0-65535)
    PortOutOfRange,
    /// Invalid host format
    InvalidHost,
    /// Invalid IPv6 address
    InvalidIPv6,
    /// Invalid IPv4 address
    InvalidIPv4,
    /// Empty scheme
    EmptyScheme,
    /// Missing host after //
    MissingHost,
    /// Unclosed bracket in IPv6 address
    UnclosedIPv6Bracket,
    /// Out of memory
    OutOfMemory,
};

/// URI component type for targeted encoding operations.
pub const Component = enum {
    scheme,
    userinfo,
    host,
    port,
    path,
    query,
    fragment,
};

/// Parsing options for different validation modes.
pub const ParseOptions = struct {
    /// Strict RFC 3986 compliance (default)
    strict: bool = true,
    /// Allow unencoded spaces
    allow_spaces: bool = false,
    /// Parse as IRI (RFC 3987)
    iri_mode: bool = false,
};

/// URN components for RFC 8141 support.
pub const UrnComponents = struct {
    /// The NID (Namespace Identifier)
    nid: ?[]const u8 = null,
    /// The NSS (Namespace Specific String)
    nss: ?[]const u8 = null,
    /// Optional r-component
    r_component: ?[]const u8 = null,
    /// Optional q-component
    q_component: ?[]const u8 = null,
    /// Optional f-component (fragment)
    f_component: ?[]const u8 = null,
};

/// Parsed URI structure.
///
/// All string fields are slices into the original input string (zero-copy).
/// Optional fields are null if not present in the URI.
///
/// ## RFC 3986 Section 3 - Syntax Components
/// ```
///          foo://example.com:8042/over/there?name=ferret#nose
///          \_/   \______________/\_________/ \_________/ \__/
///           |           |            |            |        |
///        scheme     authority       path        query   fragment
/// ```
pub const Uri = struct {
    /// The scheme component (e.g., "http", "https", "file")
    /// RFC 3986 Section 3.1
    scheme: ?[]const u8 = null,

    /// The userinfo component (e.g., "user:password")
    /// RFC 3986 Section 3.2.1
    userinfo: ?[]const u8 = null,

    /// The host component (e.g., "example.com", "192.168.1.1", "[::1]")
    /// RFC 3986 Section 3.2.2
    host: ?[]const u8 = null,

    /// The port number (e.g., 80, 443, 8080)
    /// RFC 3986 Section 3.2.3
    port: ?u16 = null,

    /// The path component (e.g., "/path/to/resource")
    /// RFC 3986 Section 3.3
    /// Note: path is never null, but may be empty string
    path: []const u8 = "",

    /// The query component without leading '?' (e.g., "key=value&foo=bar")
    /// RFC 3986 Section 3.4
    query: ?[]const u8 = null,

    /// The fragment component without leading '#' (e.g., "section1")
    /// RFC 3986 Section 3.5
    fragment: ?[]const u8 = null,

    /// The raw port string (for reconstruction)
    raw_port: ?[]const u8 = null,

    /// Original input string
    raw: []const u8 = "",

    /// URN components (populated if scheme is "urn")
    urn: ?UrnComponents = null,

    /// Check if this is a URN.
    pub fn isUrn(self: Uri) bool {
        if (self.scheme) |s| {
            return ascii.eqlIgnoreCase(s, "urn");
        }
        return false;
    }

    /// Check if the URI is absolute (has a scheme).
    pub fn isAbsolute(self: Uri) bool {
        return self.scheme != null;
    }

    /// Check if the URI is a relative reference.
    pub fn isRelative(self: Uri) bool {
        return self.scheme == null;
    }

    /// Check if the URI has an authority component.
    pub fn hasAuthority(self: Uri) bool {
        return self.host != null;
    }

    /// Get the authority component as a string.
    /// Returns null if there is no authority.
    pub fn authority(self: Uri) ?[]const u8 {
        if (self.host == null) return null;

        // Find the authority portion in the raw string
        const raw = self.raw;
        const scheme_end = if (self.scheme) |s| s.len + 1 else 0; // +1 for ':'

        // Check for "//" after scheme
        if (raw.len > scheme_end + 2 and
            raw[scheme_end] == '/' and
            raw[scheme_end + 1] == '/')
        {
            const auth_start = scheme_end + 2;
            // Find end of authority (path, query, or fragment start)
            var auth_end = auth_start;
            while (auth_end < raw.len) : (auth_end += 1) {
                const c = raw[auth_end];
                if (c == '/' or c == '?' or c == '#') break;
            }
            return raw[auth_start..auth_end];
        }

        return null;
    }

    /// Format the URI back to a string.
    pub fn format(
        self: Uri,
        writer: anytype,
    ) !void {

        // Scheme
        if (self.scheme) |s| {
            try writer.writeAll(s);
            try writer.writeByte(':');
        }

        // Authority
        if (self.host != null) {
            try writer.writeAll("//");
            if (self.userinfo) |ui| {
                try writer.writeAll(ui);
                try writer.writeByte('@');
            }
            try writer.writeAll(self.host.?);
            if (self.raw_port) |p| {
                try writer.writeByte(':');
                try writer.writeAll(p);
            }
        }

        // Path
        try writer.writeAll(self.path);

        // Query
        if (self.query) |q| {
            try writer.writeByte('?');
            try writer.writeAll(q);
        }

        // Fragment
        if (self.fragment) |f| {
            try writer.writeByte('#');
            try writer.writeAll(f);
        }
    }

    /// Create an owned copy of the URI with allocated strings.
    pub fn dupe(self: Uri, allocator: Allocator) Allocator.Error!Uri {
        var result = Uri{
            .scheme = if (self.scheme) |s| try allocator.dupe(u8, s) else null,
            .userinfo = if (self.userinfo) |ui| try allocator.dupe(u8, ui) else null,
            .host = if (self.host) |h| try allocator.dupe(u8, h) else null,
            .port = self.port,
            .path = try allocator.dupe(u8, self.path),
            .query = if (self.query) |q| try allocator.dupe(u8, q) else null,
            .fragment = if (self.fragment) |f| try allocator.dupe(u8, f) else null,
            .raw_port = if (self.raw_port) |rp| try allocator.dupe(u8, rp) else null,
            .raw = try allocator.dupe(u8, self.raw),
            .urn = null,
        };

        // Duplicate URN components if present
        if (self.urn) |urn| {
            result.urn = UrnComponents{
                .nid = if (urn.nid) |n| try allocator.dupe(u8, n) else null,
                .nss = if (urn.nss) |n| try allocator.dupe(u8, n) else null,
                .r_component = if (urn.r_component) |r| try allocator.dupe(u8, r) else null,
                .q_component = if (urn.q_component) |q| try allocator.dupe(u8, q) else null,
                .f_component = if (urn.f_component) |f| try allocator.dupe(u8, f) else null,
            };
        }

        return result;
    }

    /// Free an owned URI's allocated memory.
    pub fn deinit(self: *Uri, allocator: Allocator) void {
        if (self.scheme) |s| allocator.free(s);
        if (self.userinfo) |ui| allocator.free(ui);
        if (self.host) |h| allocator.free(h);
        if (self.query) |q| allocator.free(q);
        if (self.fragment) |f| allocator.free(f);
        if (self.raw_port) |rp| allocator.free(rp);
        if (self.path.len > 0) allocator.free(self.path);
        if (self.raw.len > 0) allocator.free(self.raw);

        // Free URN components
        if (self.urn) |urn| {
            if (urn.nid) |n| allocator.free(n);
            if (urn.nss) |n| allocator.free(n);
            if (urn.r_component) |r| allocator.free(r);
            if (urn.q_component) |q| allocator.free(q);
            if (urn.f_component) |fc| allocator.free(fc);
        }
        self.* = .{};
    }
};

/// Parse a URI string with default options.
pub fn parse(input: []const u8) ParseError!Uri {
    return parseWithOptions(input, .{});
}

/// Parse a URI string with configurable options.
pub fn parseWithOptions(input: []const u8, options: ParseOptions) ParseError!Uri {
    try validateInput(input, options);

    var result = Uri{ .raw = input };
    var pos: usize = 0;

    // Empty input
    if (input.len == 0) {
        return result;
    }

    // Try to parse scheme (RFC 3986 Section 3.1)
    // scheme = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )
    if (parseScheme(input)) |scheme_end| {
        if (scheme_end < input.len and input[scheme_end] == ':') {
            result.scheme = input[0..scheme_end];
            pos = scheme_end + 1; // Skip the ':'

            // Check for URN scheme - parse according to RFC 8141
            if (ascii.eqlIgnoreCase(result.scheme.?, "urn")) {
                result.urn = try parseUrn(input[pos..]);
                // For URNs, the path contains the full URN-specific part
                result.path = input[pos..];
                return result;
            }
        }
    }

    // Check for authority (starts with "//")
    if (pos + 1 < input.len and input[pos] == '/' and input[pos + 1] == '/') {
        pos += 2; // Skip "//"

        // Parse authority: [ userinfo "@" ] host [ ":" port ]
        const authority_end = findAuthorityEnd(input[pos..]);
        const authority_str = input[pos .. pos + authority_end];

        try parseAuthority(authority_str, &result);
        pos += authority_end;
    }

    // Parse path (RFC 3986 Section 3.3)
    const path_start = pos;
    while (pos < input.len) : (pos += 1) {
        const c = input[pos];
        if (c == '?' or c == '#') break;
    }
    result.path = input[path_start..pos];

    // Parse query (RFC 3986 Section 3.4)
    if (pos < input.len and input[pos] == '?') {
        pos += 1; // Skip '?'
        const query_start = pos;
        while (pos < input.len and input[pos] != '#') : (pos += 1) {}
        result.query = input[query_start..pos];
    }

    // Parse fragment (RFC 3986 Section 3.5)
    if (pos < input.len and input[pos] == '#') {
        pos += 1; // Skip '#'
        result.fragment = input[pos..];
    }

    return result;
}

/// Parse the scheme component.
/// Returns the length of the scheme if valid, null otherwise.
fn parseScheme(input: []const u8) ?usize {
    if (input.len == 0) return null;

    // First character must be ALPHA
    if (!ascii.isAlphabetic(input[0])) return null;

    var i: usize = 1;
    while (i < input.len) : (i += 1) {
        const c = input[i];
        if (c == ':') return i;
        // scheme = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )
        if (!ascii.isAlphanumeric(c) and c != '+' and c != '-' and c != '.') {
            return null;
        }
    }

    return null; // No ':' found
}

/// Find the end of the authority component.
fn findAuthorityEnd(input: []const u8) usize {
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        const c = input[i];
        if (c == '/' or c == '?' or c == '#') break;
    }
    return i;
}

/// Parse the authority component: [ userinfo "@" ] host [ ":" port ]
fn parseAuthority(authority: []const u8, result: *Uri) ParseError!void {
    var remaining = authority;

    // Check for userinfo (contains '@')
    if (mem.indexOf(u8, remaining, "@")) |at_pos| {
        result.userinfo = remaining[0..at_pos];
        remaining = remaining[at_pos + 1 ..];
    }

    // Parse host and port
    // Check for IPv6 address (enclosed in brackets)
    if (remaining.len > 0 and remaining[0] == '[') {
        // IPv6 address
        if (mem.indexOf(u8, remaining, "]")) |bracket_end| {
            result.host = remaining[0 .. bracket_end + 1];
            remaining = remaining[bracket_end + 1 ..];
        } else {
            return ParseError.UnclosedIPv6Bracket;
        }
    } else {
        // Regular host (or IPv4)
        // Find the port separator (last ':' not in brackets)
        var host_end = remaining.len;
        var i: usize = remaining.len;
        while (i > 0) {
            i -= 1;
            if (remaining[i] == ':') {
                host_end = i;
                break;
            }
        }
        if (host_end > 0) {
            result.host = remaining[0..host_end];
        } else if (remaining.len > 0 and !mem.startsWith(u8, remaining, ":")) {
            result.host = remaining;
            remaining = "";
        }
        remaining = remaining[host_end..];
    }

    // Parse port
    if (remaining.len > 0 and remaining[0] == ':') {
        const port_str = remaining[1..];
        if (port_str.len > 0) {
            result.raw_port = port_str;
            const port_num = std.fmt.parseInt(u16, port_str, 10) catch |err| switch (err) {
                error.InvalidCharacter => return ParseError.InvalidPort,
                error.Overflow => return ParseError.PortOutOfRange,
            };
            result.port = port_num;
        }
    }
}

/// Parse URN components according to RFC 8141.
/// URN = "urn" ":" NID ":" NSS [ "?+" r-component ] [ "?=" q-component ] [ "#" f-component ]
fn parseUrn(input: []const u8) ParseError!UrnComponents {
    var result = UrnComponents{};
    var remaining = input;

    // Parse NID (Namespace Identifier)
    // Must be at least 2 characters, followed by ':'
    if (mem.indexOf(u8, remaining, ":")) |nid_end| {
        if (nid_end < 2) {
            return ParseError.InvalidScheme; // NID too short
        }
        result.nid = remaining[0..nid_end];
        remaining = remaining[nid_end + 1 ..];
    } else {
        return ParseError.InvalidScheme; // No NID found
    }

    // Parse NSS (Namespace Specific String)
    // Everything until ?+, ?=, or #
    var nss_end = remaining.len;
    for (remaining, 0..) |c, i| {
        if (c == '?' or c == '#') {
            nss_end = i;
            break;
        }
    }
    if (nss_end > 0) {
        result.nss = remaining[0..nss_end];
    }
    remaining = remaining[nss_end..];

    // Parse optional r-component (?+...)
    if (remaining.len >= 2 and remaining[0] == '?' and remaining[1] == '+') {
        remaining = remaining[2..];
        var r_end = remaining.len;
        for (remaining, 0..) |c, i| {
            if (c == '?' or c == '#') {
                r_end = i;
                break;
            }
        }
        result.r_component = remaining[0..r_end];
        remaining = remaining[r_end..];
    }

    // Parse optional q-component (?=...)
    if (remaining.len >= 2 and remaining[0] == '?' and remaining[1] == '=') {
        remaining = remaining[2..];
        var q_end = remaining.len;
        for (remaining, 0..) |c, i| {
            if (c == '#') {
                q_end = i;
                break;
            }
        }
        result.q_component = remaining[0..q_end];
        remaining = remaining[q_end..];
    }

    // Parse optional f-component (#...)
    if (remaining.len > 0 and remaining[0] == '#') {
        result.f_component = remaining[1..];
    }

    return result;
}

/// Resolve a URI reference against a base URI (RFC 3986 Section 5).
/// The returned Uri's path is always allocated and should be freed by the caller.
pub fn resolve(allocator: Allocator, base: Uri, reference: Uri) (ParseError || Allocator.Error)!Uri {
    var target: Uri = .{};

    if (reference.scheme != null) {
        // Reference has scheme - use reference as-is
        target.scheme = reference.scheme;
        target.userinfo = reference.userinfo;
        target.host = reference.host;
        target.port = reference.port;
        target.raw_port = reference.raw_port;
        target.path = try removeDotSegments(allocator, reference.path);
        target.query = reference.query;
    } else {
        if (reference.host != null) {
            // Reference has authority
            target.userinfo = reference.userinfo;
            target.host = reference.host;
            target.port = reference.port;
            target.raw_port = reference.raw_port;
            target.path = try removeDotSegments(allocator, reference.path);
            target.query = reference.query;
        } else {
            if (reference.path.len == 0) {
                // Empty reference path - use base path (allocate copy)
                target.path = try removeDotSegments(allocator, base.path);
                if (reference.query != null) {
                    target.query = reference.query;
                } else {
                    target.query = base.query;
                }
            } else {
                if (reference.path[0] == '/') {
                    target.path = try removeDotSegments(allocator, reference.path);
                } else {
                    // Merge paths
                    const merged = try mergePaths(allocator, base, reference.path);
                    target.path = try removeDotSegments(allocator, merged);
                    allocator.free(merged);
                }
                target.query = reference.query;
            }
            target.userinfo = base.userinfo;
            target.host = base.host;
            target.port = base.port;
            target.raw_port = base.raw_port;
        }
        target.scheme = base.scheme;
    }

    target.fragment = reference.fragment;

    return target;
}

/// Merge base and reference paths (RFC 3986 Section 5.2.3).
fn mergePaths(allocator: Allocator, base: Uri, ref_path: []const u8) Allocator.Error![]u8 {
    if (base.host != null and base.path.len == 0) {
        // Base has authority and empty path
        const result = try allocator.alloc(u8, 1 + ref_path.len);
        result[0] = '/';
        @memcpy(result[1..], ref_path);
        return result;
    } else {
        // Remove everything after last '/' in base path
        var last_slash: usize = 0;
        for (base.path, 0..) |c, i| {
            if (c == '/') last_slash = i + 1;
        }
        const base_dir = base.path[0..last_slash];
        const result = try allocator.alloc(u8, base_dir.len + ref_path.len);
        @memcpy(result[0..base_dir.len], base_dir);
        @memcpy(result[base_dir.len..], ref_path);
        return result;
    }
}

/// Remove dot segments from a path (RFC 3986 Section 5.2.4).
pub fn removeDotSegments(allocator: Allocator, path: []const u8) Allocator.Error![]u8 {
    if (path.len == 0) {
        return try allocator.dupe(u8, "");
    }

    var output = std.array_list.Managed(u8).init(allocator);
    errdefer output.deinit();

    var input = path;

    while (input.len > 0) {
        // A: Remove prefix "../" or "./"
        if (mem.startsWith(u8, input, "../")) {
            input = input[3..];
            continue;
        }
        if (mem.startsWith(u8, input, "./")) {
            input = input[2..];
            continue;
        }

        // B: Remove prefix "/./" or "/."(end)
        if (mem.startsWith(u8, input, "/./")) {
            input = input[2..];
            continue;
        }
        if (mem.eql(u8, input, "/.")) {
            input = "/";
            continue;
        }

        // C: Remove prefix "/../" or "/.."(end) and remove last output segment
        if (mem.startsWith(u8, input, "/../")) {
            input = input[3..];
            removeLastSegment(&output);
            continue;
        }
        if (mem.eql(u8, input, "/..")) {
            input = "/";
            removeLastSegment(&output);
            continue;
        }

        // D: Remove "." or ".." if that's all that's left
        if (mem.eql(u8, input, ".") or mem.eql(u8, input, "..")) {
            break;
        }

        // E: Move first path segment (including initial "/" if any) to output
        var seg_end: usize = 0;
        if (input[0] == '/') seg_end = 1;
        while (seg_end < input.len and input[seg_end] != '/') : (seg_end += 1) {}

        try output.appendSlice(input[0..seg_end]);
        input = input[seg_end..];
    }

    return try output.toOwnedSlice();
}

/// Remove the last segment from the output buffer.
fn removeLastSegment(output: *std.array_list.Managed(u8)) void {
    // Find last '/'
    var i = output.items.len;
    while (i > 0) {
        i -= 1;
        if (output.items[i] == '/') {
            output.shrinkRetainingCapacity(i);
            return;
        }
    }
    // No '/' found, clear everything
    output.clearRetainingCapacity();
}

/// Normalize a URI (RFC 3986 Section 6).
pub fn normalize(allocator: Allocator, uri_input: Uri) (ParseError || Allocator.Error)!Uri {
    var result = try uri_input.dupe(allocator);

    // Case normalization - scheme and host to lowercase
    if (result.scheme) |s| {
        const lower = try allocator.alloc(u8, s.len);
        for (s, 0..) |c, i| {
            lower[i] = ascii.toLower(c);
        }
        allocator.free(result.scheme.?);
        result.scheme = lower;
    }

    if (result.host) |h| {
        // Don't lowercase IPv6 addresses
        if (h.len > 0 and h[0] != '[') {
            const lower = try allocator.alloc(u8, h.len);
            for (h, 0..) |c, i| {
                lower[i] = ascii.toLower(c);
            }
            allocator.free(result.host.?);
            result.host = lower;
        }
    }

    // Path normalization - remove dot segments
    const normalized_path = try removeDotSegments(allocator, result.path);
    allocator.free(result.path);
    result.path = normalized_path;

    return result;
}

/// Check if a string is a valid URI.
pub fn isValid(input: []const u8) bool {
    _ = parse(input) catch return false;
    return true;
}

/// Check if a URI is absolute.
pub fn isAbsolute(input: []const u8) bool {
    const parsed = parse(input) catch return false;
    return parsed.isAbsolute();
}

/// Check if a URI is a relative reference.
pub fn isRelative(input: []const u8) bool {
    const parsed = parse(input) catch return false;
    return parsed.isRelative();
}

/// Get the default port for common schemes.
pub fn defaultPort(scheme: []const u8) ?u16 {
    const ports = .{
        .{ "http", 80 },
        .{ "https", 443 },
        .{ "ftp", 21 },
        .{ "ssh", 22 },
        .{ "telnet", 23 },
        .{ "smtp", 25 },
        .{ "dns", 53 },
        .{ "gopher", 70 },
        .{ "finger", 79 },
        .{ "pop3", 110 },
        .{ "nntp", 119 },
        .{ "imap", 143 },
        .{ "snmp", 161 },
        .{ "ldap", 389 },
        .{ "rtsp", 554 },
        .{ "sip", 5060 },
        .{ "sips", 5061 },
        .{ "xmpp", 5222 },
        .{ "ws", 80 },
        .{ "wss", 443 },
    };

    // Case-insensitive comparison
    inline for (ports) |entry| {
        if (ascii.eqlIgnoreCase(scheme, entry[0])) {
            return entry[1];
        }
    }

    return null;
}

// =============================================================================
// Percent-Encoding (RFC 3986 Section 2.1)
// =============================================================================

/// Characters that are unreserved and don't need encoding.
/// unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"
fn isUnreserved(c: u8) bool {
    return ascii.isAlphanumeric(c) or c == '-' or c == '.' or c == '_' or c == '~';
}

/// Reserved sub-delimiters (RFC 3986 Section 2.2)
fn isSubDelims(c: u8) bool {
    return switch (c) {
        '!', '$', '&', '\'', '(', ')', '*', '+', ',', ';', '=' => true,
        else => false,
    };
}

/// Reserved general delimiters (RFC 3986 Section 2.2)
fn isGenDelims(c: u8) bool {
    return switch (c) {
        ':', '/', '?', '#', '[', ']', '@' => true,
        else => false,
    };
}

/// Characters allowed within a path segment (RFC 3986 Section 3.3)
fn isPchar(c: u8) bool {
    return isUnreserved(c) or isSubDelims(c) or c == ':' or c == '@';
}

fn isAllowedInComponent(c: u8, component: Component) bool {
    if (c >= 0x80) return false;

    return switch (component) {
        .scheme => ascii.isAlphanumeric(c) or c == '+' or c == '-' or c == '.',
        .userinfo => isUnreserved(c) or isSubDelims(c) or c == ':',
        .host => isUnreserved(c) or isSubDelims(c) or c == ':' or c == '[' or c == ']',
        .port => ascii.isDigit(c),
        .path => isPchar(c) or c == '/',
        .query => isPchar(c) or c == '/' or c == '?',
        .fragment => isPchar(c) or c == '/' or c == '?',
    };
}

fn validateInput(input: []const u8, options: ParseOptions) ParseError!void {
    if (!options.strict) return;

    var i: usize = 0;
    while (i < input.len) {
        const c = input[i];
        if (c == '%') {
            if (i + 2 >= input.len) return ParseError.InvalidPercentEncoding;
            _ = hexValue(input[i + 1]) orelse return ParseError.InvalidPercentEncoding;
            _ = hexValue(input[i + 2]) orelse return ParseError.InvalidPercentEncoding;
            i += 3;
            continue;
        }

        if (c == ' ') {
            if (options.allow_spaces) {
                i += 1;
                continue;
            }
            return ParseError.InvalidCharacter;
        }

        if (c >= 0x80) {
            if (options.iri_mode) {
                i += 1;
                continue;
            }
            return ParseError.InvalidCharacter;
        }

        if (isUnreserved(c) or isSubDelims(c) or isGenDelims(c)) {
            i += 1;
            continue;
        }

        return ParseError.InvalidCharacter;
    }
}

/// Percent-encode a string for the specified URI component.
pub fn percentEncode(allocator: Allocator, input: []const u8, component: Component) Allocator.Error![]u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    errdefer result.deinit();

    for (input) |c| {
        if (isAllowedInComponent(c, component)) {
            try result.append(c);
        } else {
            try result.append('%');
            try result.append(hexDigit(@as(u4, @truncate(c >> 4))));
            try result.append(hexDigit(@as(u4, @truncate(c & 0x0F))));
        }
    }

    return try result.toOwnedSlice();
}

/// Decode a percent-encoded string.
pub fn percentDecode(allocator: Allocator, input: []const u8) (ParseError || Allocator.Error)![]u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '%') {
            if (i + 2 >= input.len) {
                return ParseError.InvalidPercentEncoding;
            }
            const hi = hexValue(input[i + 1]) orelse return ParseError.InvalidPercentEncoding;
            const lo = hexValue(input[i + 2]) orelse return ParseError.InvalidPercentEncoding;
            try result.append((@as(u8, hi) << 4) | @as(u8, lo));
            i += 3;
        } else {
            try result.append(input[i]);
            i += 1;
        }
    }

    return try result.toOwnedSlice();
}

fn hexDigit(val: u4) u8 {
    return "0123456789ABCDEF"[val];
}

fn hexValue(c: u8) ?u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'A'...'F' => @intCast(c - 'A' + 10),
        'a'...'f' => @intCast(c - 'a' + 10),
        else => null,
    };
}

// =============================================================================
// Tests
// =============================================================================

test "parse basic URI" {
    const uri_result = try parse("https://example.com/path");
    try std.testing.expectEqualStrings("https", uri_result.scheme.?);
    try std.testing.expectEqualStrings("example.com", uri_result.host.?);
    try std.testing.expectEqualStrings("/path", uri_result.path);
}

test "parse full URI with all components" {
    const uri_result = try parse("https://user:pass@example.com:8080/path/to/resource?query=value&foo=bar#fragment");
    try std.testing.expectEqualStrings("https", uri_result.scheme.?);
    try std.testing.expectEqualStrings("user:pass", uri_result.userinfo.?);
    try std.testing.expectEqualStrings("example.com", uri_result.host.?);
    try std.testing.expectEqual(@as(u16, 8080), uri_result.port.?);
    try std.testing.expectEqualStrings("/path/to/resource", uri_result.path);
    try std.testing.expectEqualStrings("query=value&foo=bar", uri_result.query.?);
    try std.testing.expectEqualStrings("fragment", uri_result.fragment.?);
}

test "parse URI without scheme (relative reference)" {
    const uri_result = try parse("/path/to/resource?query#frag");
    try std.testing.expect(uri_result.scheme == null);
    try std.testing.expectEqualStrings("/path/to/resource", uri_result.path);
    try std.testing.expectEqualStrings("query", uri_result.query.?);
    try std.testing.expectEqualStrings("frag", uri_result.fragment.?);
}

test "parse URI with IPv6 host" {
    const uri_result = try parse("http://[::1]:8080/path");
    try std.testing.expectEqualStrings("[::1]", uri_result.host.?);
    try std.testing.expectEqual(@as(u16, 8080), uri_result.port.?);
}

test "parse scheme-only URI" {
    const uri_result = try parse("mailto:user@example.com");
    try std.testing.expectEqualStrings("mailto", uri_result.scheme.?);
    try std.testing.expectEqualStrings("user@example.com", uri_result.path);
}

test "parse empty URI" {
    const uri_result = try parse("");
    try std.testing.expect(uri_result.scheme == null);
    try std.testing.expectEqualStrings("", uri_result.path);
}

test "isAbsolute and isRelative" {
    try std.testing.expect(isAbsolute("https://example.com"));
    try std.testing.expect(!isAbsolute("/path/to/resource"));
    try std.testing.expect(isRelative("/path/to/resource"));
    try std.testing.expect(!isRelative("https://example.com"));
}

test "defaultPort" {
    try std.testing.expectEqual(@as(?u16, 80), defaultPort("http"));
    try std.testing.expectEqual(@as(?u16, 443), defaultPort("https"));
    try std.testing.expectEqual(@as(?u16, 443), defaultPort("HTTPS"));
    try std.testing.expectEqual(@as(?u16, 22), defaultPort("ssh"));
    try std.testing.expect(defaultPort("unknown") == null);
}

test "percentEncode" {
    const allocator = std.testing.allocator;
    const encoded = try percentEncode(allocator, "hello world!", .path);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("hello%20world%21", encoded);
}

test "percentDecode" {
    const allocator = std.testing.allocator;
    const decoded = try percentDecode(allocator, "hello%20world%21");
    defer allocator.free(decoded);
    try std.testing.expectEqualStrings("hello world!", decoded);
}

test "removeDotSegments" {
    const allocator = std.testing.allocator;

    // RFC 3986 Section 5.2.4 examples
    const test_cases = .{
        .{ "/a/b/c/./../../g", "/a/g" },
        .{ "mid/content=5/../6", "mid/6" },
        .{ "/../a", "/a" },
        .{ "/a/b/c/../d", "/a/b/d" },
        .{ "/a/b/../../../c", "/c" },
    };

    inline for (test_cases) |tc| {
        const result = try removeDotSegments(allocator, tc[0]);
        defer allocator.free(result);
        try std.testing.expectEqualStrings(tc[1], result);
    }
}

test "Uri.format" {
    const uri_result = try parse("https://user:pass@example.com:8080/path?query#frag");

    var buf: [256]u8 = undefined;
    const formatted = try std.fmt.bufPrint(&buf, "{f}", .{uri_result});

    try std.testing.expectEqualStrings("https://user:pass@example.com:8080/path?query#frag", formatted);
}

test "parse URN basic" {
    const uri_result = try parse("urn:isbn:0451450523");
    try std.testing.expectEqualStrings("urn", uri_result.scheme.?);
    try std.testing.expect(uri_result.isUrn());
    try std.testing.expectEqualStrings("isbn", uri_result.urn.?.nid.?);
    try std.testing.expectEqualStrings("0451450523", uri_result.urn.?.nss.?);
}

test "parse URN with components" {
    const uri_result = try parse("urn:example:foo-bar-baz?+resolver?=query#frag");
    try std.testing.expectEqualStrings("urn", uri_result.scheme.?);
    try std.testing.expect(uri_result.isUrn());
    try std.testing.expectEqualStrings("example", uri_result.urn.?.nid.?);
    try std.testing.expectEqualStrings("foo-bar-baz", uri_result.urn.?.nss.?);
    try std.testing.expectEqualStrings("resolver", uri_result.urn.?.r_component.?);
    try std.testing.expectEqualStrings("query", uri_result.urn.?.q_component.?);
    try std.testing.expectEqualStrings("frag", uri_result.urn.?.f_component.?);
}

test "parse URN uuid" {
    const uri_result = try parse("urn:uuid:f81d4fae-7dec-11d0-a765-00a0c91e6bf6");
    try std.testing.expectEqualStrings("urn", uri_result.scheme.?);
    try std.testing.expectEqualStrings("uuid", uri_result.urn.?.nid.?);
    try std.testing.expectEqualStrings("f81d4fae-7dec-11d0-a765-00a0c91e6bf6", uri_result.urn.?.nss.?);
}

test "parse URI with port preserves raw_port" {
    const uri_result = try parse("http://example.com:8080/path");
    try std.testing.expectEqual(@as(u16, 8080), uri_result.port.?);
    try std.testing.expectEqualStrings("8080", uri_result.raw_port.?);
}

test "resolve: reference with authority propagates raw_port" {
    const allocator = std.testing.allocator;
    const base = try parse("http://example.com/a/b");
    const reference = try parse("//other.com:9000/path");

    const resolved = try resolve(allocator, base, reference);
    defer allocator.free(resolved.path);

    try std.testing.expectEqualStrings("other.com", resolved.host.?);
    try std.testing.expectEqual(@as(u16, 9000), resolved.port.?);
    try std.testing.expectEqualStrings("9000", resolved.raw_port.?);
    try std.testing.expectEqualStrings("/path", resolved.path);
}

test "resolve: reference with scheme propagates raw_port" {
    const allocator = std.testing.allocator;
    const base = try parse("http://example.com:8080/a/b");
    const reference = try parse("https://secure.com:443/new/path");

    const resolved = try resolve(allocator, base, reference);
    defer allocator.free(resolved.path);

    try std.testing.expectEqualStrings("https", resolved.scheme.?);
    try std.testing.expectEqualStrings("secure.com", resolved.host.?);
    try std.testing.expectEqual(@as(u16, 443), resolved.port.?);
    try std.testing.expectEqualStrings("443", resolved.raw_port.?);
}

test "resolve: inherits base raw_port when reference has no authority" {
    const allocator = std.testing.allocator;
    const base = try parse("http://example.com:3000/a/b/c");
    const reference = try parse("../d");

    const resolved = try resolve(allocator, base, reference);
    defer allocator.free(resolved.path);

    try std.testing.expectEqualStrings("example.com", resolved.host.?);
    try std.testing.expectEqual(@as(u16, 3000), resolved.port.?);
    try std.testing.expectEqualStrings("3000", resolved.raw_port.?);
    try std.testing.expectEqualStrings("/a/d", resolved.path);
}

test "resolve: query-only reference inherits base raw_port" {
    const allocator = std.testing.allocator;
    const base = try parse("http://example.com:8000/path");
    const reference = try parse("?newquery");

    const resolved = try resolve(allocator, base, reference);
    defer allocator.free(resolved.path);

    try std.testing.expectEqualStrings("example.com", resolved.host.?);
    try std.testing.expectEqual(@as(u16, 8000), resolved.port.?);
    try std.testing.expectEqualStrings("8000", resolved.raw_port.?);
    try std.testing.expectEqualStrings("newquery", resolved.query.?);
}

test "resolve: base without port results in null raw_port" {
    const allocator = std.testing.allocator;
    const base = try parse("http://example.com/a/b");
    const reference = try parse("../c");

    const resolved = try resolve(allocator, base, reference);
    defer allocator.free(resolved.path);

    try std.testing.expectEqualStrings("example.com", resolved.host.?);
    try std.testing.expect(resolved.port == null);
    try std.testing.expect(resolved.raw_port == null);
}
