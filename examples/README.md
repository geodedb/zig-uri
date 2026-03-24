# URI Library Examples

This directory contains practical examples demonstrating the features of the RFC 3986 compliant URI library.

## Running Examples

Use `zig build` to build and run examples:

```bash
cd /path/to/uri

# Build all examples
zig build examples

# Run a specific example
zig build run-01_basic_parsing
zig build run-02_uri_resolution
zig build run-03_percent_encoding
zig build run-04_urn_parsing
zig build run-05_resource_registry
zig build run-06_normalization
zig build run-07_validation
zig build run-08_debug_output

# Run all examples
zig build run-examples
```

## Examples Overview

### 01_basic_parsing.zig

**Basic URI Parsing and Component Access**

Learn how to:

- Parse URIs with `uri.parse()`
- Access all URI components (scheme, host, port, path, query, fragment)
- Handle relative references
- Parse URIs with IPv6 hosts
- Get default ports for common schemes

### 02_uri_resolution.zig

**URI Reference Resolution (RFC 3986 Section 5)**

Learn how to:

- Resolve relative URIs against a base URI
- Handle all RFC 3986 resolution cases
- Build API endpoint URLs
- Resolve links on web pages

### 03_percent_encoding.zig

**Percent-Encoding and Decoding**

Learn how to:

- Encode strings for different URI components
- Decode percent-encoded strings
- Handle special characters properly
- Avoid double-encoding issues

### 04_urn_parsing.zig

**URN Parsing (RFC 8141)**

Learn how to:

- Parse Uniform Resource Names
- Access URN components (NID, NSS, r/q/f-components)
- Work with common URN namespaces (ISBN, UUID, IETF)
- Distinguish URNs from URLs

### 05_resource_registry.zig

**Resource Registry**

Learn how to:

- Store and retrieve resources by URI
- Work with named anchors in documents
- Configure capacity limits
- Handle registry errors

### 06_normalization.zig

**URI Normalization (RFC 3986 Section 6)**

Learn how to:

- Normalize URIs to canonical form
- Handle case normalization
- Remove dot segments from paths
- Compare equivalent URIs

### 07_validation.zig

**URI Validation Utilities**

Learn how to:

- Validate URI strings
- Check if URIs are absolute or relative
- Handle parse errors gracefully
- Build custom validation logic

### 08_debug_output.zig

**Debug Output Utilities**

Learn how to:

- Generate JSON output for URIs
- Use pretty-printed JSON for debugging
- Compare URIs using JSON representation
- Handle special character escaping

## Quick Reference

```zig
const uri = @import("uri");

// Parse a URI
const parsed = try uri.parse("https://example.com/path?query#frag");

// Access components
const scheme = parsed.scheme;       // "https"
const host = parsed.host;           // "example.com"
const path = parsed.path;           // "/path"
const query = parsed.query;         // "query"
const fragment = parsed.fragment;   // "frag"

// Resolve references
const base = try uri.parse("http://example.com/a/b/c");
const ref = try uri.parse("../d");
const resolved = try uri.resolve(allocator, base, ref);
defer allocator.free(resolved.path);

// Percent-encoding
const encoded = try uri.percentEncode(allocator, "hello world", .path);
defer allocator.free(encoded);  // "hello%20world"

const decoded = try uri.percentDecode(allocator, "hello%20world");
defer allocator.free(decoded);  // "hello world"

// Validation
const is_valid = uri.isValid("https://example.com");
const is_absolute = uri.isAbsolute("https://example.com");
const is_relative = uri.isRelative("/path");

// URN support
const urn = try uri.parse("urn:isbn:0451450523");
if (urn.urn) |u| {
    const nid = u.nid;  // "isbn"
    const nss = u.nss;  // "0451450523"
}

// Debug output
const json = try uri.toJson(allocator, parsed);
defer allocator.free(json);
uri.dump(parsed);  // Prints to stderr
```

## See Also

- [API Reference](../docs/API.md)
- [RFC Compliance](../docs/RFC_COMPLIANCE.md)
- [Main README](../README.md)
