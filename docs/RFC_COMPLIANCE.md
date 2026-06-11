# RFC Compliance

This document details the RFC compliance status of the URI library.

## Supported RFCs

| RFC | Title | Status | Issues |
|-----|-------|--------|--------|
| RFC 3986 | URI Generic Syntax | **Implemented** | [#1](https://gitlab.com/devnw/zig/uri/-/issues/1), [#2](https://gitlab.com/devnw/zig/uri/-/issues/2), [#3](https://gitlab.com/devnw/zig/uri/-/issues/3) |
| RFC 8141 | URN Syntax | **Implemented** | [#5](https://gitlab.com/devnw/zig/uri/-/issues/5) |
| RFC 3987 | IRI Syntax | Planned | [#13](https://gitlab.com/devnw/zig/uri/-/issues/13), [#14](https://gitlab.com/devnw/zig/uri/-/issues/14), [#15](https://gitlab.com/devnw/zig/uri/-/issues/15) |
| RFC 6874 | IPv6 Zone ID | Planned | [#16](https://gitlab.com/devnw/zig/uri/-/issues/16), [#17](https://gitlab.com/devnw/zig/uri/-/issues/17), [#18](https://gitlab.com/devnw/zig/uri/-/issues/18) |
| WHATWG | URL Standard | Partial | [#19](https://gitlab.com/devnw/zig/uri/-/issues/19) |

## RFC 3986 - URI Generic Syntax

### Section 3: Syntax Components

| Component | Status | Notes |
|-----------|--------|-------|
| 3.1 Scheme | ✅ Implemented | Case-insensitive matching |
| 3.2 Authority | ✅ Implemented | Full userinfo@host:port support |
| 3.2.1 Userinfo | ✅ Implemented | Includes deprecated password |
| 3.2.2 Host | ✅ Implemented | Reg-name, IPv4, IPv6 |
| 3.2.3 Port | ✅ Implemented | Optional, validated 0-65535 |
| 3.3 Path | ✅ Implemented | All path types |
| 3.4 Query | ✅ Implemented | Preserved as-is |
| 3.5 Fragment | ✅ Implemented | Preserved as-is |

### Section 4: URI Reference

| Feature | Status | Notes |
|---------|--------|-------|
| URI | ✅ Implemented | Absolute URI with scheme |
| Relative-ref | ✅ Implemented | No scheme |
| Absolute-URI | ✅ Implemented | No fragment |

### Section 5: Reference Resolution

| Feature | Status | Notes |
|---------|--------|-------|
| 5.2.1 Pre-parse | ✅ Implemented | |
| 5.2.2 Transform | ✅ Implemented | Full algorithm |
| 5.2.3 Merge Paths | ✅ Implemented | |
| 5.2.4 Remove Dot Segments | ✅ Implemented | |

### Section 6: Normalization

| Feature | Status | Notes |
|---------|--------|-------|
| 6.2.2.1 Case Normalization | ✅ Implemented | Scheme, host |
| 6.2.2.2 Percent-Encoding | ✅ Implemented | Decode unreserved, uppercase hex |
| 6.2.2.3 Path Segment | ✅ Implemented | Dot removal |
| 6.2.3 Scheme-Based | ✅ Implemented | Default port removal, empty path |

> **Security note (ordering):** Dot-segment removal operates on the *syntactic*
> path **before** percent-decoding. This means percent-encoded dots (`%2E`) are
> **not** activated as directory traversal — e.g. `http://h/a/b/%2e%2e/c`
> normalizes to a path that retains the `b` segment rather than collapsing to
> `/a/c`. Consumers that treat encoded segments as opaque are not surprised by a
> normalize step turning them into traversal.

## RFC 8141 - URN Syntax

| Feature | Status | Notes |
|---------|--------|-------|
| NID parsing | ✅ Implemented | Namespace Identifier |
| NSS parsing | ✅ Implemented | Namespace Specific String |
| r-component | ✅ Implemented | Resolution hints (?+) |
| q-component | ✅ Implemented | Query (?=) |
| f-component | ✅ Implemented | Fragment (#) |

## RFC 3987 - IRI Syntax (Planned)

> See milestone [v0.3.0 - IRI Support](https://gitlab.com/devnw/zig/uri/-/milestones/3)

| Feature | Status | Issue |
|---------|--------|-------|
| Unicode in path | ❌ Planned | [#13](https://gitlab.com/devnw/zig/uri/-/issues/13) |
| Unicode in query | ❌ Planned | [#13](https://gitlab.com/devnw/zig/uri/-/issues/13) |
| IRI ↔ URI conversion | ❌ Planned | [#14](https://gitlab.com/devnw/zig/uri/-/issues/14) |
| Unicode normalization | ❌ Planned | [#15](https://gitlab.com/devnw/zig/uri/-/issues/15) |

## RFC 6874 - IPv6 Zone ID (Planned)

> See milestone [v0.4.0 - IPv6 Enhancements](https://gitlab.com/devnw/zig/uri/-/milestones/4)

| Feature | Status | Issue |
|---------|--------|-------|
| Zone ID parsing | ❌ Planned | [#16](https://gitlab.com/devnw/zig/uri/-/issues/16) |
| Zone ID encoding (%25) | ❌ Planned | [#16](https://gitlab.com/devnw/zig/uri/-/issues/16) |
| IPv6 validation | ❌ Planned | [#17](https://gitlab.com/devnw/zig/uri/-/issues/17) |

## WHATWG URL Standard (Partial)

> See [#19](https://gitlab.com/devnw/zig/uri/-/issues/19)

The WHATWG URL Standard differs from RFC 3986 in several ways. Current status:

| Feature | Status | Notes |
|---------|--------|-------|
| Basic parsing | ✅ Works | Compatible with RFC 3986 |
| Special schemes | ❌ Not yet | file, http, https, ws, wss, ftp |
| Backslash normalization | ❌ Not yet | Windows path support |
| Host parsing | 🔄 Partial | IDNA not implemented |
| blob: URLs | ❌ Not yet | |
| javascript: URLs | ❌ Not yet | |

## Test Coverage

The library includes comprehensive test suites:

- **RFC 3986 Test Vectors** (`tests/rfc3986_vectors.zig`)
  - Examples from RFC 3986 Section 5.4
  - Reference resolution test cases

- **Acceptance Tests** (`tests/accept.zig`)
  - T1: Basic URI parsing
  - T2: Reference resolution
  - T3: Normalization
  - T4: URN support
  - T5: Registry operations

- **URI Dataset** (`tests/uri_dataset.zig`)
  - 500+ test cases
  - All major schemes and protocols
  - Edge cases and special characters

## References

- [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986) - Uniform Resource Identifier (URI): Generic Syntax
- [RFC 8141](https://www.rfc-editor.org/rfc/rfc8141) - Uniform Resource Names (URNs)
- [RFC 3987](https://www.rfc-editor.org/rfc/rfc3987) - Internationalized Resource Identifiers (IRIs)
- [RFC 6874](https://www.rfc-editor.org/rfc/rfc6874) - Representing IPv6 Zone Identifiers in URIs
- [WHATWG URL Standard](https://url.spec.whatwg.org/) - Living Standard for URLs
