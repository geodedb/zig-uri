# AppSec + Audit Findings Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every confirmed bug, security differential, performance issue, and documentation/CI gap surfaced by the 2026-06-11 `/security:appsec-review` and `/codepros:audit` passes on the `uri` Zig library.

**Architecture:** Pure-Zig RFC 3986/8141 URI library. Fixes are localized to `src/uri.zig` (parser/normalizer), `src/parallel.zig` (batch chunking), `src/registry.zig` (hash lookups), `src/debug.zig` (JSON capacity), `src/lib.zig` (version), `tests/` (a runaway debug print + new regression tests), CI config, and docs. All behavior-changing fixes are TDD: a failing test first, then the minimal fix.

**Tech Stack:** Zig 0.16.0; `zig build test` (inline tests), `zig build test-all` (inline + vectors + accept + dataset), GitLab CI.

**Baseline (verified 2026-06-11):** `zig build` exits 0; `zig build test` exits 0 (213 inline tests); `zig build test-all`/`test-dataset` exit 0 but print a spurious `failed command:` line (Task 2 root cause); direct dataset binary prints "All 57 tests passed".

**Conventions:**

- Run all commands from repo root `/home/benji/src/gl/gitlab.com/devnw/zig/uri`.
- Add new inline tests in the same `.zig` file as the code under test (the project's pattern — see existing `test "..."` blocks at the bottom of `src/uri.zig`).
- Commit after each task. Use Conventional Commits. Append the trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Zig 0.16 custom format: a `Uri` prints via `"{f}"` (e.g. `try std.testing.expectFmt("...", "{f}", .{u})`).

---

## Phase 1 — Correctness bugs (high priority)

### Task 1: Fix parallel batch chunk tail-drop (data corruption on large batches)

**Problem:** `chunk_size = @max(8, inputs.len / MAX_CHUNKS)` uses floor division. For `inputs.len > 512` the 64-chunk loop stops before covering all inputs, leaving the tail of `results` **uninitialized** (undefined memory read for the caller). Affects `parseUris`, `validateUris`, `normalizeUris`.

**Files:**

- Modify: `src/parallel.zig:185` (parseUris), `src/parallel.zig:297` (validateUris), `src/parallel.zig:394` (normalizeUris)
- Test: `src/parallel.zig` (new inline tests at end of file)

- [ ] **Step 1: Write failing tests** — append to the end of `src/parallel.zig`:

```zig
test "parseUris covers all inputs for large batches (no tail-drop)" {
    const allocator = std.testing.allocator;
    const n = 1000;
    const inputs = try allocator.alloc([]const u8, n);
    defer allocator.free(inputs);
    for (inputs) |*p| p.* = "https://example.com/path";
    const results = try allocator.alloc(ParseResult, n);
    defer allocator.free(results);
    // Poison results so an unwritten slot is detectable.
    for (results) |*r| r.* = .{ .components = null, .success = false, .error_msg = "UNWRITTEN" };
    parseUris(inputs, results);
    defer deinitPool();
    for (results, 0..) |r, i| {
        try std.testing.expect(r.success); // every slot must have been written
        if (r.error_msg) |m| {
            try std.testing.expect(!std.mem.eql(u8, m, "UNWRITTEN")); // i.e. never left poisoned
        }
        _ = i;
    }
}

test "validateUris covers all inputs for large batches (no tail-drop)" {
    const allocator = std.testing.allocator;
    const n = 1000;
    const inputs = try allocator.alloc([]const u8, n);
    defer allocator.free(inputs);
    for (inputs) |*p| p.* = "https://example.com/path";
    const results = try allocator.alloc(ValidateResult, n);
    defer allocator.free(results);
    for (results) |*r| r.* = .{ .valid = false, .error_msg = "UNWRITTEN" };
    validateUris(inputs, results);
    defer deinitPool();
    for (results) |r| {
        try std.testing.expect(r.valid);
        if (r.error_msg) |m| try std.testing.expect(!std.mem.eql(u8, m, "UNWRITTEN"));
    }
}

test "normalizeUris covers all inputs for large batches (no tail-drop)" {
    const allocator = std.testing.allocator;
    const n = 1000;
    const inputs = try allocator.alloc([]const u8, n);
    defer allocator.free(inputs);
    for (inputs) |*p| p.* = "https://example.com/a/b/../c";
    const results = try allocator.alloc(NormalizeResult, n);
    defer allocator.free(results);
    for (results) |*r| r.* = .{ .normalized = null, .success = false, .error_msg = "UNWRITTEN" };
    normalizeUris(allocator, inputs, results);
    defer deinitPool();
    for (results) |r| {
        try std.testing.expect(r.success);
        if (r.normalized) |s| allocator.free(s);
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test 2>&1 | tail -20`
Expected: FAIL (some tail slots still `success=false`/poisoned, or panic on undefined).

- [ ] **Step 3: Implement the fix** — change the chunk-size computation at all three sites to round up so 64 chunks always cover every input.

In `parseUris` replace `src/parallel.zig:185`:

```zig
    const chunk_size = @max(8, (inputs.len + MAX_CHUNKS - 1) / MAX_CHUNKS);
```

In `validateUris` replace `src/parallel.zig:297`:

```zig
    const chunk_size = @max(8, (inputs.len + MAX_CHUNKS - 1) / MAX_CHUNKS);
```

In `normalizeUris` replace `src/parallel.zig:394`:

```zig
    const chunk_size = @max(4, (inputs.len + MAX_CHUNKS - 1) / MAX_CHUNKS);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test 2>&1 | tail -20`
Expected: PASS (no failures).

- [ ] **Step 5: Commit**

```bash
git add src/parallel.zig
git commit -m "fix(parallel): cover all inputs in large batches (chunk tail-drop)

chunk_size used floor division; for inputs.len > 512 the 64-chunk loop
stopped before the tail, leaving results[] uninitialized. Round up so
MAX_CHUNKS chunks always span every input.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Stop `Dataset Statistics` test from corrupting the build-runner IPC

**Problem:** `tests/uri_dataset.zig` `test "Dataset Statistics"` makes ~33 `std.debug.print` calls. Under Zig 0.16's `--listen=-` build-runner protocol this corrupts the runner stream and emits a spurious `failed command:` line, so `zig build test-all`/`test-dataset` look like they failed (and could mask a real failure). The test asserts nothing.

**Files:**

- Modify: `tests/uri_dataset.zig:1033` (the `Dataset Statistics` test block)

- [ ] **Step 1: Reproduce the defect**

Run: `zig build test-dataset 2>&1 | tail -3`
Expected: output contains a line beginning `failed command: ./.zig-cache/...`.

- [ ] **Step 2: Read the test block** — Read `tests/uri_dataset.zig` lines 1033–1071 to see the `std.debug.print` statistics dump.

- [ ] **Step 3: Replace the print-only test with real assertions (no stdout writes).** Replace the entire `test "Dataset Statistics"` block with a version that computes the same counts but `expect`s invariants instead of printing them. Example shape (adapt variable names to the existing dataset iteration in that block):

```zig
test "Dataset Statistics" {
    // Compute coverage counts and assert invariants instead of printing,
    // which would corrupt the Zig 0.16 build-runner IPC stream.
    var total: usize = 0;
    var valid: usize = 0;
    for (test_cases) |tc| {
        total += 1;
        if (tc.should_parse) valid += 1;
    }
    try std.testing.expect(total > 0);
    try std.testing.expect(valid <= total);
}
```

If the original block used a different dataset symbol than `test_cases`, use that symbol. Do not emit any `std.debug.print`/`std.io` output from any test.

- [ ] **Step 4: Verify the spurious failure is gone**

Run: `zig build test-dataset 2>&1 | tail -3; echo "EXIT=$?"`
Expected: NO `failed command:` line; ends with the dataset success summary.

Run: `zig build test-all 2>&1 | tail -3`
Expected: NO `failed command:` line.

- [ ] **Step 5: Commit**

```bash
git add tests/uri_dataset.zig
git commit -m "test(dataset): assert stats instead of printing (fixes build-runner IPC corruption)

The Dataset Statistics test flooded stdout via std.debug.print, corrupting
the Zig 0.16 --listen=- protocol and producing a spurious 'failed command'
line in zig build test-all/test-dataset. Replace prints with assertions.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Make `Uri.authority()` correct for owned (resolved/normalized/duped) URIs

**Problem:** `authority()` reconstructs from `self.raw`. `resolve()` sets `raw = ""` and `normalize()` carries the pre-normalization `raw`, so `authority()` returns `null` or stale data for exactly the URIs consumers feed to host allow-lists (appsec F-03, quality N2/N3). Also has an off-by-one (`>` vs `>=`).

**Fix strategy:** (a) add a host-only fast path that returns `self.host` when there is no userinfo and no port — correct regardless of `raw`; (b) make `resolve()` and `normalize()` store an accurate serialized `raw` so the userinfo/port branch is also correct; (c) fix the boundary check to `>=`.

**Files:**

- Modify: `src/uri.zig:165-188` (authority), add `serializeRaw` helper near `dupe`
- Modify: `src/uri.zig:675` (resolve raw), `src/uri.zig:899-929` (normalize end)
- Test: `src/uri.zig` (new inline tests)

- [ ] **Step 1: Write failing tests** — append to the end of `src/uri.zig`:

```zig
test "authority() is correct for resolved URIs" {
    const allocator = std.testing.allocator;
    const base = try parse("https://example.com/a/b");
    const ref = try parse("../c");
    var resolved = try resolve(allocator, base, ref);
    defer resolved.deinit(allocator);
    try std.testing.expect(resolved.authority() != null);
    try std.testing.expectEqualStrings("example.com", resolved.authority().?);
}

test "authority() is correct for normalized URIs" {
    const allocator = std.testing.allocator;
    const u = try parse("HTTP://EXAMPLE.COM:80/x");
    var n = try normalize(allocator, u);
    defer n.deinit(allocator);
    // default http port 80 is stripped; host lowercased
    try std.testing.expectEqualStrings("example.com", n.authority().?);
}

test "authority() includes userinfo and port for resolved URIs" {
    const allocator = std.testing.allocator;
    const base = try parse("https://user@example.com:8443/a/b");
    const ref = try parse("c");
    var resolved = try resolve(allocator, base, ref);
    defer resolved.deinit(allocator);
    try std.testing.expectEqualStrings("user@example.com:8443", resolved.authority().?);
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test 2>&1 | tail -20`
Expected: FAIL (authority returns null/stale).

- [ ] **Step 3a: Add a `serializeRaw` helper.** Insert immediately before `pub fn dupe` (around `src/uri.zig:232`), inside the `Uri` struct:

```zig
    /// Serialize this URI to an owned string using the structured fields.
    /// Used by resolve()/normalize() to keep `raw` accurate for owned URIs.
    fn serializeRaw(self: Uri, allocator: Allocator) Allocator.Error![]u8 {
        var aw = std.Io.Writer.Allocating.init(allocator);
        errdefer aw.deinit();
        self.format(&aw.writer) catch return error.OutOfMemory;
        var al = aw.toArrayList();
        return al.toOwnedSlice(allocator);
    }
```

- [ ] **Step 3b: Rewrite `authority()`** — replace `src/uri.zig:165-188` with:

```zig
    pub fn authority(self: Uri) ?[]const u8 {
        if (self.host == null) return null;

        // Fast path: when there is no userinfo and no port, the authority IS
        // the host. Correct for owned URIs (resolve/normalize/dupe) whose `raw`
        // may be empty or pre-normalization.
        if (self.userinfo == null and self.raw_port == null) return self.host;

        // Otherwise the authority is contiguous in `raw`. resolve()/normalize()
        // keep `raw` accurate by re-serializing; parse() keeps the original.
        const raw = self.raw;
        const scheme_end = if (self.scheme) |s| s.len + 1 else 0; // +1 for ':'
        if (raw.len >= scheme_end + 2 and
            raw[scheme_end] == '/' and
            raw[scheme_end + 1] == '/')
        {
            const auth_start = scheme_end + 2;
            var auth_end = auth_start;
            while (auth_end < raw.len) : (auth_end += 1) {
                const c = raw[auth_end];
                if (c == '/' or c == '?' or c == '#') break;
            }
            return raw[auth_start..auth_end];
        }
        return null;
    }
```

- [ ] **Step 3c: Make `resolve()` store accurate raw** — replace `src/uri.zig:675` (`const owned_raw = try allocator.dupe(u8, "");`) and the `Uri{ ... .raw = owned_raw, ... }` return so the returned URI serializes its own raw. Concretely, change the construction to build `result`, then set `result.raw`:

Replace the `const owned_raw = try allocator.dupe(u8, "");` line with nothing (delete it), and change the `return Uri{ ... };` to:

```zig
    var result = Uri{
        .scheme = owned_scheme,
        .userinfo = owned_userinfo,
        .host = owned_host,
        .port = src_port,
        .path = allocated_path,
        .query = owned_query,
        .fragment = owned_fragment,
        .raw_port = owned_raw_port,
        .raw = "",
        .urn = null,
        .owned = true,
    };
    result.raw = try result.serializeRaw(allocator);
    return result;
```

(Keep the existing field assignments that were already present in the original `return Uri{...}` — match them exactly; only `raw` handling changes. Read `src/uri.zig:677-690` first to preserve the exact field list.)

- [ ] **Step 3d: Make `normalize()` refresh raw** — at the end of `normalize`, just before `return result;` (after the scheme-based normalization block, around `src/uri.zig:927`), insert:

```zig
    // Keep raw consistent with the normalized fields so raw-derived
    // accessors (e.g. authority()) are correct.
    allocator.free(result.raw);
    result.raw = try result.serializeRaw(allocator);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test 2>&1 | tail -20`
Expected: PASS. Then `zig build test-all 2>&1 | tail -5` — no failures, no `failed command:` line.

- [ ] **Step 5: Commit**

```bash
git add src/uri.zig
git commit -m "fix(uri): correct authority() for owned URIs (resolve/normalize/dupe)

authority() read self.raw, which resolve() left empty and normalize() left
stale, so it returned null/wrong data for URIs consumers feed to host
allow-lists. Add a host-only fast path and re-serialize raw in
resolve()/normalize() so the userinfo/port branch is accurate. Fix the
boundary off-by-one (> -> >=).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Reject malformed authority — bracketed-host trailing junk + dead branch

**Problem:** After an IPv6 `]`, `parseAuthority` silently drops trailing bytes (`http://[::1]xyz/p` → host `[::1]`, `xyz` dropped; `http://[::1]x:80` drops the port). Also lines 477–480 are an unreachable dead branch (appsec F-04, quality N4/N5).

