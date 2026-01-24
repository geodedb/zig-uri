// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! URI Debug Output
//!
//! Provides deterministic JSON output for URI structures.
//! Useful for testing and debugging URI parsing/resolution.

const std = @import("std");
const Allocator = std.mem.Allocator;
const uri_mod = @import("uri.zig");
const Uri = uri_mod.Uri;
const UrnComponents = uri_mod.UrnComponents;

/// Generate deterministic JSON representation of a URI.
/// Keys are sorted alphabetically for consistent output.
pub fn toJson(allocator: Allocator, uri: Uri) Allocator.Error![]u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    const writer = buf.writer();

    try writer.writeAll("{");

    var first = true;

    // Output fields in alphabetical order for determinism
    if (uri.fragment) |f| {
        try writeField(writer, &first, "fragment", f);
    }

    if (uri.host) |h| {
        try writeField(writer, &first, "host", h);
    }

    // Path is always present (may be empty string)
    try writeField(writer, &first, "path", uri.path);

    if (uri.port) |p| {
        try writeFieldInt(writer, &first, "port", p);
    }

    if (uri.query) |q| {
        try writeField(writer, &first, "query", q);
    }

    if (uri.scheme) |s| {
        try writeField(writer, &first, "scheme", s);
    }

    // URN components (nested object)
    if (uri.urn) |urn| {
        if (!first) try writer.writeAll(",");
        first = false;
        try writer.writeAll("\"urn\":{");

        var urn_first = true;
        if (urn.f_component) |fc| {
            try writeField(writer, &urn_first, "f_component", fc);
        }
        if (urn.nid) |nid| {
            try writeField(writer, &urn_first, "nid", nid);
        }
        if (urn.nss) |nss| {
            try writeField(writer, &urn_first, "nss", nss);
        }
        if (urn.q_component) |qc| {
            try writeField(writer, &urn_first, "q_component", qc);
        }
        if (urn.r_component) |rc| {
            try writeField(writer, &urn_first, "r_component", rc);
        }
        try writer.writeAll("}");
    }

    if (uri.userinfo) |ui| {
        try writeField(writer, &first, "userinfo", ui);
    }

    try writer.writeAll("}");

    return buf.toOwnedSlice();
}

fn writeField(writer: anytype, first: *bool, key: []const u8, value: []const u8) !void {
    if (!first.*) try writer.writeAll(",");
    first.* = false;

    try writer.writeByte('"');
    try writer.writeAll(key);
    try writer.writeAll("\":\"");
    try writeEscapedString(writer, value);
    try writer.writeByte('"');
}

fn writeFieldInt(writer: anytype, first: *bool, key: []const u8, value: u16) !void {
    if (!first.*) try writer.writeAll(",");
    first.* = false;

    try writer.writeByte('"');
    try writer.writeAll(key);
    try writer.writeAll("\":");
    try std.fmt.format(writer, "{d}", .{value});
}

fn writeEscapedString(writer: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try std.fmt.format(writer, "\\u{x:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
}

/// Generate a formatted multi-line JSON representation
pub fn toJsonPretty(allocator: Allocator, uri: Uri) Allocator.Error![]u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    const writer = buf.writer();

    try writer.writeAll("{\n");

    var first = true;

    if (uri.fragment) |f| {
        try writeFieldPretty(writer, &first, "fragment", f, 1);
    }

    if (uri.host) |h| {
        try writeFieldPretty(writer, &first, "host", h, 1);
    }

    try writeFieldPretty(writer, &first, "path", uri.path, 1);

    if (uri.port) |p| {
        try writeFieldIntPretty(writer, &first, "port", p, 1);
    }

    if (uri.query) |q| {
        try writeFieldPretty(writer, &first, "query", q, 1);
    }

    if (uri.scheme) |s| {
        try writeFieldPretty(writer, &first, "scheme", s, 1);
    }

    if (uri.urn) |urn| {
        if (!first) try writer.writeAll(",\n");
        first = false;
        try writer.writeAll("  \"urn\": {\n");

        var urn_first = true;
        if (urn.f_component) |fc| {
            try writeFieldPretty(writer, &urn_first, "f_component", fc, 2);
        }
        if (urn.nid) |nid| {
            try writeFieldPretty(writer, &urn_first, "nid", nid, 2);
        }
        if (urn.nss) |nss| {
            try writeFieldPretty(writer, &urn_first, "nss", nss, 2);
        }
        if (urn.q_component) |qc| {
            try writeFieldPretty(writer, &urn_first, "q_component", qc, 2);
        }
        if (urn.r_component) |rc| {
            try writeFieldPretty(writer, &urn_first, "r_component", rc, 2);
        }
        try writer.writeAll("\n  }");
    }

    if (uri.userinfo) |ui| {
        try writeFieldPretty(writer, &first, "userinfo", ui, 1);
    }

    try writer.writeAll("\n}");

    return buf.toOwnedSlice();
}

