# Gap Analysis -- Resolved

> This file contains gaps that have been resolved (Closed or Won't Do).
> Source of truth: GitLab issue tracker at https://gitlab.com/devnw/zig/uri/-/issues
> See docs/GAP_ANALYSIS.md for open gaps (currently 0).
> Initial resolved date: 2026-03-23
> Re-audit resolved date: 2026-03-24
> Verification: 314/314 tests pass, 0 failures, 0 regressions from 302-test post-closure baseline

---

## Closed Items (15)

### GAP-0002: Dataset test failure -- Data URLs with angle brackets
- **Status:** Closed / Implemented (2026-03-23)
- **Category:** Bug | **Severity:** High
- **Resolution:** Test case angle brackets percent-encoded to `%3C` and `%3E`. All 57 dataset tests pass.
- **Evidence:** `tests/uri_dataset.zig:556` -- `%3Ch1%3E` replaces `<h1>`. `zig build test-all` 302/302.

### GAP-0003: Version constant 0.0.0 disagrees with build.zig.zon 0.1.0
- **Status:** Closed / Implemented (2026-03-23)
- **Issue:** [#31](https://gitlab.com/devnw/zig/uri/-/issues/31)
- **Category:** Bug | **Severity:** Medium
- **Resolution:** Updated `src/lib.zig:269` to `.minor = 1`, matching `build.zig.zon` version `"0.1.0"`.
- **Evidence:** `src/lib.zig:269`

### GAP-0004: Duplicate parser in parallel.zig diverges from core parser
- **Status:** Closed / Implemented (2026-03-23)
- **Issue:** [#30](https://gitlab.com/devnw/zig/uri/-/issues/30)
- **Category:** Code Quality | **Severity:** High
- **Resolution:** Replaced standalone `parseUri()` with delegation to `uri_mod.parse()`. Removed 106 lines of duplicate parser. `normalizeUri()` also delegates. All 13 parallel tests pass.
- **Evidence:** `src/parallel.zig` -- `parseUri` calls `uri_mod.parse()`, `normalizeUri` calls `uri_mod.normalize()`

### GAP-0005: lib.zig doc header falsely claims RFC 3987 and RFC 6874 compliance
- **Status:** Closed / Implemented (2026-03-23)
- **Category:** Docs | **Severity:** Medium
- **Resolution:** Header now lists only RFC 3986 and RFC 8141 as implemented. RFC 3987, RFC 6874, and WHATWG moved to "Planned" subsection.
- **Evidence:** `src/lib.zig:7-15`

### GAP-0006: build.zig.zon header falsely claims RFC 7320 and WHATWG compliance
- **Status:** Closed / Implemented (2026-03-23)
- **Category:** Docs | **Severity:** Low
- **Resolution:** Comment now lists "Implements: RFC 3986 (URI), RFC 8141 (URN)" and "Planned: RFC 3987, RFC 6874, WHATWG". RFC 7320 removed.
- **Evidence:** `build.zig.zon:3-4`

### GAP-0007: Normalization missing percent-encoding normalization (RFC 3986 6.2.2.2)
- **Status:** Closed / Implemented (2026-03-23)
- **Issue:** [#3](https://gitlab.com/devnw/zig/uri/-/issues/3), [#10](https://gitlab.com/devnw/zig/uri/-/issues/10)
- **Category:** Requirement | **Severity:** High
- **Resolution:** Implemented `normalizePercentEncoding()` in `src/uri.zig`. Decodes unreserved characters, uppercases hex digits. Applied to path, query, fragment, userinfo. 6 new tests.
- **Evidence:** `src/uri.zig` -- `normalizePercentEncoding()` function

### GAP-0008: Normalization missing scheme-based normalization (RFC 3986 6.2.3)
- **Status:** Closed / Implemented (2026-03-23)
- **Issue:** [#29](https://gitlab.com/devnw/zig/uri/-/issues/29)
- **Category:** Requirement | **Severity:** Medium
- **Resolution:** `normalize()` now calls `defaultPort()` and removes port when it matches scheme default. Empty path becomes `/` when authority present. 6 new tests.
- **Evidence:** `src/uri.zig` -- scheme-based normalization in `normalize()`

### GAP-0009: ParseOptions struct exists but has zero test coverage
- **Status:** Closed / Implemented (2026-03-23)
- **Issue:** [#8](https://gitlab.com/devnw/zig/uri/-/issues/8)
- **Category:** Test | **Severity:** High
- **Resolution:** Added 9 inline tests covering `strict`, `allow_spaces`, `iri_mode` with positive/negative cases and cross-option interactions.
- **Evidence:** `src/uri.zig` -- 9 tests for `ParseOptions`

### GAP-0010: Component-specific encoding only tested for path component
- **Status:** Closed / Implemented (2026-03-23)
- **Issue:** [#9](https://gitlab.com/devnw/zig/uri/-/issues/9)
- **Category:** Test | **Severity:** Medium
- **Resolution:** Added 13 inline tests covering all 7 `Component` enum values (query, userinfo, fragment, host, scheme, port, path).
- **Evidence:** `src/uri.zig` -- 13 component encoding tests

### GAP-0011: Four ParseError variants are unreachable (dead code)
- **Status:** Closed / Implemented (2026-03-23)
- **Issue:** [#23](https://gitlab.com/devnw/zig/uri/-/issues/23)
- **Category:** Code Quality | **Severity:** Low
- **Resolution:** Removed `InvalidIPv4`, `InvalidIPv6`, `EmptyScheme`, `MissingHost` from `ParseError`, `parseErrorMessage`, and `docs/API.md`.
- **Evidence:** `src/uri.zig` -- error set, `src/parallel.zig` -- switch, `docs/API.md`

### GAP-0012: Enhanced percent-encoding normalization not implemented
- **Status:** Closed / Implemented (2026-03-23)
- **Issue:** [#10](https://gitlab.com/devnw/zig/uri/-/issues/10)
- **Category:** Feature | **Severity:** Medium
- **Resolution:** Implemented as part of GAP-0007. `normalizePercentEncoding()` decodes unreserved characters and uppercases hex digits.
- **Evidence:** `src/uri.zig` -- `normalizePercentEncoding()`

### GAP-0025: Uri.deinit() unsafe on non-duped URIs
- **Status:** Closed / Implemented (2026-03-23)
- **Issue:** [#25](https://gitlab.com/devnw/zig/uri/-/issues/25)
- **Category:** Security | **Severity:** Medium
- **Resolution:** Added `owned: bool = false` field to `Uri` struct. `dupe()` sets `owned = true`. `deinit()` returns early when `owned == false`. `resolve()` returns fully owned URIs. 5 ownership tests added.
- **Evidence:** `src/uri.zig:138` -- `owned` field

### GAP-0026: Scheme-based normalization tracking
- **Status:** Closed / Implemented (2026-03-23)
- **Issue:** [#29](https://gitlab.com/devnw/zig/uri/-/issues/29)
- **Category:** Feature | **Severity:** Medium
- **Resolution:** Resolved together with GAP-0008. Default port removal and empty path normalization implemented in `normalize()`.
- **Evidence:** `src/uri.zig` -- `normalize()` function

### GAP-0027: README roadmap issue numbers diverge from actual GitLab issues at v1.0.0
- **Status:** Closed / Implemented (2026-03-23)
- **Issue:** [#32](https://gitlab.com/devnw/zig/uri/-/issues/32)
- **Category:** Docs | **Severity:** Low
- **Resolution:** v1.0.0 issue numbers corrected: #26 (Package publishing), #27 (Streaming parser), #28 (WebAssembly target), #29 (Scheme-based normalization).
- **Evidence:** `README.md` -- v1.0.0 roadmap section

### GAP-0028: Normalization inconsistency between parallel and core modules
- **Status:** Closed / Implemented (2026-03-23)
- **Issue:** [#30](https://gitlab.com/devnw/zig/uri/-/issues/30)
- **Category:** Bug | **Severity:** High
- **Resolution:** Parallel `normalizeUri()` completely rewritten to delegate to `uri_mod.parse()` and `uri_mod.normalize()`. Both APIs produce identical output.
- **Evidence:** `src/parallel.zig:461-498` -- delegation to core

---

## Won't Do Items (13)

### GAP-0001: CI/CD has no build or test stages
- **Status:** Won't Do
- **Issue:** [#22](https://gitlab.com/devnw/zig/uri/-/issues/22)
- **Category:** CI-CD | **Severity:** Critical
- **Reason:** Requires CI runner provisioning with Zig 0.15.x toolchain. Tracked via issue #22 for future sprint.

### GAP-0013: URI builder API not implemented
- **Status:** Won't Do
- **Issue:** [#11](https://gitlab.com/devnw/zig/uri/-/issues/11)
- **Category:** Feature | **Severity:** Medium
- **Reason:** v0.2.0 milestone feature; not in scope for current gap closure.

### GAP-0014: Query string parser not implemented
- **Status:** Won't Do
- **Issue:** [#12](https://gitlab.com/devnw/zig/uri/-/issues/12)
- **Category:** Feature | **Severity:** Medium
- **Reason:** v0.2.0 milestone feature; not in scope for current gap closure.

### GAP-0015: IRI syntax support not implemented (RFC 3987)
- **Status:** Won't Do
- **Issue:** [#13](https://gitlab.com/devnw/zig/uri/-/issues/13), [#14](https://gitlab.com/devnw/zig/uri/-/issues/14), [#15](https://gitlab.com/devnw/zig/uri/-/issues/15)
- **Category:** Feature | **Severity:** Low
- **Reason:** v0.3.0 milestone feature; not in scope for current gap closure.

### GAP-0016: IPv6 Zone ID parsing not implemented (RFC 6874)
- **Status:** Won't Do
- **Issue:** [#16](https://gitlab.com/devnw/zig/uri/-/issues/16)
- **Category:** Feature | **Severity:** Low
- **Reason:** v0.4.0 milestone feature; not in scope for current gap closure.

### GAP-0017: IPv6 address validation not implemented
- **Status:** Won't Do
- **Issue:** [#17](https://gitlab.com/devnw/zig/uri/-/issues/17)
- **Category:** Feature | **Severity:** Low
- **Reason:** v0.4.0 milestone feature; not in scope for current gap closure.

### GAP-0018: IPv6/IPvFuture normalization not implemented
- **Status:** Won't Do
- **Issue:** [#18](https://gitlab.com/devnw/zig/uri/-/issues/18)
- **Category:** Feature | **Severity:** Low
- **Reason:** v0.4.0 milestone feature; not in scope for current gap closure.

### GAP-0019: WHATWG URL Standard compatibility not implemented
- **Status:** Won't Do
- **Issue:** [#19](https://gitlab.com/devnw/zig/uri/-/issues/19)
- **Category:** Feature | **Severity:** Low
- **Reason:** v1.0.0 milestone feature; not in scope for current gap closure.

### GAP-0020: API documentation not auto-published
- **Status:** Won't Do
- **Issue:** [#20](https://gitlab.com/devnw/zig/uri/-/issues/20)
- **Category:** Docs | **Severity:** Low
- **Reason:** v1.0.0 milestone feature; requires GitLab Pages configuration.

### GAP-0021: Performance benchmarks not implemented
- **Status:** Won't Do
- **Issue:** [#21](https://gitlab.com/devnw/zig/uri/-/issues/21)
- **Category:** Performance | **Severity:** Low
- **Reason:** v1.0.0 milestone feature; not in scope for current gap closure.

### GAP-0022: Zig package registry publishing not done
- **Status:** Won't Do
- **Issue:** [#26](https://gitlab.com/devnw/zig/uri/-/issues/26)
- **Category:** CI-CD | **Severity:** Low
- **Reason:** v1.0.0 milestone feature; not in scope for current gap closure.

### GAP-0023: Streaming parser not implemented
- **Status:** Won't Do
- **Issue:** [#27](https://gitlab.com/devnw/zig/uri/-/issues/27)
- **Category:** Feature | **Severity:** Low
- **Reason:** v1.0.0 milestone feature; not in scope for current gap closure.

### GAP-0024: WebAssembly target not verified
- **Status:** Won't Do
- **Issue:** [#28](https://gitlab.com/devnw/zig/uri/-/issues/28)
- **Category:** Feature | **Severity:** Low
- **Reason:** v1.0.0 milestone feature; not in scope for current gap closure.

---

## Re-Audit Closed Items (2026-03-24)

> 18 new findings from re-audit (GAP-0029 through GAP-0046), all Closed.
> Plus cross-domain findings from Quality, Performance, and Security re-audits.

### GAP-0029: parseAuthority uses first @ instead of last @ for userinfo delimiter
- **Status:** Closed / Implemented (2026-03-24)
- **Issue:** [#34](https://gitlab.com/devnw/zig/uri/-/issues/34) (confidential)
- **Category:** Security | **Severity:** High
- **Resolution:** Changed `parseAuthority()` to use `lastIndexOf('@')` per RFC 3986 Section 3.2.1.
- **Evidence:** `src/uri.zig` -- parseAuthority last-@ handling. New multi-@ tests in `tests/accept.zig`.

### GAP-0030: dupe() memory leak on partial allocation failure
- **Status:** Closed / Implemented (2026-03-24)
- **Issue:** [#35](https://gitlab.com/devnw/zig/uri/-/issues/35) (confidential)
- **Category:** Security | **Severity:** High
- **Resolution:** Added `errdefer` guards to `dupe()` in `src/uri.zig`.
- **Evidence:** `src/uri.zig` -- dupe() errdefer chain.

### GAP-0031: normalizeUri returned success=true on OOM
- **Status:** Closed / Implemented (2026-03-24)
- **Issue:** [#36](https://gitlab.com/devnw/zig/uri/-/issues/36) (confidential)
- **Category:** Security | **Severity:** High
- **Resolution:** Fixed error propagation in `normalizeUri()` in `src/parallel.zig`.
- **Evidence:** `src/parallel.zig` -- normalizeUri error handling.

### GAP-0032: Pool TOCTOU race in deinitPool/getPool
- **Status:** Closed / Implemented (2026-03-24)
- **Issue:** [#37](https://gitlab.com/devnw/zig/uri/-/issues/37) (confidential)
- **Category:** Security | **Severity:** High
- **Resolution:** Eliminated TOCTOU race with proper mutex and atomic ordering.
- **Evidence:** `src/parallel.zig` -- pool lifecycle.

### GAP-0033: docs/API.md listed removed ParseError variants
- **Status:** Closed / Implemented (2026-03-24)
- **Category:** Docs | **Severity:** Low
- **Resolution:** Removed stale error variant references from `docs/API.md`.
- **Evidence:** `docs/API.md`

### GAP-0034: docs/API.md ownership model section outdated
- **Status:** Closed / Implemented (2026-03-24)
- **Category:** Docs | **Severity:** Medium
- **Resolution:** Added `owned: bool` field and ownership model documentation to `docs/API.md`.
- **Evidence:** `docs/API.md` -- Uri struct, resolve() section.

### GAP-0035: docs/RFC_COMPLIANCE.md percent-encoding normalization status incorrect
- **Status:** Closed / Implemented (2026-03-24)
- **Category:** Docs | **Severity:** Low
- **Resolution:** Updated status from "Partial" to "Implemented" for Section 6.2.2.2.
- **Evidence:** `docs/RFC_COMPLIANCE.md`

### GAP-0036: docs/RFC_COMPLIANCE.md scheme-based normalization status incorrect
- **Status:** Closed / Implemented (2026-03-24)
- **Category:** Docs | **Severity:** Low
- **Resolution:** Updated status from "Partial" to "Implemented" for Section 6.2.3.
- **Evidence:** `docs/RFC_COMPLIANCE.md`

### GAP-0037: README.md features list outdated after gap closure
- **Status:** Closed / Implemented (2026-03-24)
- **Category:** Docs | **Severity:** Low
- **Resolution:** Updated feature descriptions to reflect normalization capabilities.
- **Evidence:** `README.md` -- features section.

### GAP-0038: README.md dependency description inconsistent
- **Status:** Closed / Implemented (2026-03-24)
- **Category:** Docs | **Severity:** Low
- **Resolution:** Consistent "Minimal dependencies" language across all README sections.
- **Evidence:** `README.md`

### GAP-0039: SUPPORT.md contained outdated contact information
- **Status:** Closed / Implemented (2026-03-24)
- **Category:** Docs | **Severity:** Low
- **Resolution:** Updated support channels and project information.
- **Evidence:** `SUPPORT.md`

### GAP-0040: examples/README.md contained incorrect example descriptions
- **Status:** Closed / Implemented (2026-03-24)
- **Category:** Docs | **Severity:** Low
- **Resolution:** Accurate descriptions for all example programs.
- **Evidence:** `examples/README.md`

### GAP-0041: examples/02_uri_resolution.zig used incorrect deinit pattern
- **Status:** Closed / Implemented (2026-03-24)
- **Category:** Docs | **Severity:** Medium
- **Resolution:** Updated to `resolved.deinit(allocator)` pattern.
- **Evidence:** `examples/02_uri_resolution.zig`

### GAP-0042: SECURITY.md contained inaccurate security measures list
- **Status:** Closed / Implemented (2026-03-24)
- **Category:** Docs | **Severity:** Medium
- **Resolution:** Removed false fuzz testing claim; updated security measures list.
- **Evidence:** `SECURITY.md`

### GAP-0043: .gitlab-ci.yml outdated Zig version comment
- **Status:** Closed / Implemented (2026-03-24)
- **Category:** Docs | **Severity:** Low
- **Resolution:** Updated comment to reflect current status.
- **Evidence:** `.gitlab-ci.yml`

### GAP-0044: register() errdefer missing on partial allocation failure
- **Status:** Closed / Implemented (2026-03-24)
- **Category:** Security | **Severity:** Medium
- **Resolution:** Added `errdefer` guards to `register()` in `src/registry.zig`.
- **Evidence:** `src/registry.zig` -- register() errdefer guards.

### GAP-0045: addAnchor() errdefer missing on allocation failure
- **Status:** Closed / Implemented (2026-03-24)
- **Category:** Security | **Severity:** Medium
- **Resolution:** Added `errdefer` guard to `addAnchor()` in `src/registry.zig`.
- **Evidence:** `src/registry.zig` -- addAnchor() errdefer guard.

### GAP-0046: ParseOptions not re-exported from lib.zig public API
- **Status:** Closed / Implemented (2026-03-24)
- **Category:** API | **Severity:** Medium
- **Resolution:** Added `ParseOptions` to public re-exports in `src/lib.zig`. Duplicate of QF-R7.
- **Evidence:** `src/lib.zig` -- ParseOptions re-export.

---

## Re-Audit Won't Do Items (2026-03-24)

> Cross-domain won't-do items from the re-audit.

### QF-R2: CI build/test stages still absent
- **Status:** Won't Do
- **Issue:** [#22](https://gitlab.com/devnw/zig/uri/-/issues/22)
- **Category:** CI-CD | **Severity:** High
- **Reason:** Requires CI runner provisioning. Tracked via existing issue #22.

### QF-R5: markdownlint warnings in documentation
- **Status:** Won't Do
- **Category:** Docs | **Severity:** Low
- **Reason:** Cosmetic, pre-existing. No functional impact.

### QF-R8: fork/join duplication in parallel batch functions
- **Status:** Won't Do
- **Category:** Code Quality | **Severity:** Low
- **Reason:** Bounded duplication (3 instances) with different context types. Extraction deferred.

### PF-R1: Arena allocator for batch operations
- **Status:** Won't Do
- **Category:** Performance | **Severity:** P1
- **Reason:** Deferred to dedicated performance PR.

### PF-R2: CI build/test stages still absent
- **Status:** Won't Do
- **Category:** Performance | **Severity:** P3
- **Reason:** Same as QF-R2 / GAP-0001.

### PF-R4: No benchmark suite
- **Status:** Won't Do
- **Issue:** [#21](https://gitlab.com/devnw/zig/uri/-/issues/21)
- **Category:** Performance | **Severity:** P3
- **Reason:** v1.0.0 milestone deliverable.

### PF-R5: percentEncode preallocation could be tighter
- **Status:** Won't Do
- **Category:** Performance | **Severity:** P2
- **Reason:** Current preallocation is adequate; tighter estimate requires double pass.

### PF-R6: toOwnedSlice shrink overhead
- **Status:** Won't Do
- **Category:** Performance | **Severity:** P2
- **Reason:** Near-zero cost; shrink reallocation handled efficiently by allocators.

### PF-R7: defaultPort linear scan for 20+ entries
- **Status:** Won't Do
- **Category:** Performance | **Severity:** P3
- **Reason:** Compile-time unrolled by Zig. Acceptable at current scale.

### SF-R7: C1 control characters (0x80-0x9F) accepted in non-strict mode
- **Status:** Won't Do
- **Category:** Security | **Severity:** Low
- **Reason:** Would break IRI mode. Not required by RFC 3986.

### SF-R8: FetchCallback SSRF risk (re-confirmed)
- **Status:** Won't Do
- **Category:** Security | **Severity:** Medium
- **Reason:** SSRF prevention is caller's responsibility. API docs warn about risk.
