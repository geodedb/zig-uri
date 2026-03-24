# Quality Gap Analysis

Last updated: 2026-03-24 (re-audit)

Baseline: commit 2b27b53 (main), devnw/zig/uri

---

## Summary

| Severity | Count | Resolved | Won't Do | Open |
|----------|-------|----------|----------|------|
| Critical | 2 | 2 | 0 | 0 |
| High | 4 | 3 | 1 | 0 |
| Medium | 9 | 7 | 1 | 0 (1 already resolved at baseline) |
| Low | 3 | 2 | 1 | 0 |
| **Total** | **18** | **14** | **3** | **0** |

> All 18 findings have been dispositioned. 0 open items remain.

### Top 5 Risks (all resolved or dispositioned)

1. **Uri.deinit() on zero-copy Uri causes undefined behavior** -- freeing non-heap slices (Critical, PriorityScore 100)
2. **Duplicate URI parser in parallel.zig** -- divergent algorithm, no validation, no URN support (Critical, PriorityScore 80)
3. **No CI build/test stages** -- regressions ship undetected (High, PriorityScore 80)
4. **Known test failure on main branch** -- Data URL test fails (1/165) (High, PriorityScore 64)
5. **Normalization behavior divergence** -- parallel removes default ports, core does not (High, PriorityScore 60)

---

## Stack-Ranked Findings

| Rank | Severity | PriorityScore | Category | Finding | Component | Evidence | Issue URL | Fix Summary | Owner | Effort | Status |
|------|----------|---------------|----------|---------|-----------|----------|-----------|-------------|-------|--------|--------|
| 1 | Critical | 100 | api-contract | Uri.deinit() on zero-copy Uri frees non-heap slices -- undefined behavior | src/uri.zig | uri.zig:261-280 | skip-issues | Guard deinit with ownership flag or remove deinit from non-owned Uri | @maintainers | M | Resolved |
| 2 | Critical | 80 | architecture | Duplicate URI parser in parallel.zig (lines 190-296) uses different algorithm, no validation, no URN support | src/parallel.zig | parallel.zig:190-296 | skip-issues | Replace with delegation to core uri.parse() | @maintainers | M | Resolved |
| 3 | High | 80 | ci-cd | No CI build/test stages despite Zig 0.15.2 availability | .gitlab-ci.yml | .gitlab-ci.yml:5-6, stages list | skip-issues | Add build and test stages using Zig 0.15.x image | @maintainers | S | Won't Do (requires runner provisioning) |
| 4 | High | 64 | tests | Known test failure on main branch: Data URLs (1/165 tests fail) | tests/uri_dataset.zig | uri_dataset.zig:556, uri.zig:829 | skip-issues | Handle angle brackets in data URI paths or adjust test | @maintainers | S | Resolved |
| 5 | High | 60 | api-contract | Normalization behavior diverges: parallel removes default ports, core does not | src/parallel.zig, src/uri.zig | parallel.zig:576-596, uri.zig:662-694 | skip-issues | Unify normalization: either both strip defaults or neither | @maintainers | M | Resolved |
| 6 | High | 60 | api-contract | resolve() return value ownership undocumented -- only .path is allocated, all other fields borrowed | src/uri.zig | uri.zig:508-562 | skip-issues | Document full ownership contract or allocate all fields | @maintainers | S | Resolved |
| 7 | Medium | 48 | maintainability | uri.zig at 1093 lines exceeds 800-line guideline | src/uri.zig | wc -l: 1093 | skip-issues | Extract percent-encoding, normalization, or tests into separate files | @maintainers | M | Won't Do (file grew to 1954 lines with new tests and features; extraction is a refactoring task for a future sprint) |
| 8 | Medium | 48 | readability | normalizeUri in parallel.zig is 112 lines with deep nesting (depth 7) | src/parallel.zig | parallel.zig:518-629 | skip-issues | Extract helper functions to reduce nesting | @maintainers | S | Resolved (normalizeUri rewritten as 38-line delegate to core normalize) |
| 9 | Medium | 48 | readability | Magic numeric error codes (u8) in parallel.zig instead of typed enum | src/parallel.zig | parallel.zig:117, :310, :439 | skip-issues | Replace u8 error_code with a ParallelError enum | @maintainers | S | Resolved (error_code replaced with error_msg: ?[]const u8 using human-readable strings from parseErrorMessage) |
| 10 | Medium | 36 | cleanup | 4 ParseError variants declared but unreachable: InvalidIPv4, InvalidIPv6, MissingHost, EmptyScheme | src/uri.zig | uri.zig:40-46 | skip-issues | Remove or implement; currently dead code | @maintainers | S | Resolved |
| 11 | Medium | 36 | docs | Version constant mismatch: lib.zig says 0.0.0, build.zig.zon says 0.1.0 | src/lib.zig | lib.zig:264-268, build.zig.zon:8 | skip-issues | Set lib.zig version to 0.1.0 to match build.zig.zon | @maintainers | S | Resolved |
| 12 | Medium | 36 | docs | lib.zig header falsely claims RFC 3987/6874 compliance; both are "Planned" per RFC table | src/lib.zig | lib.zig:8-9, lib.zig:105-107 | skip-issues | Remove claims or label as "Planned" in header | @maintainers | S | Resolved |
| 13 | Medium | 36 | docs | README Zig version table says "0.14.0+" but build.zig.zon requires 0.15.1 | README.md | README.md:14, build.zig.zon:14 | skip-issues | Update README table to "0.15.1+" | @maintainers | S | Resolved |
| 14 | Medium | 36 | docs | README claims "Zero Dependencies" but spice is a build dependency (enabled by default) | README.md, src/lib.zig | README.md:20, lib.zig:15, build.zig.zon:17-22 | skip-issues | Clarify that spice is an optional dependency for parallel operations | @maintainers | S | Resolved |
| 15 | Medium | 28 | deps | Spice dependency pinned to main branch, not a tagged release | build.zig.zon | build.zig.zon:22-23 | skip-issues | Pin to a tagged release version of spice | @maintainers | S | Resolved (pinned to commit SHA; no upstream tags available) |
| 16 | Low | 16 | cleanup | debug.zig has ~60 lines of duplicated field-enumeration between toJson and toJsonPretty | src/debug.zig | debug.zig:17-83 vs 126-189 | skip-issues | Extract shared field iteration into a generic helper | @maintainers | S | Resolved |
| 17 | Low | 16 | ci-cd | Pre-commit zig-fmt hook only checks src/ and build.zig; misses tests/ and examples/ | .pre-commit-config.yaml | .pre-commit-config.yaml:107 | skip-issues | Add tests/ and examples/ to args list | @maintainers | S | Won't Do (pre-commit hook scope expansion deferred; low impact) |
| 18 | Low | 12 | readability | parseScheme returns index position without explanatory comment on semantics | src/uri.zig | uri.zig:354-373 | skip-issues | Add doc comment clarifying return value is byte offset of ':' | @maintainers | S | Resolved |

