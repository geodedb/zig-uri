// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! # URI - RFC 3986 Compliant URI/URL Parser for Zig
//!
//! A production-grade URI parsing and manipulation library strictly adhering to:
//! - RFC 3986 (Uniform Resource Identifier - Generic Syntax)
//! - RFC 3987 (Internationalized Resource Identifiers - IRIs)
//! - RFC 6874 (IPv6 Zone Identifiers in URIs)
//! - WHATWG URL Standard (for web compatibility)
//!
//! ## Features
//!
//! - **RFC-compliant**: Every component follows RFC 3986 grammar precisely
//! - **Zero dependencies**: Only uses Zig standard library
//! - **Memory-safe**: No allocations for parsing, zero-copy slicing
//! - **Cross-platform**: Works on all Zig-supported targets
//! - **Unicode support**: IRI parsing with proper encoding/decoding
//! - **URL normalization**: Case normalization, path simplification
//!
//! ## Quick Start
//!
//! ### Parsing a URI
//!
//! ```zig
//! const uri = @import("uri");
//!
//! // Parse a URI string
//! const parsed = try uri.parse("https://user:pass@example.com:8080/path?query=value#fragment");
//!
//! // Access components
//! std.debug.print("Scheme: {s}\n", .{parsed.scheme.?});        // "https"
//! std.debug.print("Host: {s}\n", .{parsed.host.?});            // "example.com"
//! std.debug.print("Port: {d}\n", .{parsed.port.?});            // 8080
//! std.debug.print("Path: {s}\n", .{parsed.path});              // "/path"
//! std.debug.print("Query: {s}\n", .{parsed.query.?});          // "query=value"
//! std.debug.print("Fragment: {s}\n", .{parsed.fragment.?});    // "fragment"
//! ```
//!
//! ### URI Reference Resolution (RFC 3986 Section 5)
//!
//! ```zig
//! const base = try uri.parse("http://example.com/a/b/c");
//! const reference = try uri.parse("../d");
//! const resolved = try uri.resolve(base, reference);
//! // Result: "http://example.com/a/d"
//! ```
//!
//! ### Percent-Encoding/Decoding
//!
//! ```zig
//! // Encode special characters
//! const encoded = try uri.percentEncode(allocator, "hello world!");
//! // Result: "hello%20world%21"
//!
//! // Decode percent-encoded strings
//! const decoded = try uri.percentDecode(allocator, "hello%20world%21");
//! // Result: "hello world!"
//! ```
//!
//! ## URI Components (RFC 3986 Section 3)
//!
//! ```
//!          foo://example.com:8042/over/there?name=ferret#nose
//!          \_/   \______________/\_________/ \_________/ \__/
//!           |           |            |            |        |
//!        scheme     authority       path        query   fragment
//!           |   _____________________|__
//!          / \ /                        \
//!          urn:example:animal:ferret:nose
//! ```
//!
//! The authority component further breaks down into:
//! ```
//!          userinfo       host          port
//!          ┌──┴───┐ ┌──────┴──────┐ ┌───┴───┐
//!          user:pass@www.example.com:8080
//! ```
//!
//! ## Memory Model
//!
//! The parser operates in zero-copy mode by default, returning slices into
//! the original input string. This means:
//!
//! - No memory allocation required for basic parsing
//! - The input string must outlive the parsed URI structure
//! - For owned copies, use `Uri.dupe(allocator)` or `Uri.format(allocator)`
//!
//! ## Validation Levels
//!
//! The library supports different validation modes:
//!
//! - **Strict**: Full RFC 3986 compliance, rejects invalid URIs
//! - **Lenient**: Accepts common deviations (unencoded spaces, etc.)
//! - **WHATWG**: Web browser URL parsing semantics
//!
//! ## RFC Compliance Matrix
//!
//! | RFC | Section | Feature | Status |
//! |-----|---------|---------|--------|
//! | RFC 3986 | 3 | URI syntax components | Implemented |
//! | RFC 3986 | 4 | URI reference | Implemented |
//! | RFC 3986 | 5 | Reference resolution | Implemented |
//! | RFC 3986 | 6 | Normalization | Implemented |
//! | RFC 3987 | 2 | IRI syntax | Planned |
//! | RFC 6874 | 2 | IPv6 Zone ID | Planned |
//! | WHATWG | - | URL Standard | Partial |
//!
//! ## License
//!
//! See LICENSE file in repository root.

