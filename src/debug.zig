// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! URI Debug Output
//!
//! Provides deterministic JSON output for URI structures.
//! Useful for testing and debugging URI parsing/resolution.
//!
//! **Security:** Userinfo credentials are automatically redacted in all
//! output functions. Passwords (the portion after `:` in userinfo) are
//! replaced with `***` to prevent credential leakage in logs.

const std = @import("std");
const Allocator = std.mem.Allocator;
const uri_mod = @import("uri.zig");
const Uri = uri_mod.Uri;
const UrnComponents = uri_mod.UrnComponents;

/// Formatting mode for JSON serialization.
const JsonMode = enum {
    compact,
    pretty,
};

/// Redact the password portion of a userinfo string.
///
/// Returns the username part (everything before the first ':') and a flag
/// indicating whether a password was present. The caller can then write
/// `username:***` if redacted, or just the username if not.
///
/// This function does not allocate -- it returns slices into the input.
fn redactUserinfo(userinfo: []const u8) struct { username: []const u8, has_password: bool } {
    if (std.mem.indexOfScalar(u8, userinfo, ':')) |colon_pos| {
        return .{ .username = userinfo[0..colon_pos], .has_password = true };
    }
    return .{ .username = userinfo, .has_password = false };
}

/// Write all URI fields as JSON to the given writer.
/// Shared implementation for both compact and pretty modes.
fn writeUriFields(writer: anytype, uri: Uri, mode: JsonMode) !void {
    var first = true;
    const indent: usize = 1;

    // Output fields in alphabetical order for determinism
    if (uri.fragment) |f| {
        try writeFieldDispatch(writer, &first, "fragment", f, mode, indent);
    }

    if (uri.host) |h| {
        try writeFieldDispatch(writer, &first, "host", h, mode, indent);
    }

    // Path is always present (may be empty string)
    try writeFieldDispatch(writer, &first, "path", uri.path, mode, indent);

    if (uri.port) |p| {
        try writeFieldIntDispatch(writer, &first, "port", p, mode, indent);
    }

    if (uri.query) |q| {
        try writeFieldDispatch(writer, &first, "query", q, mode, indent);
    }

    if (uri.scheme) |s| {
        try writeFieldDispatch(writer, &first, "scheme", s, mode, indent);
    }

    // URN components (nested object)
    if (uri.urn) |urn| {
        switch (mode) {
            .compact => {
                if (!first) try writer.writeAll(",");
                first = false;
                try writer.writeAll("\"urn\":{");
            },
            .pretty => {
                if (!first) try writer.writeAll(",\n");
                first = false;
                try writer.writeAll("  \"urn\": {\n");
            },
        }

        var urn_first = true;
        const urn_indent: usize = 2;
        if (urn.f_component) |fc| {
            try writeFieldDispatch(writer, &urn_first, "f_component", fc, mode, urn_indent);
        }
        if (urn.nid) |nid| {
            try writeFieldDispatch(writer, &urn_first, "nid", nid, mode, urn_indent);
        }
        if (urn.nss) |nss| {
            try writeFieldDispatch(writer, &urn_first, "nss", nss, mode, urn_indent);
        }
        if (urn.q_component) |qc| {
            try writeFieldDispatch(writer, &urn_first, "q_component", qc, mode, urn_indent);
        }
        if (urn.r_component) |rc| {
            try writeFieldDispatch(writer, &urn_first, "r_component", rc, mode, urn_indent);
        }

        switch (mode) {
            .compact => try writer.writeAll("}"),
            .pretty => try writer.writeAll("\n  }"),
        }
    }

    if (uri.userinfo) |ui| {
        try writeRedactedUserinfoField(writer, &first, ui, mode, indent);
    }
}

/// Write a redacted userinfo field value.
fn writeRedactedUserinfoField(writer: anytype, first: *bool, userinfo: []const u8, mode: JsonMode, indent: usize) !void {
    const redacted = redactUserinfo(userinfo);

    switch (mode) {
        .compact => {
            if (!first.*) try writer.writeAll(",");
            first.* = false;
            try writer.writeAll("\"userinfo\":\"");
        },
        .pretty => {
            if (!first.*) try writer.writeAll(",\n");
            first.* = false;
            for (0..indent) |_| try writer.writeAll("  ");
            try writer.writeAll("\"userinfo\": \"");
        },
    }

    try writeEscapedString(writer, redacted.username);
    if (redacted.has_password) {
        try writer.writeAll(":***");
    }
    try writer.writeByte('"');
}