fn writeFieldPretty(writer: anytype, first: *bool, key: []const u8, value: []const u8, indent: usize) !void {
    if (!first.*) try writer.writeAll(",\n");
    first.* = false;

    for (0..indent) |_| try writer.writeAll("  ");
    try writer.writeByte('"');
    try writer.writeAll(key);
    try writer.writeAll("\": \"");
    try writeEscapedString(writer, value);
    try writer.writeByte('"');
}

fn writeFieldIntPretty(writer: anytype, first: *bool, key: []const u8, value: u16, indent: usize) !void {
    if (!first.*) try writer.writeAll(",\n");
    first.* = false;

    for (0..indent) |_| try writer.writeAll("  ");
    try writer.writeByte('"');
    try writer.writeAll(key);
    try writer.writeAll("\": ");
    try std.fmt.format(writer, "{d}", .{value});
}

/// Dump URI components to stderr for debugging
pub fn dump(uri: Uri) void {
    std.debug.print("URI Debug Dump:\n", .{});
    std.debug.print("  scheme:   {?s}\n", .{uri.scheme});
    std.debug.print("  userinfo: {?s}\n", .{uri.userinfo});
    std.debug.print("  host:     {?s}\n", .{uri.host});
    std.debug.print("  port:     {?d}\n", .{uri.port});
    std.debug.print("  path:     {s}\n", .{uri.path});
    std.debug.print("  query:    {?s}\n", .{uri.query});
    std.debug.print("  fragment: {?s}\n", .{uri.fragment});
    if (uri.urn) |urn| {
        std.debug.print("  URN:\n", .{});
        std.debug.print("    nid:         {?s}\n", .{urn.nid});
        std.debug.print("    nss:         {?s}\n", .{urn.nss});
        std.debug.print("    r_component: {?s}\n", .{urn.r_component});
        std.debug.print("    q_component: {?s}\n", .{urn.q_component});
        std.debug.print("    f_component: {?s}\n", .{urn.f_component});
    }
}

// =============================================================================
// Tests
// =============================================================================

test "toJson basic URI" {
    const allocator = std.testing.allocator;
    const uri = try uri_mod.parse("https://example.com/path?query=value#frag");
    const json = try toJson(allocator, uri);
    defer allocator.free(json);

    // Verify JSON structure (keys should be alphabetically sorted)
    try std.testing.expect(std.mem.indexOf(u8, json, "\"fragment\":\"frag\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"host\":\"example.com\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"path\":\"/path\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"query\":\"query=value\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"scheme\":\"https\"") != null);
}

test "toJson URN" {
    const allocator = std.testing.allocator;
    const uri = try uri_mod.parse("urn:isbn:0451450523");
    const json = try toJson(allocator, uri);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"scheme\":\"urn\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"nid\":\"isbn\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"nss\":\"0451450523\"") != null);
}

test "toJson escapes special characters" {
    const allocator = std.testing.allocator;
    var uri = Uri{};
    uri.path = "/path/with\"quotes";
    const json = try toJson(allocator, uri);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\\\"") != null);
}

test "toJsonPretty formatting" {
    const allocator = std.testing.allocator;
    const uri = try uri_mod.parse("https://example.com/path");
    const json = try toJsonPretty(allocator, uri);
    defer allocator.free(json);

    // Should have newlines and indentation
    try std.testing.expect(std.mem.indexOf(u8, json, "\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "  ") != null);
}
