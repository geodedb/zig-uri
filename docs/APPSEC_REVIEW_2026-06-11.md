# Application Security Code Review — `devnw/zig/uri` (RFC 3986 URI Parser)

**Reviewer role:** Defensive, evidence-first appsec code review
**Standards:** OWASP Top 10:2025, CIS Controls v8.1.2
**Target:** `/home/benji/src/gl/gitlab.com/devnw/zig/uri` — branch `main`, HEAD `01d10ef`, package `uri` v0.1.4
**Date:** 2026-06-11

---

## 1. Scope and Assumptions

**Reviewed (full working tree, clean):**

- `src/uri.zig` (2032 lines) — RFC 3986 parser, resolver, normalizer, percent codec
- `src/parallel.zig` (659 lines) — batch parse/validate/normalize via `thread_pool`
- `src/registry.zig` (369 lines) — in-memory resource registry with fetch callback
- `src/debug.zig` (404 lines) — JSON/stderr serialization with userinfo redaction
- `src/lib.zig` (318 lines) — public API surface
- `build.zig`, `build.zig.zon`, `.gitlab-ci.yml`, `.pre-commit-config.yaml`, `.gitleaks.toml`, `Makefile`, `scripts/detect_diamond_deps.py`, `SECURITY.md`
- `docs/SECURITY_GAP_ANALYSIS.md` (reconciled)

**Method:** Source-to-sink tracing of untrusted URI input plus empirical validation against the real `src/lib.zig` under Zig 0.16.0 with ~30 adversarial inputs. No repository file was modified.

**Assumptions:**

- Trust boundary: untrusted URI strings from any source; downstream consumers depend on correct, safe component splitting.
- Library code: no auth, no network, no PII storage. SSRF/redirect outcomes materialize only in consumers.
- Zig safety builds (`Debug`, `ReleaseSafe`) trap on integer overflow / OOB; `ReleaseFast`/`ReleaseSmall` do not. CI tests all four modes.

**Reconciliation with `docs/SECURITY_GAP_ANALYSIS.md`:** The 13 original + 8 re-audit findings are genuinely fixed in current code (verified in source). The findings below are new or are regressions/residuals not captured by the prior audit.

---

## 2. Executive Summary

- No memory-safety defects or panics found on hostile input. Prior critical/high memory bugs are genuinely fixed.
- Dominant risk class is parsing-differential / URL-confusion, not memory safety: port parsing (`8_080`, `+443`), silent truncation after IPv6 brackets, no host-character validation.
- `normalize()` activates percent-encoded dot-segments (`/a/b/%2e%2e/c` → `/a/c`).
- `Uri.authority()` returns `null` for owned URIs (output of `resolve`/`normalize`/`dupe`).
- Supply chain is in good shape; one residual: CI `fuzz` job runs `--fuzz` but no fuzz harness exists.
- Thread safety is sound by documentation + design.

**Overall confidence: High** for parser/normalizer findings (empirically reproduced).

---

## 3. Findings Table

| ID | Severity | Confidence | Title | Location | OWASP 2025 | Status |
|----|----------|-----------|-------|----------|-----------|--------|
| F-01 | Medium | High | Port parser accepts non-`DIGIT` strings (`+443`, `8_080`, leading zeros) | `src/uri.zig:489` | A06 / A05 | New |
| F-02 | Medium | High | `normalize()` activates percent-encoded dot-segments (`%2e%2e`→`..`→traversal) | `src/uri.zig:856-904` | A01 / A06 | New |
| F-03 | Medium | High | `Uri.authority()` returns `null` for owned (resolved/normalized/duped) URIs | `src/uri.zig:165-188` | A06 | New |
| F-04 | Low | High | No host-component character validation; silent truncation after IPv6 `]` | `src/uri.zig:442-482` | A06 | New |
| F-05 | Low | High | Host case-normalization lowercases percent-encoding hex (`%2F`→`%2f`) | `src/uri.zig:868-874` | A06 | New |
| F-06 | Low | Medium | CI `fuzz` job runs `--fuzz` with zero fuzz harnesses | `.gitlab-ci.yml:155-174` | A09 / A02 | New (residual) |
| F-07 | Low | High | Non-strict mode disables all character validation | `src/uri.zig:1048` | A06 | By-design; flag |
| F-08 | Info | High | `SECURITY.md` documents `spice` dependency; actual dep is `thread_pool` | `SECURITY.md:37` | A02 | New |
| F-09 | Info | Medium | No default input-length bound; `max_input_len` defaults to `null` | `src/uri.zig:66-67,333-335` | A10 / A05 | Reconciled |

---

## 4. Finding Details