**Files:**

- Modify: `src/uri.zig:455-482` (parseAuthority)
- Test: `src/uri.zig` (new inline tests)

- [ ] **Step 1: Write failing tests** — append to end of `src/uri.zig`:

```zig
test "rejects trailing junk after IPv6 bracket" {
    try std.testing.expectError(ParseError.InvalidHost, parse("http://[::1]xyz/p"));
}

test "accepts valid bracketed host with port" {
    const u = try parse("http://[::1]:8080/p");
    try std.testing.expectEqualStrings("[::1]", u.host.?);
    try std.testing.expectEqual(@as(u16, 8080), u.port.?);
}

test "accepts valid bracketed host without port" {
    const u = try parse("http://[::1]/p");
    try std.testing.expectEqualStrings("[::1]", u.host.?);
}
```

- [ ] **Step 2: Run tests to verify the first fails**

Run: `zig build test 2>&1 | tail -20`
Expected: FAIL on "rejects trailing junk after IPv6 bracket" (currently parses successfully).

- [ ] **Step 3: Implement** — replace the IPv6 branch and remove the dead `else if`. Replace `src/uri.zig:455-482` with:

```zig
    if (remaining.len > 0 and remaining[0] == '[') {
        // IPv6 / IPvFuture address
        if (mem.indexOf(u8, remaining, "]")) |bracket_end| {
            result.host = remaining[0 .. bracket_end + 1];
            remaining = remaining[bracket_end + 1 ..];
            // After the closing bracket, only a port (":...") or end-of-authority
            // is valid. Any other trailing bytes are malformed.
            if (remaining.len > 0 and remaining[0] != ':') {
                return ParseError.InvalidHost;
            }
        } else {
            return ParseError.UnclosedIPv6Bracket;
        }
    } else {
        // Regular host (or IPv4). Find the last ':' (port separator).
        var host_end = remaining.len;
        var i: usize = remaining.len;
        while (i > 0) {
            i -= 1;
            if (remaining[i] == ':') {
                host_end = i;
                break;
            }
        }
        if (host_end > 0) {
            result.host = remaining[0..host_end];
        }
        remaining = remaining[host_end..];
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test 2>&1 | tail -20`
Expected: PASS. Then `zig build test-all 2>&1 | tail -5` — no failures.

