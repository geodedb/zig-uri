# Gap Analysis
## Gaps

> Generated: 2026-03-23 | Re-Audit: 2026-03-24
> Scope: All 32 tracked requirements for devnw/zig/uri
> Baseline: commit 2b27b53 (main)
> Total open gaps: 0
> Closed: 33 | Won't Do: 13 | Blocked: 0
> Re-audit added 18 findings (GAP-0029 through GAP-0046), all Closed.

### GAP-0001: CI/CD has no build or test stages
- **Status: Won't Do** (requires CI runner provisioning with Zig 0.15.x toolchain; tracked via issue #22 for future sprint)
- **Issue:** [#22](https://gitlab.com/devnw/zig/uri/-/issues/22)
- **Category:** CI-CD
- **Severity:** Critical
- **Requirement source:** README.md roadmap v1.0.0 item #22; `.gitlab-ci.yml`
- **Current state (evidence):**
  - `.gitlab-ci.yml`:1-42 -- Only includes security scanning (SAST, dependency scanning, secrets, gitleaks), SBOM generation, and release stages. No `build` or `test` stages exist.
  - `.gitlab-ci.yml`:5 -- Comment reads: `NOTE: Build/test skipped - requires Zig 0.15.x which is not yet released.`
  - `build.zig.zon`:14 -- `minimum_zig_version = "0.15.1"` confirming Zig 0.15.1+ is required. Zig 0.15.2 is publicly available.
- **Why this is a gap:** The CI comment claims Zig 0.15.x is unreleased, but it has been available since before this analysis. Every commit merges without any compilation or test verification.
- **Impact/Risk:** Regressions ship undetected. The existing test failure (GAP-0002) proves this -- it has been in main for multiple commits. No gating means broken code reaches releases.
- **Recommended fix:** Add `build` and `test` stages to `.gitlab-ci.yml` using a Zig 0.15.x Docker image or Nix shell. Run `zig build test-all` as a pipeline gate. Remove the outdated comment.
- **Acceptance criteria:** CI pipeline runs `zig build test-all` on every MR and push to main. Pipeline fails if any test fails.

---

### GAP-0002: Dataset test failure -- Data URLs with angle brackets
- **Status: Closed / Implemented** (2026-03-23)
- **Issue:** None (new finding, no existing GitLab issue)
- **Category:** Bug
- **Severity:** High
- **Requirement source:** Requirement #1 (RFC 3986 parsing); `tests/uri_dataset.zig`
- **Current state (evidence):**
  - `zig build test-all` output: `error: 'uri_dataset.test.Data URLs' failed` -- `ParseError.InvalidCharacter` at `uri.zig:829`
  - `tests/uri_dataset.zig`:556 -- Test case `data:text/html,<h1>Hello</h1>` expects successful parse, but `<` and `>` are rejected by strict validation.
  - `src/uri.zig`:794-831 -- `validateInput()` with default strict mode rejects characters not in unreserved, sub-delims, or gen-delims sets. `<` and `>` are not in those sets per RFC 3986.
- **Why this is a gap:** The test expects strict-mode parsing to accept `<` and `>`, which violates RFC 3986 Section 2.2. Either the test expectation is wrong (the URI should be percent-encoded) or the parser needs a lenient/data-URI mode. As-is, `zig build test-all` fails on main.
- **Impact/Risk:** Test suite does not pass cleanly. CI cannot gate on `test-all` until resolved. Erodes confidence in test reliability.
- **Recommended fix:** Either (a) percent-encode the angle brackets in the test case to `%3C` and `%3E`, or (b) add a separate test that uses `parseWithOptions` with `strict: false`, or (c) skip that specific test case with a comment explaining RFC 3986 non-compliance.
- **Acceptance criteria:** `zig build test-all` passes with 0 test failures.
- **Resolution:** Test case angle brackets percent-encoded to `%3C` and `%3E`. All dataset tests now pass (57 test cases, 0 failures). `zig build test-all` completes with 0 failures across 302 tests.

---

### GAP-0003: Version constant 0.0.0 disagrees with build.zig.zon 0.1.0
- **Status: Closed / Implemented** (2026-03-23)
- **Issue:** [#31](https://gitlab.com/devnw/zig/uri/-/issues/31)
- **Category:** Bug
- **Severity:** Medium
- **Requirement source:** Internal consistency; `src/lib.zig` vs `build.zig.zon`
- **Current state (evidence):**
  - `src/lib.zig`:264-268 -- `version = std.SemanticVersion{ .major = 0, .minor = 0, .patch = 0 }`
  - `build.zig.zon`:8 -- `.version = "0.1.0"`
  - `README.md`:6 -- `Current Version: v0.1.0`
- **Why this is a gap:** The programmatic version constant reports 0.0.0 while all other sources say 0.1.0. Consumers checking `lib.version` at runtime get incorrect information.
- **Impact/Risk:** Any downstream code relying on `uri.version` for compatibility checks will get wrong data. Misleading for debugging and version-gated behavior.
- **Recommended fix:** Update `lib.zig` version constant to `.minor = 1`.
- **Acceptance criteria:** `lib.zig` version constant matches `build.zig.zon` version string exactly.
- **Resolution:** Updated `src/lib.zig:269` to `.minor = 1`, matching `build.zig.zon` version `"0.1.0"`.

---

### GAP-0004: Duplicate parser in parallel.zig diverges from core parser
- **Status: Closed / Implemented** (2026-03-23)
- **Issue:** [#30](https://gitlab.com/devnw/zig/uri/-/issues/30)
- **Category:** Code Quality
- **Severity:** High
- **Requirement source:** Requirement #30 (parallel ops); architectural consistency
- **Current state (evidence):**
  - `src/parallel.zig`:190-296 -- `parseUri()` and `parseHostPort()` implement a second, independent URI parser (106 lines) that does not call `uri.parse()` or `uri.parseWithOptions()`.
  - `src/uri.zig`:284-352 -- Core parser with full RFC 3986 validation.
  - Divergences observed:
    - parallel.zig skips `validateInput()` -- no strict character validation.
    - parallel.zig uses its own `UriComponents` struct (line 100-108) instead of `uri.Uri`.
    - parallel.zig returns a different error model (`error_code: u8` vs `ParseError` enum).
    - parallel.zig normalizes default ports in `normalizeUri()` (lines 576-596), but `uri.normalize()` (line 663-694) does not.
- **Why this is a gap:** Two parsers that can produce different results for the same input create inconsistency. The parallel parser is less strict and may accept invalid URIs that the core parser rejects. Maintenance cost doubles for any parser fix.
- **Impact/Risk:** Users get different parsing behavior depending on whether they use `parse()` vs `parallel.parseUris()`. The parallel normalizer removes default ports while the core normalizer does not -- semantically different output for the same URI.
- **Recommended fix:** Refactor `parallel.zig` to delegate to `uri.parse()` internally, wrapping results into the parallel result type. Remove the duplicate parser logic. Align normalization behavior.
- **Acceptance criteria:** `parallel.parseUris()` produces identical parse results to `uri.parse()` for all inputs. `parallel.normalizeUris()` produces identical normalization to `uri.normalize()`. Only one parser implementation exists.
- **Resolution:** Replaced the standalone `parseUri()` in `src/parallel.zig` with a delegation to `uri_mod.parse()`. The `parseUri` function now calls the core parser and maps the result to `ParseResult`/`UriComponents`. Similarly, `normalizeUri()` now delegates to `uri_mod.parse()` followed by `uri_mod.normalize()`. The duplicate parser code (106 lines) and duplicate normalizer code were removed entirely. Error handling uses `parseErrorMessage()` to convert `ParseError` to human-readable strings. All 13 parallel tests pass.

---

### GAP-0005: lib.zig doc header falsely claims RFC 3987 and RFC 6874 compliance
- **Status: RESOLVED**
- **Issue:** None (new finding, no existing GitLab issue)
- **Category:** Docs
- **Severity:** Medium
- **Requirement source:** Documentation accuracy; `src/lib.zig`
- **Current state (evidence):**
  - `src/lib.zig`:7-10 -- Claims adherence to RFC 3987 (IRI), RFC 6874 (IPv6 Zone ID), and WHATWG URL Standard.
  - `docs/RFC_COMPLIANCE.md`:66-99 -- All three are listed as "Planned" or "Partial" with no implementation.
  - `src/lib.zig`:105-107 -- RFC compliance matrix in the doc comments correctly marks RFC 3987 as "Planned" and RFC 6874 as "Planned", contradicting lines 7-10 in the same file.
- **Why this is a gap:** The module-level doc comment states the library "strictly adheres to" standards it does not implement. This is misleading to users reading auto-generated docs.
- **Impact/Risk:** Users may adopt the library expecting IRI or IPv6 Zone ID support and discover it is absent at runtime.
- **Recommended fix:** Change lines 7-10 to only list RFC 3986 and RFC 8141. Add a "Planned" section listing RFC 3987, RFC 6874, and WHATWG.
- **Acceptance criteria:** Module doc header only claims compliance with actually-implemented RFCs.
- **Resolution:** Header now lists only RFC 3986 and RFC 8141 as implemented. RFC 3987, RFC 6874, and WHATWG moved to a "Planned" subsection. "Unicode support" claim removed. "Zero dependencies" updated to "Minimal dependencies" to reflect optional spice dependency.

---

### GAP-0006: build.zig.zon header falsely claims RFC 7320 and WHATWG compliance
- **Status: RESOLVED**
- **Issue:** None (new finding, no existing GitLab issue)
- **Category:** Docs
- **Severity:** Low
- **Requirement source:** Documentation accuracy; `build.zig.zon`
- **Current state (evidence):**
  - `build.zig.zon`:3-4 -- Comment claims `RFC 7320 (URI Design), WHATWG URL Standard compliant`
  - RFC 7320 is not mentioned anywhere else in the codebase and is not implemented.
  - WHATWG is acknowledged as "Partial" in `docs/RFC_COMPLIANCE.md`:87-100.
- **Why this is a gap:** Claims compliance with standards that are not implemented or tracked.
- **Impact/Risk:** Minor -- comments in `build.zig.zon` are less visible than module docs, but still misleading.
- **Recommended fix:** Remove RFC 7320 and WHATWG claims from the `build.zig.zon` comment. Mention only RFC 3986 and RFC 8141.
- **Acceptance criteria:** `build.zig.zon` comment accurately reflects implemented standards.
- **Resolution:** Comment now lists "Implements: RFC 3986 (URI), RFC 8141 (URN)" and "Planned: RFC 3987 (IRI), RFC 6874 (IPv6 Zone ID), WHATWG URL Standard". RFC 7320 removed entirely.

---

### GAP-0007: Normalization missing percent-encoding normalization (RFC 3986 6.2.2.2)
- **Status: RESOLVED**
- **Issue:** [#3](https://gitlab.com/devnw/zig/uri/-/issues/3), [#10](https://gitlab.com/devnw/zig/uri/-/issues/10)
- **Category:** Requirement
- **Severity:** High
- **Requirement source:** Requirement #3 (normalization), RFC 3986 Section 6.2.2.2; GitLab issue #10
- **Resolution:** Implemented `normalizePercentEncoding()` helper in `src/uri.zig` that decodes percent-encoded unreserved characters (ALPHA, DIGIT, `-`, `.`, `_`, `~`) and uppercases hex digits for remaining encoded sequences. Applied to path, query, fragment, and userinfo in `normalize()`. Six new tests verify the behavior: unreserved ALPHA decoding, tilde decoding, hex digit uppercasing, space preservation, mixed query/fragment, and userinfo normalization.

---

### GAP-0008: Normalization missing scheme-based normalization (RFC 3986 6.2.3)
- **Status: RESOLVED**
- **Issue:** [#29](https://gitlab.com/devnw/zig/uri/-/issues/29)
- **Category:** Requirement
- **Severity:** Medium
- **Requirement source:** Requirement #3 (normalization), RFC 3986 Section 6.2.3; GitLab issue #29; README roadmap v1.0.0
- **Resolution:** `normalize()` now calls `defaultPort()` and removes the port when it matches the scheme's default. Also ensures empty path becomes `/` when authority is present. The parallel normalizer test was updated to align with the core behavior. Six new tests verify: default port removal for http (80), https (443), ftp (21), non-default port preservation (8080), empty path slash addition, and uppercase scheme with default port.

---

### GAP-0009: ParseOptions struct exists but has zero test coverage
- **Status: Resolved** (2026-03-23)
- **Issue:** [#8](https://gitlab.com/devnw/zig/uri/-/issues/8)
- **Category:** Test
- **Severity:** High
- **Requirement source:** Requirement #8 (ParseOptions); v0.2.0 milestone
- **Current state (evidence):**
  - `src/uri.zig`:65-72 -- `ParseOptions` with fields `strict`, `allow_spaces`, `iri_mode`.
  - `src/uri.zig`:289 -- `parseWithOptions(input, options)` used by `parse()`.
  - `src/uri.zig`:794-831 -- `validateInput()` reads all three options.
  - Grep for `parseWithOptions` or `ParseOptions` in `tests/` directory: no matches.
  - Grep in `src/uri.zig` tests (lines 888-1093): No test calls `parseWithOptions` with non-default options.
- **Why this is a gap:** The `allow_spaces` and `iri_mode` options exist in code and are exercised by `validateInput()`, but no test verifies their behavior. `strict: false` is also untested.
- **Impact/Risk:** Regressions in options handling will not be caught. Users cannot rely on documented lenient/IRI modes working correctly.
- **Recommended fix:** Add test cases: (1) `parseWithOptions` with `strict: false` accepts `<` and `>`, (2) `parseWithOptions` with `allow_spaces: true` accepts spaces, (3) `parseWithOptions` with `iri_mode: true` accepts UTF-8, (4) default strict mode rejects all of the above.
- **Acceptance criteria:** At least 4 tests cover non-default ParseOptions. Each option field has at least one positive and one negative test.
- **Resolution:** Added 9 inline tests in `src/uri.zig` covering all three `ParseOptions` fields (`strict`, `allow_spaces`, `iri_mode`) with both positive (accepts) and negative (rejects) cases, plus cross-option interaction tests. All 150 tests pass.

---

### GAP-0010: Component-specific encoding only tested for path component
- **Status: Closed / Implemented** (2026-03-23)
- **Issue:** [#9](https://gitlab.com/devnw/zig/uri/-/issues/9)
- **Category:** Test
- **Severity:** Medium
- **Requirement source:** Requirement #9 (component-specific encoding); v0.2.0 milestone
- **Current state (evidence):**
  - `src/uri.zig`:780-792 -- `isAllowedInComponent()` implements distinct rules for all 7 components (scheme, userinfo, host, port, path, query, fragment).
  - `src/uri.zig`:951-957 -- Only test for `percentEncode` uses `.path` component.
  - `tests/accept.zig`:326-336 -- Roundtrip test also uses `.path` only.
- **Why this is a gap:** 6 of 7 component encoding paths have zero test coverage. The scheme encoding (rejects non-alphanumeric except `+`, `-`, `.`) and userinfo encoding (includes `:`) have different character sets that are never verified.
- **Impact/Risk:** Bugs in component-specific encoding for query, fragment, userinfo, host, scheme, or port will not be detected.
- **Recommended fix:** Add tests for `percentEncode` with each component type, verifying that component-specific characters are preserved and others are encoded.
- **Acceptance criteria:** Each of the 7 `Component` enum values has at least one `percentEncode` test case.
- **Resolution:** Added 13 inline tests in `src/uri.zig` covering all 7 `Component` enum values (query, userinfo, fragment, host, scheme, port, path). Each component has at least one positive (allows expected characters) and one negative (encodes disallowed characters) test. All tests pass.

---

### GAP-0011: Four ParseError variants are unreachable (dead code)
- **Status: RESOLVED**
- **Issue:** [#23](https://gitlab.com/devnw/zig/uri/-/issues/23)
- **Category:** Code Quality
- **Severity:** Low
- **Requirement source:** Requirement #23 (error handling)
- **Resolution:** Removed the four unreachable variants (`InvalidIPv4`, `InvalidIPv6`, `EmptyScheme`, `MissingHost`) from the `ParseError` error set, the `parseErrorMessage` switch in `parallel.zig`, and the `docs/API.md` documentation. These can be re-added when IPv4/IPv6 validation is implemented (see GAP-0017).

---

### GAP-0012: Enhanced percent-encoding normalization not implemented
- **Status: RESOLVED**
- **Issue:** [#10](https://gitlab.com/devnw/zig/uri/-/issues/10)
- **Category:** Feature
- **Severity:** Medium
- **Requirement source:** GitLab issue #10; README roadmap v0.2.0
- **Resolution:** Implemented as part of GAP-0007 fix. The `normalizePercentEncoding()` function decodes unreserved characters and uppercases hex digits. Applied to path, query, fragment, and userinfo components.

---

### GAP-0013: URI builder API not implemented
- **Status: Won't Do** (v0.2.0 milestone feature; not in scope for current gap closure)
- **Issue:** [#11](https://gitlab.com/devnw/zig/uri/-/issues/11)
- **Category:** Feature
- **Severity:** Medium
- **Requirement source:** GitLab issue #11; README roadmap v0.2.0
- **Current state (evidence):**
  - No builder API found in any source file. `Uri.format()` exists for serialization but there is no fluent builder for constructing URIs from components.
- **Why this is a gap:** Listed as v0.2.0 deliverable. Users must manually construct `Uri` structs.
- **Impact/Risk:** Blocks v0.2.0 milestone. Users lack a safe API for constructing URIs with proper encoding.
- **Recommended fix:** Implement a `UriBuilder` struct with methods like `setScheme()`, `setHost()`, `setPath()`, `setQuery()`, `build()` that handles encoding.
- **Acceptance criteria:** Builder API exists, handles percent-encoding automatically, and has tests for at least: scheme-only, full URI, relative reference, and URI with special characters.

---

### GAP-0014: Query string parser not implemented
- **Status: Won't Do** (v0.2.0 milestone feature; not in scope for current gap closure)
- **Issue:** [#12](https://gitlab.com/devnw/zig/uri/-/issues/12)
- **Category:** Feature
- **Severity:** Medium
- **Requirement source:** GitLab issue #12; README roadmap v0.2.0
- **Current state (evidence):**
  - No query parsing function found. `uri.query` returns the raw query string but does not parse key-value pairs.
- **Why this is a gap:** Listed as v0.2.0 deliverable. Query parsing (splitting on `&` and `=`, decoding values) is a common need.
- **Impact/Risk:** Blocks v0.2.0 milestone.
- **Recommended fix:** Add `parseQuery()` function returning an iterator or slice of key-value pairs.
- **Acceptance criteria:** Function exists that parses `key1=value1&key2=value2` into iterable pairs. Handles percent-decoded values. Tests cover empty query, single pair, multiple pairs, missing value, and encoded characters.

---

### GAP-0015: IRI syntax support not implemented (RFC 3987)
- **Status: Won't Do** (v0.3.0 milestone feature; not in scope for current gap closure)
- **Issue:** [#13](https://gitlab.com/devnw/zig/uri/-/issues/13), [#14](https://gitlab.com/devnw/zig/uri/-/issues/14), [#15](https://gitlab.com/devnw/zig/uri/-/issues/15)
- **Category:** Feature
- **Severity:** Low
- **Requirement source:** GitLab issues #13, #14, #15; README roadmap v0.3.0
- **Current state (evidence):**
  - `ParseOptions.iri_mode` exists but only allows high bytes (>= 0x80) through `validateInput()`. No actual IRI-specific parsing, normalization, or conversion is implemented.
  - No IRI-to-URI or URI-to-IRI conversion functions exist.
- **Why this is a gap:** v0.3.0 milestone deliverable, entirely unimplemented beyond a validation bypass flag.
- **Impact/Risk:** Blocks v0.3.0 milestone. `iri_mode: true` allows bytes through but does not perform proper Unicode handling.
- **Recommended fix:** Implement in v0.3.0 cycle. Add IRI parsing with UTF-8 validation, IRI-to-URI conversion with percent-encoding of non-ASCII, and Unicode normalization (NFC).
- **Acceptance criteria:** IRI with non-ASCII characters in path/query is parsed correctly. `iri_mode` performs UTF-8 validation. Conversion functions produce RFC-compliant output.

---

### GAP-0016: IPv6 Zone ID parsing not implemented (RFC 6874)
- **Status: Won't Do** (v0.4.0 milestone feature; not in scope for current gap closure)
- **Issue:** [#16](https://gitlab.com/devnw/zig/uri/-/issues/16)
- **Category:** Feature
- **Severity:** Low
- **Requirement source:** GitLab issues #16, #17, #18; README roadmap v0.4.0
- **Current state (evidence):**
  - No zone ID parsing in `parseAuthority()` (uri.zig:386-438). IPv6 addresses in brackets are captured but zone IDs (e.g., `[fe80::1%25eth0]`) are not recognized or extracted.
- **Why this is a gap:** v0.4.0 milestone deliverable, not implemented.
- **Impact/Risk:** Link-local IPv6 addresses with zone IDs cannot be represented. Blocks v0.4.0.
- **Recommended fix:** Implement in v0.4.0 cycle.
- **Acceptance criteria:** Parser extracts zone ID from `[fe80::1%25eth0]`. Zone ID is accessible as a field. Tests cover zone ID presence and absence.

---

### GAP-0017: IPv6 address validation not implemented
- **Status: Won't Do** (v0.4.0 milestone feature; not in scope for current gap closure)
- **Issue:** [#17](https://gitlab.com/devnw/zig/uri/-/issues/17)
- **Category:** Feature
- **Severity:** Low
- **Requirement source:** GitLab issue #17; README roadmap v0.4.0
- **Current state (evidence):**
  - `src/uri.zig`:397-404 -- Parser captures content between `[` and `]` without validating it is a well-formed IPv6 address.
  - `ParseError.InvalidIPv6` exists (line 40) but is never returned (see GAP-0011).
- **Why this is a gap:** `http://[not-an-ipv6-address]/path` parses successfully without error.
- **Impact/Risk:** Invalid URIs accepted silently. v0.4.0 blocker.
- **Recommended fix:** Implement IPv6 address format validation in `parseAuthority()`. Return `InvalidIPv6` for malformed addresses.
- **Acceptance criteria:** `http://[invalid]/path` returns `InvalidIPv6`. Valid IPv6 forms (full, compressed, IPv4-mapped) are accepted.

---

### GAP-0018: IPv6/IPvFuture normalization not implemented
- **Status: Won't Do** (v0.4.0 milestone feature; not in scope for current gap closure)
- **Issue:** [#18](https://gitlab.com/devnw/zig/uri/-/issues/18)
- **Category:** Feature
- **Severity:** Low
- **Requirement source:** GitLab issue #18; README roadmap v0.4.0
- **Current state (evidence):**
  - `src/uri.zig`:677-686 -- `normalize()` skips lowercasing for IPv6 hosts (`h[0] == '['`), but does not normalize IPv6 representation (e.g., compress `::0:0:0` to `::`). IPvFuture (`[v1.addr]`) is not handled.
- **Why this is a gap:** v0.4.0 deliverable.
- **Impact/Risk:** Blocks v0.4.0.
- **Recommended fix:** Implement in v0.4.0 cycle.
- **Acceptance criteria:** IPv6 addresses are normalized to canonical compressed form. IPvFuture addresses are preserved.

---

### GAP-0019: WHATWG URL Standard compatibility not implemented
- **Status: Won't Do** (v1.0.0 milestone feature; not in scope for current gap closure)
- **Issue:** [#19](https://gitlab.com/devnw/zig/uri/-/issues/19)
- **Category:** Feature
- **Severity:** Low
- **Requirement source:** GitLab issue #19; README roadmap v1.0.0
- **Current state (evidence):**
  - `docs/RFC_COMPLIANCE.md`:87-100 -- Lists 5 WHATWG features as "Not yet", 1 as "Partial".
  - No WHATWG-specific parsing code exists.
- **Why this is a gap:** v1.0.0 milestone deliverable, not implemented.
- **Impact/Risk:** Blocks v1.0.0. Web browser URL compatibility unavailable.
- **Recommended fix:** Implement in v1.0.0 cycle per WHATWG URL Standard.
- **Acceptance criteria:** Special scheme handling, backslash normalization, and IDNA host parsing work per WHATWG spec.

---

### GAP-0020: API documentation not auto-published
- **Status: Won't Do** (v1.0.0 milestone feature; requires GitLab Pages deployment configuration)
- **Issue:** [#20](https://gitlab.com/devnw/zig/uri/-/issues/20)
- **Category:** Docs
- **Severity:** Low
- **Requirement source:** GitLab issue #20; README roadmap v1.0.0
- **Current state (evidence):**
  - `docs/API.md` exists with manual documentation.
  - `build.zig`:209-217 -- `docs` build step generates Zig auto-docs via `getEmittedDocs()`.
  - `.gitlab-ci.yml` has no docs deployment stage.
- **Why this is a gap:** Docs are generated locally but not published. GitLab Pages or similar deployment is not configured.
- **Impact/Risk:** Users cannot view API docs online. v1.0.0 blocker.
- **Recommended fix:** Add a GitLab Pages deployment stage to CI that runs `zig build docs` and publishes to Pages.
- **Acceptance criteria:** API docs are auto-published and accessible via GitLab Pages URL on every main branch push.

---

### GAP-0021: Performance benchmarks not implemented
- **Status: Won't Do** (v1.0.0 milestone feature; not in scope for current gap closure)
- **Issue:** [#21](https://gitlab.com/devnw/zig/uri/-/issues/21)
- **Category:** Performance
- **Severity:** Low
- **Requirement source:** GitLab issue #21; README roadmap v1.0.0
- **Current state (evidence):**
  - No benchmark files found. No `zig build bench` step in `build.zig`.
- **Why this is a gap:** v1.0.0 milestone deliverable.
- **Impact/Risk:** No performance baseline; regressions undetectable.
- **Recommended fix:** Add benchmarks for parse, normalize, resolve, and percentEncode/Decode operations.
- **Acceptance criteria:** `zig build bench` runs and reports throughput for core operations.

---

### GAP-0022: Zig package registry publishing not done
- **Status: Won't Do** (v1.0.0 milestone feature; not in scope for current gap closure)
- **Issue:** [#26](https://gitlab.com/devnw/zig/uri/-/issues/26)
- **Category:** CI-CD
- **Severity:** Low
- **Requirement source:** GitLab issue #26; README roadmap v1.0.0
- **Current state (evidence):**
  - Package is available via GitLab archive URL (build.zig.zon shows this), but not published to the Zig package index.
- **Why this is a gap:** v1.0.0 milestone deliverable.
- **Impact/Risk:** Discoverability reduced. Users must manually add the URL.
- **Recommended fix:** Publish to Zig package index when v1.0.0 is reached.
- **Acceptance criteria:** Package is discoverable via `zig fetch` from the official package index.

---

### GAP-0023: Streaming parser not implemented
- **Status: Won't Do** (v1.0.0 milestone feature; not in scope for current gap closure)
- **Issue:** [#27](https://gitlab.com/devnw/zig/uri/-/issues/27)
- **Category:** Feature
- **Severity:** Low
- **Requirement source:** GitLab issue #27; README roadmap v1.0.0
- **Current state (evidence):**
  - No streaming/incremental parser API found.
- **Why this is a gap:** v1.0.0 milestone deliverable.
- **Impact/Risk:** Blocks v1.0.0. Large URI processing requires full string in memory.
- **Recommended fix:** Implement in v1.0.0 cycle.
- **Acceptance criteria:** Streaming parser API exists that can consume URI data incrementally.

---

### GAP-0024: WebAssembly target not verified
- **Status: Won't Do** (v1.0.0 milestone feature; not in scope for current gap closure)
- **Issue:** [#28](https://gitlab.com/devnw/zig/uri/-/issues/28)
- **Category:** Feature
- **Severity:** Low
- **Requirement source:** GitLab issue #28; README roadmap v1.0.0
- **Current state (evidence):**
  - No WASM-specific build targets, tests, or CI verification.
  - Library is pure Zig with no OS-specific code, so it likely compiles to WASM, but this is not verified.
- **Why this is a gap:** v1.0.0 milestone deliverable. Not verified in CI.
- **Impact/Risk:** Blocks v1.0.0. May break silently if OS-specific code is added.
- **Recommended fix:** Add WASM cross-compilation step to CI. Verify with `zig build -Dtarget=wasm32-wasi`.
- **Acceptance criteria:** CI verifies WASM compilation succeeds. Tests pass under WASM runtime.

---

### GAP-0025: Uri.deinit() unsafe on non-duped URIs
- **Status: Closed / Implemented** (2026-03-23)
- **Issue:** [#25](https://gitlab.com/devnw/zig/uri/-/issues/25)
- **Category:** Security
- **Severity:** Medium
- **Requirement source:** Requirement #25 (memory safety audit)
- **Current state (evidence):**
  - No documentation of a memory safety audit.
  - `src/uri.zig`:268 -- `deinit()` frees `self.path` only when `path.len > 0`, but parsed URIs have paths that are slices into the input (not allocated). Only `dupe()`d or `resolve()`d URIs have allocated paths. A caller who calls `deinit()` on a non-duped URI will attempt to free a non-owned slice, causing undefined behavior.
  - `src/uri.zig`:269 -- Same issue with `self.raw`.
- **Why this is a gap:** The `deinit()` function is unsafe to call on parsed (non-duped) URIs. This is a use-after-free / double-free risk. There is no documentation warning about this, and no mechanism (e.g., `is_owned` flag) to prevent it.
- **Impact/Risk:** Memory corruption if users call `deinit()` on a parsed URI. Zig's allocator will likely panic on debug builds but may silently corrupt in release.
- **Recommended fix:** Either (a) add an `is_owned: bool` field that is set by `dupe()`/`resolve()` and checked by `deinit()`, or (b) document clearly that `deinit()` must only be called on URIs returned by `dupe()` or `normalize()`, or (c) rename to `deinitOwned()` to make the contract explicit.
- **Acceptance criteria:** Calling `deinit()` on a parsed (non-duped) URI either safely no-ops or fails with a clear error. Documentation states the ownership model.
- **Resolution:** Added `owned: bool = false` field to `Uri` struct (`src/uri.zig:138`). `dupe()` sets `owned = true`. `deinit()` returns early (safe no-op) when `owned == false`. `resolve()` now returns a fully owned Uri. Removed incorrect `path.len > 0` and `raw.len > 0` guards. 5 new ownership tests added. All tests pass.

---

### GAP-0026: Scheme-based normalization tracking
- **Status: RESOLVED**
- **Issue:** [#29](https://gitlab.com/devnw/zig/uri/-/issues/29)
- **Category:** Feature
- **Severity:** Medium
- **Requirement source:** GitLab issue #29; README roadmap v1.0.0
- **Resolution:** Resolved together with GAP-0008. Scheme-based normalization (default port removal, empty path normalization) is now implemented in the core `normalize()` function.

---

### GAP-0027: README roadmap issue numbers diverge from actual GitLab issues at v1.0.0
- **Issue:** [#32](https://gitlab.com/devnw/zig/uri/-/issues/32)
- **Category:** Docs
- **Severity:** Low
- **Requirement source:** Internal consistency; README.md roadmap
- **Current state (evidence):**
  - `README.md`:162 -- Lists `#11` as "Query string parsing" but the phase 2 scan calls requirement #11 "URI builder" and #12 "query parser". The README actually maps #11 to query and #12 to builder -- reversed from the scan.
  - v1.0.0 section maps #23 to "Zig package registry", #24 to "Scheme-based normalization", #25 to "Streaming parser", #26 to "WebAssembly target". These differ from the actual GitLab issues at those numbers.
- **Why this is a gap:** The README roadmap uses GitLab issue numbers that do not match actual issue titles. New issues #27-#29 were created for the features that were incorrectly referenced.
- **Impact/Risk:** Confusion when cross-referencing. No functional impact.
- **Recommended fix:** Update README roadmap to reference the correct issue numbers (#27, #28, #29 for streaming, WASM, scheme-normalization respectively).
- **Acceptance criteria:** All `#N` references in README link to the correct GitLab issue.
- **Status:** Resolved -- v1.0.0 issue numbers corrected: #26 (Package publishing), #27 (Streaming parser), #28 (WebAssembly target), #29 (Scheme-based normalization).

---

### GAP-0028: Normalization inconsistency between parallel and core modules
- **Status: Closed / Implemented** (2026-03-23)
- **Issue:** [#30](https://gitlab.com/devnw/zig/uri/-/issues/30)
- **Category:** Bug
- **Severity:** High
- **Requirement source:** Architectural consistency; requirements #3 and #30
- **Current state (evidence):**
  - `src/parallel.zig`:576-596 -- `normalizeUri()` removes default ports for http(80) and https(443).
  - `src/uri.zig`:662-694 -- `normalize()` does NOT remove default ports.
  - `src/parallel.zig`:599-628 -- parallel normalizer does not perform dot-segment removal.
  - `src/uri.zig`:688-691 -- core normalizer DOES perform dot-segment removal.
- **Why this is a gap:** Two normalization implementations produce different outputs for the same input. `normalizeUris(["http://example.com:80/a/../b"])` produces `http://example.com/a/../b` (no port, no dot removal). `normalize(parse("http://example.com:80/a/../b"))` produces `http://example.com:80/b` (has port, dot segments removed). Neither is fully correct.
- **Impact/Risk:** Users get semantically different results depending on which API they call. This is a correctness bug.
- **Recommended fix:** Eliminate the parallel normalizer's custom implementation. Delegate to `uri.normalize()` internally. See also GAP-0004.
- **Acceptance criteria:** `parallel.normalizeUris()` and `uri.normalize()` produce identical output for any given input.
- **Resolution:** The parallel `normalizeUri()` function was completely rewritten to delegate to `uri_mod.parse()` and `uri_mod.normalize()` (`src/parallel.zig:461-498`). The duplicate normalization logic was removed. Both APIs now produce identical output because they use the same underlying implementation. Scheme-based normalization (default port removal, empty path handling) is applied consistently. All parallel normalization tests pass.

---

## Re-Audit (2026-03-24)

> Re-audit of the codebase after initial gap closure. 41 total findings across all domains.
> 18 findings tracked here (GAP-0029 through GAP-0046).
> All 18 are Closed.
> Tests: 314/314 pass (up from 302 baseline, +12 new tests).

---

### GAP-0029: parseAuthority uses first @ instead of last @ for userinfo delimiter
- **Status: Closed / Implemented** (2026-03-24)
- **Issue:** [#34](https://gitlab.com/devnw/zig/uri/-/issues/34) (confidential)
- **Category:** Security
- **Severity:** High
- **Resolution:** `parseAuthority()` in `src/uri.zig` updated to use `lastIndexOf('@')` instead of `indexOf('@')` per RFC 3986 Section 3.2.1. Prevents userinfo spoofing with embedded `@` characters. New tests added for multi-@ URIs.

---

### GAP-0030: dupe() memory leak on partial allocation failure
- **Status: Closed / Implemented** (2026-03-24)
- **Issue:** [#35](https://gitlab.com/devnw/zig/uri/-/issues/35) (confidential)
- **Category:** Security
- **Severity:** High
- **Resolution:** Added `errdefer` guards to `dupe()` in `src/uri.zig` to free previously allocated fields when a subsequent allocation fails. Prevents memory leaks on OOM during partial duplication.

---

### GAP-0031: normalizeUri returned success=true on OOM
- **Status: Closed / Implemented** (2026-03-24)
- **Issue:** [#36](https://gitlab.com/devnw/zig/uri/-/issues/36) (confidential)
- **Category:** Security
- **Severity:** High
- **Resolution:** `normalizeUri()` in `src/parallel.zig` now correctly propagates allocation errors and sets `success = false` with an appropriate error message when OOM occurs during normalization.

---

### GAP-0032: Pool TOCTOU race in deinitPool/getPool
- **Status: Closed / Implemented** (2026-03-24)
- **Issue:** [#37](https://gitlab.com/devnw/zig/uri/-/issues/37) (confidential)
- **Category:** Security
- **Severity:** High
- **Resolution:** Eliminated TOCTOU race between `deinitPool()` and `getPool()` by using atomic operations on the `pool_initialized` flag with proper acquire/release ordering. Both functions now use the same mutex for state transitions.

---

### GAP-0033: docs/API.md listed removed ParseError variants
- **Status: Closed / Implemented** (2026-03-24)
- **Category:** Docs
- **Severity:** Low
- **Resolution:** Removed stale references to `InvalidIPv4`, `InvalidIPv6`, `EmptyScheme`, and `MissingHost` from `docs/API.md`. Documentation now matches the actual error set in `src/uri.zig`.

---

### GAP-0034: docs/API.md ownership model section outdated
- **Status: Closed / Implemented** (2026-03-24)
- **Category:** Docs
- **Severity:** Medium
- **Resolution:** Updated `docs/API.md` Uri struct documentation to include the `owned: bool` field and explain the borrowed vs. owned ownership model. Updated `resolve()` section with ownership paragraph.

---

### GAP-0035: docs/RFC_COMPLIANCE.md percent-encoding normalization status incorrect
- **Status: Closed / Implemented** (2026-03-24)
- **Category:** Docs
- **Severity:** Low
- **Resolution:** Updated `docs/RFC_COMPLIANCE.md` to reflect that percent-encoding normalization (Section 6.2.2.2) and scheme-based normalization (Section 6.2.3) are now implemented. Status changed from "Partial" to "Implemented".

---

### GAP-0036: docs/RFC_COMPLIANCE.md scheme-based normalization status incorrect
- **Status: Closed / Implemented** (2026-03-24)
- **Category:** Docs
- **Severity:** Low
- **Resolution:** Updated `docs/RFC_COMPLIANCE.md` Section 6.2.3 entry to "Implemented". Default port removal and empty-path normalization are functional.

---

### GAP-0037: README.md features list outdated after gap closure
- **Status: Closed / Implemented** (2026-03-24)
- **Category:** Docs
- **Severity:** Low
- **Resolution:** Updated `README.md` feature descriptions to reflect implemented normalization capabilities (percent-encoding normalization, scheme-based normalization, default port removal).

---

### GAP-0038: README.md dependency description inconsistent
- **Status: Closed / Implemented** (2026-03-24)
- **Category:** Docs
- **Severity:** Low
- **Resolution:** Ensured all README sections consistently describe the dependency situation as "Minimal dependencies" with the spice optional dependency for parallel operations.

---

### GAP-0039: SUPPORT.md contained outdated contact information
- **Status: Closed / Implemented** (2026-03-24)
- **Category:** Docs
- **Severity:** Low
- **Resolution:** Updated `SUPPORT.md` with current support channels and accurate project information.

---

### GAP-0040: examples/README.md contained incorrect example descriptions
- **Status: Closed / Implemented** (2026-03-24)
- **Category:** Docs
- **Severity:** Low
- **Resolution:** Updated `examples/README.md` to accurately describe the example programs including the updated resolution example that demonstrates the ownership model.

---

### GAP-0041: examples/02_uri_resolution.zig used incorrect deinit pattern
- **Status: Closed / Implemented** (2026-03-24)
- **Category:** Docs
- **Severity:** Medium
- **Resolution:** Updated `examples/02_uri_resolution.zig` to use the correct `resolved.deinit(allocator)` pattern instead of `allocator.free(resolved.path)`, matching the new ownership model.

---

### GAP-0042: SECURITY.md contained inaccurate security measures list
- **Status: Closed / Implemented** (2026-03-24)
- **Category:** Docs
- **Severity:** Medium
- **Resolution:** Updated `SECURITY.md` to remove false fuzz testing claim and accurately describe implemented security measures including ownership tracking, credential redaction, and input validation hardening.

---

### GAP-0043: .gitlab-ci.yml outdated Zig version comment
- **Status: Closed / Implemented** (2026-03-24)
- **Category:** Docs
- **Severity:** Low
- **Resolution:** Updated the comment in `.gitlab-ci.yml` to reflect current Zig 0.15.x availability status and reference issue #22 for CI build/test stage tracking.

---

### GAP-0044: register() errdefer missing on partial allocation failure
- **Status: Closed / Implemented** (2026-03-24)
- **Category:** Security
- **Severity:** Medium
- **Resolution:** Added `errdefer` guards to `register()` and related functions in `src/registry.zig` to properly clean up on partial allocation failures. Prevents memory leaks when registration fails partway through.

---

### GAP-0045: addAnchor() errdefer missing on allocation failure
- **Status: Closed / Implemented** (2026-03-24)
- **Category:** Security
- **Severity:** Medium
- **Resolution:** Added `errdefer` guard to `addAnchor()` in `src/registry.zig` to free the allocated anchor name if the subsequent hash map insertion fails.

---

### GAP-0046: ParseOptions not re-exported from lib.zig public API
- **Status: Closed / Implemented** (2026-03-24)
- **Category:** API
- **Severity:** Medium
- **Resolution:** Added `ParseOptions` to the public re-exports in `src/lib.zig` so consumers can access it directly via the library's root namespace. This is a duplicate of QF-R7 in the Quality Gap Analysis.

---

## Gap Status Summary

| Status | Count | Gap-IDs |
|--------|-------|---------|
| Closed | 15 | GAP-0002, GAP-0003, GAP-0004, GAP-0005, GAP-0006, GAP-0007, GAP-0008, GAP-0009, GAP-0010, GAP-0011, GAP-0012, GAP-0025, GAP-0026, GAP-0027, GAP-0028 |
| Won't Do | 13 | GAP-0001, GAP-0013, GAP-0014, GAP-0015, GAP-0016, GAP-0017, GAP-0018, GAP-0019, GAP-0020, GAP-0021, GAP-0022, GAP-0023, GAP-0024 |
| Blocked | 0 | -- |
| Remaining Open | 0 | -- |

All 28 gaps have been dispositioned. No open items remain.
