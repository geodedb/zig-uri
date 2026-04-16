// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! URI Resource Registry
//!
//! Provides a registry for managing URI resources with optional fetch callbacks.
//! Supports caps for limiting memory usage and resource counts.

const std = @import("std");
const Allocator = std.mem.Allocator;
const uri_mod = @import("uri.zig");
const Uri = uri_mod.Uri;

/// Registry limits/caps
pub const Caps = struct {
    /// Maximum number of documents in registry
    max_docs: usize = 1000,
    /// Maximum total bytes for all resources
    max_bytes: usize = 10 * 1024 * 1024, // 10 MB
    /// Maximum number of anchors per document
    max_anchors: usize = 100,
    /// Maximum URI length
    max_uri_len: usize = 2048,
    /// Maximum depth for reference resolution
    max_resolve_depth: usize = 10,
};

/// Resource fetch callback type
pub const FetchCallback = *const fn (uri: []const u8, allocator: Allocator) FetchError![]u8;

/// Fetch error types
pub const FetchError = error{
    NotFound,
    NetworkError,
    Timeout,
    OutOfMemory,
    InvalidUri,
    TooLarge,
    UnsupportedScheme,
};

/// Registry error types
pub const RegistryError = error{
    CapacityExceeded,
    DocumentNotFound,
    AnchorNotFound,
    DuplicateUri,
    InvalidUri,
    OutOfMemory,
    FetchFailed,
};

/// Anchor within a document
pub const Anchor = struct {
    name: []const u8,
    /// Byte offset within the document
    offset: usize,
    /// Length of the anchored content
    length: usize,
};

/// A registered resource/document
pub const Resource = struct {
    /// The canonical URI for this resource
    uri: []const u8,
    /// The resource content (owned)
    content: []const u8,
    /// Named anchors within this resource
    anchors: std.StringHashMap(Anchor),
    /// Metadata
    content_type: ?[]const u8,
    /// When the resource was registered/fetched
    timestamp: i64,

    pub fn deinit(self: *Resource, allocator: Allocator) void {
        allocator.free(self.uri);
        allocator.free(self.content);
        if (self.content_type) |ct| allocator.free(ct);

        // Free anchor names
        var anchor_it = self.anchors.iterator();
        while (anchor_it.next()) |entry| {
            allocator.free(entry.value_ptr.name);
        }
        self.anchors.deinit();
    }
};