### F-01 — Port parser accepts non-`DIGIT` strings — Medium

RFC 3986 §3.2.3: `port = *DIGIT`. `std.fmt.parseInt` accepts a leading sign and `_` separators. Confirmed: `http://h:+443/p` → port=443; `http://h:8_080/p` → port=8080; `http://h:0080/p` → port=80. Numeric and textual views of the port diverge, undermining allow-list / SSRF-port checks. **Remediation:** validate `port_str` against `*DIGIT` before `parseInt`. CWE-20, CWE-1286.

### F-02 — `normalize()` activates percent-encoded dot-segments — Medium

`normalize()` decodes unreserved octets (`%2E`→`.`) then removes dot segments. Confirmed: `http://h/a/b/%2e%2e/c` → `/a/c`; `http://EXAMPLE.com/%2e%2e/secret` → `/secret`. Path-confusion / traversal differential for consumers that normalize around an authorization/cache boundary. **Remediation:** perform dot-segment removal on the pre-decode path, or document the activation explicitly. CWE-41, CWE-707.

### F-03 — `Uri.authority()` returns `null` for owned URIs — Medium

`authority()` reconstructs from `self.raw`, but `resolve()` sets `raw = ""`. Confirmed: owned URI with host `example.com` returns `authority() = null`. A security accessor returns wrong results for exactly the resolved URIs consumers feed to allow-lists. **Remediation:** reconstruct from `userinfo`/`host`/`raw_port` fields. CWE-665.

### F-04 — No host-character validation; silent truncation after IPv6 `]` — Low

`parseAuthority` slices host without per-component validation; bracketed branch discards trailing bytes. Confirmed: `http://[::1]xyz/p` → host `[::1]` (xyz dropped); `http://a]b[c/p` accepted. **Remediation:** validate each host byte with `isAllowedInComponent(.host)`; reject trailing bytes between `]` and delimiter. CWE-20.

### F-05 — Host case-normalization lowercases percent-encoding hex — Low

`normalize()` lowercases host in place but skips `normalizePercentEncoding` for host. Confirmed: `http://ex%2Fample.com/p` → `ex%2fample.com` (RFC §6.2.2.2 requires uppercase hex). **Remediation:** apply percent-encoding normalization to host. CWE-178.

### F-06 — CI `fuzz` job runs `--fuzz` with no fuzz harness — Low

`.gitlab-ci.yml` runs `zig build test --fuzz` but no `std.testing.fuzz` usage exists in any `.zig` file. Green stage gives false fuzzing assurance. **Remediation:** add a real fuzz target for `parse`/`parseWithOptions`/`normalize`/`resolve`/`percentDecode`. CWE-1059, CWE-778.

### F-07 — Non-strict mode disables all character validation — Low (by design)

`validateInput` rejects C0/DEL in all modes (good), then `if (!options.strict) return;` skips all other checks. Backslash `\`, spaces, high bytes enter components. **Remediation:** document that non-strict mode performs no structural validation and must not be used for security decisions; recommend `strict=true`. CWE-20.

### F-08 — `SECURITY.md` documents wrong dependency — Info

`SECURITY.md:37` references optional `spice`; actual dep is `thread_pool 0.2.4`. **Remediation:** update doc. A02:2025.

### F-09 — No default input-length bound — Info (reconciled)

`ParseOptions.max_input_len` defaults to `null` (unbounded). Parser is O(n) allocation-free so DoS is proportional. **Remediation:** consider a conservative default for the `parse()` wrapper or document the requirement. CWE-400.

---

## 5. Secure Design Notes

Memory safety is solid (ownership flag, errdefer chains, zero-copy parse). Control-character defense in all modes. IRI UTF-8 validation correct. Credential redaction in debug output. Integer-overflow-safe registry. Explicit concurrency contracts. Last-`@` userinfo split. Strong supply chain (single pinned dep, pinned CI components, SHA-256-verified toolchain, SAST/dependency/secret/gitleaks/SBOM scanning).

## 6. Coverage Gaps and Questions

- No fuzzing performed; no-panic conclusion is sampled, not exhaustive.
- `tests/` not exhaustively line-audited.
- `thread_pool` transitive code out of scope.
- Consumer impact for F-01..F-05 is inferred.

## 7. Prioritized Next Actions

1. F-03 (Medium): fix `Uri.authority()` to reconstruct from fields.
2. F-01 (Medium): reject non-`DIGIT` port strings.
3. F-02 (Medium): fix/document `normalize()` dot-segment ordering.
4. F-06 (Low): add a real fuzz harness.
5. F-04 / F-05 (Low): host validation + percent normalization on host.
6. F-07 / F-08 / F-09 (Low/Info): docs + default length bound.
