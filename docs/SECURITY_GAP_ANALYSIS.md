# Security Gap Analysis

> Last updated: 2026-03-24 (re-audit)
> Scope: Security review of devnw/zig/uri library (Phase 3 deep review + re-audit)
> Baseline: commit 2b27b53 (main branch)
> Mode: skip-issues (initial audit); re-audit created confidential issues #34-37

---

## Summary

| Severity | Count |
|----------|-------|
| Critical | 1 (Resolved) |
| High     | 4 (all Resolved) |
| Medium   | 5 (4 Resolved, 1 Won't Do) |
| Low      | 3 (2 Resolved, 1 Won't Do) |
| **Total**| **13 (11 Resolved, 2 Won't Do, 0 Open)**|

**Secrets scan:** 0 real secrets found. 29 TruffleHog false positives from test fixture URIs containing dummy credentials -- no rotation required.

### Top 5 Risks

1. **[CRITICAL] Uri.deinit() frees non-heap slices on zero-copy URIs** -- undefined behavior, heap corruption, crash (Risk Score: 100)
2. **[HIGH] CONFIDENTIAL: Debug functions serialize credentials in plaintext** -- credential leak via logs/JSON output (Risk Score: 80)
3. **[HIGH] getPool() returns dangling pointer after deinitPool()** -- use-after-free in concurrent scenarios (Risk Score: 64)
4. **[HIGH] Parallel parseUri() skips all input validation** -- parser differential, malformed URIs accepted (Risk Score: 60)
5. **[HIGH] Spice dependency pinned to main branch** -- supply chain risk, untested code pulled on build (Risk Score: 48) -- **RESOLVED: pinned to commit SHA bbf106dc8131a514a4d1687cc2173f124f5c8181**

---

## Stack-Ranked Findings

| Rank | Severity | Risk Score | Finding | Component | CWE / OWASP | Evidence (file:line) | Issue URL | Fix | Owner | Due | Status |
|------|----------|------------|---------|-----------|-------------|----------------------|-----------|-----|-------|-----|--------|
| 1 | Critical | 100 | deinit() frees non-heap slices on parsed (zero-copy) URIs | uri.zig | CWE-761 / CWE-416 / A06:2021 | `src/uri.zig:261-280` | skip-issues | Add ownership flag to Uri struct | -- | 7 days | Resolved |
| 2 | High | 80 | CONFIDENTIAL: Debug functions leak credentials in plaintext | debug.zig | CWE-532 / CWE-200 / A04:2021 | `src/debug.zig:76-78,182-183,218` | skip-issues | Redact userinfo in serialization | -- | 30 days | Resolved |
| 3 | High | 64 | getPool() returns raw pointer, dangling after deinitPool() | parallel.zig | CWE-416 / A06:2021 | `src/parallel.zig:70-81,83-93` | skip-issues | Return optional or reference-counted handle | -- | 30 days | Resolved (documented lifecycle constraint; double-checked locking with atomic bool) |
| 4 | High | 60 | Parallel parseUri() skips all input validation | parallel.zig | CWE-20 / A03:2021 | `src/parallel.zig:190-272` | skip-issues | Delegate to parseWithOptions or replicate validation | -- | 30 days | Resolved (duplicate parser eliminated; delegates to core uri.parse()) |
| 5 | High | 48 | Spice dependency pinned to main branch, not tagged release | build.zig.zon | CWE-829 / A06:2021 | `build.zig.zon:22` | skip-issues | Pin to tagged release with hash verification | -- | 30 days | Resolved (pinned to commit SHA; no upstream tags available) |
| 6 | Medium | 48 | validateInput() disabled when strict=false, allows null bytes | uri.zig | CWE-20 / CWE-158 / A03:2021 | `src/uri.zig:794-795` | skip-issues | Add minimal validation for control chars even in non-strict mode | -- | 90 days | Resolved |
| 7 | Medium | 36 | IRI mode accepts >= 0x80 bytes without UTF-8 validation | uri.zig | CWE-176 / A03:2021 | `src/uri.zig:816-819` | skip-issues | Add UTF-8 sequence validation in IRI path | -- | 90 days | Resolved |
| 8 | Medium | 36 | Registry has no thread safety despite parallel module existing | registry.zig | CWE-362 / CWE-567 / A04:2021 | `src/registry.zig:90-118` | skip-issues | Add mutex or document single-threaded constraint | -- | 90 days | Resolved |
| 9 | Medium | 36 | FetchCallback passes untrusted URI to user callback without validation | registry.zig | CWE-918 / A10:2021 | `src/registry.zig:173-185` | skip-issues | Validate/sanitize URI before passing to callback | -- | 90 days | Won't Do (SSRF prevention is caller responsibility; documented in API) |
| 10 | Medium | 24 | SECURITY.md falsely claims fuzz testing exists | SECURITY.md | CWE-1059 / A05:2021 | `SECURITY.md:37` | skip-issues | Remove claim or implement fuzz testing | -- | 90 days | Resolved |
| 11 | Low | 20 | No input length limit on parse() | uri.zig | CWE-400 / A05:2021 | `src/uri.zig:284-286` | skip-issues | Add configurable max input length | -- | 180 days | Resolved |
| 12 | Low | 16 | Anchor offset+length overflow risk on 32-bit targets | registry.zig | CWE-190 / CWE-125 / A06:2021 | `src/registry.zig:234` | skip-issues | Use checked arithmetic for offset+length | -- | 180 days | Resolved |
| 13 | Low | 12 | Hardcoded page_allocator in thread pool | parallel.zig | CWE-770 / A05:2021 | `src/parallel.zig:77` | skip-issues | Accept allocator parameter | -- | 180 days | Won't Do (page_allocator is thread-safe by design; documented tradeoff) |

---

## Detailed Findings

---

### Finding 1: Uri.deinit() frees non-heap slices on zero-copy (parsed) URIs

**Severity:** Critical
**Risk Score:** 100 (Impact: 5 x Likelihood: 5 x 4)
**Confidence:** `confidence::confirmed`
**Exploit Surface:** Any consumer of the library
**SLA:** 7 days

**Summary:** `Uri.deinit()` unconditionally calls `allocator.free()` on every non-null field. However, `parse()` returns a zero-copy Uri whose slices point into the original input buffer (not heap-allocated memory). Calling `deinit()` on such a Uri passes non-heap pointers to `allocator.free()`, causing undefined behavior: heap corruption, crashes, or exploitable memory corruption.

**Impact:** An attacker or unwitting caller who parses a URI and then calls `deinit()` triggers undefined behavior. In Zig's default allocator this typically causes a safety-check panic in safe mode, or silent heap corruption in release mode. Score: 5 -- heap corruption / potential code execution.

**Likelihood:** Score: 5 -- No runtime guard exists. The API is public and the distinction between "owned" and "borrowed" URIs is undocumented. Any user who calls `parse()` then `deinit()` hits this. The `dupe()` function (line 232) creates owned copies, but nothing prevents calling `deinit()` on the parse result.

**Evidence:**

`src/uri.zig:261-280` -- `deinit()` frees all fields unconditionally:
```zig
pub fn deinit(self: *Uri, allocator: Allocator) void {
    if (self.scheme) |s| allocator.free(s);
    if (self.userinfo) |ui| allocator.free(ui);
    if (self.host) |h| allocator.free(h);
    // ... all fields freed
}
```

`src/uri.zig:284-292` -- `parse()` / `parseWithOptions()` stores slices from the input:
```zig
pub fn parseWithOptions(input: []const u8, options: ParseOptions) ParseError!Uri {
    try validateInput(input, options);
    var result = Uri{ .raw = input };  // raw points to caller's buffer
    // ... all parsed fields are sub-slices of input
}
```

There is no `owned: bool` flag or equivalent to distinguish heap-backed from borrowed slices.

**Attack Scenario:** A consumer library accepts URIs from untrusted input, parses them, processes them, then calls `deinit()` expecting cleanup. This corrupts the heap. In release mode, subsequent allocations may return already-in-use memory, leading to data corruption or control-flow hijacking.

**Fix Guidance:**
1. Add an `owned: bool` field to `Uri` (default `false`).
2. Set `owned = true` only in `dupe()`.
3. In `deinit()`, guard all `allocator.free()` calls behind `if (self.owned)`.
4. Alternatively, make `deinit()` accept an optional allocator and only free when provided, or split into `deinit()` (for owned) and a no-op `release()` (for borrowed).

**Acceptance Criteria:**
- Calling `deinit()` on a `parse()` result is either a compile error, a safe no-op, or clearly documented as prohibited with a runtime assertion.
- Calling `deinit()` on a `dupe()` result correctly frees all memory with no leaks.
- Unit tests cover both paths.

**Status: Resolved**

**Resolution (2026-03-23):**
- Added `owned: bool = false` field to `Uri` struct.
- `dupe()` sets `owned = true` on the returned Uri.
- `deinit()` returns early (safe no-op) when `owned == false`.
- `resolve()` now returns a fully owned Uri (all fields allocated) instead of a mix of borrowed and allocated fields.
- `normalize()` already used `dupe()` internally, so it inherits `owned = true` automatically.
- Removed incorrect `path.len > 0` and `raw.len > 0` guards in `deinit()` -- owned URIs unconditionally free all fields including empty strings allocated by `dupe()`.
- Updated all callers of `resolve()` (tests, examples) to use `deinit()` instead of `allocator.free(resolved.path)`.
- Added 5 new tests covering ownership tracking for parse, dupe, normalize, resolve, and empty-path edge case.
- All 175 tests pass (73 unit + 19 RFC vectors + 26 acceptance + 57 dataset).

**References:**
- CWE-761: Free of Pointer not at Start of Buffer
- CWE-416: Use After Free
- OWASP A06:2021 Vulnerable and Outdated Components (misuse of unsafe API)

**Affected Paths:** `src/uri.zig`, `tests/rfc3986_vectors.zig`, `tests/accept.zig`, `examples/02_uri_resolution.zig`

---

### Finding 2: CONFIDENTIAL -- Debug functions leak credentials in plaintext

**Severity:** High
**Risk Score:** 80 (Impact: 4 x Likelihood: 5 x 4)
**Confidence:** `confidence::confirmed`
**Exploit Surface:** Any application using debug/logging functions
**SLA:** 30 days
**Confidential:** Yes -- credential exposure

**Summary:** `toJson()`, `toJsonPretty()`, and `dump()` serialize the `userinfo` field without any redaction. Per RFC 3986, the userinfo component can contain `username:password`. These functions output credentials in plaintext to JSON strings and stderr, which commonly end up in log files, monitoring systems, and error reports.

**Impact:** Credentials embedded in URIs are leaked to logs, JSON output, and stderr. In production systems this means passwords appear in log aggregation platforms (ELK, Datadog, CloudWatch), crash reports, and debug dumps. Score: 4 -- credential leak.

**Likelihood:** Score: 5 -- The functions are the primary debugging/serialization interface. Any URI with credentials (e.g., database connection strings, authenticated HTTP URIs) will have passwords serialized verbatim.

**Evidence:**

`src/debug.zig:76-78` -- `toJson()` outputs userinfo verbatim:
```zig
if (uri.userinfo) |ui| {
    try writeField(writer, &first, "userinfo", ui);
}
```

`src/debug.zig:182-183` -- `toJsonPretty()` same pattern:
```zig
if (uri.userinfo) |ui| {
    try writeFieldPretty(writer, &first, "userinfo", ui, 1);
}
```

`src/debug.zig:218` -- `dump()` prints to stderr:
```zig
std.debug.print("  userinfo: {?s}\n", .{uri.userinfo});
```

**Attack Scenario:** A web application parses database connection URIs (`postgres://admin:<REDACTED>@db.internal:5432/prod`) and logs them via `dump()` or `toJson()` during error handling. The password appears in application logs accessible to operations staff, log aggregation systems, or attackers who gain log access.

**Fix Guidance:**
1. When serializing `userinfo`, redact the password portion: if `userinfo` contains `:`, replace everything after the first `:` with `[REDACTED]`.
2. Add an option to control redaction behavior (e.g., `SerializeOptions{ .redact_credentials = true }`) defaulting to redacted.
3. Consider splitting userinfo into `username` and `password` fields during parsing, and never serializing `password` in debug output.

**Acceptance Criteria:**
- `toJson()`, `toJsonPretty()`, and `dump()` redact the password portion of userinfo by default.
- A test verifies that `user:secret@host` serializes as `user:[REDACTED]@host` or `user:***@host`.
- An explicit opt-in flag is required to include raw credentials.

**References:**
- CWE-532: Insertion of Sensitive Information into Log File
- CWE-200: Exposure of Sensitive Information to an Unauthorized Actor
- OWASP A04:2021 Insecure Design

**Affected Paths:** `src/debug.zig`

**Resolution (2026-03-23):**
- Added `redactUserinfo()` helper that splits on the first `:` and flags password presence without allocating.
- `toJson()`, `toJsonPretty()`, and `dump()` now redact the password portion of userinfo, outputting `user:***` instead of the raw password.
- Extracted shared field-enumeration logic into `writeUriFields()` with a `JsonMode` enum, eliminating ~60 lines of duplication between `toJson` and `toJsonPretty`.
- Added 8 new tests covering: password redaction in compact and pretty JSON, username-only preservation, absent userinfo, empty password, multiple colons.
- Note: An explicit opt-in flag for raw credentials was not added. The debug functions are intended for logging/debugging only; the raw `userinfo` field remains accessible on the `Uri` struct for callers that need it.

---

### Finding 3: getPool() returns dangling pointer after deinitPool() -- RESOLVED

**Status: Resolved**

**Resolution (2026-03-23):** Implemented double-checked locking with a separate `pool_initialized` atomic bool. Fast path performs `@atomicLoad` with `.acquire` ordering; slow path acquires the mutex and publishes via `@atomicStore` with `.release` ordering. Added comprehensive doc comment to `deinitPool()` documenting the lifecycle constraint: it must NOT be called while parallel operations are in flight. Callers must ensure all batch operations have completed before teardown.

**Severity:** High
**Risk Score:** 64 (Impact: 4 x Likelihood: 4 x 4)
**Confidence:** `confidence::confirmed`
**Exploit Surface:** Library consumers using parallel API
**SLA:** 30 days

**Summary:** `getPool()` returns a raw pointer (`*spice.ThreadPool`) to the global pool. If `deinitPool()` is called (e.g., during shutdown) while other code still holds a reference from a prior `getPool()` call, the pointer becomes dangling. Any subsequent use is a use-after-free.

**Impact:** Use-after-free on the thread pool structure. This can cause crashes, heap corruption, or in adversarial conditions, code execution. Score: 4.

**Likelihood:** Score: 4 -- Concurrent teardown is a common pattern in multi-threaded applications. The pool is global mutable state with no reference counting. Any code that caches the pool pointer across a deinitPool() boundary triggers this.

**Evidence:**

`src/parallel.zig:70-81` -- `getPool()` returns address of optional's payload:
```zig
pub fn getPool() if (build_options.enable_spice) *spice.ThreadPool else void {
    // ...
    return &global_pool.?;  // raw pointer to global mutable state
}
```

`src/parallel.zig:83-93` -- `deinitPool()` nullifies after deinit:
```zig
pub fn deinitPool() void {
    // ...
    if (global_pool) |*pool| {
        pool.deinit();
        global_pool = null;  // pointer from getPool() is now dangling
    }
}
```

**Attack Scenario:** Application code calls `getPool()`, stores the pointer, then a shutdown handler calls `deinitPool()`. Subsequent use of the stored pointer reads freed memory. In adversarial conditions, an attacker who can influence heap layout after the free could achieve code execution.

**Fix Guidance:**
1. Use reference counting: `getPool()` increments a refcount, return a handle that decrements on `release()`. `deinitPool()` waits for refcount to reach zero.
2. Alternatively, return an optional and document that callers must not cache the result.
3. Consider an RAII-style `PoolGuard` that holds a reference and releases on deinit.

**Acceptance Criteria:**
- It is impossible to use a pool reference after `deinitPool()` completes without triggering a detectable error.
- Tests verify that using a pool reference after deinit is either a compile error or a runtime-detected error (not UB).

**References:**
- CWE-416: Use After Free
- OWASP A06:2021 Vulnerable and Outdated Components

**Affected Paths:** `src/parallel.zig`

---

### Finding 4: Parallel parseUri() skips all input validation -- RESOLVED

**Status: Resolved**

**Resolution (2026-03-23):** The standalone `parseUri()` function was replaced with a delegation to `uri_mod.parse()` (`src/parallel.zig`). The parallel parser now uses the exact same validation and parsing logic as the core parser. The 106-line duplicate parser code was removed. The parser differential vulnerability no longer exists. All 302 tests pass.

**Severity:** High
**Risk Score:** 60 (Impact: 3 x Likelihood: 5 x 4)
**Confidence:** `confidence::confirmed`
**Exploit Surface:** Any consumer using the parallel batch parsing API
**SLA:** 30 days

**Summary:** The `parseUri()` function in `parallel.zig` implements its own URI parsing logic without calling `validateInput()` or any of the validation from `uri.zig`. This creates a parser differential: the same input may be rejected by `uri.parse()` but accepted by the parallel API, allowing malformed or malicious URIs through.

**Impact:** Malformed URIs containing null bytes, control characters, or invalid percent-encoding are accepted through the parallel API while being rejected by the standard parser. This can lead to injection attacks if downstream consumers trust the parsed result. Score: 3.

**Likelihood:** Score: 5 -- The parallel API is the primary batch processing interface. Any input passed through it bypasses all validation. No special conditions are required.

**Evidence:**

`src/parallel.zig:190-272` -- `parseUri()` implements ad-hoc parsing with no validation:
```zig
fn parseUri(input: []const u8) ParseResult {
    if (input.len == 0) {
        return .{ .components = .{ ... }, .success = true, .error_code = 0 };
    }
    var remaining = input;
    // ... direct string splitting with no character validation
    // No call to validateInput(), no percent-encoding checks,
    // no control character rejection
}
```

Compare with `src/uri.zig:289-290` which validates first:
```zig
pub fn parseWithOptions(input: []const u8, options: ParseOptions) ParseError!Uri {
    try validateInput(input, options);
```

**Attack Scenario:** An application uses the parallel API to batch-parse URIs from untrusted input. A URI containing `http://evil.com%00@trusted.com/` is accepted without error. Downstream code that checks the host field sees `evil.com\x00@trusted.com` and may truncate at the null byte, connecting to `evil.com` instead of `trusted.com`.

**Fix Guidance:**
1. Have `parseUri()` delegate to `uri.parseWithOptions()` instead of reimplementing parsing.
2. If a separate implementation is needed for performance, replicate the validation logic from `validateInput()`.
3. Add integration tests that verify both parsers reject the same invalid inputs.

**Acceptance Criteria:**
- The parallel parser rejects the same set of invalid inputs as the standard parser.
- A test suite runs identical invalid inputs through both APIs and asserts identical rejection.

**References:**
- CWE-20: Improper Input Validation
- OWASP A03:2021 Injection

**Affected Paths:** `src/parallel.zig`

---

### Finding 5: Spice dependency pinned to main branch -- RESOLVED

**Status:** Resolved
**Severity:** High
**Risk Score:** 48 (Impact: 4 x Likelihood: 3 x 4)
**Confidence:** `confidence::confirmed`
**Exploit Surface:** Build pipeline / supply chain
**SLA:** 30 days

**Summary:** The `spice` dependency in `build.zig.zon` was fetched from a `main` branch archive URL rather than a tagged release. This meant every build fetched whatever was currently on `main`, which could include broken, untested, or malicious code.

**Resolution:** The URL has been updated to pin to commit SHA `bbf106dc8131a514a4d1687cc2173f124f5c8181` instead of the mutable `main` branch. The upstream spice repository has no tagged releases, so a commit-pinned URL is used. The hash was verified to match. When the upstream repository publishes tagged releases, the URL should be updated to reference a tag instead.

**Impact:** A compromise of the spice repository's main branch, or an accidental breaking change, would propagate to all builds of this library. Score: 4 -- supply chain compromise can lead to arbitrary code execution.

**Likelihood:** Score: 3 -- Requires either a compromise of the upstream repo or an accidental push of broken code to main. The hash provides some protection, but the URL pattern (`main/spice-main.tar.gz`) suggests the hash may need updating when main changes.

**Evidence (before fix):**

`build.zig.zon:20`:
```
.url = "https://gitlab.com/devnw/zig/spice/-/archive/main/spice-main.tar.gz",
```

The URL referenced `/archive/main/` rather than a tagged version like `/archive/v0.1.0/`.

**Evidence (after fix):**

`build.zig.zon:22`:
```
.url = "https://gitlab.com/devnw/zig/spice/-/archive/bbf106dc8131a514a4d1687cc2173f124f5c8181/spice-bbf106dc8131a514a4d1687cc2173f124f5c8181.tar.gz",
```

The URL now references a specific immutable commit SHA.

**Fix Guidance:**
1. Create a tagged release of the spice library (e.g., `v0.1.0`).
2. Update the URL to reference the tagged archive: `.../archive/v0.1.0/spice-v0.1.0.tar.gz`.
3. Verify the hash matches the tagged release archive.
4. Document the update procedure for dependency versions.

**Acceptance Criteria:**
- `build.zig.zon` references a specific commit SHA URL for the spice dependency (tagged release not available upstream).
- The hash corresponds to a specific immutable commit, not a moving branch.

**References:**
- CWE-829: Inclusion of Functionality from Untrusted Control Sphere
- OWASP A06:2021 Vulnerable and Outdated Components

**Affected Paths:** `build.zig.zon`

---

### Finding 6: validateInput() completely disabled when strict=false

**Severity:** Medium
**Risk Score:** 48 (Impact: 3 x Likelihood: 4 x 4)
**Confidence:** `confidence::confirmed`
**Exploit Surface:** Any consumer using default parse options
**SLA:** 90 days

**Summary:** When `strict=false` (which appears to be the default mode), `validateInput()` returns immediately without checking anything. This means null bytes (`\x00`), control characters (`\x01`-`\x1F`), and other dangerous bytes are accepted into parsed URI fields.

**Impact:** Null bytes and control characters in URI fields can cause truncation attacks, header injection, log injection, and other injection vectors in downstream consumers. Score: 3.

**Likelihood:** Score: 4 -- Default parsing mode skips all validation. Any untrusted input is accepted.

**Evidence:**

`src/uri.zig:794-795`:
```zig
fn validateInput(input: []const u8, options: ParseOptions) ParseError!void {
    if (!options.strict) return;  // ALL validation skipped
```

**Fix Guidance:**
1. Even in non-strict mode, reject null bytes (`\x00`) and ASCII control characters (`\x01`-`\x1F` excluding TAB).
2. Move the minimum safety checks (null byte, control char rejection) before the strict-mode gate.
3. Only skip the stricter checks (percent-encoding validation, character set enforcement) in non-strict mode.

**Acceptance Criteria:**
- `parse()` rejects null bytes in all modes.
- `parse()` rejects ASCII control characters (except possibly TAB/CR/LF per RFC) in all modes.
- Tests verify rejection of `\x00` and `\x01` in non-strict mode.

**References:**
- CWE-20: Improper Input Validation
- CWE-158: Improper Neutralization of Null Byte
- OWASP A03:2021 Injection

**Affected Paths:** `src/uri.zig`

---

### Finding 7: IRI mode accepts bytes >= 0x80 without UTF-8 validation

**Severity:** Medium
**Risk Score:** 36 (Impact: 3 x Likelihood: 3 x 4)
**Confidence:** `confidence::confirmed`
**Exploit Surface:** Consumers using IRI mode
**SLA:** 90 days

**Summary:** When `iri_mode` is enabled, bytes >= 0x80 are accepted without verifying they form valid UTF-8 sequences. RFC 3987 (IRI) requires that international characters be valid Unicode. Invalid byte sequences can cause downstream parsing errors or encoding-based attacks.

**Impact:** Invalid UTF-8 sequences in URI fields can cause mojibake, truncation, or encoding-based attacks in downstream systems. Score: 3.

**Likelihood:** Score: 3 -- Requires IRI mode to be enabled and malformed input. IRI mode is opt-in.

**Evidence:**

`src/uri.zig:816-819`:
```zig
if (c >= 0x80) {
    if (options.iri_mode) {
        i += 1;      // accepts any byte >= 0x80 without UTF-8 validation
        continue;
    }
```

The code advances by exactly 1 byte regardless of the expected UTF-8 multi-byte sequence length.

**Fix Guidance:**
1. When `iri_mode` is true and a byte >= 0x80 is encountered, decode the full UTF-8 sequence using `std.unicode.utf8Decode()`.
2. Reject invalid sequences (overlong encodings, surrogate pairs, bytes > U+10FFFF).
3. Advance `i` by the correct sequence length (2-4 bytes).

**Acceptance Criteria:**
- IRI mode rejects invalid UTF-8 sequences (e.g., `0xFF`, `0xFE`, truncated multi-byte sequences).
- IRI mode correctly advances past valid multi-byte UTF-8 sequences.
- Tests cover valid CJK/emoji URIs and reject isolated continuation bytes.

**References:**
- CWE-176: Improper Handling of Unicode Encoding
- OWASP A03:2021 Injection
- RFC 3987 Section 2.1

**Affected Paths:** `src/uri.zig`

---

### Finding 8: Registry has no thread safety

**Severity:** Medium
**Risk Score:** 36 (Impact: 3 x Likelihood: 3 x 4)
**Confidence:** `confidence::confirmed`
**Exploit Surface:** Multi-threaded applications using Registry + parallel module
**SLA:** 90 days

**Summary:** The `Registry` struct uses `std.StringHashMap` without any synchronization primitives (mutex, rwlock). The library includes a `parallel` module that encourages multi-threaded use, but the Registry is not safe for concurrent access.

**Impact:** Concurrent reads and writes to the Registry cause data races: corrupted hash map state, lost entries, or crashes. Score: 3.

**Likelihood:** Score: 3 -- Requires multi-threaded use of Registry. The existence of the parallel module makes this plausible but not guaranteed.

**Evidence:**

`src/registry.zig:90-118` -- No mutex or synchronization in Registry:
```zig
pub const Registry = struct {
    allocator: Allocator,
    resources: std.StringHashMap(Resource),  // no mutex protection
    // ...
    pub fn deinit(self: *Registry) void {
        var it = self.resources.iterator();  // unsafe under concurrent mutation
```

**Fix Guidance:**
1. Add a `std.Thread.Mutex` or `std.Thread.RwLock` to `Registry`.
2. Lock on all public methods (register, get, contains, remove, etc.).
3. Alternatively, clearly document that Registry is not thread-safe and must be externally synchronized.

**Acceptance Criteria:**
- Either: Registry is protected by internal synchronization, OR documentation explicitly states it is not thread-safe.
- If synchronized: stress tests with concurrent register/get operations pass without races.

**References:**
- CWE-362: Concurrent Execution using Shared Resource with Improper Synchronization
- CWE-567: Unsynchronized Access to Shared Data in a Multithreaded Context
- OWASP A04:2021 Insecure Design

**Affected Paths:** `src/registry.zig`

---

### Finding 9: FetchCallback passes untrusted URI to user callback without validation -- WON'T DO

**Status: Won't Do**

**Won't Do reason (2026-03-23):** SSRF prevention is the responsibility of the callback implementer, not the URI library. The library validates URI syntax but cannot know which hosts/schemes are safe for a given application. The Registry API documentation should warn about SSRF risk, but the library should not impose scheme restrictions.

**Severity:** Medium
**Risk Score:** 36 (Impact: 3 x Likelihood: 3 x 4)
**Confidence:** `confidence::suspected`
**Exploit Surface:** Applications using Registry with auto-fetch
**SLA:** 90 days

**Summary:** `Registry.get()` with `auto_fetch=true` passes the raw URI string directly to the user-provided `FetchCallback` without any validation or sanitization. If the callback performs network requests, this enables SSRF.

**Impact:** An attacker who controls the URI string passed to `Registry.get()` can direct the fetch callback to internal services (`http://169.254.169.254/metadata/`, `file:///etc/passwd`, etc.). Score: 3.

**Likelihood:** Score: 3 -- Requires the application to use auto-fetch with a callback that performs network requests, AND an attacker-controlled URI. This is a realistic but constrained scenario.

**Evidence:**

`src/registry.zig:173-185`:
```zig
pub fn get(self: *Registry, uri_str: []const u8, auto_fetch: bool) RegistryError!*Resource {
    if (self.resources.getPtr(uri_str)) |resource| {
        return resource;
    }
    if (auto_fetch) {
        if (self.fetch_callback) |fetch| {
            const content = fetch(uri_str, self.allocator) catch return RegistryError.FetchFailed;
            // uri_str passed directly to callback -- no scheme/host validation
```

**How to Verify:** Create a test with a mock FetchCallback that records the URI it receives. Pass `file:///etc/passwd` or `http://169.254.169.254/` to `get()` with `auto_fetch=true` and verify the callback receives the malicious URI unmodified.

**Fix Guidance:**
1. Validate the URI scheme before passing to the callback (e.g., only allow `http://` and `https://`).
2. Parse the URI and validate the host is not a private/reserved IP range.
3. Document the security implications of FetchCallback in the API docs.

**Acceptance Criteria:**
- Documentation warns about SSRF risk with FetchCallback.
- Optionally: scheme validation rejects non-HTTP(S) URIs before invoking the callback.

**References:**
- CWE-918: Server-Side Request Forgery
- OWASP A10:2021 Server-Side Request Forgery

**Affected Paths:** `src/registry.zig`

---

### Finding 10: SECURITY.md falsely claims fuzz testing exists

**Severity:** Medium
**Risk Score:** 24 (Impact: 2 x Likelihood: 3 x 4)
**Confidence:** `confidence::confirmed`
**Exploit Surface:** N/A (documentation accuracy)
**SLA:** 90 days

**Summary:** `SECURITY.md` line 37 claims "Fuzz testing for parser inputs" as an implemented security measure. No fuzz testing code, configuration, or CI integration exists in the repository.

**Impact:** False security claims mislead consumers into believing the parser has been fuzz-tested, potentially reducing their own security diligence. Score: 2 -- misleading documentation.

**Likelihood:** Score: 3 -- The claim is publicly visible and directly influences security assessments.

**Evidence:**

`SECURITY.md:37`:
```
- Fuzz testing for parser inputs
```

Grep for "fuzz" across the repository returns only `SECURITY.md` itself -- no fuzz harness, AFL/libfuzzer config, or fuzz corpus exists.

**Fix Guidance:**
1. Remove the "Fuzz testing" claim from SECURITY.md, or
2. Implement fuzz testing (e.g., Zig's built-in `std.testing.fuzz`) and add it to CI, then the claim becomes valid.

**Acceptance Criteria:**
- SECURITY.md only claims security measures that are actually implemented, OR
- A fuzz testing harness exists, runs in CI, and covers the parser.

**References:**
- CWE-1059: Insufficient Technical Documentation
- OWASP A05:2021 Security Misconfiguration

**Affected Paths:** `SECURITY.md`

---

### Finding 11: No input length limit on parse()

**Severity:** Low
**Risk Score:** 20 (Impact: 2 x Likelihood: 2.5 x 4)
**Confidence:** `confidence::confirmed`
**Exploit Surface:** Applications parsing untrusted input
**SLA:** 180 days

**Summary:** `parse()` and `parseWithOptions()` accept input of arbitrary length with no configurable limit. An attacker can submit extremely large inputs to cause excessive memory allocation and CPU consumption.

**Impact:** Denial of service through memory exhaustion or CPU-bound parsing of multi-megabyte inputs. Score: 2 -- availability impact only.

**Likelihood:** Score: 2.5 -- Requires the application to pass untrusted input directly to parse(). Most applications will have their own input limits upstream.

**Evidence:**

`src/uri.zig:284-286`:
```zig
pub fn parse(input: []const u8) ParseError!Uri {
    return parseWithOptions(input, .{});  // no length check
}
```

**Fix Guidance:**
1. Add a `max_input_length` field to `ParseOptions` with a sensible default (e.g., 8192 bytes per RFC 7230 recommendation for HTTP URIs).
2. Check input length at the start of `parseWithOptions()` and return an error if exceeded.

**Acceptance Criteria:**
- `ParseOptions` includes a configurable max length.
- Inputs exceeding the limit return a clear error.
- Default limit is documented.

**References:**
- CWE-400: Uncontrolled Resource Consumption
- OWASP A05:2021 Security Misconfiguration

**Affected Paths:** `src/uri.zig`

---

### Finding 12: Anchor offset+length overflow risk on 32-bit targets

**Severity:** Low
**Risk Score:** 16 (Impact: 2 x Likelihood: 2 x 4)
**Confidence:** `confidence::suspected`
**Exploit Surface:** 32-bit targets only
**SLA:** 180 days

**Summary:** In `getAnchorContent()`, the expression `anchor.offset + anchor.length` could overflow on 32-bit targets where `usize` is 32 bits. If overflow occurs, the bounds check passes but the resulting slice points to incorrect memory.

**Impact:** Out-of-bounds read leading to information disclosure. Score: 2 -- limited to 32-bit targets.

**Likelihood:** Score: 2 -- Requires 32-bit target AND attacker-controlled anchor values that sum to > 2^32.

**Evidence:**

`src/registry.zig:234`:
```zig
if (anchor.offset + anchor.length > resource.content.len) {
    // overflow of offset+length would wrap around, passing the check
```

**How to Verify:** On a 32-bit target, create an anchor with offset=0xFFFFFFFF and length=2. Verify whether `offset + length` wraps to 1, passing the bounds check.

**Fix Guidance:**
1. Use `std.math.add(usize, anchor.offset, anchor.length)` which returns an error on overflow.
2. Alternatively: `if (anchor.length > resource.content.len - anchor.offset)`.

**Acceptance Criteria:**
- Overflow of offset+length is detected and returns an error.
- A test verifies overflow detection on the host architecture.

**References:**
- CWE-190: Integer Overflow
- CWE-125: Out-of-bounds Read
- OWASP A06:2021 Vulnerable and Outdated Components

**Affected Paths:** `src/registry.zig`

---

### Finding 13: Hardcoded page_allocator in thread pool -- WON'T DO

**Status: Won't Do**

**Won't Do reason (2026-03-23):** `page_allocator` is thread-safe by design and acceptable for the pool's infrequent, large allocations (thread stacks). Documented tradeoff in `src/parallel.zig`. Switching to a userspace allocator would add complexity without meaningful benefit for this use case.

**Severity:** Low
**Risk Score:** 12 (Impact: 1 x Likelihood: 3 x 4)
**Confidence:** `confidence::confirmed`
**Exploit Surface:** Library consumers
**SLA:** 180 days

**Summary:** `getPool()` initializes the global thread pool with `std.heap.page_allocator`, which is hardcoded. This prevents consumers from using custom allocators (e.g., arena allocators, tracking allocators) and makes memory usage opaque.

**Impact:** Cannot track or limit thread pool memory usage. In resource-constrained environments this could lead to unexpected OOM. Score: 1 -- hardening concern.

**Likelihood:** Score: 3 -- Every user of the parallel API is affected.

**Evidence:**

`src/parallel.zig:77`:
```zig
global_pool = spice.ThreadPool.init(std.heap.page_allocator);
```

**Fix Guidance:**
1. Accept an `Allocator` parameter in `getPool()` or a module-level `init()` function.
2. Fall back to `page_allocator` only if no allocator is provided.

**Acceptance Criteria:**
- Consumers can provide a custom allocator for the thread pool.
- Default behavior remains unchanged for backward compatibility.

**References:**
- CWE-770: Allocation of Resources Without Limits or Throttling
- OWASP A05:2021 Security Misconfiguration

**Affected Paths:** `src/parallel.zig`

---

## Findings by Area

### Memory Safety (Findings 1, 3)
- **Critical:** deinit() on zero-copy URIs frees non-heap memory (UB, heap corruption)
- **High:** getPool() dangling pointer after deinitPool()

### Credential / Information Exposure (Finding 2)
- **High (CONFIDENTIAL):** Debug serialization functions leak userinfo passwords in plaintext

### Input Validation (Findings 4, 6, 7)
- **High:** Parallel parser skips all validation (parser differential)
- **Medium:** Non-strict mode accepts null bytes and control characters
- **Medium:** IRI mode lacks UTF-8 validation

### Concurrency (Finding 8)
- **Medium:** Registry lacks thread safety despite parallel module

### Supply Chain (Finding 5) -- RESOLVED
- ~~**High:** Spice dependency on floating main branch~~ -- Pinned to commit SHA `bbf106dc8131a514a4d1687cc2173f124f5c8181`

### SSRF / Injection (Finding 9)
- **Medium:** FetchCallback passes untrusted URIs to user callback

### Documentation (Finding 10)
- **Medium:** False fuzz testing claim in SECURITY.md

### Denial of Service / Resource Limits (Findings 11, 13)
- **Low:** No input length limit
- **Low:** Hardcoded page_allocator

### Integer Safety (Finding 12)
- **Low:** Anchor offset+length overflow on 32-bit

---

## Remediation Roadmap

### Quick Wins (< 1 day each)

| Finding | Task | Effort |
|---------|------|--------|
| 10 | Remove false fuzz testing claim from SECURITY.md | 15 min |
| 5 | ~~Pin spice dependency to a tagged release~~ RESOLVED (pinned to commit SHA) | 30 min |
| 12 | Use checked arithmetic for anchor offset+length | 30 min |
| 2 | Add password redaction to debug serialization functions | 2-4 hours |
| 11 | Add max input length to ParseOptions | 2-4 hours |

### Medium Effort (1-5 days each)

| Finding | Task | Effort |
|---------|------|--------|
| 1 | Add ownership tracking to Uri, guard deinit() | 1-2 days |
| 6 | Add minimum validation (null byte, control char) in non-strict mode | 1 day |
| 7 | Implement UTF-8 validation for IRI mode | 1-2 days |
| 4 | Unify parallel parser with standard parser validation | 1-2 days |
| 13 | Make thread pool allocator configurable | 1 day |

### Strategic (> 5 days)

| Finding | Task | Effort |
|---------|------|--------|
| 3 | Implement reference-counted pool handle to prevent dangling pointers | 3-5 days |
| 8 | Add synchronization to Registry or redesign for thread safety | 3-5 days |
| 9 | Add URI scheme/host validation for FetchCallback + SSRF documentation | 2-3 days |
| -- | Implement fuzz testing harness and CI integration (addresses Finding 10 fully) | 5-10 days |

---

## Immediate Actions Required

1. **Finding 1 (Critical, 7-day SLA):** The deinit-on-zero-copy-URI bug is the highest priority. It causes undefined behavior in any code that calls `parse()` then `deinit()`. Begin remediation immediately.

2. **Finding 2 (CONFIDENTIAL, 30-day SLA):** Credential leakage through debug functions. While not exploitable remotely, any application logging parsed URIs is leaking passwords today.

3. **Finding 5 (High, 30-day SLA):** ~~Pin the spice dependency to a tagged release. This is a 30-minute fix that eliminates ongoing supply chain risk.~~ **RESOLVED** -- Pinned to commit SHA `bbf106dc8131a514a4d1687cc2173f124f5c8181`. Update to a tagged release when upstream publishes one.

---

## Blockers and Unknowns

- **Finding 9 (SSRF):** Marked `confidence::suspected`. To confirm, verify whether any known consumers use `FetchCallback` with network-fetching implementations. If no consumers use auto-fetch with network callbacks, this is theoretical.

- **Finding 12 (Integer overflow):** Marked `confidence::suspected`. To confirm, test on a 32-bit target or verify whether Zig's safety checks catch the overflow in safe mode. Zig's debug/safe builds detect integer overflow, so this may only be exploitable in `ReleaseFast` or `ReleaseSmall` builds.

- **Finding 8 (Thread safety):** The Registry may be intentionally single-threaded. Confirm with maintainers whether concurrent Registry access is a supported use case before adding synchronization overhead.

---

## Re-Audit (2026-03-24)

> Re-audit after initial gap closure. 8 security-domain findings.
> Closed: 6 | Won't Do: 2
> Tests: 314/314 pass (up from 302 baseline).
> 4 confidential GitLab issues created and closed (#34-37).

### SF-R1: parseAuthority uses first @ instead of last @ for userinfo delimiter
- **Status: Closed / Implemented** (2026-03-24)
- **Issue:** [#34](https://gitlab.com/devnw/zig/uri/-/issues/34) (confidential)
- **Severity:** High
- **Risk Score:** 60 (Impact: 3 x Likelihood: 5 x 4)
- **CWE:** CWE-20 (Improper Input Validation)
- **Summary:** `parseAuthority()` used `indexOf('@')` to find the userinfo delimiter, but RFC 3986 Section 3.2.1 specifies the last `@` should be used. A URI like `user@evil.com@trusted.com` would incorrectly extract `user` as userinfo and `evil.com@trusted.com` as host, when the correct parsing is `user@evil.com` as userinfo and `trusted.com` as host.
- **Resolution:** Changed to `lastIndexOf('@')` in `src/uri.zig`. Added tests for multi-@ URIs.
- **Evidence:** `src/uri.zig` -- parseAuthority `lastIndexOf('@')`

### SF-R2: dupe() memory leak on partial allocation failure
- **Status: Closed / Implemented** (2026-03-24)
- **Issue:** [#35](https://gitlab.com/devnw/zig/uri/-/issues/35) (confidential)
- **Severity:** High
- **Risk Score:** 48 (Impact: 3 x Likelihood: 4 x 4)
- **CWE:** CWE-401 (Missing Release of Memory after Effective Lifetime)
- **Summary:** `dupe()` allocates copies of each URI field sequentially. If the 4th allocation fails (OOM), the first 3 allocated fields are leaked because there are no `errdefer` guards.
- **Resolution:** Added `errdefer` guards to free each successfully allocated field if a subsequent allocation fails.
- **Evidence:** `src/uri.zig` -- dupe() errdefer chain

### SF-R3: normalizeUri returned success=true on OOM
- **Status: Closed / Implemented** (2026-03-24)
- **Issue:** [#36](https://gitlab.com/devnw/zig/uri/-/issues/36) (confidential)
- **Severity:** High
- **Risk Score:** 48 (Impact: 3 x Likelihood: 4 x 4)
- **CWE:** CWE-252 (Unchecked Return Value)
- **Summary:** `normalizeUri()` in `src/parallel.zig` caught OOM errors from the core normalizer but still returned `success = true` with a partial or empty normalized result. Consumers relying on the success flag would use garbage data.
- **Resolution:** Error propagation corrected; OOM now sets `success = false` and populates `error_msg`.
- **Evidence:** `src/parallel.zig` -- normalizeUri error handling

### SF-R4: Pool TOCTOU race in deinitPool/getPool
- **Status: Closed / Implemented** (2026-03-24)
- **Issue:** [#37](https://gitlab.com/devnw/zig/uri/-/issues/37) (confidential)
- **Severity:** High
- **Risk Score:** 48 (Impact: 4 x Likelihood: 3 x 4)
- **CWE:** CWE-367 (Time-of-check Time-of-use Race Condition)
- **Summary:** A TOCTOU race existed between checking `pool_initialized` and acquiring the mutex in both `getPool()` and `deinitPool()`. A thread calling `deinitPool()` could destroy the pool between another thread's atomic check and mutex acquisition.
- **Resolution:** Both `getPool()` and `deinitPool()` use the same mutex for state transitions. The atomic `pool_initialized` flag is only used as a fast-path optimization; the authoritative state is protected by the mutex.
- **Evidence:** `src/parallel.zig` -- pool lifecycle with mutex protection

### SF-R5: register() errdefer missing on partial allocation failure
- **Status: Closed / Implemented** (2026-03-24)
- **Severity:** Medium
- **Risk Score:** 36 (Impact: 3 x Likelihood: 3 x 4)
- **CWE:** CWE-401 (Missing Release of Memory after Effective Lifetime)
- **Summary:** `register()` in `src/registry.zig` allocated the URI key string and resource content without `errdefer` guards. If the hash map insertion failed, the allocated strings would leak.
- **Resolution:** Added `errdefer` guards to clean up allocations on failure.
- **Evidence:** `src/registry.zig` -- register() errdefer guards

### SF-R6: addAnchor() errdefer missing on allocation failure
- **Status: Closed / Implemented** (2026-03-24)
- **Severity:** Medium
- **Risk Score:** 36 (Impact: 3 x Likelihood: 3 x 4)
- **CWE:** CWE-401 (Missing Release of Memory after Effective Lifetime)
- **Summary:** `addAnchor()` in `src/registry.zig` allocated the anchor name string but did not have an `errdefer` to free it if the subsequent hash map insertion failed.
- **Resolution:** Added `errdefer` guard to free anchor name on insertion failure.
- **Evidence:** `src/registry.zig` -- addAnchor() errdefer guard

### SF-R7: C1 control characters (0x80-0x9F) accepted in non-strict mode
- **Status: Won't Do**
- **Severity:** Low
- **Risk Score:** 12 (Impact: 1 x Likelihood: 3 x 4)
- **CWE:** CWE-20 (Improper Input Validation)
- **Summary:** In non-strict mode, C1 control characters (0x80-0x9F) are accepted because the non-strict validation only rejects C0 control characters (0x00-0x1F). C1 characters are rarely used in practice but could cause issues in downstream processing.
- **Reason:** C1 control character rejection would break IRI mode, which legitimately uses bytes >= 0x80 for UTF-8 multi-byte sequences. The existing UTF-8 validation in IRI mode correctly validates these sequences. In non-IRI non-strict mode, rejecting 0x80-0x9F would be an arbitrary restriction not required by RFC 3986. Deferred.

### SF-R8: FetchCallback SSRF risk (re-confirmed)
- **Status: Won't Do**
- **Severity:** Medium
- **Risk Score:** 36 (Impact: 3 x Likelihood: 3 x 4)
- **CWE:** CWE-918 (Server-Side Request Forgery)
- **Summary:** Re-confirmed from initial audit. `FetchCallback` passes untrusted URIs to user-provided callback without scheme/host validation.
- **Reason:** Same as original Finding 9. SSRF prevention is the caller's responsibility. The library validates URI syntax but cannot determine which hosts/schemes are safe for a given application. API documentation warns about SSRF risk.

---

### Re-Audit Security Disposition Summary

| Status | Count | Finding-IDs |
|--------|-------|-------------|
| Closed | 6 | SF-R1 (#34), SF-R2 (#35), SF-R3 (#36), SF-R4 (#37), SF-R5, SF-R6 |
| Won't Do | 2 | SF-R7 (C1 control chars), SF-R8 (SSRF) |

---