/// URI Resource Registry
///
/// Thread Safety: This type is NOT thread-safe. Concurrent access from
/// multiple threads requires external synchronization (e.g., a mutex).
/// All mutating operations (register, remove, addAnchor) as well as
/// reads (get, getAnchorContent, contains, stats) must be serialized
/// when the registry is shared across threads.
pub const Registry = struct {
    allocator: Allocator,
    resources: std.StringHashMap(Resource),
    caps: Caps,
    fetch_callback: ?FetchCallback,
    total_bytes: usize,

    pub fn init(allocator: Allocator) Registry {
        return initWithCaps(allocator, .{});
    }

    pub fn initWithCaps(allocator: Allocator, caps: Caps) Registry {
        return Registry{
            .allocator = allocator,
            .resources = std.StringHashMap(Resource).init(allocator),
            .caps = caps,
            .fetch_callback = null,
            .total_bytes = 0,
        };
    }

    pub fn deinit(self: *Registry) void {
        var it = self.resources.iterator();
        while (it.next()) |entry| {
            var resource = entry.value_ptr;
            resource.deinit(self.allocator);
        }
        self.resources.deinit();
    }

    /// Set the fetch callback for automatic resource retrieval
    pub fn setFetchCallback(self: *Registry, callback: FetchCallback) void {
        self.fetch_callback = callback;
    }

    /// Register a resource with the given URI and content
    pub fn register(
        self: *Registry,
        uri_str: []const u8,
        content: []const u8,
        content_type: ?[]const u8,
    ) RegistryError!void {
        // Check caps
        if (self.resources.count() >= self.caps.max_docs) {
            return RegistryError.CapacityExceeded;
        }
        if (self.total_bytes + content.len > self.caps.max_bytes) {
            return RegistryError.CapacityExceeded;
        }
        if (uri_str.len > self.caps.max_uri_len) {
            return RegistryError.InvalidUri;
        }

        // Check for duplicate
        if (self.resources.contains(uri_str)) {
            return RegistryError.DuplicateUri;
        }

        // Allocate and store
        const uri_copy = self.allocator.dupe(u8, uri_str) catch return RegistryError.OutOfMemory;
        errdefer self.allocator.free(uri_copy);

        const content_copy = self.allocator.dupe(u8, content) catch return RegistryError.OutOfMemory;
        errdefer self.allocator.free(content_copy);

        const ct_copy = if (content_type) |ct|
            self.allocator.dupe(u8, ct) catch return RegistryError.OutOfMemory
        else
            null;
        errdefer if (ct_copy) |ct| self.allocator.free(ct);

        const resource = Resource{
            .uri = uri_copy,
            .content = content_copy,
            .anchors = std.StringHashMap(Anchor).init(self.allocator),
            .content_type = ct_copy,
            .timestamp = 0,
        };

        self.resources.put(uri_copy, resource) catch return RegistryError.OutOfMemory;
        self.total_bytes += content.len;
    }

    /// Get a resource by URI, optionally fetching if not found
    pub fn get(self: *Registry, uri_str: []const u8, auto_fetch: bool) RegistryError!*Resource {
        if (self.resources.getPtr(uri_str)) |resource| {
            return resource;
        }

        if (auto_fetch) {
            if (self.fetch_callback) |fetch| {
                const content = fetch(uri_str, self.allocator) catch return RegistryError.FetchFailed;
                defer self.allocator.free(content);

                try self.register(uri_str, content, null);
                return self.resources.getPtr(uri_str) orelse return RegistryError.DocumentNotFound;
            }
        }

        return RegistryError.DocumentNotFound;
    }

    /// Check if a URI is registered
    pub fn contains(self: *Registry, uri_str: []const u8) bool {
        return self.resources.contains(uri_str);
    }

    /// Remove a resource by URI
    pub fn remove(self: *Registry, uri_str: []const u8) bool {
        if (self.resources.fetchRemove(uri_str)) |kv| {
            self.total_bytes -= kv.value.content.len;
            var resource = kv.value;
            resource.deinit(self.allocator);
            return true;
        }
        return false;
    }

    /// Add an anchor to a resource
    pub fn addAnchor(
        self: *Registry,
        uri_str: []const u8,
        anchor_name: []const u8,
        offset: usize,
        length: usize,
    ) RegistryError!void {
        const resource = self.resources.getPtr(uri_str) orelse return RegistryError.DocumentNotFound;

        if (resource.anchors.count() >= self.caps.max_anchors) {
            return RegistryError.CapacityExceeded;
        }

        const name_copy = self.allocator.dupe(u8, anchor_name) catch return RegistryError.OutOfMemory;
        errdefer self.allocator.free(name_copy);
        resource.anchors.put(name_copy, Anchor{
            .name = name_copy,
            .offset = offset,
            .length = length,
        }) catch return RegistryError.OutOfMemory;
    }

    /// Get content at an anchor
    pub fn getAnchorContent(self: *Registry, uri_str: []const u8, anchor_name: []const u8) RegistryError![]const u8 {
        const resource = self.resources.getPtr(uri_str) orelse return RegistryError.DocumentNotFound;
        const anchor = resource.anchors.get(anchor_name) orelse return RegistryError.AnchorNotFound;

        const end = std.math.add(usize, anchor.offset, anchor.length) catch return RegistryError.AnchorNotFound;
        if (end > resource.content.len) {
            return RegistryError.AnchorNotFound;
        }

        return resource.content[anchor.offset..end];
    }

    /// Get registry statistics
    pub fn stats(self: *Registry) struct { doc_count: usize, total_bytes: usize, anchor_count: usize } {
        var anchor_count: usize = 0;
        var it = self.resources.iterator();
        while (it.next()) |entry| {
            anchor_count += entry.value_ptr.anchors.count();
        }

        return .{
            .doc_count = self.resources.count(),
            .total_bytes = self.total_bytes,
            .anchor_count = anchor_count,
        };
    }
};