- [ ] **Step 5: Commit**

```bash
git add src/uri.zig
git commit -m "fix(uri): reject trailing junk after IPv6 bracket; drop dead branch

http://[::1]xyz silently dropped the trailing bytes. Require end-of-authority
or ':' after ']'. Remove the unreachable else-if in the regular-host path.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Phase 2 — Parser RFC hardening

### Task 5: Reject non-DIGIT port strings (`+443`, `8_080`, signs)

**Problem:** Port parsing delegates to `std.fmt.parseInt`, which accepts `+`/`-` signs and `_` digit separators, so `http://h:+443/p` → 443 and `http://h:8_080/p` → 8080. RFC 3986 §3.2.3: `port = *DIGIT` (appsec F-01).

**Files:**

- Modify: `src/uri.zig:485-495` (port parsing in parseAuthority)
- Test: `src/uri.zig`

- [ ] **Step 1: Write failing tests** — append to end of `src/uri.zig`:

```zig
test "rejects port with sign or underscore" {
    try std.testing.expectError(ParseError.InvalidPort, parse("http://h:+443/p"));
    try std.testing.expectError(ParseError.InvalidPort, parse("http://h:8_080/p"));
    try std.testing.expectError(ParseError.InvalidPort, parse("http://h:-1/p"));
}

test "accepts plain digit port" {
    const u = try parse("http://h:8080/p");
    try std.testing.expectEqual(@as(u16, 8080), u.port.?);
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test 2>&1 | tail -20`
Expected: FAIL (signed/underscored ports currently accepted).