/// Dispatch a string field write to the appropriate mode-specific writer.
fn writeFieldDispatch(writer: anytype, first: *bool, key: []const u8, value: []const u8, mode: JsonMode, indent: usize) !void {
    switch (mode) {
        .compact => try writeField(writer, first, key, value),
        .pretty => try writeFieldPretty(writer, first, key, value, indent),
    }
}

/// Dispatch an integer field write to the appropriate mode-specific writer.
fn writeFieldIntDispatch(writer: anytype, first: *bool, key: []const u8, value: u16, mode: JsonMode, indent: usize) !void {
    switch (mode) {
        .compact => try writeFieldInt(writer, first, key, value),
        .pretty => try writeFieldIntPretty(writer, first, key, value, indent),
    }
}

/// Generate deterministic JSON representation of a URI.
/// Keys are sorted alphabetically for consistent output.
///
/// Userinfo passwords are automatically redacted.
pub fn toJson(allocator: Allocator, uri: Uri) Allocator.Error![]u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    const writer = buf.writer();

    try writer.writeAll("{");
    try writeUriFields(writer, uri, .compact);
    try writer.writeAll("}");

    return buf.toOwnedSlice();
}

/// Generate a formatted multi-line JSON representation.
///
/// Userinfo passwords are automatically redacted.
pub fn toJsonPretty(allocator: Allocator, uri: Uri) Allocator.Error![]u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    const writer = buf.writer();

    try writer.writeAll("{\n");
    try writeUriFields(writer, uri, .pretty);
    try writer.writeAll("\n}");

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

/// Dump URI components to stderr for debugging.
///
/// Userinfo passwords are automatically redacted.
pub fn dump(uri: Uri) void {
    std.debug.print("URI Debug Dump:\n", .{});
    std.debug.print("  scheme:   {?s}\n", .{uri.scheme});

    if (uri.userinfo) |ui| {
        const redacted = redactUserinfo(ui);
        if (redacted.has_password) {
            std.debug.print("  userinfo: {s}:***\n", .{redacted.username});
        } else {
            std.debug.print("  userinfo: {s}\n", .{redacted.username});
        }
    } else {
        std.debug.print("  userinfo: null\n", .{});
    }

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

test "toJson redacts password in userinfo" {
    const allocator = std.testing.allocator;
    const uri = try uri_mod.parse("https://user:secret@host.example.com/path");
    const json = try toJson(allocator, uri);
    defer allocator.free(json);

    // Password must be redacted
    try std.testing.expect(std.mem.indexOf(u8, json, "\"userinfo\":\"user:***\"") != null);
    // Original password must NOT appear
    try std.testing.expect(std.mem.indexOf(u8, json, "secret") == null);
}

test "toJson preserves username-only userinfo" {
    const allocator = std.testing.allocator;
    const uri = try uri_mod.parse("https://user@host.example.com/path");
    const json = try toJson(allocator, uri);
    defer allocator.free(json);

    // Username without password should appear as-is
    try std.testing.expect(std.mem.indexOf(u8, json, "\"userinfo\":\"user\"") != null);
    // Should not contain redaction marker
    try std.testing.expect(std.mem.indexOf(u8, json, "***") == null);
}

test "toJson omits userinfo when absent" {
    const allocator = std.testing.allocator;
    const uri = try uri_mod.parse("https://host.example.com/path");
    const json = try toJson(allocator, uri);
    defer allocator.free(json);

    // No userinfo field should be present
    try std.testing.expect(std.mem.indexOf(u8, json, "userinfo") == null);
}

test "toJsonPretty redacts password in userinfo" {
    const allocator = std.testing.allocator;
    const uri = try uri_mod.parse("https://admin:hunter2@host.example.com/path");
    const json = try toJsonPretty(allocator, uri);
    defer allocator.free(json);

    // Password must be redacted in pretty output too
    try std.testing.expect(std.mem.indexOf(u8, json, "\"userinfo\": \"admin:***\"") != null);
    // Original password must NOT appear
    try std.testing.expect(std.mem.indexOf(u8, json, "hunter2") == null);
}

test "redactUserinfo with password" {
    const result = redactUserinfo("user:secret");
    try std.testing.expectEqualStrings("user", result.username);
    try std.testing.expect(result.has_password);
}

test "redactUserinfo without password" {
    const result = redactUserinfo("justuser");
    try std.testing.expectEqualStrings("justuser", result.username);
    try std.testing.expect(!result.has_password);
}

test "redactUserinfo with empty password" {
    const result = redactUserinfo("user:");
    try std.testing.expectEqualStrings("user", result.username);
    try std.testing.expect(result.has_password);
}

test "redactUserinfo with multiple colons" {
    const result = redactUserinfo("user:pass:extra");
    try std.testing.expectEqualStrings("user", result.username);
    try std.testing.expect(result.has_password);
}
