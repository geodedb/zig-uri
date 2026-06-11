# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do not** open a public issue
2. Email security concerns to: <security@codepros.dev>
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

We will acknowledge receipt within 48 hours and provide a detailed response within 7 days.

## Security Measures

This project implements the following security measures:

### CI/CD Security Scanning

- **SAST**: Static Application Security Testing via GitLab
- **Secret Detection**: Automated scanning for hardcoded secrets
- **License Scanning**: Compliance verification for dependencies
- **Gitleaks**: Enhanced secrets detection

### Code Security

- Memory-safe Zig implementation
- No external C dependencies. Core parsing uses Zig standard library only; optional `thread-pool` dependency (Zig library, pinned to an immutable git commit SHA plus Zig package hash) for parallel batch operations
- Compile-time safety checks enabled
- Fuzz testing for parser inputs via `std.testing.fuzz` (exercised by the CI `fuzz` stage)

### Guidance for Consumers Making Security Decisions

- **Use strict mode (the default) for untrusted input.** Non-strict mode
  (`strict: false`) still rejects C0/DEL control bytes, but performs no other
  structural character validation — backslashes, spaces, and high bytes pass
  into components. Do not use non-strict parsing for SSRF/redirect/host
  allow-list decisions.
- **Bound input length for untrusted sources.** `ParseOptions.max_input_len`
  defaults to `null` (unbounded). The parser is single-pass and allocation-free,
  so cost is proportional to input size, but callers handling attacker-controlled
  input should set `max_input_len` (the resource `Registry` enforces its own
  `max_uri_len`, default 2048).
- **Authorize on parsed components, then normalize.** `normalize()` removes dot
  segments on the syntactic path *before* percent-decoding, so percent-encoded
  dots (`%2E`) are not promoted to directory traversal.
- **Compare hosts only after `normalize()`.** Normalization is RFC 3986-correct:
  it lowercases the host and decodes percent-encoded unreserved octets, so
  `int%65rnal`, `INTERNAL`, and `internal` all converge to the same host. A
  consumer that allow/deny-lists on the *pre-normalization* host string can be
  evaded; always normalize before comparing.

### Release Security

- All releases are tagged and signed
- SPDX license identifiers in all source files
- Apache-2.0 license

## Security Updates

Security updates will be released as patch versions. Subscribe to releases to be notified.