- [ ] **Step 3: Implement** — replace `src/uri.zig:485-495` (the `// Parse port` block) with a `*DIGIT` guard before `parseInt`:

```zig
    // Parse port
    if (remaining.len > 0 and remaining[0] == ':') {
        const port_str = remaining[1..];
        if (port_str.len > 0) {
            result.raw_port = port_str;
            // RFC 3986 Section 3.2.3: port = *DIGIT. Reject signs and
            // underscore separators that std.fmt.parseInt would otherwise accept.
            for (port_str) |pc| {
                if (!ascii.isDigit(pc)) return ParseError.InvalidPort;
            }
            const port_num = std.fmt.parseInt(u16, port_str, 10) catch |err| switch (err) {
                error.InvalidCharacter => return ParseError.InvalidPort,
                error.Overflow => return ParseError.PortOutOfRange,
            };
            result.port = port_num;
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test 2>&1 | tail -20`
Expected: PASS. Then `zig build test-all 2>&1 | tail -5` — no failures.

- [ ] **Step 5: Commit**

```bash
git add src/uri.zig
git commit -m "fix(uri): reject non-DIGIT port strings (RFC 3986 3.2.3)

std.fmt.parseInt accepted +443 and 8_080. Validate port is *DIGIT before
conversion so numeric and textual port views can't diverge.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Don't activate percent-encoded dot-segments during normalize

**Problem:** `normalize()` runs `normalizePercentEncoding` (decodes `%2E`→`.`) *before* `removeDotSegments`, so `http://h/a/b/%2e%2e/c` normalizes to `/a/c` — an encoded segment a consumer treated as opaque becomes active traversal (appsec F-02). Fix: remove dot segments on the syntactic (pre-decode) path so only literal `.`/`..` segments collapse; encoded dots decode to literal `.` characters within segment names and are not treated as traversal.

**Files:**

- Modify: `src/uri.zig:876-904` (order of path normalization in `normalize`)
- Test: `src/uri.zig`

- [ ] **Step 1: Write failing tests** — append to end of `src/uri.zig`:

```zig
test "normalize does not activate percent-encoded dot segments" {
    const allocator = std.testing.allocator;
    const u = try parse("http://h/a/b/%2e%2e/c");
    var n = try normalize(allocator, u);
    defer n.deinit(allocator);
    // %2e%2e decodes to a literal ".." segment name, NOT a parent-dir traversal.
    // The /b segment must NOT be popped.
    try std.testing.expect(std.mem.indexOf(u8, n.path, "b") != null);
}

test "normalize still removes literal dot segments" {
    const allocator = std.testing.allocator;
    const u = try parse("http://h/a/b/../c");
    var n = try normalize(allocator, u);
    defer n.deinit(allocator);
    try std.testing.expectEqualStrings("/a/c", n.path);
}
```

- [ ] **Step 2: Run tests to verify the first fails**

Run: `zig build test 2>&1 | tail -20`
Expected: FAIL on "does not activate percent-encoded dot segments" (currently `/b` is popped).

- [ ] **Step 3: Implement** — reorder so `removeDotSegments` runs on `result.path` *before* `normalizePercentEncoding`. In `normalize`, move the dot-segment block (currently `src/uri.zig:899-904`) to run **before** the percent-encoding block (currently `src/uri.zig:878-882`). Resulting order for the path:

