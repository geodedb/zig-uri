# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.5] - 2026-06-11

Security, correctness, and performance hardening from a full appsec + audit pass.

### Fixed
- Parallel batch APIs (`parseUris`/`validateUris`/`normalizeUris`) could leave the
  tail of `results` uninitialized for batches larger than 512 (floor-division
  chunking); all inputs are now covered.
- `Uri.authority()` returned `null`/stale data for owned URIs produced by
  `resolve()`/`normalize()`/`dupe()`; it is now correct.
- Double-free in `normalize()` and memory leaks in `serializeRaw()` and
  `resolve()` under allocation failure.
- Port parser rejected non-`DIGIT` strings (`+443`, `8_080`) per RFC 3986 §3.2.3.
- Malformed authority with trailing bytes after an IPv6 `]` is now rejected.
- `normalize()` keeps percent-encoded dot segments encoded (`%2E`/`%2E%2E`) so
  they are never promoted to directory traversal; normalization is idempotent.
- Host percent-encoding case is normalized (`%2f` → `%2F`) per RFC 3986 §6.2.2.2.
- `zig build test-all`/`test-dataset` no longer emit a spurious `failed command`
  diagnostic (removed `std.debug.print` from a test).

### Changed
- CI gates the RFC vector, acceptance, and dataset suites via `zig build test-all`.
- The `version` constant is asserted against `build.zig.zon` to prevent drift.
- Performance: normalize fast-paths, registry single-hash `getOrPut`, JSON writer
  pre-sizing, and batch normalize reuses the canonical serialization.

### Security
- Added a real `std.testing.fuzz` target driving parse/normalize/resolve.
- Documented consumer guidance (strict mode, input bounds, normalize-before-compare).

## [0.1.4] - 2026-06-11

### Changed
- Aligned the `thread-pool` dependency pin (immutable git commit SHA + Zig package hash).

## [0.1.3] - 2026-06-11

### Changed
- Release bump with tagged sibling dependencies.

## [0.1.2] - 2026-06-11

### Changed
- Release bump with tagged sibling dependencies.

## [0.1.1] - 2026-06-11

### Changed
- Migrated the parallel batch-operations dependency from `spice` to `thread-pool`
  (pinned by immutable git commit SHA + Zig package hash).
- Raised the minimum supported Zig version to 0.16.0 (from 0.15.x).
- Standardized `.pre-commit-config.yaml` from the geode upstream.

## [0.1.0] - 2026-01-24

Initial public release with RFC 3986 compliant URI parsing.

### Added
- Merge request template for consistent contributions
- Issue templates for bug reports, features, and questions
- RFC 3986 compliant URI parsing with full component access (scheme, authority, userinfo, host, port, path, query, fragment)
- RFC 8141 URN support with NID, NSS, and r/q/f-components parsing
- URI reference resolution per RFC 3986 Section 5
- Path and case normalization per RFC 3986 Section 6
- Percent-encoding and decoding support
- Parse options with strict, allow_spaces, and iri_mode validation
- Component-aware encoding that respects URI component rules
- Resource registry for document storage with fetch callbacks and anchor support
- Debug utilities for development
- Zero-copy parsing with no allocations for basic operations
- Cross-platform support for all Zig targets
- Apache-2.0 open source license
- Comprehensive test suite including RFC test vectors and 500+ URI dataset tests
- Project documentation including API reference and RFC compliance details
- Nix development environment support
- Make build targets for development workflow

### Changed
- Updated CI catalog components to v1.7.1
- CI configuration to use DevNW CI Catalog components
- Runner configuration to use Alpine Linux

### Security
- Added GitLab native Secret Detection
- Enabled Advanced SAST and Dependency Scanning
- SAST (Static Application Security Testing) integration
- Secret Detection configuration
- SBOM (Software Bill of Materials) generation

## [0.0.1] - 2025-12-30

Initial development release.

### Added
- Core URI parsing library implementation
- Initial project structure
- Basic CI/CD pipeline setup

[Unreleased]: https://gitlab.com/devnw/zig/uri/-/compare/v0.1.5...HEAD
[0.1.5]: https://gitlab.com/devnw/zig/uri/-/compare/v0.1.4...v0.1.5
[0.1.4]: https://gitlab.com/devnw/zig/uri/-/compare/v0.1.3...v0.1.4
[0.1.3]: https://gitlab.com/devnw/zig/uri/-/compare/v0.1.2...v0.1.3
[0.1.2]: https://gitlab.com/devnw/zig/uri/-/compare/v0.1.1...v0.1.2
[0.1.1]: https://gitlab.com/devnw/zig/uri/-/compare/v0.1.0...v0.1.1
[0.1.0]: https://gitlab.com/devnw/zig/uri/-/compare/v0.0.1...v0.1.0
[0.0.1]: https://gitlab.com/devnw/zig/uri/-/releases/v0.0.1
