# API Reference

Complete API reference for the URI library.

> **Related Issues:** [#20 - API Documentation](https://gitlab.com/devnw/zig/uri/-/issues/20)

## Table of Contents

- [Types](#types)
- [Parsing Functions](#parsing-functions)
- [Resolution Functions](#resolution-functions)
- [Normalization Functions](#normalization-functions)
- [Encoding Functions](#encoding-functions)
- [Utility Functions](#utility-functions)
- [Registry](#registry)
- [Debug Utilities](#debug-utilities)

## Types

### Uri

The main parsed URI structure. When returned by `parse()`, string fields are
borrowed slices into the original input (zero-copy). When returned by
`resolve()`, `normalize()`, or `dupe()`, all string fields are independently
allocated copies and `owned` is `true` -- the caller must call `deinit()` to
free the memory.

```zig
pub const Uri = struct {
    /// The scheme component (e.g., "http", "https", "file")
    scheme: ?[]const u8 = null,

    /// The userinfo component (e.g., "user:password")
    userinfo: ?[]const u8 = null,

    /// The host component (e.g., "example.com", "[::1]")
    host: ?[]const u8 = null,

    /// The port number (e.g., 80, 443, 8080)
    port: ?u16 = null,

    /// The path component (never null, may be empty)
    path: []const u8 = "",

    /// The query component without leading '?'
    query: ?[]const u8 = null,

    /// The fragment component without leading '#'
    fragment: ?[]const u8 = null,

    /// URN components (if scheme is "urn")
    urn: ?UrnComponents = null,

    /// Raw port string before parsing to integer
    raw_port: ?[]const u8 = null,

    /// Original input string
    raw: []const u8 = "",

    /// Whether this Uri owns its string memory.
    /// When true (from resolve/normalize/dupe), deinit() frees all fields.
    /// When false (from parse), fields are borrowed and deinit() is a no-op.
    owned: bool = false,
};
```

#### Methods

| Method | Description |
|--------|-------------|
| `isAbsolute()` | Returns true if URI has a scheme |
| `isRelative()` | Returns true if URI has no scheme |
| `hasAuthority()` | Returns true if URI has a host |
| `isUrn()` | Returns true if scheme is "urn" |
| `authority()` | Returns the authority component as a string |
| `format(writer)` | Writes URI to a writer (Zig 0.16 custom format; use `"{f}"`) |
| `dupe(allocator)` | Creates an owned copy with allocated memory |
| `deinit(allocator)` | Frees an owned URI's memory |

### UrnComponents

Components for URN (RFC 8141) parsing.

```zig
pub const UrnComponents = struct {
    nid: ?[]const u8 = null,        // Namespace Identifier
    nss: ?[]const u8 = null,        // Namespace Specific String
    r_component: ?[]const u8 = null, // Resolution component (?+...)
    q_component: ?[]const u8 = null, // Query component (?=...)
    f_component: ?[]const u8 = null, // Fragment component (#...)
};
```

### ParseError

Errors that can occur during parsing.

```zig
pub const ParseError = error{
    InvalidCharacter,
    InvalidPercentEncoding,
    InvalidScheme,
    InvalidPort,
    PortOutOfRange,
    InvalidHost,
    UnclosedIPv6Bracket,
    OutOfMemory,
    InputTooLong,
};
```

- `InputTooLong`: Input exceeds the configured `max_input_len` limit

### Component

URI component types for targeted encoding operations.

```zig
pub const Component = enum {
    scheme,
    userinfo,
    host,
    port,
    path,
    query,
    fragment,
};
```

## Parsing Functions

### parse

```zig
pub fn parse(input: []const u8) ParseError!Uri
```

Parse a URI string into its components.

**Example:**

```zig
const uri = @import("uri");

const result = try uri.parse("https://user:pass@example.com:8080/path?query#frag");
// result.scheme = "https"
// result.userinfo = "user:pass"
// result.host = "example.com"
// result.port = 8080
// result.path = "/path"
// result.query = "query"
// result.fragment = "frag"
```

### parseWithOptions

```zig
pub fn parseWithOptions(input: []const u8, options: ParseOptions) ParseError!Uri
```

Parse a URI with configurable validation mode.

- `strict = true` validates RFC 3986 character rules and percent-encoding.
- `allow_spaces = true` permits literal spaces in the input.
- `iri_mode = true` allows non-ASCII bytes (RFC 3987 style input).

### ParseOptions

```zig
pub const ParseOptions = struct {
    strict: bool = true,
    allow_spaces: bool = false,
    iri_mode: bool = false,
    max_input_len: ?usize = null,
};
```

- `strict`: Enable full RFC 3986 character validation (default: `true`)
- `allow_spaces`: Accept unencoded spaces in URI components (default: `false`)
- `iri_mode`: Accept valid UTF-8 sequences per RFC 3987 (default: `false`)
- `max_input_len`: Maximum input length in bytes; `null` for no limit (default: `null`)

## Resolution Functions

### resolve

```zig
pub fn resolve(allocator: Allocator, base: Uri, reference: Uri) !Uri
```

Resolve a URI reference against a base URI (RFC 3986 Section 5).

**Ownership:** The returned `Uri` has `owned = true`. All string fields (`scheme`,
`host`, `path`, `query`, `fragment`, `userinfo`, `raw_port`, `raw`) are
independently allocated copies. The caller must call `deinit()` to free the
memory. Because all fields are owned, the resolved URI remains valid even after
the base and reference URIs go out of scope.

**Example:**

```zig
const base = try uri.parse("http://example.com/a/b/c");
const reference = try uri.parse("../d");
var resolved = try uri.resolve(allocator, base, reference);
defer resolved.deinit(allocator);
// resolved path = "/a/d"
```

### removeDotSegments

```zig
pub fn removeDotSegments(allocator: Allocator, path: []const u8) ![]u8
```

Remove dot segments from a path (RFC 3986 Section 5.2.4).

## Normalization Functions

### normalize

```zig
pub fn normalize(allocator: Allocator, uri_input: Uri) !Uri
```

Normalize a URI (RFC 3986 Section 6).

Normalizations applied:

1. Case normalization (scheme and host to lowercase)
2. Percent-encoding normalization (decode unreserved characters, uppercase hex digits)
3. Path segment normalization (remove dot segments)
4. Scheme-based normalization (remove default ports, ensure non-empty path with authority)

## Encoding Functions

### percentEncode

```zig
pub fn percentEncode(allocator: Allocator, input: []const u8, component: Component) ![]u8
```

Percent-encode a string for use in a URI component.

**Example:**

```zig
const encoded = try uri.percentEncode(allocator, "hello world!", .path);
defer allocator.free(encoded);
// encoded = "hello%20world%21"
```

### percentDecode

```zig
pub fn percentDecode(allocator: Allocator, input: []const u8) ![]u8
```

Decode a percent-encoded string.

**Example:**

```zig
const decoded = try uri.percentDecode(allocator, "hello%20world%21");
defer allocator.free(decoded);
// decoded = "hello world!"
```

## Utility Functions

### isValid

```zig
pub fn isValid(input: []const u8) bool
```

Check if a string is a valid URI.

### isAbsolute

```zig
pub fn isAbsolute(input: []const u8) bool
```

Check if a URI string is absolute (has a scheme).

### isRelative

```zig
pub fn isRelative(input: []const u8) bool
```

Check if a URI string is a relative reference.

### defaultPort

```zig
pub fn defaultPort(scheme: []const u8) ?u16
```

Get the default port for a scheme.

| Scheme | Port |
|--------|------|
| http | 80 |
| https | 443 |
| ftp | 21 |
| ssh | 22 |
| ws | 80 |
| wss | 443 |
| ... | ... |

## Registry

The registry provides document storage with fetch callback support.

### Registry

```zig
pub const Registry = struct {
    pub fn init(allocator: Allocator) Registry;
    pub fn initWithCaps(allocator: Allocator, caps: Caps) Registry;
    pub fn deinit(self: *Registry) void;

    pub fn setFetchCallback(self: *Registry, callback: FetchCallback) void;
    pub fn register(self: *Registry, uri: []const u8, content: []const u8, content_type: ?[]const u8) !void;
    pub fn get(self: *Registry, uri: []const u8, auto_fetch: bool) !*Resource;
    pub fn contains(self: *Registry, uri: []const u8) bool;
    pub fn remove(self: *Registry, uri: []const u8) bool;
    pub fn addAnchor(self: *Registry, uri: []const u8, name: []const u8, offset: usize, length: usize) !void;
    pub fn getAnchorContent(self: *Registry, uri: []const u8, anchor: []const u8) ![]const u8;
    pub fn stats(self: *Registry) struct { doc_count: usize, total_bytes: usize, anchor_count: usize };
};
```

### Caps

```zig
pub const Caps = struct {
    max_docs: usize = 1000,
    max_bytes: usize = 10 * 1024 * 1024, // 10 MB
    max_anchors: usize = 100,
    max_uri_len: usize = 2048,
    max_resolve_depth: usize = 10,
};
```

## Debug Utilities

### toJson

```zig
pub fn toJson(allocator: Allocator, uri: Uri) ![]u8
```

Generate deterministic JSON output for a URI (keys sorted alphabetically).

### toJsonPretty

```zig
pub fn toJsonPretty(allocator: Allocator, uri: Uri) ![]u8
```

Generate formatted multi-line JSON output.

### dump

```zig
pub fn dump(uri: Uri) void
```

Dump URI components to stderr for debugging.