```zig
    // Path normalization - remove dot segments on the *syntactic* path first,
    // so percent-encoded "%2E" dots are not promoted to active traversal
    // (RFC 3986 Section 6.2.2.3 operates on path segments, not decoded octets).
    {
        const normalized_path = try removeDotSegments(allocator, result.path);
        allocator.free(result.path);
        result.path = normalized_path;
    }

    // Percent-encoding normalization (Section 6.2.2.2): decode unreserved,
    // uppercase remaining hex. Applied AFTER dot-segment removal.
    {
        const normalized = try normalizePercentEncoding(allocator, result.path);
        allocator.free(result.path);
        result.path = normalized;
    }
```

Keep the query/fragment/userinfo percent-normalization blocks where they are.

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test 2>&1 | tail -20`
Expected: PASS. Then `zig build test-all 2>&1 | tail -5` — no failures (existing normalization vectors still pass).

- [ ] **Step 5: Update RFC compliance doc** — add a short note to `docs/RFC_COMPLIANCE.md` under normalization stating that dot-segment removal operates on the syntactic path before percent-decoding, so `%2E`-encoded dots are not activated as traversal.

- [ ] **Step 6: Commit**

```bash
git add src/uri.zig docs/RFC_COMPLIANCE.md
git commit -m "fix(uri): remove dot segments before percent-decoding in normalize

Decoding %2E->'.' before dot-segment removal let encoded '..' become active
directory traversal (/a/b/%2e%2e/c -> /a/c). Remove dot segments on the
syntactic path first so only literal ./.. collapse.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Normalize percent-encoding in the host (uppercase hex)

**Problem:** `normalize()` lowercases the whole host in place but never percent-normalizes it, so `%2F`→`%2f` (RFC 3986 §6.2.2.2 requires uppercase hex). Two hosts differing only in host percent-encoding case normalize differently (appsec F-05).

**Files:**

- Modify: `src/uri.zig:868-874` (host normalization in `normalize`)
- Test: `src/uri.zig`

- [ ] **Step 1: Write failing test** — append to end of `src/uri.zig`:

```zig
test "normalize uppercases percent-encoding hex in host" {
    const allocator = std.testing.allocator;
    const a = try parse("http://ex%2Fample.com/p");
    var na = try normalize(allocator, a);
    defer na.deinit(allocator);
    const b = try parse("http://ex%2fample.com/p");
    var nb = try normalize(allocator, b);
    defer nb.deinit(allocator);
    try std.testing.expectEqualStrings(na.host.?, nb.host.?);
    try std.testing.expect(std.mem.indexOf(u8, na.host.?, "%2F") != null);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zig build test 2>&1 | tail -20`
Expected: FAIL (host contains lowercased `%2f`).

- [ ] **Step 3: Implement** — replace the host block (`src/uri.zig:868-874`) so it percent-normalizes the host (which uppercases hex and decodes unreserved) and then lowercases only non-percent-encoded bytes. Non-IPv6 hosts only:

```zig
    if (result.host) |h| {
        // Don't touch IPv6 / IPvFuture literals.
        if (h.len > 0 and h[0] != '[') {
            // Percent-normalize first (uppercases remaining hex, decodes unreserved).
            const pn = try normalizePercentEncoding(allocator, h);
            allocator.free(result.host.?);
            result.host = pn;
            // Lowercase only outside percent-encoded triplets.
            const mutable = @constCast(result.host.?);
            var hi: usize = 0;
            while (hi < mutable.len) : (hi += 1) {
                if (mutable[hi] == '%' and hi + 2 < mutable.len) {
                    hi += 2; // skip the two hex digits (already uppercased)
                    continue;
                }
                mutable[hi] = ascii.toLower(mutable[hi]);
            }
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test 2>&1 | tail -20`
Expected: PASS. Then `zig build test-all 2>&1 | tail -5` — no failures.

- [ ] **Step 5: Commit**

```bash
git add src/uri.zig
git commit -m "fix(uri): normalize percent-encoding case in host (RFC 3986 6.2.2.2)

normalize() lowercased the whole host, corrupting %2F->%2f. Percent-normalize
the host (uppercase hex, decode unreserved), then lowercase only non-encoded
bytes.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Phase 3 — Performance

### Task 8: Guard normalize path allocations (dot-segment + percent fast-paths)

**Problem:** `normalize()` always allocates+scans the path twice and percent-normalizes path/query/fragment/userinfo even when there is no `%` and no dot segment (perf N1/N2).

**Files:**

- Modify: `src/uri.zig` `normalize` (Task 6 reordered blocks) and `normalizePercentEncoding` (`src/uri.zig:809`)
- Test: `src/uri.zig`

- [ ] **Step 1: Write a behavior-preserving test** (allocation count is hard to assert portably; assert outputs are unchanged for the fast-path cases). Append to end of `src/uri.zig`:

```zig
test "normalize fast-paths preserve output" {
    const allocator = std.testing.allocator;
    const u = try parse("http://example.com/api/v1/users?q=1#f");
    var n = try normalize(allocator, u);
    defer n.deinit(allocator);
    try std.testing.expectEqualStrings("/api/v1/users", n.path);
    try std.testing.expectEqualStrings("q=1", n.query.?);
    try std.testing.expectEqualStrings("f", n.fragment.?);
}
```

- [ ] **Step 2: Run test (should pass already — it's a guard against regression)**

Run: `zig build test 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 3a: Add a `%` fast-path to `normalizePercentEncoding`** — at the top of the function (`src/uri.zig:809`, right after the doc comment / before building the ArrayList), insert:

```zig
    // Fast path: nothing to normalize without a percent sign.
    if (mem.indexOfScalar(u8, input, '%') == null) {
        return allocator.dupe(u8, input);
    }
```

- [ ] **Step 3b: Guard dot-segment removal in `normalize`** — wrap the `removeDotSegments` block (from Task 6) so it only allocates when needed:

```zig
    if (pathHasDotSegments(result.path)) {
        const normalized_path = try removeDotSegments(allocator, result.path);
        allocator.free(result.path);
        result.path = normalized_path;
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test 2>&1 | tail -10`
Expected: PASS. Then `zig build test-all 2>&1 | tail -5` — no failures.

- [ ] **Step 5: Commit**

```bash
git add src/uri.zig
git commit -m "perf(uri): fast-path normalize (skip percent/dot-segment work when absent)

normalizePercentEncoding now returns a dup when there's no '%'; normalize
only runs removeDotSegments when the path actually has dot segments.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Single hash on registry register/get

**Problem:** `register()` does `contains()` then `put()` (2 hashes); the auto-fetch path then re-`getPtr()` (3rd hash) (perf N4/N5).

**Files:**

- Modify: `src/registry.zig:148-177` (register), `src/registry.zig:185-192` (get auto-fetch)
- Test: `src/registry.zig` (ensure existing tests still pass; add a duplicate-detection test if none exists)

- [ ] **Step 1: Confirm existing behavior with tests**

Run: `zig build test 2>&1 | tail -10`
Expected: PASS (baseline).

- [ ] **Step 2: Implement `getOrPut` in `register`** — replace the duplicate-check + put (`src/registry.zig:149-176`) with:

```zig
        // Single hash: getOrPut detects duplicates and reserves the slot.
        const uri_copy = self.allocator.dupe(u8, uri_str) catch return RegistryError.OutOfMemory;
        errdefer self.allocator.free(uri_copy);

        const gop = self.resources.getOrPut(uri_copy) catch return RegistryError.OutOfMemory;
        if (gop.found_existing) {
            return RegistryError.DuplicateUri;
        }
        errdefer _ = self.resources.remove(uri_copy);

        const content_copy = self.allocator.dupe(u8, content) catch return RegistryError.OutOfMemory;
        errdefer self.allocator.free(content_copy);

        const ct_copy = if (content_type) |ct|
            self.allocator.dupe(u8, ct) catch return RegistryError.OutOfMemory
        else
            null;
        errdefer if (ct_copy) |ct| self.allocator.free(ct);

        gop.key_ptr.* = uri_copy;
        gop.value_ptr.* = Resource{
            .uri = uri_copy,
            .content = content_copy,
            .anchors = std.StringHashMap(Anchor).init(self.allocator),
            .content_type = ct_copy,
            .timestamp = 0,
        };
        self.total_bytes += content.len;
```

(Note: the capacity/byte/uri-len checks above this block at `src/registry.zig:138-147` stay unchanged. Read that block first to keep it intact.)

- [ ] **Step 3: Run tests to verify they pass**

Run: `zig build test 2>&1 | tail -10`
Expected: PASS. Then `zig build test-all 2>&1 | tail -5` — no failures.

- [ ] **Step 4: Commit**

```bash
git add src/registry.zig
git commit -m "perf(registry): single hash on register via getOrPut

Replace contains()+put() (two hashes) with getOrPut (one hash) and keep
duplicate detection. Preserves errdefer cleanup on partial failure.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: Pre-size JSON allocating writer in debug.zig

**Problem:** `toJson`/`toJsonPretty` init `Io.Writer.Allocating` with no capacity hint → growth reallocs (perf N7).

**Files:**

- Modify: `src/debug.zig:158-170` (toJson), `src/debug.zig:175-187` (toJsonPretty)
- Test: `src/debug.zig` (existing JSON tests guard correctness)

- [ ] **Step 1: Confirm baseline**

Run: `zig build test 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 2: Implement capacity hint** — change both functions to use `initCapacity`. For `toJson` (`src/debug.zig:159`) replace `std.Io.Writer.Allocating.init(allocator)` with an estimate based on the URI raw length plus JSON overhead:

```zig
    const hint = uri.raw.len + 256;
    var aw = std.Io.Writer.Allocating.initCapacity(allocator, hint) catch
        std.Io.Writer.Allocating.init(allocator);
```

Apply the same change in `toJsonPretty` (`src/debug.zig:176`).

If `initCapacity` has a different signature in this Zig version, fall back to `var aw = std.Io.Writer.Allocating.init(allocator); aw.ensureUnusedCapacity(hint) catch {};` — verify against `zig build`.

- [ ] **Step 3: Run tests to verify they pass**

Run: `zig build test 2>&1 | tail -10`
Expected: PASS. Then `zig build test-all 2>&1 | tail -5` — no failures.

- [ ] **Step 4: Commit**

```bash
git add src/debug.zig
git commit -m "perf(debug): pre-size JSON allocating writer to cut growth reallocs

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Phase 4 — Docs & consistency

### Task 11: Sync version constant + add drift guard test

**Problem:** `src/lib.zig` `version` = 0.1.0 but `build.zig.zon` = 0.1.4 (appsec/quality N7, GAP-0047).

**Files:**

- Modify: `src/lib.zig:272-276`
- Test: `src/lib.zig` (new inline test that reads build.zig.zon version)

- [ ] **Step 1: Write failing test** — append to end of `src/lib.zig`:

```zig
test "version constant matches build.zig.zon" {
    const zon = @embedFile("../build.zig.zon");
    // Find the .version = "X.Y.Z" string and assert our constant matches.
    const needle = ".version = \"";
    const idx = std.mem.indexOf(u8, zon, needle).?;
    const start = idx + needle.len;
    const end = std.mem.indexOfScalarPos(u8, zon, start, '"').?;
    const ver_str = zon[start..end];
    var buf: [32]u8 = undefined;
    const ours = try std.fmt.bufPrint(&buf, "{d}.{d}.{d}", .{ version.major, version.minor, version.patch });
    try std.testing.expectEqualStrings(ver_str, ours);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zig build test 2>&1 | tail -20`
Expected: FAIL (`0.1.4` != `0.1.0`). If `@embedFile("../build.zig.zon")` fails to resolve, add `build.zig.zon` to the module's allowed embed paths is not needed — `@embedFile` is relative to the source file; `src/lib.zig` → `../build.zig.zon` is correct. If the build disallows embedding outside the module root, instead hardcode the expected `"0.1.4"` string in the test and add a comment to bump both together.

- [ ] **Step 3: Implement** — update `src/lib.zig:272-276`:

```zig
pub const version = std.SemanticVersion{
    .major = 0,
    .minor = 1,
    .patch = 4,
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `zig build test 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/lib.zig
git commit -m "fix(lib): sync version constant to 0.1.4 and guard against drift

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 12: Fix source-adjacent doc-comment API examples in lib.zig

**Problem:** `src/lib.zig` doc comments show non-compiling/incorrect examples: `resolve(base, ref)` missing allocator (N9), `Uri.format(allocator)` which doesn't exist (N10), `percentEncode(allocator, "hello world!")` missing the `component` arg and wrong expected output (N11), WHATWG row marked "Partial" with no implementation (N12).

**Files:**

- Modify: `src/lib.zig` (doc comments only — lines ~48, ~56-57, ~90, ~111; read them first to get exact text)

- [ ] **Step 1: Read** `src/lib.zig:40-115` to capture exact comment text.