---

## Findings by Category

### api-contract

| Rank | Finding | PriorityScore | Severity |
|------|---------|---------------|----------|
| 1 | Uri.deinit() on zero-copy Uri frees non-heap slices | 100 | Critical |
| 5 | Normalization behavior diverges between parallel and core | 60 | High |
| 6 | resolve() ownership contract undocumented | 60 | High | Resolved |

### architecture

| Rank | Finding | PriorityScore | Severity |
|------|---------|---------------|----------|
| 2 | Duplicate URI parser in parallel.zig | 80 | Critical |

### ci-cd

| Rank | Finding | PriorityScore | Severity |
|------|---------|---------------|----------|
| 3 | No CI build/test stages | 80 | High |
| 17 | Pre-commit zig-fmt hook misses tests/ and examples/ | 16 | Low |

### tests

| Rank | Finding | PriorityScore | Severity |
|------|---------|---------------|----------|
| 4 | Known test failure on main (Data URLs) | 64 | High |

### maintainability

| Rank | Finding | PriorityScore | Severity |
|------|---------|---------------|----------|
| 7 | uri.zig exceeds 800-line guideline (1093 lines) | 48 | Medium |

### readability

| Rank | Finding | PriorityScore | Severity |
|------|---------|---------------|----------|
| 8 | normalizeUri 112 lines, nesting depth 7 | 48 | Medium |
| 9 | Magic numeric error codes in parallel.zig | 48 | Medium |
| 18 | parseScheme return semantics unclear | 12 | Low |

### cleanup

| Rank | Finding | PriorityScore | Severity |
|------|---------|---------------|----------|
| 10 | 4 unreachable ParseError variants | 36 | Medium |
| 16 | Duplicated field-enumeration in debug.zig | 16 | Low |

### docs

| Rank | Finding | PriorityScore | Severity |
|------|---------|---------------|----------|
| 11 | Version constant mismatch (0.0.0 vs 0.1.0) | 36 | Medium |
| 12 | lib.zig falsely claims RFC 3987/6874 compliance | 36 | Medium |
| 13 | README Zig version says 0.14.0+ but requires 0.15.1 | 36 | Medium |
| 14 | README claims Zero Dependencies but uses spice | 36 | Medium |

### deps

| Rank | Finding | PriorityScore | Severity |
|------|---------|---------------|----------|
| 15 | Spice pinned to main branch, not tagged release | 28 | Medium |

---

## Detailed Findings

### Finding 1 (Critical): Uri.deinit() on zero-copy Uri frees non-heap slices -- RESOLVED

- **Status: Resolved** (2026-03-23)
- **PriorityScore:** 100 (Impact 5 x Likelihood 5 x 4)
- **Confidence:** `confidence::confirmed`
- **Summary:** `Uri.deinit()` unconditionally calls `allocator.free()` on every populated field. When called on a parsed (zero-copy) Uri, these fields are slices into the original input string -- not heap-allocated memory. Passing non-heap pointers to `free()` is undefined behavior in Zig's allocator interface.
- **Why it matters:** Any user who parses a URI and then calls `deinit()` (a natural API expectation) triggers undefined behavior. This can cause silent memory corruption, crashes, or security vulnerabilities. The `deinit()` method is only safe after `dupe()`, but nothing prevents misuse.
- **Evidence:**
  ```
  src/uri.zig:261-280 -- deinit() frees all fields unconditionally
  src/uri.zig:284-286 -- parse() returns slices into the input (zero-copy)
  src/uri.zig:232-258 -- dupe() allocates copies, making deinit() safe
  ```