const std = @import("std");

// =============================================================================
// Core URI Module
// =============================================================================

/// Core URI parsing and manipulation (RFC 3986).
pub const uri = @import("uri.zig");

/// URI Resource Registry with fetch callback support.
pub const registry = @import("registry.zig");

/// Debug output utilities for URI structures.
pub const debug = @import("debug.zig");

// =============================================================================
// Public Type Re-exports
// =============================================================================

/// Parsed URI structure with all components.
///
/// Components are optional slices into the original input string (zero-copy).
/// Use `.dupe()` to create an owned copy with allocated memory.
pub const Uri = uri.Uri;

/// URI parsing error types.
pub const ParseError = uri.ParseError;

/// URI component types for targeted operations.
pub const Component = uri.Component;

/// URN components for RFC 8141 support.
pub const UrnComponents = uri.UrnComponents;

/// Resource registry for managing URI documents.
pub const Registry = registry.Registry;

/// Registry capacity limits.
pub const Caps = registry.Caps;

// =============================================================================
// Primary API Functions
// =============================================================================

/// Parse a URI string into its components.
///
/// This is the main entry point for URI parsing. Returns a `Uri` structure
/// with slices pointing into the original input string.
///
/// ## Parameters
/// - `input`: The URI string to parse
///
/// ## Returns
/// A `Uri` structure on success, or a `ParseError` on failure.
///
/// ## Example
/// ```zig
/// const parsed = try parse("https://example.com/path");
/// std.debug.print("Host: {s}\n", .{parsed.host.?});
/// ```
///
/// ## RFC Reference
/// RFC 3986 Section 3 - Syntax Components
pub const parse = uri.parse;

/// Parse a URI with configurable validation mode.
pub const parseWithOptions = uri.parseWithOptions;

/// Resolve a URI reference against a base URI (RFC 3986 Section 5).
///
/// Implements the reference resolution algorithm to produce a target URI
/// from a base URI and a relative reference.
///
/// ## Example
/// ```zig
/// const base = try parse("http://example.com/a/b/c");
/// const ref = try parse("../d");
/// const target = try resolve(allocator, base, ref);
/// // Result: "http://example.com/a/d"
/// ```
pub const resolve = uri.resolve;

/// Normalize a URI according to RFC 3986 Section 6.
///
/// Applies syntax-based normalization:
/// - Case normalization (scheme and host to lowercase)
/// - Percent-encoding normalization
/// - Path segment normalization (remove dot segments)
pub const normalize = uri.normalize;

// =============================================================================
// Percent-Encoding Functions (RFC 3986 Section 2.1)
// =============================================================================

/// Percent-encode a string for use in a URI component.
///
/// Encodes characters that are not allowed in the specified component
/// according to RFC 3986.
///
/// ## Example
/// ```zig
/// const encoded = try percentEncode(allocator, "hello world", .query);
/// // Result: "hello%20world"
/// ```
pub const percentEncode = uri.percentEncode;

/// Decode a percent-encoded string.
///
/// ## Example
/// ```zig
/// const decoded = try percentDecode(allocator, "hello%20world");
/// // Result: "hello world"
/// ```
pub const percentDecode = uri.percentDecode;

// =============================================================================
// Utility Functions
// =============================================================================

/// Check if a string is a valid URI.
pub const isValid = uri.isValid;

/// Check if a URI is absolute (has a scheme).
pub const isAbsolute = uri.isAbsolute;

/// Check if a URI is a relative reference.
pub const isRelative = uri.isRelative;

/// Get the default port for a scheme (e.g., 80 for http, 443 for https).
pub const defaultPort = uri.defaultPort;

// =============================================================================
// Debug Functions
// =============================================================================

/// Generate deterministic JSON output for a URI (useful for testing).
pub const toJson = debug.toJson;

/// Generate pretty-printed JSON output for a URI.
pub const toJsonPretty = debug.toJsonPretty;

/// Dump URI components to stderr for debugging.
pub const dump = debug.dump;

// =============================================================================
// Version Information
// =============================================================================

pub const version = std.SemanticVersion{
    .major = 0,
    .minor = 0,
    .patch = 0,
};

// =============================================================================
// Tests
// =============================================================================

test {
    // Run tests for all submodules
    std.testing.refAllDecls(@This());
}
