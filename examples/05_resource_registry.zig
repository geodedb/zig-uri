// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros
//
// Example: Resource Registry
//
// This example demonstrates the URI Resource Registry, which provides
// document storage with support for:
// - Storing and retrieving resources by URI
// - Named anchors within documents
// - Capacity limits for memory management
// - Optional fetch callbacks for automatic resource retrieval
//
// Build and run:
//   zig build run-05_resource_registry

const std = @import("std");
const uri = @import("uri");

const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // =========================================================================
    // Example 1: Basic Registry Operations
    // =========================================================================
    print("\n=== Example 1: Basic Registry Operations ===\n", .{});

    // Initialize a registry
    var registry = uri.Registry.init(allocator);
    defer registry.deinit();

    // Register some resources
    try registry.register(
        "https://example.com/schema.json",
        \\{"type": "object", "properties": {"name": {"type": "string"}}}
    ,
        "application/json",
    );

    try registry.register(
        "https://example.com/users/1",
        \\{"id": 1, "name": "Alice", "email": "alice@example.com"}
    ,
        "application/json",
    );

    try registry.register(
        "https://example.com/docs/readme.txt",
        "Welcome to the documentation!\n\nThis is a sample readme file.",
        "text/plain",
    );

    print("Registered 3 resources.\n\n", .{});

    // Retrieve a resource
    const schema = try registry.get("https://example.com/schema.json", false);
    print("Schema URI: {s}\n", .{schema.uri});
    print("Content-Type: {s}\n", .{schema.content_type orelse "(none)"});
    print("Content: {s}\n", .{schema.content});

    // Check if a resource exists
    const exists = registry.contains("https://example.com/users/1");
    print("\nUser resource exists: {}\n", .{exists});

    // =========================================================================
    // Example 2: Registry Statistics
    // =========================================================================
    print("\n=== Example 2: Registry Statistics ===\n", .{});

    const stats = registry.stats();
    print("Documents:    {d}\n", .{stats.doc_count});
    print("Total bytes:  {d}\n", .{stats.total_bytes});
    print("Anchors:      {d}\n", .{stats.anchor_count});

    // =========================================================================
    // Example 3: Working with Anchors
    // =========================================================================
    print("\n=== Example 3: Working with Anchors ===\n", .{});

    // Register a document with multiple sections
    const doc_content =
        \\# Introduction
        \\Welcome to the guide.
        \\
        \\# Getting Started
        \\Here's how to begin.
        \\
        \\# Advanced Topics
        \\For experienced users.
    ;

    try registry.register("https://example.com/guide.md", doc_content, "text/markdown");

    // Add anchors to mark sections
    try registry.addAnchor("https://example.com/guide.md", "introduction", 0, 35);
    try registry.addAnchor("https://example.com/guide.md", "getting-started", 37, 42);
    try registry.addAnchor("https://example.com/guide.md", "advanced", 80, 41);

    // Retrieve anchor content
    const intro = try registry.getAnchorContent("https://example.com/guide.md", "introduction");
    print("Introduction section:\n{s}\n", .{intro});

    const getting_started = try registry.getAnchorContent("https://example.com/guide.md", "getting-started");
    print("\nGetting Started section:\n{s}\n", .{getting_started});

    // =========================================================================
    // Example 4: Registry with Capacity Limits
    // =========================================================================
    print("\n=== Example 4: Registry with Capacity Limits ===\n", .{});

    // Create a registry with strict limits
    var limited_registry = uri.Registry.initWithCaps(allocator, .{
        .max_docs = 5,
        .max_bytes = 1024, // 1 KB max
        .max_anchors = 10,
        .max_uri_len = 256,
    });
    defer limited_registry.deinit();

    print("Created registry with limits:\n", .{});
    print("  max_docs: 5\n", .{});
    print("  max_bytes: 1024\n", .{});
    print("  max_anchors: 10\n", .{});
    print("  max_uri_len: 256\n\n", .{});

    // Register documents until we hit the limit
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var uri_buf: [64]u8 = undefined;
        const uri_str = try std.fmt.bufPrint(&uri_buf, "https://example.com/doc{d}", .{i});

        limited_registry.register(uri_str, "Document content here.", null) catch |err| {
            print("Failed to register doc{d}: {}\n", .{ i, err });
            break;
        };
        print("Registered doc{d}\n", .{i});
    }

    const limited_stats = limited_registry.stats();
    print("\nFinal state: {d} documents, {d} bytes\n", .{ limited_stats.doc_count, limited_stats.total_bytes });

    // =========================================================================
    // Example 5: Removing Resources
    // =========================================================================
    print("\n=== Example 5: Removing Resources ===\n", .{});

    // Check current state
    print("Before removal: {d} documents\n", .{registry.stats().doc_count});

    // Remove a resource
    const removed = registry.remove("https://example.com/users/1");
    print("Removed users/1: {}\n", .{removed});

    // Try to remove a non-existent resource
    const not_found = registry.remove("https://example.com/nonexistent");
    print("Removed nonexistent: {}\n", .{not_found});

    print("After removal: {d} documents\n", .{registry.stats().doc_count});

    // =========================================================================
    // Example 6: Error Handling
    // =========================================================================
    print("\n=== Example 6: Error Handling ===\n", .{});

    // Try to get a non-existent resource
    _ = registry.get("https://example.com/does-not-exist", false) catch |err| {
        print("Expected error: {}\n", .{err});
    };

    // Try to register a duplicate
    registry.register("https://example.com/schema.json", "duplicate", null) catch |err| {
        print("Duplicate URI error: {}\n", .{err});
    };

    // Try to get non-existent anchor
    _ = registry.getAnchorContent("https://example.com/guide.md", "nonexistent") catch |err| {
        print("Anchor not found error: {}\n", .{err});
    };

    // =========================================================================
    // Example 7: Practical Use Case - JSON Schema Registry
    // =========================================================================
    print("\n=== Example 7: JSON Schema Registry ===\n", .{});

    var schema_registry = uri.Registry.init(allocator);
    defer schema_registry.deinit();

    // Register related schemas
    try schema_registry.register(
        "https://api.example.com/schemas/user.json",
        \\{
        \\  "$id": "https://api.example.com/schemas/user.json",
        \\  "type": "object",
        \\  "properties": {
        \\    "id": {"type": "integer"},
        \\    "name": {"type": "string"},
        \\    "address": {"$ref": "address.json"}
        \\  }
        \\}
    ,
        "application/schema+json",
    );

    try schema_registry.register(
        "https://api.example.com/schemas/address.json",
        \\{
        \\  "$id": "https://api.example.com/schemas/address.json",
        \\  "type": "object",
        \\  "properties": {
        \\    "street": {"type": "string"},
        \\    "city": {"type": "string"},
        \\    "country": {"type": "string"}
        \\  }
        \\}
    ,
        "application/schema+json",
    );

    print("Schema registry created with 2 schemas.\n", .{});
    print("This pattern is useful for:\n", .{});
    print("  - JSON Schema validation\n", .{});
    print("  - OpenAPI specification references\n", .{});
    print("  - GraphQL schema federation\n", .{});

    const schema_stats = schema_registry.stats();
    print("\nRegistry contains {d} schemas ({d} bytes)\n", .{ schema_stats.doc_count, schema_stats.total_bytes });

    print("\n", .{});
}
