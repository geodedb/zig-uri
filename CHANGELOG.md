# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://gitlab.com/devnw/zig/uri/-/compare/v0.1.0...HEAD
[0.1.0]: https://gitlab.com/devnw/zig/uri/-/compare/v0.0.1...v0.1.0
[0.0.1]: https://gitlab.com/devnw/zig/uri/-/releases/v0.0.1
