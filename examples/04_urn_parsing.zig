// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// Example: URN Parsing (RFC 8141)
//
// This example demonstrates parsing of Uniform Resource Names (URNs).
// URNs are persistent, location-independent identifiers for resources.
//
// URN Structure:
//   urn:<NID>:<NSS>[?+<r-component>][?=<q-component>][#<f-component>]
//
// Where:
//   NID = Namespace Identifier (e.g., isbn, uuid, ietf)
//   NSS = Namespace Specific String
//   r-component = resolution parameters
//   q-component = query parameters
//   f-component = fragment
//
// Build and run:
//   zig build run-04_urn_parsing

const std = @import("std");
const uri = @import("uri");

const print = std.debug.print;

pub fn main() !void {
    // =========================================================================
    // Example 1: ISBN URN (International Standard Book Number)
    // =========================================================================
    print("\n=== Example 1: ISBN URN ===\n", .{});

    const isbn_urn = try uri.parse("urn:isbn:0451450523");

    print("URN:      {s}\n", .{isbn_urn.raw});
    print("Scheme:   {s}\n", .{isbn_urn.scheme orelse "(none)"});
    print("Is URN:   {}\n", .{isbn_urn.isUrn()});

    if (isbn_urn.urn) |urn| {
        print("NID:      {s}\n", .{urn.nid orelse "(none)"});
        print("NSS:      {s}\n", .{urn.nss orelse "(none)"});
    }

    // =========================================================================
    // Example 2: UUID URN (Universally Unique Identifier)
    // =========================================================================
    print("\n=== Example 2: UUID URN ===\n", .{});

    const uuid_urn = try uri.parse("urn:uuid:f81d4fae-7dec-11d0-a765-00a0c91e6bf6");

    print("URN:    {s}\n", .{uuid_urn.raw});

    if (uuid_urn.urn) |urn| {
        print("NID:    {s}\n", .{urn.nid orelse "(none)"});
        print("NSS:    {s}\n", .{urn.nss orelse "(none)"});
    }

    // =========================================================================
    // Example 3: IETF URN (RFC documents)
    // =========================================================================
    print("\n=== Example 3: IETF URN ===\n", .{});

    const ietf_urn = try uri.parse("urn:ietf:rfc:3986");

    print("URN:    {s}\n", .{ietf_urn.raw});
    print("This URN identifies RFC 3986 (URI Generic Syntax)\n", .{});

    if (ietf_urn.urn) |urn| {
        print("NID:    {s}\n", .{urn.nid orelse "(none)"});
        print("NSS:    {s}\n", .{urn.nss orelse "(none)"});
    }

    // =========================================================================
    // Example 4: URN with all optional components
    // =========================================================================
    print("\n=== Example 4: URN with Optional Components ===\n", .{});

    const full_urn = try uri.parse("urn:example:foo-bar-baz?+resolver?=query#frag");

    print("URN:          {s}\n", .{full_urn.raw});

    if (full_urn.urn) |urn| {
        print("NID:          {s}\n", .{urn.nid orelse "(none)"});
        print("NSS:          {s}\n", .{urn.nss orelse "(none)"});
        print("r-component:  {s}\n", .{urn.r_component orelse "(none)"});
        print("q-component:  {s}\n", .{urn.q_component orelse "(none)"});
        print("f-component:  {s}\n", .{urn.f_component orelse "(none)"});
    }

    // =========================================================================
    // Example 5: OID URN (Object Identifier)
    // =========================================================================
    print("\n=== Example 5: OID URN ===\n", .{});

    const oid_urn = try uri.parse("urn:oid:2.16.840.1.113883.3.24");

    print("URN:    {s}\n", .{oid_urn.raw});
    print("OID URNs identify objects in hierarchical namespaces\n", .{});

    if (oid_urn.urn) |urn| {
        print("NID:    {s}\n", .{urn.nid orelse "(none)"});
        print("NSS:    {s}\n", .{urn.nss orelse "(none)"});
    }

    // =========================================================================
    // Example 6: Various URN namespaces
    // =========================================================================
    print("\n=== Example 6: Various URN Namespaces ===\n", .{});

    const urns = [_]struct { urn_str: []const u8, desc: []const u8 }{
        .{ .urn_str = "urn:isbn:0451450523", .desc = "Book ISBN" },
        .{ .urn_str = "urn:issn:1535-3613", .desc = "Journal ISSN" },
        .{ .urn_str = "urn:uuid:6e8bc430-9c3a-11d9-9669-0800200c9a66", .desc = "UUID" },
        .{ .urn_str = "urn:mpeg:mpeg7:schema:2001", .desc = "MPEG-7 schema" },
        .{ .urn_str = "urn:sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", .desc = "SHA-256 hash" },
    };

    for (urns) |u| {
        const parsed = try uri.parse(u.urn_str);
        if (parsed.urn) |urn| {
            print("\n  {s}:\n", .{u.desc});
            print("    URN: {s}\n", .{u.urn_str});
            print("    NID: {s}\n", .{urn.nid orelse "(none)"});
            print("    NSS: {s}\n", .{urn.nss orelse "(none)"});
        }
    }

    // =========================================================================
    // Example 7: Distinguishing URNs from URLs
    // =========================================================================
    print("\n=== Example 7: URNs vs URLs ===\n", .{});

    const identifiers = [_][]const u8{
        "urn:isbn:0451450523",
        "https://example.com/books/0451450523",
        "urn:uuid:f81d4fae-7dec-11d0-a765-00a0c91e6bf6",
        "http://example.com/resources/f81d4fae-7dec-11d0-a765-00a0c91e6bf6",
    };

    for (identifiers) |id| {
        const parsed = try uri.parse(id);
        const uri_type = if (parsed.isUrn()) "URN (name)" else "URL (locator)";
        print("  {s}\n    Type: {s}\n\n", .{ id, uri_type });
    }

    print("URNs identify WHAT a resource is (persistent name)\n", .{});
    print("URLs identify WHERE a resource is (location)\n", .{});

    print("\n", .{});
}