- [ ] **Step 2: Edit the four doc comments:**
  - `resolve` example → `const resolved = try uri.resolve(allocator, base, reference); defer resolved.deinit(allocator);`
  - Remove the `Uri.format(allocator)` reference (keep only `Uri.dupe(allocator)`).
  - `percentEncode` example → `uri.percentEncode(allocator, "hello world!", .query)` and fix the expected output comment to `"hello%20world!"`.
  - WHATWG matrix row → status `Planned` (consistent with the header's Planned list).

- [ ] **Step 3: Verify it still builds**

Run: `zig build 2>&1 | tail -5; echo "EXIT=$?"`
Expected: EXIT=0.

- [ ] **Step 4: Commit**

```bash
git add src/lib.zig
git commit -m "docs(lib): correct API examples (resolve/format/percentEncode/WHATWG)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 13: Fix repo docs drift (README, SECURITY.md, build.zig, API.md, CHANGELOG)

**Problem:** README names `spice` dep / version v0.1.0 / Zig 0.15.1 (GAP-0050, F-08, N8); SECURITY.md names `spice` (F-08); build.zig header claims IRI/WHATWG support (GAP-0052); API.md shows outdated `format(writer)` (GAP-0054); CHANGELOG missing 0.1.1–0.1.4 (GAP-0051).

**Files:**

- Modify: `README.md`, `SECURITY.md`, `build.zig:9`, `docs/API.md:76`, `CHANGELOG.md`

- [ ] **Step 1: README** — set "Current Version" to `v0.1.4`; Zig version to `0.16.0`; replace the "optional `spice` dependency" wording with "optional `thread-pool` dependency for parallel batch operations". Grep to confirm: `grep -ni 'spice\|0\.1\.0\|0\.15' README.md`.

- [ ] **Step 2: SECURITY.md** — replace the `spice` dependency description (`SECURITY.md:37`) with `thread-pool` pinned by git commit SHA + Zig package hash. Confirm: `grep -ni spice SECURITY.md` returns nothing.

- [ ] **Step 3: build.zig** — change the header line (`build.zig:9`) to claim only RFC 3986 and RFC 8141 as implemented (mark RFC 3987/WHATWG planned), matching `src/lib.zig` and `build.zig.zon`.

- [ ] **Step 4: API.md** — update the `format` row (`docs/API.md:76`) to the current signature `format(self, writer)` and note `{f}` usage under Zig 0.16.

- [ ] **Step 5: CHANGELOG** — add entries for `0.1.1`, `0.1.2`, `0.1.3`, `0.1.4` (dependency `spice`→`thread-pool` migration, Zig 0.15→0.16, release pins) and update the compare links at the bottom.

- [ ] **Step 6: Verify build unaffected**

Run: `zig build 2>&1 | tail -3; echo "EXIT=$?"`
Expected: EXIT=0.

- [ ] **Step 7: Commit**

```bash
git add README.md SECURITY.md build.zig docs/API.md CHANGELOG.md
git commit -m "docs: fix drift after thread-pool/Zig-0.16 migration (version, dep, RFC claims)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Phase 5 — CI & fuzzing

### Task 14: Add a real fuzz harness and make the fuzz job meaningful

**Problem:** CI runs `zig build test --fuzz` but no `std.testing.fuzz` target exists, so it fuzzes nothing (appsec F-06, GAP-0053).

**Files:**

- Create/modify: a fuzz target in `src/uri.zig` (inline `test` using `std.testing.fuzz`)
- Modify: `SECURITY.md` (drop "(planned)" once real)

- [ ] **Step 1: Add a fuzz test** — append to end of `src/uri.zig`. Use the Zig 0.16 `std.testing.fuzz` signature `fn(context, []const u8) anyerror!void`:

```zig
test "fuzz parse/normalize/resolve does not panic" {
    const Ctx = struct {
        fn run(_: @This(), input: []const u8) anyerror!void {
            // parse must never panic on arbitrary bytes; errors are fine.
            const u = parse(input) catch return;
            // normalize/resolve on a successfully-parsed URI must not panic/leak.
            var n = normalize(std.testing.allocator, u) catch return;
            n.deinit(std.testing.allocator);
        }
    };
    try std.testing.fuzz(Ctx{}, Ctx.run, .{});
}
```

If the local `std.testing.fuzz` signature differs, adapt to the form `zig build` accepts; verify with `zig build test 2>&1 | tail`.

- [ ] **Step 2: Verify it builds and runs in normal test mode**

Run: `zig build test 2>&1 | tail -10`
Expected: PASS (in non-fuzz mode the harness runs the body once with empty/seed input).

- [ ] **Step 3: Verify the fuzz job exercises it**

Run: `timeout 30 zig build test --fuzz 2>&1 | tail -10; echo "EXIT=$?"`
Expected: runs without panicking (timeout/exit 124 is acceptable for a fuzz loop).

- [ ] **Step 4: Update SECURITY.md** — change the "Fuzz testing for parser inputs (planned)" line to reflect that a basic fuzz target exists and runs in CI.

- [ ] **Step 5: Commit**

```bash
git add src/uri.zig SECURITY.md
git commit -m "test(fuzz): add std.testing.fuzz target for parse/normalize

Makes the CI fuzz stage exercise a real harness instead of nothing.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 15: Gate the RFC/acceptance/dataset suites in CI

**Problem:** CI `test` job runs only `zig build test` (inline). The RFC vector, acceptance, and dataset suites are never run in CI, so an RFC-compliance regression ships undetected (GAP-0048). Safe only after Task 2 (no spurious dataset failure).

**Files:**

- Modify: `.gitlab-ci.yml` (the `test` job script)

- [ ] **Step 1: Read** the `test` job in `.gitlab-ci.yml` (around lines 95–137) to capture exact script lines.

- [ ] **Step 2: Change the test command** from `zig build test --summary all` to `zig build test-all --summary all` in the main `test` job. Leave the `test-release-safe/fast/small` jobs as `zig build test` (they exercise inline tests across optimize modes), or upgrade them to `test-all` too if build time allows.

- [ ] **Step 3: Verify locally that `test-all` is a clean gate**

Run: `zig build test-all 2>&1 | tail -5; echo "EXIT=$?"`
Expected: EXIT=0, no `failed command:` line (depends on Task 2 being done).

- [ ] **Step 4: Lint the YAML**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.gitlab-ci.yml'))" && echo "YAML OK"`
Expected: `YAML OK`.

- [ ] **Step 5: Commit**

```bash
git add .gitlab-ci.yml
git commit -m "ci: gate RFC vectors, acceptance, and dataset suites via test-all

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Phase 6 — Final verification & re-review

### Task 16: Full verification gate

- [ ] **Step 1: Format check**

Run: `zig fmt --check src/ tests/ build.zig 2>&1; echo "EXIT=$?"`
Expected: EXIT=0 (no diff). If it fails, run `zig fmt src/ tests/ build.zig` and re-commit the formatting in the relevant task's files.

- [ ] **Step 2: Full test gate**

Run: `zig build test-all 2>&1 | tail -8; echo "EXIT=$?"`
Expected: EXIT=0, no `failed command:` line.

- [ ] **Step 3: Build all optimize modes**

Run: `for m in Debug ReleaseSafe ReleaseFast ReleaseSmall; do zig build -Doptimize=$m 2>&1 | tail -2; echo "$m EXIT=$?"; done`
Expected: all EXIT=0.

- [ ] **Step 4: Examples still build** (if `zig build examples` exists)

Run: `zig build examples 2>&1 | tail -5; echo "EXIT=$?"`
Expected: EXIT=0.

- [ ] **Step 5: Re-run reviews** — re-run `/security:appsec-review` and `/codepros:audit`. Any NEW confirmed finding becomes a new task appended here; loop Phases 1–6 until both come back with no new actionable findings.

---

## Self-Review (coverage check)

| Finding | Task |
|---------|------|
| perf N6 parallel chunk tail-drop | 1 |
| quality N1 / GAP-0049 test-dataset print | 2 |
| appsec F-03 / quality N2,N3 authority() owned | 3 |
| appsec F-04 / quality N4,N5 bracket junk + dead branch | 4 |
| appsec F-01 port *DIGIT | 5 |
| appsec F-02 normalize dot-segment activation | 6 |
| appsec F-05 host percent-encoding case | 7 |
| perf N1,N2 normalize fast-paths | 8 |
| perf N4,N5 registry hashing | 9 |
| perf N7 debug JSON capacity | 10 |
| quality N7 / GAP-0047 version constant | 11 |
| quality N9,N10,N11,N12 lib.zig doc examples | 12 |
| GAP-0050,0051,0052,0054 / F-08 / N8 docs drift | 13 |
| appsec F-06 / GAP-0053 fuzz harness | 14 |
| GAP-0048 CI test-all gate | 15 |
| appsec F-07 (non-strict) / F-09 (max_input_len) | Documented as accepted-by-design in Task 13 SECURITY.md notes |
| Final verification + re-review loop | 16 |
