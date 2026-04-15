// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

const std = @import("std");

/// Build configuration for the URI library
///
/// A fully RFC-compliant URI/URL parsing and manipulation library for Zig.
/// Supports RFC 3986 (URI), RFC 3987 (IRI), and WHATWG URL Standard.
pub fn build(b: *std.Build) void {
    // Standard target and optimization options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // thread-pool parallelism option
    const enable_tp = b.option(bool, "thread-pool", "Enable thread-pool-based parallelism") orelse true;

    // Get thread-pool dependency if enabled
    const tp_mod: ?*std.Build.Module = if (enable_tp) blk: {
        const tp_dep = b.dependency("thread_pool", .{
            .target = target,
            .optimize = optimize,
        });
        break :blk tp_dep.module("thread_pool");
    } else null;

    // ==========================================================================
    // Library Module
    // ==========================================================================

    const uri_module = b.addModule("uri", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (tp_mod) |tm| uri_module.addImport("thread_pool", tm);

    // ==========================================================================
    // Unit Tests
    // ==========================================================================

    const lib_test_mod = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (tp_mod) |tm| lib_test_mod.addImport("thread_pool", tm);
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_test_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // ==========================================================================
    // URI Parser Tests
    // ==========================================================================

    const uri_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/uri.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_uri_tests = b.addRunArtifact(uri_tests);
    test_step.dependOn(&run_uri_tests.step);

    // ==========================================================================
    // RFC Test Vectors (RFC 3986 examples)
    // ==========================================================================

    const rfc_vectors_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/rfc3986_vectors.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "uri", .module = uri_module },
            },
        }),
    });

    const run_rfc_vectors = b.addRunArtifact(rfc_vectors_test);
    const test_vectors_step = b.step("test-vectors", "Run RFC 3986 test vectors");
    test_vectors_step.dependOn(&run_rfc_vectors.step);

    // ==========================================================================
    // Acceptance Tests (T1-T5)
    // ==========================================================================

    const accept_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/accept.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "uri", .module = uri_module },
            },
        }),
    });

    const run_accept_tests = b.addRunArtifact(accept_tests);
    const test_accept_step = b.step("test-accept", "Run acceptance tests (T1-T5)");
    test_accept_step.dependOn(&run_accept_tests.step);

    // ==========================================================================
    // URI Dataset Tests (Comprehensive URI collection)
    // ==========================================================================

    const dataset_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/uri_dataset.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "uri", .module = uri_module },
            },
        }),
    });

    const run_dataset_tests = b.addRunArtifact(dataset_tests);
    const test_dataset_step = b.step("test-dataset", "Run comprehensive URI dataset tests");
    test_dataset_step.dependOn(&run_dataset_tests.step);

    // ==========================================================================
    // All Tests Step
    // ==========================================================================

    const test_all_step = b.step("test-all", "Run all tests including RFC vectors, acceptance, and dataset");
    test_all_step.dependOn(&run_lib_unit_tests.step);
    test_all_step.dependOn(&run_uri_tests.step);
    test_all_step.dependOn(&run_rfc_vectors.step);
    test_all_step.dependOn(&run_accept_tests.step);
    test_all_step.dependOn(&run_dataset_tests.step);

    // ==========================================================================
    // Examples
    // ==========================================================================

    const examples_step = b.step("examples", "Build all examples");
    const run_examples_step = b.step("run-examples", "Build and run all examples");

    const example_files = [_][]const u8{
        "01_basic_parsing",
        "02_uri_resolution",
        "03_percent_encoding",
        "04_urn_parsing",
        "05_resource_registry",
        "06_normalization",
        "07_validation",
        "08_debug_output",
    };

    for (example_files) |example_name| {
        const example_path = b.fmt("examples/{s}.zig", .{example_name});
        const example = b.addExecutable(.{
            .name = example_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(example_path),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "uri", .module = uri_module },
                },
            }),
        });

        const install_example = b.addInstallArtifact(example, .{});
        examples_step.dependOn(&install_example.step);

        const run_example = b.addRunArtifact(example);
        run_examples_step.dependOn(&run_example.step);

        // Create individual run step for each example
        const run_step_name = b.fmt("run-{s}", .{example_name});
        const run_step_desc = b.fmt("Run the {s} example", .{example_name});
        const individual_run_step = b.step(run_step_name, run_step_desc);
        individual_run_step.dependOn(&run_example.step);
    }

    // ==========================================================================
    // Format Check Step
    // ==========================================================================

    const fmt_step = b.step("fmt", "Check source formatting");
    const fmt = b.addFmt(.{
        .paths = &.{
            "src",
            "tests",
            "examples",
            "build.zig",
        },
        .check = true,
    });
    fmt_step.dependOn(&fmt.step);

    // ==========================================================================
    // Documentation Generation
    // ==========================================================================

    const docs_step = b.step("docs", "Generate documentation");
    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib_unit_tests.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs_step.dependOn(&install_docs.step);
}