// =============================================================================
// Tests
// =============================================================================

test "Registry basic operations" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    // Register a resource
    try registry.register("https://example.com/doc", "Hello, World!", "text/plain");

    // Get the resource
    const resource = try registry.get("https://example.com/doc", false);
    try std.testing.expectEqualStrings("Hello, World!", resource.content);
    try std.testing.expectEqualStrings("text/plain", resource.content_type.?);

    // Check contains
    try std.testing.expect(registry.contains("https://example.com/doc"));
    try std.testing.expect(!registry.contains("https://example.com/other"));

    // Check stats
    const s = registry.stats();
    try std.testing.expectEqual(@as(usize, 1), s.doc_count);
    try std.testing.expectEqual(@as(usize, 13), s.total_bytes);
}

test "Registry caps enforcement" {
    const allocator = std.testing.allocator;
    var registry = Registry.initWithCaps(allocator, .{ .max_docs = 2, .max_bytes = 100 });
    defer registry.deinit();

    try registry.register("https://example.com/1", "Content 1", null);
    try registry.register("https://example.com/2", "Content 2", null);

    // Should fail - max docs reached
    try std.testing.expectError(RegistryError.CapacityExceeded, registry.register("https://example.com/3", "Content 3", null));
}

test "Registry anchors" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    const content = "Hello, World! This is a test.";
    try registry.register("https://example.com/doc", content, null);

    // Add anchors
    try registry.addAnchor("https://example.com/doc", "greeting", 0, 13);
    try registry.addAnchor("https://example.com/doc", "message", 14, 15);

    // Get anchor content
    const greeting = try registry.getAnchorContent("https://example.com/doc", "greeting");
    try std.testing.expectEqualStrings("Hello, World!", greeting);

    const message = try registry.getAnchorContent("https://example.com/doc", "message");
    try std.testing.expectEqualStrings("This is a test.", message);
}

test "Registry remove" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    try registry.register("https://example.com/doc", "Content", null);
    try std.testing.expect(registry.contains("https://example.com/doc"));

    const removed = registry.remove("https://example.com/doc");
    try std.testing.expect(removed);
    try std.testing.expect(!registry.contains("https://example.com/doc"));

    // Remove non-existent should return false
    try std.testing.expect(!registry.remove("https://example.com/nonexistent"));
}

test "Registry anchor overflow offset+length returns error" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    const content = "Short";
    try registry.register("https://example.com/doc", content, null);

    // Add an anchor with values that would overflow when added together
    // std.math.maxInt(usize) + 1 overflows
    try registry.addAnchor("https://example.com/doc", "overflow", std.math.maxInt(usize), 1);

    // Getting anchor content should return AnchorNotFound due to overflow, not wrap around
    try std.testing.expectError(RegistryError.AnchorNotFound, registry.getAnchorContent("https://example.com/doc", "overflow"));
}

test "Registry anchor offset beyond content returns error" {
    const allocator = std.testing.allocator;
    var registry = Registry.init(allocator);
    defer registry.deinit();

    const content = "Hello";
    try registry.register("https://example.com/doc", content, null);

    // Anchor that extends beyond content
    try registry.addAnchor("https://example.com/doc", "bad", 3, 10);
    try std.testing.expectError(RegistryError.AnchorNotFound, registry.getAnchorContent("https://example.com/doc", "bad"));
}
