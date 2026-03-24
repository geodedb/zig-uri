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
    /// Unclosed bracket in IPv6 address
    UnclosedIPv6Bracket,
    /// Out of memory
    OutOfMemory,
    /// Input exceeds maximum allowed length
    InputTooLong,
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
    /// Maximum allowed input length in bytes. Null means no limit (default).
    max_input_len: ?usize = null,
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

    /// Whether this Uri owns its string memory (allocated via dupe/normalize/resolve).
    /// When true, deinit() will free all string fields.
    /// When false (e.g., after parse()), fields are borrowed slices and deinit() is a no-op.
    owned: bool = false,

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
        const scheme = if (self.scheme) |s| try allocator.dupe(u8, s) else null;
        errdefer if (scheme) |s| allocator.free(s);

        const userinfo = if (self.userinfo) |ui| try allocator.dupe(u8, ui) else null;
        errdefer if (userinfo) |ui| allocator.free(ui);

        const host = if (self.host) |h| try allocator.dupe(u8, h) else null;
        errdefer if (host) |h| allocator.free(h);

        const path = try allocator.dupe(u8, self.path);
        errdefer allocator.free(path);

        const query = if (self.query) |q| try allocator.dupe(u8, q) else null;
        errdefer if (query) |q| allocator.free(q);

        const fragment = if (self.fragment) |f| try allocator.dupe(u8, f) else null;
        errdefer if (fragment) |f| allocator.free(f);

        const raw_port = if (self.raw_port) |rp| try allocator.dupe(u8, rp) else null;
        errdefer if (raw_port) |rp| allocator.free(rp);

        const raw = try allocator.dupe(u8, self.raw);
        errdefer allocator.free(raw);

        var result = Uri{
            .scheme = scheme,
            .userinfo = userinfo,
            .host = host,
            .port = self.port,
            .path = path,
            .query = query,
            .fragment = fragment,
            .raw_port = raw_port,
            .raw = raw,
            .urn = null,
            .owned = true,
        };

        // Duplicate URN components if present
        if (self.urn) |urn| {
            const nid = if (urn.nid) |n| try allocator.dupe(u8, n) else null;
            errdefer if (nid) |n| allocator.free(n);

            const nss = if (urn.nss) |n| try allocator.dupe(u8, n) else null;
            errdefer if (nss) |n| allocator.free(n);

            const r_component = if (urn.r_component) |r| try allocator.dupe(u8, r) else null;
            errdefer if (r_component) |r| allocator.free(r);

            const q_component = if (urn.q_component) |q| try allocator.dupe(u8, q) else null;
            errdefer if (q_component) |q| allocator.free(q);

            const f_component = if (urn.f_component) |f| try allocator.dupe(u8, f) else null;

            result.urn = UrnComponents{
                .nid = nid,
                .nss = nss,
                .r_component = r_component,
                .q_component = q_component,
                .f_component = f_component,
            };
        }

        return result;
    }

    /// Free an owned URI's allocated memory.
    /// If the Uri is not owned (e.g., returned by parse()), this is a safe no-op.
    pub fn deinit(self: *Uri, allocator: Allocator) void {
        if (!self.owned) return;

        if (self.scheme) |s| allocator.free(s);
        if (self.userinfo) |ui| allocator.free(ui);
        if (self.host) |h| allocator.free(h);
        if (self.query) |q| allocator.free(q);
        if (self.fragment) |f| allocator.free(f);
        if (self.raw_port) |rp| allocator.free(rp);
        allocator.free(self.path);
        allocator.free(self.raw);

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
    if (options.max_input_len) |max_len| {
        if (input.len > max_len) return ParseError.InputTooLong;
    }
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

/// Locate the scheme delimiter in a URI string.
///
/// Scans `input` for a valid RFC 3986 scheme followed by a colon (`:`).
/// A valid scheme starts with an ASCII letter and is followed by any
/// combination of letters, digits, `+`, `-`, or `.`.
///
/// Returns the index of the colon that terminates the scheme (i.e., the
/// length of the scheme name), or `null` if no valid scheme is found.
///
/// An index is returned rather than a slice so the caller can decide
/// whether to slice `input[0..i]` for the scheme or `input[i+1..]` for the
/// remainder without an extra bounds check or redundant pointer.
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
    // RFC 3986 Section 3.2: use the LAST '@' to split userinfo from host,
    // since '@' may appear percent-encoded or literally within userinfo.
    if (std.mem.lastIndexOfScalar(u8, remaining, '@')) |at_pos| {
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
///
/// The returned `Uri` has `owned = true` -- all string fields (`scheme`, `host`,
/// `path`, `query`, `fragment`, `userinfo`, `raw_port`, `raw`) are independently
/// allocated copies. The caller is responsible for calling `deinit()` to free the
/// memory when the resolved URI is no longer needed.
///
/// Recommended usage pattern:
/// ```
/// var resolved = try uri.resolve(allocator, base, reference);
/// defer resolved.deinit(allocator);
/// ```
///
/// Because the resolved URI owns all of its memory, it remains valid even after
/// the base and reference URIs go out of scope or their backing strings are freed.
pub fn resolve(allocator: Allocator, base: Uri, reference: Uri) (ParseError || Allocator.Error)!Uri {
    // First, determine which source each field comes from (RFC 3986 Section 5.2.2)
    var src_scheme: ?[]const u8 = null;
    var src_userinfo: ?[]const u8 = null;
    var src_host: ?[]const u8 = null;
    var src_port: ?u16 = null;
    var src_raw_port: ?[]const u8 = null;
    var src_query: ?[]const u8 = null;
    var allocated_path: []u8 = undefined;

    if (reference.scheme != null) {
        // Reference has scheme - use reference as-is
        src_scheme = reference.scheme;
        src_userinfo = reference.userinfo;
        src_host = reference.host;
        src_port = reference.port;
        src_raw_port = reference.raw_port;
        allocated_path = if (pathHasDotSegments(reference.path))
            try removeDotSegments(allocator, reference.path)
        else
            try allocator.dupe(u8, reference.path);
        src_query = reference.query;
    } else {
        if (reference.host != null) {
            // Reference has authority
            src_userinfo = reference.userinfo;
            src_host = reference.host;
            src_port = reference.port;
            src_raw_port = reference.raw_port;
            allocated_path = if (pathHasDotSegments(reference.path))
                try removeDotSegments(allocator, reference.path)
            else
                try allocator.dupe(u8, reference.path);
            src_query = reference.query;
        } else {
            if (reference.path.len == 0) {
                // Empty reference path - use base path
                allocated_path = if (pathHasDotSegments(base.path))
                    try removeDotSegments(allocator, base.path)
                else
                    try allocator.dupe(u8, base.path);
                if (reference.query != null) {
                    src_query = reference.query;
                } else {
                    src_query = base.query;
                }
            } else {
                if (reference.path[0] == '/') {
                    allocated_path = if (pathHasDotSegments(reference.path))
                        try removeDotSegments(allocator, reference.path)
                    else
                        try allocator.dupe(u8, reference.path);
                } else {
                    // Merge paths -- mergePaths returns an owned buffer
                    const merged = try mergePaths(allocator, base, reference.path);
                    if (pathHasDotSegments(merged)) {
                        allocated_path = try removeDotSegments(allocator, merged);
                        allocator.free(merged);
                    } else {
                        // No dot segments: reuse the merged buffer directly
                        // instead of duplicating then freeing it
                        allocated_path = merged;
                    }
                }
                src_query = reference.query;
            }
            src_userinfo = base.userinfo;
            src_host = base.host;
            src_port = base.port;
            src_raw_port = base.raw_port;
        }
        src_scheme = base.scheme;
    }
    errdefer allocator.free(allocated_path);

    // Allocate owned copies of all borrowed string fields
    const owned_scheme = if (src_scheme) |s| try allocator.dupe(u8, s) else null;
    errdefer if (owned_scheme) |s| allocator.free(s);

    const owned_userinfo = if (src_userinfo) |ui| try allocator.dupe(u8, ui) else null;
    errdefer if (owned_userinfo) |ui| allocator.free(ui);

    const owned_host = if (src_host) |h| try allocator.dupe(u8, h) else null;
    errdefer if (owned_host) |h| allocator.free(h);

    const owned_query = if (src_query) |q| try allocator.dupe(u8, q) else null;
    errdefer if (owned_query) |q| allocator.free(q);

    const owned_fragment = if (reference.fragment) |f| try allocator.dupe(u8, f) else null;
    errdefer if (owned_fragment) |f| allocator.free(f);

    const owned_raw_port = if (src_raw_port) |rp| try allocator.dupe(u8, rp) else null;
    errdefer if (owned_raw_port) |rp| allocator.free(rp);

    const owned_raw = try allocator.dupe(u8, "");

    return Uri{
        .scheme = owned_scheme,
        .userinfo = owned_userinfo,
        .host = owned_host,
        .port = src_port,
        .path = allocated_path,
        .query = owned_query,
        .fragment = owned_fragment,
        .raw_port = owned_raw_port,
        .raw = owned_raw,
        .urn = null,
        .owned = true,
    };
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

/// Check whether a path contains dot segments that need removal.
/// Dot segments are "." and ".." path segments per RFC 3986 Section 5.2.4.
fn pathHasDotSegments(path: []const u8) bool {
    // Starts with "./" or "../"
    if (mem.startsWith(u8, path, "./") or mem.startsWith(u8, path, "../")) return true;
    // Is exactly "." or ".."
    if (mem.eql(u8, path, ".") or mem.eql(u8, path, "..")) return true;
    // Contains "/./" or "/../"
    if (mem.indexOf(u8, path, "/./") != null or mem.indexOf(u8, path, "/../") != null) return true;
    // Ends with "/." or "/.."
    if (mem.endsWith(u8, path, "/.") or mem.endsWith(u8, path, "/..")) return true;
    return false;
}

/// Remove dot segments from a path (RFC 3986 Section 5.2.4).
pub fn removeDotSegments(allocator: Allocator, path: []const u8) Allocator.Error![]u8 {
    if (path.len == 0) {
        return try allocator.alloc(u8, 0);
    }

    var output = std.array_list.Managed(u8).init(allocator);
    errdefer output.deinit();
    try output.ensureTotalCapacity(path.len);

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

/// Normalize percent-encoding in a URI component string (RFC 3986 Section 6.2.2.2).
///
/// - Decodes percent-encoded unreserved characters (ALPHA, DIGIT, '-', '.', '_', '~')
/// - Uppercases hex digits in percent-encoded sequences that remain encoded
fn normalizePercentEncoding(allocator: Allocator, input: []const u8) (ParseError || Allocator.Error)![]u8 {
    var result = std.array_list.Managed(u8).init(allocator);
    errdefer result.deinit();
    try result.ensureTotalCapacity(input.len);

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '%' and i + 2 < input.len) {
            const hi = hexValue(input[i + 1]) orelse {
                // Not a valid percent-encoding; copy literally
                try result.append(input[i]);
                i += 1;
                continue;
            };
            const lo = hexValue(input[i + 2]) orelse {
                try result.append(input[i]);
                i += 1;
                continue;
            };
            const decoded_byte = (@as(u8, hi) << 4) | @as(u8, lo);

            if (isUnreserved(decoded_byte)) {
                // Decode: unreserved characters should not be percent-encoded
                try result.append(decoded_byte);
            } else {
                // Keep encoded but uppercase the hex digits
                try result.append('%');
                try result.append(ascii.toUpper(input[i + 1]));
                try result.append(ascii.toUpper(input[i + 2]));
            }
            i += 3;
        } else {
            try result.append(input[i]);
            i += 1;
        }
    }

    return try result.toOwnedSlice();
}

/// Normalize a URI (RFC 3986 Section 6).
///
/// Applies the following normalizations:
/// - Case normalization: scheme and host to lowercase (Section 6.2.2.1)
/// - Percent-encoding normalization: decode unreserved, uppercase hex (Section 6.2.2.2)
/// - Path segment normalization: remove dot segments (Section 6.2.2.3)
/// - Scheme-based normalization: remove default ports, ensure non-empty path (Section 6.2.3)
pub fn normalize(allocator: Allocator, uri_input: Uri) (ParseError || Allocator.Error)!Uri {
    var result = try uri_input.dupe(allocator);
    errdefer result.deinit(allocator);

    // Case normalization - scheme and host to lowercase (Section 6.2.2.1)
    // Since dupe() returns owned (allocated) buffers, we can lowercase in-place
    // without allocating new buffers and freeing the old ones.
    if (result.scheme) |s| {
        const mutable = @constCast(s);
        for (mutable) |*c| c.* = ascii.toLower(c.*);
    }

    if (result.host) |h| {
        // Don't lowercase IPv6 addresses
        if (h.len > 0 and h[0] != '[') {
            const mutable = @constCast(h);
            for (mutable) |*c| c.* = ascii.toLower(c.*);
        }
    }

    // Percent-encoding normalization (Section 6.2.2.2)
    // Apply to all string components that may contain percent-encoded sequences
    {
        const normalized = try normalizePercentEncoding(allocator, result.path);
        allocator.free(result.path);
        result.path = normalized;
    }
    if (result.query) |q| {
        const normalized = try normalizePercentEncoding(allocator, q);
        allocator.free(result.query.?);
        result.query = normalized;
    }
    if (result.fragment) |f| {
        const normalized = try normalizePercentEncoding(allocator, f);
        allocator.free(result.fragment.?);
        result.fragment = normalized;
    }
    if (result.userinfo) |ui| {
        const normalized = try normalizePercentEncoding(allocator, ui);
        allocator.free(result.userinfo.?);
        result.userinfo = normalized;
    }

    // Path normalization - remove dot segments (Section 6.2.2.3)
    {
        const normalized_path = try removeDotSegments(allocator, result.path);
        allocator.free(result.path);
        result.path = normalized_path;
    }

    // Scheme-based normalization (Section 6.2.3)
    if (result.scheme) |scheme| {
        // Remove default port if it matches the scheme's default
        if (result.port) |port| {
            if (defaultPort(scheme)) |dp| {
                if (port == dp) {
                    result.port = null;
                    if (result.raw_port) |rp| {
                        allocator.free(rp);
                        result.raw_port = null;
                    }
                }
            }
        }

        // Ensure path is "/" when authority is present and path is empty
        // (for schemes like http, https, ftp, etc.)
        if (result.host != null and result.path.len == 0) {
            allocator.free(result.path);
            result.path = try allocator.dupe(u8, "/");
        }
    }

    return result;
}

/// Check if a string is a valid URI.
pub fn isValid(input: []const u8) bool {
    _ = parse(input) catch return false;
    return true;
}

/// Check if a URI is absolute (has a scheme).
/// Uses a lightweight scan for the scheme prefix instead of a full parse.
/// RFC 3986 Section 3.1: scheme = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )
pub fn isAbsolute(input: []const u8) bool {
    if (input.len == 0) return false;
    // First character must be ALPHA
    if (!ascii.isAlphabetic(input[0])) return false;
    // Scan for ':' preceded only by valid scheme characters
    for (input[1..]) |c| {
        if (c == ':') return true;
        if (!ascii.isAlphanumeric(c) and c != '+' and c != '-' and c != '.') return false;
    }
    return false;
}

/// Check if a URI is a relative reference (has no scheme).
/// Uses a lightweight scan instead of a full parse.
pub fn isRelative(input: []const u8) bool {
    return !isAbsolute(input);
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
    // Always reject null bytes and control characters, even in lenient mode.
    // These are never valid in URIs under any specification (RFC 3986, RFC 3987, WHATWG).
    for (input) |c| {
        if (c <= 0x1F or c == 0x7F) {
            return ParseError.InvalidCharacter;
        }
    }

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
                // Validate proper UTF-8 sequence (RFC 3987 requires valid Unicode)
                const seq_len = utf8SequenceLength(c) orelse return ParseError.InvalidCharacter;
                if (i + seq_len > input.len) return ParseError.InvalidCharacter;
                // Verify all continuation bytes are 0x80-0xBF
                for (input[i + 1 .. i + seq_len]) |cont| {
                    if (cont & 0xC0 != 0x80) return ParseError.InvalidCharacter;
                }
                // Reject overlong encodings
                if (seq_len == 2 and c & 0x1E == 0) return ParseError.InvalidCharacter;
                if (seq_len == 3 and c == 0xE0 and input[i + 1] & 0x20 == 0) return ParseError.InvalidCharacter;
                if (seq_len == 4 and c == 0xF0 and input[i + 1] & 0x30 == 0) return ParseError.InvalidCharacter;
                i += seq_len;
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
    try result.ensureTotalCapacity(input.len);

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
    try result.ensureTotalCapacity(input.len);

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

/// Determine the expected length of a UTF-8 sequence from its leading byte.
/// Returns null for invalid leading bytes (continuation bytes 0x80-0xBF, or
/// bytes >= 0xF8 which are not valid UTF-8 leading bytes).
fn utf8SequenceLength(leading: u8) ?usize {
    if (leading & 0x80 == 0) return 1; // 0xxxxxxx: ASCII
    if (leading & 0xE0 == 0xC0) return 2; // 110xxxxx
    if (leading & 0xF0 == 0xE0) return 3; // 1110xxxx
    if (leading & 0xF8 == 0xF0) return 4; // 11110xxx
    return null; // continuation byte or invalid
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
    // RFC 3986: '!' is a sub-delim, allowed in paths without encoding
    const encoded = try percentEncode(allocator, "hello world!", .path);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("hello%20world!", encoded);
}
test "percentEncode path encodes space and preserves slash" {
    const allocator = std.testing.allocator;
    // Space is not allowed in path, must be encoded as %20.
    // Slash is allowed in path component (RFC 3986 Section 3.3).
    const encoded = try percentEncode(allocator, "hello world/page", .path);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("hello%20world/page", encoded);
}

test "percentEncode query component allows question mark and slash" {
    const allocator = std.testing.allocator;
    // RFC 3986 Section 3.4: query allows pchar / "/" / "?"
    // '?' and '/' should NOT be encoded in query.
    const encoded = try percentEncode(allocator, "key?value/other", .query);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("key?value/other", encoded);
}

test "percentEncode query component encodes hash and space" {
    const allocator = std.testing.allocator;
    // '#' is a gen-delim that starts a fragment, not allowed in query.
    // Space is never allowed unencoded.
    const encoded = try percentEncode(allocator, "q=hello world#bad", .query);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("q=hello%20world%23bad", encoded);
}

test "percentEncode userinfo component encodes at-sign" {
    const allocator = std.testing.allocator;
    // RFC 3986 Section 3.2.1: userinfo = *( unreserved / pct-encoded / sub-delims / ":" )
    // '@' is NOT in the allowed set for userinfo, so it must be encoded.
    const encoded = try percentEncode(allocator, "user@host", .userinfo);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("user%40host", encoded);
}

test "percentEncode userinfo component allows colon and sub-delims" {
    const allocator = std.testing.allocator;
    // ':' and sub-delims like '!' and '=' are allowed in userinfo.
    const encoded = try percentEncode(allocator, "user:pass!=ok", .userinfo);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("user:pass!=ok", encoded);
}

test "percentEncode fragment component allows slash and question mark" {
    const allocator = std.testing.allocator;
    // RFC 3986 Section 3.5: fragment allows pchar / "/" / "?"
    const encoded = try percentEncode(allocator, "section/sub?detail", .fragment);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("section/sub?detail", encoded);
}

test "percentEncode fragment component encodes hash and space" {
    const allocator = std.testing.allocator;
    // '#' is a gen-delim not in the fragment allowed set.
    const encoded = try percentEncode(allocator, "frag#inner space", .fragment);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("frag%23inner%20space", encoded);
}

test "percentEncode host component allows brackets and colon" {
    const allocator = std.testing.allocator;
    // RFC 3986 Section 3.2.2: host allows unreserved / sub-delims / ":" / "[" / "]"
    // '[', ']', ':' are needed for IPv6 literals like [::1].
    const encoded = try percentEncode(allocator, "[::1]", .host);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("[::1]", encoded);
}

test "percentEncode host component encodes at-sign and slash" {
    const allocator = std.testing.allocator;
    // '@' and '/' are not in the host allowed set and must be encoded.
    const encoded = try percentEncode(allocator, "host@evil/path", .host);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("host%40evil%2Fpath", encoded);
}

test "percentEncode scheme component allows alphanumeric plus minus dot" {
    const allocator = std.testing.allocator;
    // RFC 3986 Section 3.1: scheme = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )
    const encoded = try percentEncode(allocator, "my+scheme-1.0", .scheme);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("my+scheme-1.0", encoded);
}

test "percentEncode scheme component encodes disallowed characters" {
    const allocator = std.testing.allocator;
    // Characters like ':', '/', '@', '!' are not allowed in scheme.
    const encoded = try percentEncode(allocator, "http://x", .scheme);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("http%3A%2F%2Fx", encoded);
}

test "percentEncode port component allows only digits" {
    const allocator = std.testing.allocator;
    // RFC 3986 Section 3.2.3: port = *DIGIT
    const encoded = try percentEncode(allocator, "8080", .port);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("8080", encoded);
}

test "percentEncode port component encodes non-digit characters" {
    const allocator = std.testing.allocator;
    // Any non-digit character must be encoded in port component.
    const encoded = try percentEncode(allocator, "80ab", .port);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("80%61%62", encoded);
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

    var resolved = try resolve(allocator, base, reference);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("other.com", resolved.host.?);
    try std.testing.expectEqual(@as(u16, 9000), resolved.port.?);
    try std.testing.expectEqualStrings("9000", resolved.raw_port.?);
    try std.testing.expectEqualStrings("/path", resolved.path);
}

test "resolve: reference with scheme propagates raw_port" {
    const allocator = std.testing.allocator;
    const base = try parse("http://example.com:8080/a/b");
    const reference = try parse("https://secure.com:443/new/path");

    var resolved = try resolve(allocator, base, reference);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("https", resolved.scheme.?);
    try std.testing.expectEqualStrings("secure.com", resolved.host.?);
    try std.testing.expectEqual(@as(u16, 443), resolved.port.?);
    try std.testing.expectEqualStrings("443", resolved.raw_port.?);
}

test "resolve: inherits base raw_port when reference has no authority" {
    const allocator = std.testing.allocator;
    const base = try parse("http://example.com:3000/a/b/c");
    const reference = try parse("../d");

    var resolved = try resolve(allocator, base, reference);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("example.com", resolved.host.?);
    try std.testing.expectEqual(@as(u16, 3000), resolved.port.?);
    try std.testing.expectEqualStrings("3000", resolved.raw_port.?);
    try std.testing.expectEqualStrings("/a/d", resolved.path);
}

test "resolve: query-only reference inherits base raw_port" {
    const allocator = std.testing.allocator;
    const base = try parse("http://example.com:8000/path");
    const reference = try parse("?newquery");

    var resolved = try resolve(allocator, base, reference);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("example.com", resolved.host.?);
    try std.testing.expectEqual(@as(u16, 8000), resolved.port.?);
    try std.testing.expectEqualStrings("8000", resolved.raw_port.?);
    try std.testing.expectEqualStrings("newquery", resolved.query.?);
}

test "resolve: base without port results in null raw_port" {
    const allocator = std.testing.allocator;
    const base = try parse("http://example.com/a/b");
    const reference = try parse("../c");

    var resolved = try resolve(allocator, base, reference);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("example.com", resolved.host.?);
    try std.testing.expect(resolved.port == null);
    try std.testing.expect(resolved.raw_port == null);
}

// =============================================================================
// Ownership tracking tests
// =============================================================================

test "parse returns non-owned Uri, deinit is safe no-op" {
    const allocator = std.testing.allocator;
    var uri_result = try parse("https://user:pass@example.com:8080/path?query#frag");

    // Parsed URIs are not owned (zero-copy slices into input)
    try std.testing.expect(!uri_result.owned);

    // deinit on a non-owned Uri must be a safe no-op (no free calls, no mutations)
    uri_result.deinit(allocator);

    // Fields remain unchanged since deinit is a no-op for non-owned URIs
    try std.testing.expectEqualStrings("https", uri_result.scheme.?);
    try std.testing.expectEqualStrings("/path", uri_result.path);
}

test "dupe returns owned Uri, deinit frees all memory" {
    const allocator = std.testing.allocator;
    const parsed = try parse("https://user:pass@example.com:8080/path?query#frag");

    // dupe allocates owned copies of all fields
    var duped = try parsed.dupe(allocator);
    try std.testing.expect(duped.owned);

    // Verify fields match original
    try std.testing.expectEqualStrings("https", duped.scheme.?);
    try std.testing.expectEqualStrings("user:pass", duped.userinfo.?);
    try std.testing.expectEqualStrings("example.com", duped.host.?);
    try std.testing.expectEqual(@as(u16, 8080), duped.port.?);
    try std.testing.expectEqualStrings("/path", duped.path);
    try std.testing.expectEqualStrings("query", duped.query.?);
    try std.testing.expectEqualStrings("frag", duped.fragment.?);
    try std.testing.expectEqualStrings("8080", duped.raw_port.?);

    // deinit on owned Uri frees all memory (testing allocator detects leaks)
    duped.deinit(allocator);
}

test "normalize returns owned Uri, deinit frees all memory" {
    const allocator = std.testing.allocator;
    const parsed = try parse("HTTP://EXAMPLE.COM/a/b/../c");

    var normalized = try normalize(allocator, parsed);
    try std.testing.expect(normalized.owned);

    // Verify normalization occurred
    try std.testing.expectEqualStrings("http", normalized.scheme.?);
    try std.testing.expectEqualStrings("example.com", normalized.host.?);
    try std.testing.expectEqualStrings("/a/c", normalized.path);

    // deinit frees all memory (testing allocator detects leaks)
    normalized.deinit(allocator);
}

test "resolve returns owned Uri, deinit frees all memory" {
    const allocator = std.testing.allocator;
    const base = try parse("http://example.com/a/b/c");
    const reference = try parse("../d?q=1#f");

    var resolved = try resolve(allocator, base, reference);
    try std.testing.expect(resolved.owned);

    // Verify resolution
    try std.testing.expectEqualStrings("http", resolved.scheme.?);
    try std.testing.expectEqualStrings("example.com", resolved.host.?);
    try std.testing.expectEqualStrings("/a/d", resolved.path);
    try std.testing.expectEqualStrings("q=1", resolved.query.?);
    try std.testing.expectEqualStrings("f", resolved.fragment.?);

    // deinit frees all memory (testing allocator detects leaks)
    resolved.deinit(allocator);
}

test "dupe of empty path Uri is properly owned" {
    const allocator = std.testing.allocator;
    const parsed = try parse("http://example.com");

    // path is empty string, but dupe still allocates it
    var duped = try parsed.dupe(allocator);
    try std.testing.expect(duped.owned);
    try std.testing.expectEqualStrings("", duped.path);

    // deinit must free the empty allocated path without issues
    duped.deinit(allocator);
}

// =============================================================================
// Percent-encoding normalization tests (RFC 3986 Section 6.2.2.2)
// =============================================================================

test "normalize: percent-encoded unreserved ALPHA is decoded" {
    const allocator = std.testing.allocator;
    // %41 = 'A', which is unreserved (ALPHA)
    const parsed = try parse("http://example.com/%41%42%43");

    var normalized = try normalize(allocator, parsed);
    defer normalized.deinit(allocator);

    try std.testing.expectEqualStrings("/ABC", normalized.path);
}

test "normalize: percent-encoded tilde is decoded" {
    const allocator = std.testing.allocator;
    // %7E = '~', which is unreserved
    const parsed = try parse("http://example.com/%7e%7E");

    var normalized = try normalize(allocator, parsed);
    defer normalized.deinit(allocator);

    try std.testing.expectEqualStrings("/~~", normalized.path);
}

test "normalize: lowercase hex digits are uppercased for reserved chars" {
    const allocator = std.testing.allocator;
    // %2a = '*' which is a sub-delim (reserved), should stay encoded but uppercase hex
    const parsed = try parse("http://example.com/%2a");

    var normalized = try normalize(allocator, parsed);
    defer normalized.deinit(allocator);

    try std.testing.expectEqualStrings("/%2A", normalized.path);
}

test "normalize: space percent-encoding is preserved" {
    const allocator = std.testing.allocator;
    // %20 = space, not unreserved, should remain encoded
    const parsed = try parse("http://example.com/hello%20world");

    var normalized = try normalize(allocator, parsed);
    defer normalized.deinit(allocator);

    try std.testing.expectEqualStrings("/hello%20world", normalized.path);
}

test "normalize: mixed percent-encoding in query and fragment" {
    const allocator = std.testing.allocator;
    // %41 = 'A' (unreserved, decode), %3d = '=' (sub-delim/reserved, uppercase hex)
    const parsed = try parse("http://example.com/path?%41%3dval#%41frag");

    var normalized = try normalize(allocator, parsed);
    defer normalized.deinit(allocator);

    try std.testing.expectEqualStrings("A%3Dval", normalized.query.?);
    try std.testing.expectEqualStrings("Afrag", normalized.fragment.?);
}

test "normalize: percent-encoding normalization in userinfo" {
    const allocator = std.testing.allocator;
    // %75 = 'u' (unreserved ALPHA, decode)
    const parsed = try parse("http://%75ser@example.com/path");

    var normalized = try normalize(allocator, parsed);
    defer normalized.deinit(allocator);

    try std.testing.expectEqualStrings("user", normalized.userinfo.?);
}

// =============================================================================
// Scheme-based normalization tests (RFC 3986 Section 6.2.3)
// =============================================================================

test "normalize: removes default port 80 for http" {
    const allocator = std.testing.allocator;
    const parsed = try parse("http://example.com:80/path");

    var normalized = try normalize(allocator, parsed);
    defer normalized.deinit(allocator);

    try std.testing.expectEqualStrings("http", normalized.scheme.?);
    try std.testing.expectEqualStrings("example.com", normalized.host.?);
    try std.testing.expect(normalized.port == null);
    try std.testing.expect(normalized.raw_port == null);
    try std.testing.expectEqualStrings("/path", normalized.path);
}

test "normalize: removes default port 443 for https" {
    const allocator = std.testing.allocator;
    const parsed = try parse("https://example.com:443/");

    var normalized = try normalize(allocator, parsed);
    defer normalized.deinit(allocator);

    try std.testing.expectEqualStrings("https", normalized.scheme.?);
    try std.testing.expect(normalized.port == null);
    try std.testing.expect(normalized.raw_port == null);
    try std.testing.expectEqualStrings("/", normalized.path);
}

test "normalize: preserves non-default port" {
    const allocator = std.testing.allocator;
    const parsed = try parse("http://example.com:8080/");

    var normalized = try normalize(allocator, parsed);
    defer normalized.deinit(allocator);

    try std.testing.expectEqual(@as(u16, 8080), normalized.port.?);
    try std.testing.expectEqualStrings("8080", normalized.raw_port.?);
    try std.testing.expectEqualStrings("/", normalized.path);
}

test "normalize: removes default port 21 for ftp" {
    const allocator = std.testing.allocator;
    const parsed = try parse("ftp://example.com:21/");

    var normalized = try normalize(allocator, parsed);
    defer normalized.deinit(allocator);

    try std.testing.expectEqualStrings("ftp", normalized.scheme.?);
    try std.testing.expect(normalized.port == null);
    try std.testing.expect(normalized.raw_port == null);
    try std.testing.expectEqualStrings("/", normalized.path);
}

test "normalize: adds slash for empty path with authority" {
    const allocator = std.testing.allocator;
    const parsed = try parse("http://example.com");

    var normalized = try normalize(allocator, parsed);
    defer normalized.deinit(allocator);

    try std.testing.expectEqualStrings("http", normalized.scheme.?);
    try std.testing.expectEqualStrings("example.com", normalized.host.?);
    try std.testing.expectEqualStrings("/", normalized.path);
}

test "normalize: scheme-based normalization with uppercase scheme" {
    const allocator = std.testing.allocator;
    // Uppercase scheme should be lowered first, then default port matched
    const parsed = try parse("HTTP://EXAMPLE.COM:80/path");

    var normalized = try normalize(allocator, parsed);
    defer normalized.deinit(allocator);

    try std.testing.expectEqualStrings("http", normalized.scheme.?);
    try std.testing.expectEqualStrings("example.com", normalized.host.?);
    try std.testing.expect(normalized.port == null);
    try std.testing.expect(normalized.raw_port == null);
    try std.testing.expectEqualStrings("/path", normalized.path);
}

// =============================================================================
// ParseOptions Tests
// =============================================================================

test "parseWithOptions strict=false accepts angle brackets" {
    const uri_result = try parseWithOptions("data:text/html,<h1>Hello</h1>", .{ .strict = false });
    try std.testing.expectEqualStrings("data", uri_result.scheme.?);
    try std.testing.expectEqualStrings("text/html,<h1>Hello</h1>", uri_result.path);
}

test "parseWithOptions strict=true rejects angle brackets" {
    const result = parseWithOptions("data:text/html,<h1>Hello</h1>", .{});
    try std.testing.expectError(ParseError.InvalidCharacter, result);
}

test "parseWithOptions allow_spaces accepts spaces in strict mode" {
    const uri_result = try parseWithOptions("http://example.com/path with spaces", .{ .allow_spaces = true });
    try std.testing.expectEqualStrings("http", uri_result.scheme.?);
    try std.testing.expectEqualStrings("example.com", uri_result.host.?);
    try std.testing.expectEqualStrings("/path with spaces", uri_result.path);
}

test "parseWithOptions strict rejects spaces" {
    const result = parseWithOptions("http://example.com/path with spaces", .{});
    try std.testing.expectError(ParseError.InvalidCharacter, result);
}

test "parseWithOptions iri_mode accepts high bytes in strict mode" {
    const uri_result = try parseWithOptions("http://example.com/caf\xc3\xa9", .{ .iri_mode = true });
    try std.testing.expectEqualStrings("http", uri_result.scheme.?);
    try std.testing.expectEqualStrings("example.com", uri_result.host.?);
    try std.testing.expectEqualStrings("/caf\xc3\xa9", uri_result.path);
}

test "parseWithOptions strict rejects high bytes" {
    const result = parseWithOptions("http://example.com/caf\xc3\xa9", .{});
    try std.testing.expectError(ParseError.InvalidCharacter, result);
}

test "parseWithOptions strict=false accepts all non-standard characters" {
    // strict=false bypasses validateInput entirely, so any character is accepted
    const uri_result = try parseWithOptions("http://example.com/p a t h<>|\xc3\xa9", .{ .strict = false });
    try std.testing.expectEqualStrings("http", uri_result.scheme.?);
    try std.testing.expectEqualStrings("example.com", uri_result.host.?);
    try std.testing.expectEqualStrings("/p a t h<>|\xc3\xa9", uri_result.path);
}

test "parseWithOptions allow_spaces without iri_mode still rejects high bytes" {
    const result = parseWithOptions("http://example.com/path \xc3\xa9", .{ .allow_spaces = true });
    try std.testing.expectError(ParseError.InvalidCharacter, result);
}

test "parseWithOptions iri_mode without allow_spaces still rejects spaces" {
    const result = parseWithOptions("http://example.com/path name", .{ .iri_mode = true });
    try std.testing.expectError(ParseError.InvalidCharacter, result);
}

// =============================================================================
// Security Hardening Tests
// =============================================================================

test "null byte rejected even with strict=false" {
    const result = parseWithOptions("http://example.com/path\x00rest", .{ .strict = false });
    try std.testing.expectError(ParseError.InvalidCharacter, result);
}

test "control character rejected even with strict=false" {
    // Test several C0 control chars
    const result_tab = parseWithOptions("http://example.com/path\x09rest", .{ .strict = false });
    try std.testing.expectError(ParseError.InvalidCharacter, result_tab);

    const result_newline = parseWithOptions("http://example.com/path\x0Arest", .{ .strict = false });
    try std.testing.expectError(ParseError.InvalidCharacter, result_newline);

    const result_cr = parseWithOptions("http://example.com/path\x0Drest", .{ .strict = false });
    try std.testing.expectError(ParseError.InvalidCharacter, result_cr);

    const result_bell = parseWithOptions("http://example.com/path\x07rest", .{ .strict = false });
    try std.testing.expectError(ParseError.InvalidCharacter, result_bell);

    // DEL character (0x7F)
    const result_del = parseWithOptions("http://example.com/path\x7Frest", .{ .strict = false });
    try std.testing.expectError(ParseError.InvalidCharacter, result_del);
}

test "null byte rejected in strict mode" {
    const result = parseWithOptions("http://example.com/path\x00rest", .{ .strict = true });
    try std.testing.expectError(ParseError.InvalidCharacter, result);
}

test "valid UTF-8 in IRI mode accepted" {
    // U+00E9 (e-acute): 0xC3 0xA9 -- valid 2-byte sequence
    const result = try parseWithOptions("http://example.com/caf\xc3\xa9", .{ .iri_mode = true });
    try std.testing.expectEqualStrings("http", result.scheme.?);
    try std.testing.expectEqualStrings("example.com", result.host.?);
    try std.testing.expectEqualStrings("/caf\xc3\xa9", result.path);
}

test "valid 3-byte UTF-8 in IRI mode accepted" {
    // U+4E16 (Chinese character): 0xE4 0xB8 0x96
    const result = try parseWithOptions("http://example.com/\xe4\xb8\x96", .{ .iri_mode = true });
    try std.testing.expectEqualStrings("http", result.scheme.?);
    try std.testing.expectEqualStrings("/\xe4\xb8\x96", result.path);
}

test "valid 4-byte UTF-8 in IRI mode accepted" {
    // U+1F600 (grinning face): 0xF0 0x9F 0x98 0x80
    const result = try parseWithOptions("http://example.com/\xf0\x9f\x98\x80", .{ .iri_mode = true });
    try std.testing.expectEqualStrings("http", result.scheme.?);
    try std.testing.expectEqualStrings("/\xf0\x9f\x98\x80", result.path);
}

test "invalid UTF-8 sequence in IRI mode rejected - truncated 2-byte" {
    // 0xC3 without continuation byte
    const result = parseWithOptions("http://example.com/caf\xc3", .{ .iri_mode = true });
    try std.testing.expectError(ParseError.InvalidCharacter, result);
}

test "invalid UTF-8 sequence in IRI mode rejected - bad continuation" {
    // 0xC3 followed by non-continuation byte (0x28 = '(')
    const result = parseWithOptions("http://example.com/caf\xc3\x28", .{ .iri_mode = true });
    try std.testing.expectError(ParseError.InvalidCharacter, result);
}

test "invalid UTF-8 overlong encoding in IRI mode rejected" {
    // Overlong encoding of U+002F (/): 0xC0 0xAF
    const result = parseWithOptions("http://example.com/\xc0\xaf", .{ .iri_mode = true });
    try std.testing.expectError(ParseError.InvalidCharacter, result);
}

test "invalid UTF-8 sequence in IRI mode rejected - bare continuation byte" {
    // 0x80 is a continuation byte without a leading byte
    const result = parseWithOptions("http://example.com/\x80", .{ .iri_mode = true });
    try std.testing.expectError(ParseError.InvalidCharacter, result);
}

test "max_input_len rejects input exceeding limit" {
    const result = parseWithOptions("http://example.com/path", .{ .max_input_len = 10 });
    try std.testing.expectError(ParseError.InputTooLong, result);
}

test "max_input_len accepts input within limit" {
    const uri_result = try parseWithOptions("http://a.b", .{ .max_input_len = 100 });
    try std.testing.expectEqualStrings("http", uri_result.scheme.?);
}

test "max_input_len null means no limit" {
    // Default null should accept any length
    const uri_result = try parseWithOptions("http://example.com/path", .{});
    try std.testing.expectEqualStrings("http", uri_result.scheme.?);
}

test "max_input_len exact boundary accepted" {
    const input = "http://a.b";
    const uri_result = try parseWithOptions(input, .{ .max_input_len = input.len });
    try std.testing.expectEqualStrings("http", uri_result.scheme.?);
}

test "max_input_len one less than input rejected" {
    const input = "http://a.b";
    const result = parseWithOptions(input, .{ .max_input_len = input.len - 1 });
    try std.testing.expectError(ParseError.InputTooLong, result);
}

// =============================================================================
// Performance optimization verification tests
// =============================================================================

test "isAbsolute short-circuit: standard schemes" {
    try std.testing.expect(isAbsolute("http://example.com"));
    try std.testing.expect(isAbsolute("https://example.com"));
    try std.testing.expect(isAbsolute("ftp://files.example.com"));
    try std.testing.expect(isAbsolute("mailto:user@example.com"));
    try std.testing.expect(isAbsolute("urn:isbn:0451450523"));
    try std.testing.expect(isAbsolute("ssh://host/path"));
    try std.testing.expect(isAbsolute("custom+scheme.v2-beta:data"));
}

test "isAbsolute short-circuit: non-absolute inputs" {
    try std.testing.expect(!isAbsolute(""));
    try std.testing.expect(!isAbsolute("/path/to/resource"));
    try std.testing.expect(!isAbsolute("//authority/path"));
    try std.testing.expect(!isAbsolute("?query"));
    try std.testing.expect(!isAbsolute("#fragment"));
    try std.testing.expect(!isAbsolute("relative/path"));
    try std.testing.expect(!isAbsolute("123notscheme:data"));
    try std.testing.expect(!isAbsolute(":no-scheme"));
}

test "isRelative short-circuit: relative references" {
    try std.testing.expect(isRelative(""));
    try std.testing.expect(isRelative("/path"));
    try std.testing.expect(isRelative("//host/path"));
    try std.testing.expect(isRelative("relative"));
    try std.testing.expect(isRelative("?query"));
    try std.testing.expect(isRelative("#frag"));
}

test "isRelative short-circuit: absolute URIs are not relative" {
    try std.testing.expect(!isRelative("http://example.com"));
    try std.testing.expect(!isRelative("ftp://host"));
    try std.testing.expect(!isRelative("mailto:user@host"));
}

test "normalize in-place lowercasing preserves correct behavior" {
    const allocator = std.testing.allocator;

    // Mixed case scheme and host
    const parsed = try parse("HtTp://ExAmPlE.CoM:8080/Path?Query#Frag");
    var normalized = try normalize(allocator, parsed);
    defer normalized.deinit(allocator);

    try std.testing.expectEqualStrings("http", normalized.scheme.?);
    try std.testing.expectEqualStrings("example.com", normalized.host.?);
    // Path, query, fragment should NOT be lowered (case-sensitive)
    try std.testing.expectEqualStrings("/Path", normalized.path);
    try std.testing.expectEqualStrings("Query", normalized.query.?);
    try std.testing.expectEqualStrings("Frag", normalized.fragment.?);
}

test "normalize in-place lowercasing with IPv6 host" {
    const allocator = std.testing.allocator;

    // IPv6 host should NOT be lowercased
    const parsed = try parse("HTTP://[::1]:8080/path");
    var normalized = try normalize(allocator, parsed);
    defer normalized.deinit(allocator);

    try std.testing.expectEqualStrings("http", normalized.scheme.?);
    try std.testing.expectEqualStrings("[::1]", normalized.host.?);
}

test "resolve merge path reuses buffer when no dot segments" {
    const allocator = std.testing.allocator;

    // Relative path with no dots: merged buffer should be reused directly
    const base = try parse("http://example.com/a/b/c");
    const reference = try parse("d/e");

    var resolved = try resolve(allocator, base, reference);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("/a/b/d/e", resolved.path);
    try std.testing.expectEqualStrings("http", resolved.scheme.?);
    try std.testing.expectEqualStrings("example.com", resolved.host.?);
}

test "resolve merge path with dot segments still works correctly" {
    const allocator = std.testing.allocator;

    // Relative path with dots: requires removeDotSegments
    const base = try parse("http://example.com/a/b/c");
    const reference = try parse("../d");

    var resolved = try resolve(allocator, base, reference);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("/a/d", resolved.path);
}

test "resolve merge path with base authority and empty base path" {
    const allocator = std.testing.allocator;

    // Base has authority and empty path: merge prepends "/"
    const base = try parse("http://example.com");
    const reference = try parse("path");

    var resolved = try resolve(allocator, base, reference);
    defer resolved.deinit(allocator);

    try std.testing.expectEqualStrings("/path", resolved.path);
}

test "parseAuthority handles multiple @ in userinfo" {
    const result = try parse("http://user@host@example.com/path");
    try std.testing.expectEqualStrings("user@host", result.userinfo.?);
    try std.testing.expectEqualStrings("example.com", result.host.?);
    try std.testing.expectEqualStrings("/path", result.path);
}

test "parseAuthority handles single @ correctly" {
    const result = try parse("http://user:pass@example.com/path");
    try std.testing.expectEqualStrings("user:pass", result.userinfo.?);
    try std.testing.expectEqualStrings("example.com", result.host.?);
}

test "parseAuthority with no @" {
    const result = try parse("http://example.com/path");
    try std.testing.expect(result.userinfo == null);
    try std.testing.expectEqualStrings("example.com", result.host.?);
}

test "authority returns full authority string" {
    const result = try parse("http://user:pass@example.com:8080/path");
    const auth = result.authority();
    try std.testing.expect(auth != null);
    try std.testing.expectEqualStrings("user:pass@example.com:8080", auth.?);
}

test "authority returns null when no authority" {
    const result = try parse("urn:isbn:0451450523");
    try std.testing.expect(result.authority() == null);
}

test "authority with host only" {
    const result = try parse("http://example.com/path");
    const auth = result.authority();
    try std.testing.expect(auth != null);
    try std.testing.expectEqualStrings("example.com", auth.?);
}