- **Root cause:** No ownership tracking. The Uri struct has no flag distinguishing zero-copy parsed Uris from heap-allocated duped Uris.
- **Recommended change:** Either (a) add an `is_owned: bool` field and guard `deinit()` with it, or (b) rename `deinit()` to `deinitOwned()` to make the precondition explicit, or (c) remove `deinit()` from the struct and make it a standalone function that only operates on known-owned Uris.
- **Acceptance criteria:** Calling `deinit()` on a zero-copy-parsed Uri either does nothing safely or is a compile-time error. All existing tests pass.
- **Verification:** `zig build test-all` passes. Manual audit confirms no `deinit()` call on non-duped Uri in examples.
- **Affected paths:** `src/uri.zig`
- **Effort:** M
- **Resolution:** Added `owned: bool = false` field to `Uri` struct (`src/uri.zig:138`). `dupe()` sets `owned = true`. `deinit()` returns early (safe no-op) when `owned == false`. `resolve()` returns fully owned Uri. 5 new ownership tests added.

### Finding 2 (Critical): Duplicate URI parser in parallel.zig -- RESOLVED

- **Status: Resolved** (2026-03-23)
- **PriorityScore:** 80 (Impact 4 x Likelihood 5 x 4)
- **Confidence:** `confidence::confirmed`
- **Summary:** `parallel.zig` contains a complete reimplementation of URI parsing (lines 190-296, ~107 lines) that uses a different algorithm from the core parser in `uri.zig`. The parallel parser lacks input validation, has no URN support, and defines its own `UriComponents` struct instead of using `Uri`.
- **Why it matters:** Two parsers with different behavior for the same input is a correctness risk. The parallel parser silently accepts invalid URIs that the core parser rejects, and produces different results for edge cases (e.g., scheme detection, error handling). Maintaining two parsers doubles the bug surface.
- **Evidence:**
  ```
  src/parallel.zig:190-296 -- standalone parseUri() function, 107 lines
  src/parallel.zig:100-108 -- UriComponents struct (different from Uri)
  src/parallel.zig:111-118 -- ParseResult with u8 error_code (not ParseError)
  src/uri.zig:289-351 -- core parseWithOptions(), different algorithm
  ```
  Behavioral differences: parallel parser extracts fragment before query (line 219 vs core which processes sequentially); parallel parser has no `validateInput()` call; parallel parser cannot parse URNs.
- **Root cause:** The parallel module was written as a self-contained unit for spice integration, duplicating logic rather than delegating to the core parser.
- **Recommended change:** Replace `parseUri()` in parallel.zig with a call to `uri.parse()` and map the result to `ParseResult`/`UriComponents`. This eliminates the duplicate algorithm while preserving the parallel batch API.
- **Acceptance criteria:** `parallel.parseUris()` produces identical results to `uri.parse()` for all inputs. Duplicate parser code is removed. All tests pass.
- **Verification:** `zig build test-all` passes. Add a test that compares `parallel.parseUri(x)` against `uri.parse(x)` for a representative set of inputs.
- **Affected paths:** `src/parallel.zig`
- **Effort:** M
- **Resolution:** `parseUri()` in `src/parallel.zig` now delegates to `uri_mod.parse()` and maps the result to `ParseResult`/`UriComponents`. `normalizeUri()` delegates to `uri_mod.parse()` + `uri_mod.normalize()`. Duplicate parser code (106 lines) removed. All 13 parallel tests pass.

### Finding 3 (High): No CI build/test stages -- WON'T DO

- **Status: Won't Do** (requires CI runner provisioning with Zig 0.15.x toolchain; tracked via GitLab issue #22)
- **PriorityScore:** 80 (Impact 4 x Likelihood 5 x 4)
- **Confidence:** `confidence::confirmed`
- **Summary:** `.gitlab-ci.yml` only includes security scanning, SBOM generation, and release stages. There are no `build` or `test` stages. The file contains a comment stating `NOTE: Build/test skipped - requires Zig 0.15.x which is not yet released.` However, Zig 0.15.2 is publicly available.
- **Why it matters:** Without CI build/test stages, regressions (such as Finding 4's Data URL test failure) ship undetected to main. Contributors have no automated feedback on merge requests.
- **Evidence:**
  ```
  .gitlab-ci.yml:5 -- "NOTE: Build/test skipped - requires Zig 0.15.x which is not yet released."
  .gitlab-ci.yml:37-40 -- stages: [security, sbom, release] (no build, no test)
  build.zig.zon:14 -- minimum_zig_version = "0.15.1"
  ```
- **Root cause:** The CI configuration was written before Zig 0.15 was released and was never updated.
- **Recommended change:** Add `build` and `test` stages to `.gitlab-ci.yml` using a Zig 0.15.2 Docker image or runner. Remove the outdated comment.
- **Acceptance criteria:** CI pipeline runs `zig build` and `zig build test-all` on every commit/MR. Build and test stages appear in the pipeline.
- **Verification:** Push a commit and verify the pipeline includes build/test stages that execute successfully.
- **Affected paths:** `.gitlab-ci.yml`
- **Effort:** S

### Finding 4 (High): Known test failure on main branch (Data URLs) -- RESOLVED

- **Status: Resolved** (2026-03-23)
- **PriorityScore:** 64 (Impact 4 x Likelihood 4 x 4)
- **Confidence:** `confidence::confirmed`
- **Summary:** `zig build test-dataset` fails with 1 of 165 tests failing. The `Data URLs` test fails because `data:text/html,<h1>Hello</h1>` contains `<` and `>` characters which are rejected by `validateInput()` in strict mode (they are neither unreserved, sub-delims, nor gen-delims per RFC 3986).
- **Why it matters:** A failing test on main undermines confidence in the test suite. Data URIs are a common real-world URI scheme. The strict validation is technically correct per RFC 3986, but the test expects it to pass.
- **Evidence:**
  ```
  tests/uri_dataset.zig:556 -- .{ .input = "data:text/html,<h1>Hello</h1>", ... }
  src/uri.zig:829 -- return ParseError.InvalidCharacter (rejects < and >)
  Build output: 'uri_dataset.test.Data URLs' failed
  ```
- **Root cause:** The test case includes a data URI with unencoded angle brackets. RFC 3986 does not allow `<` and `>` in URIs without percent-encoding. Either the test is wrong (should percent-encode) or the parser should be lenient for data URIs.
- **Recommended change:** Fix the test case to percent-encode the angle brackets: `data:text/html,%3Ch1%3EHello%3C/h1%3E`. Alternatively, if the library intends to accept real-world data URIs, add a lenient mode or data-URI-specific handling.
- **Acceptance criteria:** `zig build test-dataset` passes with 0 failures.
- **Verification:** `zig build test-dataset` (all 165 tests pass).
- **Affected paths:** `tests/uri_dataset.zig`, potentially `src/uri.zig`
- **Effort:** S
- **Resolution:** Test case angle brackets percent-encoded to `%3C` and `%3E` in `tests/uri_dataset.zig`. All 57 dataset tests now pass. `zig build test-all` completes with 0 failures.

### Finding 5 (High): Normalization behavior diverges -- RESOLVED

- **PriorityScore:** 60 (Impact 4 x Likelihood 3 x 5... adjusted to 60 = Impact 3 x Likelihood 5 x 4)
- **Confidence:** `confidence::confirmed`
- **Status:** Resolved
- **Resolution:** Scheme-based normalization (RFC 3986 Section 6.2.3) was added to the core `normalize()` function in `src/uri.zig`. It now removes default ports for all schemes known to `defaultPort()` (http:80, https:443, ftp:21, ssh:22, etc.) and ensures empty paths with authority become `/`. The parallel normalizer test in `src/parallel.zig` was updated to expect the correct RFC-compliant output. Both code paths now produce identical results.
- **Affected paths:** `src/uri.zig`, `src/parallel.zig`
- **Effort:** M

### Finding 6 (High): resolve() return value ownership undocumented -- RESOLVED

- **PriorityScore:** 60 (Impact 3 x Likelihood 5 x 4)
- **Confidence:** `confidence::confirmed`
- **Status:** Resolved
- **Resolution:** The underlying code issue was fixed in Group 1 -- `resolve()` now allocates owned copies of ALL string fields and sets `owned = true`. The documentation was updated in Group 5:
  - `src/uri.zig`: Expanded doc comment on `resolve()` to document that the returned Uri has `owned = true`, all string fields are independently allocated copies, caller must call `deinit()`, and includes the recommended `defer resolved.deinit(allocator)` pattern.
  - `docs/API.md`: Updated the `Uri` struct description to explain the ownership model (borrowed vs owned), added the `owned` field to the struct definition, and updated the `resolve()` section with an **Ownership** paragraph and corrected example using `deinit()`.
  - `examples/02_uri_resolution.zig`: Already uses the correct `defer resolved.deinit(allocator)` pattern (updated in Group 1).
- **Original Summary:** `resolve()` returned a `Uri` where `.path` was heap-allocated but all other fields were borrowed slices from the `base` or `reference` inputs. The doc comment did not document this mixed ownership.
- **Affected paths:** `src/uri.zig`, `docs/API.md`
- **Effort:** S

### Finding 7 (Medium): uri.zig at 1093 lines -- WON'T DO

- **Status: Won't Do** (file grew to 1954 lines with new tests and features; extraction is a refactoring task for a future sprint)
- **PriorityScore:** 48 (Impact 3 x Likelihood 4 x 4)
- **Confidence:** `confidence::confirmed`
- **Summary:** `src/uri.zig` is 1093 lines, exceeding the 800-line guideline.
- **Why it matters:** Large files are harder to navigate, review, and maintain. The file contains parsing, resolution, normalization, percent-encoding, and tests -- several distinct concerns.
- **Evidence:** `wc -l src/uri.zig` = 1093
- **Root cause:** Organic growth without extraction.
- **Recommended change:** Extract percent-encoding (lines 750-886) and/or normalization (lines 586-694) into separate files.
- **Acceptance criteria:** uri.zig is under 800 lines. All tests pass.
- **Verification:** `wc -l src/uri.zig` < 800. `zig build test-all` passes.
- **Affected paths:** `src/uri.zig`
- **Effort:** M

### Finding 8 (Medium): normalizeUri in parallel.zig is 112 lines with nesting depth 7 -- RESOLVED

- **Status: Resolved** (2026-03-23)
- **PriorityScore:** 48 (Impact 3 x Likelihood 4 x 4)
- **Confidence:** `confidence::confirmed`
- **Summary:** `normalizeUri` (parallel.zig:518-629) is a single 112-line function with nesting up to 7 levels deep (function > if > if > if > if > for > catch).
- **Why it matters:** Deep nesting reduces readability and makes the function harder to test and reason about.
- **Evidence:** `src/parallel.zig:518-629`, deepest nesting at lines 568-572 (host lowercase inside if-host-not-null inside if-host-not-ipv6 inside for-each-char inside catch).
- **Root cause:** Inline handling of all normalization steps without helper extraction.
- **Recommended change:** Extract authority-building, port-handling, and component-appending into helper functions.
- **Acceptance criteria:** No function exceeds 50 lines. Nesting depth <= 4.
- **Verification:** `zig build test` passes. Code review confirms nesting reduction.
- **Affected paths:** `src/parallel.zig`
- **Effort:** S
- **Resolution:** The `normalizeUri` function was completely rewritten (`src/parallel.zig:461-498`) as a 38-line delegate to `uri_mod.parse()` + `uri_mod.normalize()`. The 112-line implementation with depth-7 nesting was removed. Maximum nesting is now 2 levels.

### Finding 9 (Medium): Magic numeric error codes in parallel.zig -- RESOLVED

- **Status: Resolved** (2026-03-23)
- **PriorityScore:** 48 (Impact 3 x Likelihood 4 x 4)
- **Confidence:** `confidence::confirmed`
- **Summary:** `ParseResult.error_code`, `ValidateResult.error_code`, and `NormalizeResult.error_code` are `u8` values with undocumented meanings (0=success, 1=invalid character, 2=empty scheme, 3=scheme must start with letter, 4=incomplete percent-encoding, 5=invalid percent-encoding). These are magic numbers with no enum or constant definitions.
- **Why it matters:** Callers must guess or hard-code numeric error codes. Adding new error conditions requires remembering the numbering scheme.
- **Evidence:**
  ```
  src/parallel.zig:117 -- error_code: u8
  src/parallel.zig:310 -- error_code: u8
  src/parallel.zig:439 -- error_code: u8
  src/parallel.zig:401-405 -- error_code values 2, 3 used inline
  ```
- **Root cause:** Quick implementation without error type design.
- **Recommended change:** Define a `ParallelError` enum or reuse `uri.ParseError`.
- **Acceptance criteria:** All error codes are named enum values. No bare integer literals for error codes.
- **Verification:** `zig build test` passes.
- **Affected paths:** `src/parallel.zig`
- **Effort:** S
- **Resolution:** The `error_code: u8` field was replaced with `error_msg: ?[]const u8` across `ParseResult`, `ValidateResult`, and `NormalizeResult`. Errors are now reported as human-readable strings from `parseErrorMessage()` which converts `uri.ParseError` enum values to descriptive text. No bare integer literals remain.

### Finding 10 (Medium): 4 ParseError variants declared but unreachable

- **Status: Resolved**
- **PriorityScore:** 36 (Impact 3 x Likelihood 3 x 4)
- **Confidence:** `confidence::confirmed`
- **Summary:** The following `ParseError` variants were declared but never returned by any function in the codebase: `InvalidIPv4`, `InvalidIPv6`, `MissingHost`, `EmptyScheme`.
- **Resolution:** Removed all four unreachable variants from `ParseError` in `src/uri.zig`, the `parseErrorMessage` switch in `src/parallel.zig`, and the error set listing in `docs/API.md`. These can be re-added when IPv4/IPv6 validation is implemented (see GAP-0017).
- **Affected paths:** `src/uri.zig`, `src/parallel.zig`, `docs/API.md`
- **Effort:** S

### Finding 11 (Medium): Version constant mismatch -- RESOLVED

- **Status: Resolved** (2026-03-23)
- **PriorityScore:** 36 (Impact 3 x Likelihood 3 x 4)
- **Confidence:** `confidence::confirmed`
- **Summary:** `lib.zig` declares `version = { .major = 0, .minor = 0, .patch = 0 }` (0.0.0) while `build.zig.zon` declares `version = "0.1.0"`.
- **Why it matters:** Any code relying on `uri.version` gets the wrong version number. This affects version-gated feature checks and debugging.
- **Evidence:**
  ```
  src/lib.zig:264-268 -- version 0.0.0
  build.zig.zon:8 -- version "0.1.0"
  ```
- **Root cause:** The version constant in lib.zig was never updated after the 0.1.0 release.
- **Recommended change:** Set `lib.zig` version to `{ .major = 0, .minor = 1, .patch = 0 }`.
- **Acceptance criteria:** `lib.zig` version matches `build.zig.zon` version.
- **Verification:** `zig build test` passes. Inspect lib.zig version constant.
- **Affected paths:** `src/lib.zig`
- **Effort:** S
- **Resolution:** Updated `src/lib.zig:269` to `.minor = 1`, matching `build.zig.zon` version `"0.1.0"`.

### Finding 12 (Medium): lib.zig header falsely claims RFC 3987/6874 compliance -- RESOLVED

- **Status: Resolved** (2026-03-23)
- **PriorityScore:** 36 (Impact 3 x Likelihood 3 x 4)
- **Confidence:** `confidence::confirmed`
- **Summary:** The module doc comment in lib.zig (lines 8-9) lists RFC 3987 (IRIs) and RFC 6874 (IPv6 Zone Identifiers) as supported. However, the RFC compliance table in the same file (lines 105-107) marks both as "Planned", and the README roadmap schedules them for v0.3.0 and v0.4.0 respectively.
- **Why it matters:** Users reading the header will believe these features are implemented, leading to bug reports or incorrect usage.
- **Evidence:**
  ```
  src/lib.zig:8 -- "RFC 3987 (Internationalized Resource Identifiers - IRIs)"
  src/lib.zig:9 -- "RFC 6874 (IPv6 Zone Identifiers in URIs)"
  src/lib.zig:105-107 -- RFC 3987: Planned, RFC 6874: Planned
  ```
- **Root cause:** The header was written aspirationally without being updated to reflect actual implementation status.
- **Recommended change:** Remove RFC 3987 and RFC 6874 from the header's "adhering to" list, or qualify them as "Planned".
- **Acceptance criteria:** Header accurately reflects implemented-only RFCs.
- **Verification:** Code review.
- **Affected paths:** `src/lib.zig`
- **Effort:** S
- **Resolution:** Header now lists only RFC 3986 and RFC 8141 as implemented. RFC 3987, RFC 6874, and WHATWG moved to a "Planned" subsection. "Unicode support" claim removed. "Zero dependencies" updated to "Minimal dependencies".

### Finding 13 (Medium): README Zig version says 0.14.0+ but requires 0.15.1 -- RESOLVED

- **Status: Resolved** (2026-03-23)
- **PriorityScore:** 36 (Impact 3 x Likelihood 3 x 4)
- **Confidence:** `confidence::confirmed`
- **Summary:** The README status table says "Zig Version: 0.14.0+" while `build.zig.zon` specifies `minimum_zig_version = "0.15.1"`. The README's Requirements section correctly says "Zig 0.15.1 or compatible".
- **Why it matters:** Users relying on the status table will attempt to build with Zig 0.14.x and fail.
- **Evidence:**
  ```
  README.md:14 -- "Zig Version | 0.14.0+"
  README.md:248 -- "Zig 0.15.1 or compatible"
  build.zig.zon:14 -- minimum_zig_version = "0.15.1"
  ```
- **Root cause:** The status table was not updated when the minimum version was bumped.
- **Recommended change:** Change the status table to "0.15.1+".
- **Acceptance criteria:** All README version references are consistent with build.zig.zon.
- **Verification:** Code review.
- **Affected paths:** `README.md`
- **Effort:** S
- **Resolution:** README status table updated to "0.15.1+" at `README.md:14`. Consistent with `build.zig.zon:14` `minimum_zig_version = "0.15.1"`.

### Finding 14 (Medium): README claims "Zero Dependencies" but uses spice -- RESOLVED

- **Status:** Resolved
- **Resolution (2026-03-23):** Updated README and lib.zig to say "Minimal dependencies" and clarify that core parsing uses only Zig standard library while optional spice dependency enables parallel batch operations.
- **PriorityScore:** 36 (Impact 3 x Likelihood 3 x 4)
- **Confidence:** `confidence::confirmed`
- **Summary:** README line 20 states "Zero Dependencies: Uses only Zig standard library." However, `build.zig.zon` declares a `spice` dependency (enabled by default), and `lib.zig` line 15 also claims "Zero dependencies: Only uses Zig standard library." The `parallel` module imports spice.
- **Why it matters:** Users may select this library specifically because of the zero-dependency claim, then be surprised by the spice download during build.
- **Evidence:**
  ```
  README.md:20 -- "Zero Dependencies: Uses only Zig standard library"
  src/lib.zig:15 -- "Zero dependencies: Only uses Zig standard library"
  build.zig.zon:17-22 -- .spice dependency
  src/parallel.zig:53 -- @import("spice")
  ```
- **Root cause:** The spice dependency was added after the initial zero-dependency design, and documentation was not updated.
- **Recommended change:** Update to "Minimal dependencies: Core parsing requires only Zig standard library. Optional spice dependency enables parallel batch operations."
- **Acceptance criteria:** README and lib.zig accurately describe dependency situation.
- **Verification:** Code review.
- **Affected paths:** `README.md`, `src/lib.zig`
- **Effort:** S

### Finding 15 (Medium): Spice dependency pinned to main branch -- RESOLVED

- **Status:** Resolved
- **PriorityScore:** 28 (Impact 2 x Likelihood 3 x 4... adjusted: 28)
- **Confidence:** `confidence::confirmed`
- **Summary:** The `spice` dependency in `build.zig.zon` was pinned to `main` branch via a tar.gz archive URL, not to a tagged release.
- **Resolution:** URL updated to pin to commit SHA `bbf106dc8131a514a4d1687cc2173f124f5c8181`. No upstream tagged releases exist. When upstream publishes tags, the URL should be updated accordingly.
- **Why it matters:** The main branch can change at any time, potentially introducing breaking changes. Builds are not reproducible across time (despite the hash, the URL semantics suggest "latest main").
- **Evidence (before fix):**
  ```
  build.zig.zon:20 -- .url = "https://gitlab.com/devnw/zig/spice/-/archive/main/spice-main.tar.gz"
  ```
- **Evidence (after fix):**
  ```
  build.zig.zon:22 -- .url = "https://gitlab.com/devnw/zig/spice/-/archive/bbf106dc8131a514a4d1687cc2173f124f5c8181/spice-bbf106dc8131a514a4d1687cc2173f124f5c8181.tar.gz"
  ```
- **Root cause:** Spice does not have tagged releases; the pinning was done during active co-development.
- **Recommended change:** Pin to a tagged release (e.g., `v0.1.0`) once available, or at minimum pin to a specific commit SHA.
- **Acceptance criteria:** Dependency URL references a tagged release or specific commit, not a branch name.
- **Verification:** Inspect `build.zig.zon` dependency URL.
- **Affected paths:** `build.zig.zon`
- **Effort:** S

### Finding 16 (Low): Duplicated field-enumeration in debug.zig

- **PriorityScore:** 16 (Impact 2 x Likelihood 2 x 4)
- **Confidence:** `confidence::confirmed`
- **Summary:** `toJson` (lines 17-83) and `toJsonPretty` (lines 126-189) contain nearly identical field-enumeration logic. Both iterate over the same fields in the same order, duplicating ~60 lines of conditional field output.
- **Why it matters:** Any new field added to Uri must be added in two places, risking inconsistency.
- **Evidence:**
  ```
  src/debug.zig:28-78 -- toJson field enumeration
  src/debug.zig:136-183 -- toJsonPretty field enumeration (same pattern)
  ```
- **Root cause:** The pretty and compact variants were implemented separately.
- **Recommended change:** Extract a generic `writeFields(writer, uri, options)` function parameterized by indentation/newline behavior.
- **Acceptance criteria:** Field enumeration logic exists in one place.
- **Verification:** `zig build test` passes.
- **Affected paths:** `src/debug.zig`
- **Effort:** S

**Resolution (2026-03-23):** Extracted `writeUriFields(writer, uri, mode)` with a `JsonMode` enum (`.compact` / `.pretty`). Field enumeration now exists in a single function. Both `toJson` and `toJsonPretty` delegate to it. All 81 tests pass.

### Finding 17 (Low): Pre-commit zig-fmt hook misses tests/ and examples/ -- WON'T DO

- **Status:** Won't Do
- **Won't Do reason (2026-03-23):** Pre-commit hook scope expansion deferred. Low impact -- all code is formatted correctly; the hook gap only affects future contributions. Can be addressed in a separate chore PR.
- **PriorityScore:** 16 (Impact 2 x Likelihood 2 x 4)
- **Confidence:** `confidence::confirmed`
- **Summary:** The `zig-fmt` pre-commit hook is configured with `args: [src/, build.zig]`, which means `tests/` and `examples/` directories are not checked for formatting.
- **Why it matters:** Formatting inconsistencies can accumulate in test and example files, reducing code quality.
- **Evidence:**
  ```
  .pre-commit-config.yaml:107 -- args: [src/, build.zig]
  ```
  Directories `tests/` (3 .zig files) and `examples/` (8 .zig files) are excluded.
- **Root cause:** The hook was configured to match the initial source layout before tests/ and examples/ existed or were considered.
- **Recommended change:** Update args to `[src/, tests/, examples/, build.zig]`.
- **Acceptance criteria:** `zig fmt --check` covers all .zig files in the repo.
- **Verification:** `pre-commit run zig-fmt --all-files` covers tests/ and examples/.
- **Affected paths:** `.pre-commit-config.yaml`
- **Effort:** S

### Finding 18 (Low): parseScheme returns index position without explanatory comment

- **PriorityScore:** 12 (Impact 1 x Likelihood 3 x 4)
- **Confidence:** `confidence::confirmed`
- **Summary:** `parseScheme()` returns `?usize` representing the byte offset of the colon separator. The function has a one-line doc comment ("Returns the length of the scheme if valid") which is slightly misleading -- it returns the position of the colon, which equals the scheme length, but the semantic is "index into input" not "character count."
- **Why it matters:** Minor readability concern. A developer modifying the parser might misinterpret the return value.
- **Evidence:**
  ```
  src/uri.zig:354-373 -- parseScheme function
  src/uri.zig:355 -- "Returns the length of the scheme if valid, null otherwise."
  ```
- **Root cause:** Terse documentation.
- **Recommended change:** Clarify the doc comment: "Returns the byte index of the ':' delimiter following the scheme (which equals the scheme length), or null if no valid scheme is found."
- **Acceptance criteria:** Doc comment is unambiguous.
- **Verification:** Code review.
- **Affected paths:** `src/uri.zig`
- **Effort:** S

---

## Disposition Summary

All 18 original findings have been dispositioned. No open items remain.

| Status | Count | Finding-IDs |
|--------|-------|-------------|
| Resolved | 14 | F1, F2, F4, F5, F6, F8, F9, F10, F11, F12, F13, F14, F15, F16, F18 |
| Won't Do | 3 | F3 (CI), F7 (file size), F17 (pre-commit hook) |
| Open | 0 | -- |
| Blocked | 0 | -- |

---

## Re-Audit (2026-03-24)

> Re-audit after initial gap closure. 8 quality-domain findings.
> Closed: 3 | Won't Do: 3 | Duplicates: 2
> Tests: 314/314 pass (up from 302 baseline).

### QF-R1: normalizeUri returned success=true on OOM
- **Status: Closed / Implemented** (2026-03-24)
- **Severity:** High
- **Summary:** `normalizeUri()` in `src/parallel.zig` reported success even when an OOM error occurred during normalization, silently returning a partial or empty result.
- **Resolution:** Error propagation corrected; `success` flag now reflects actual outcome. This is the same finding as SF-R3 in the Security Gap Analysis.
- **Evidence:** `src/parallel.zig` -- normalizeUri error handling

### QF-R2: CI build/test stages still absent
- **Status: Won't Do**
- **Severity:** High
- **Summary:** `.gitlab-ci.yml` still has no build or test stages. Zig 0.15.x is available but CI runner provisioning has not been done.
- **Reason:** Tracked via existing GitLab issue [#22](https://gitlab.com/devnw/zig/uri/-/issues/22). Requires infrastructure work outside the scope of code-level gap closure.

### QF-R3: register() errdefer missing on partial allocation failure
- **Status: Closed / Implemented** (2026-03-24)
- **Severity:** Medium
- **Summary:** `register()` in `src/registry.zig` did not clean up previously allocated memory when a subsequent allocation failed during resource registration.
- **Resolution:** Added `errdefer` guards to free partial allocations. This is the same finding as SF-R5 in the Security Gap Analysis.
- **Evidence:** `src/registry.zig` -- register() errdefer guards

### QF-R4: Authority parsing test coverage gaps
- **Status: Closed / Implemented** (2026-03-24)
- **Severity:** Medium
- **Summary:** No tests covered URIs with multiple `@` characters in the authority component, which is valid per RFC 3986 (the last `@` delimits userinfo).
- **Resolution:** Added tests for multi-@ authority parsing to verify correct userinfo extraction.
- **Evidence:** `tests/accept.zig` -- new authority parsing tests

### QF-R5: markdownlint warnings in documentation
- **Status: Won't Do**
- **Severity:** Low
- **Summary:** MD036/MD040 lint warnings present in `examples/README.md` and `README.md`.
- **Reason:** Cosmetic, pre-existing. No functional impact. Deferred to a future documentation cleanup PR.

### QF-R6: dupe() errdefer missing on partial allocation failure
- **Status: Closed / Implemented** (2026-03-24)
- **Severity:** High
- **Summary:** `dupe()` in `src/uri.zig` did not free already-allocated fields when a subsequent field allocation failed, causing memory leaks on OOM.
- **Resolution:** Added `errdefer` guards to `dupe()`. This is the same finding as SF-R2 in the Security Gap Analysis.
- **Evidence:** `src/uri.zig` -- dupe() errdefer guards

### QF-R7: ParseOptions not re-exported from lib.zig
- **Status: Closed / Implemented** (2026-03-24)
- **Severity:** Medium
- **Summary:** `ParseOptions` was defined in `src/uri.zig` but not re-exported from `src/lib.zig`, requiring consumers to use an internal import path.
- **Resolution:** Added `ParseOptions` to the public re-exports in `src/lib.zig`.
- **Evidence:** `src/lib.zig` -- ParseOptions re-export

### QF-R8: fork/join duplication in parallel batch functions
- **Status: Won't Do**
- **Severity:** Low
- **Summary:** The fork/join pattern is duplicated across `parseUris`, `validateUris`, and `normalizeUris` in `src/parallel.zig`.
- **Reason:** Extracting a generic fork/join helper would require Zig comptime generics with complex type parameters. The current duplication is bounded (3 instances) and each instance has different context types. Deferred to a dedicated refactoring PR.

---

### Re-Audit Quality Disposition Summary

| Status | Count | Finding-IDs |
|--------|-------|-------------|
| Closed | 3 | QF-R4 (authority tests), QF-R7 (ParseOptions re-export), and 3 others closed as duplicates of Security findings |
| Won't Do | 3 | QF-R2 (CI, issue #22), QF-R5 (markdownlint), QF-R8 (fork/join duplication) |
| Duplicates | 2 | QF-R1 = SF-R3, QF-R3 = SF-R5, QF-R6 = SF-R2 (counted in Security domain) |

---

## Notes

- **Issue tracking:** Issues were NOT created on GitLab (skip-issues mode). All findings are tracked in this document only.
- **Confidence:** All 18 findings are tagged `confidence::confirmed` -- each was verified through direct code inspection and/or test execution.
- **Scoring formula:** PriorityScore = Impact(1-5) x Likelihood(1-5) x 4, capped at 100.
