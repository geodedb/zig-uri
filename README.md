# URI

RFC 3986 compliant URI/URL parsing and manipulation library for Zig.

> **Project Status:** Active Development
> **Current Version:** v0.1.0
> **GitLab:** [devnw/zig/uri](https://gitlab.com/devnw/zig/uri)

## Features

- **RFC Compliant**: Strict adherence to RFC 3986 (URI Generic Syntax) and RFC 8141 (URN)
- **Zero Dependencies**: Uses only Zig standard library
- **Zero-Copy Parsing**: No allocations for basic parsing operations
- **Cross-Platform**: Works on all Zig-supported targets
- **Full Component Access**: Scheme, authority, userinfo, host, port, path, query, fragment
- **URI Resolution**: RFC 3986 Section 5 reference resolution algorithm
- **Normalization**: Case and path normalization per RFC 3986 Section 6
- **Percent-Encoding**: Complete encode/decode support
- **Parse Options**: Strict/allow_spaces/iri_mode validation applied on input
- **Component-Aware Encoding**: Percent-encoding respects URI component rules
- **URN Support**: Full RFC 8141 URN parsing with NID, NSS, and r/q/f-components
- **Resource Registry**: Document storage with fetch callbacks and anchor support

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .uri = .{
        .url = "https://gitlab.com/devnw/zig/uri/-/archive/main/uri-main.tar.gz",
        .hash = "...",
    },
},
```

Then in your `build.zig`:

```zig
const uri_dep = b.dependency("uri", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("uri", uri_dep.module("uri"));
```

## Quick Start

### Parse a URI

```zig
const uri = @import("uri");

pub fn main() !void {
    const parsed = try uri.parse("https://user:pass@example.com:8080/path?query=value#fragment");

    // Access components
    std.debug.print("Scheme: {s}\n", .{parsed.scheme.?});        // "https"
    std.debug.print("Host: {s}\n", .{parsed.host.?});            // "example.com"
    std.debug.print("Port: {d}\n", .{parsed.port.?});            // 8080
    std.debug.print("Path: {s}\n", .{parsed.path});              // "/path"
    std.debug.print("Query: {s}\n", .{parsed.query.?});          // "query=value"
    std.debug.print("Fragment: {s}\n", .{parsed.fragment.?});    // "fragment"
}
```

### Parse a URN

```zig
const parsed = try uri.parse("urn:isbn:0451450523");

std.debug.print("NID: {s}\n", .{parsed.urn.?.nid.?});   // "isbn"
std.debug.print("NSS: {s}\n", .{parsed.urn.?.nss.?});   // "0451450523"
```

### Resolve URI References

```zig
const allocator = std.heap.page_allocator;
const base = try uri.parse("http://example.com/a/b/c");
const reference = try uri.parse("../d");
const resolved = try uri.resolve(allocator, base, reference);
// Result: "http://example.com/a/d"
```

### Percent-Encoding

```zig
// Encode
const encoded = try uri.percentEncode(allocator, "hello world!", .path);
// Result: "hello%20world%21"

// Decode
const decoded = try uri.percentDecode(allocator, "hello%20world%21");
// Result: "hello world!"
```

### Resource Registry

```zig
var reg = uri.Registry.init(allocator);
defer reg.deinit();

try reg.register("https://example.com/schema.json", "{\"type\":\"object\"}", "application/json");
const resource = try reg.get("https://example.com/schema.json", false);
```

## URI Components

```
         foo://user:pass@example.com:8042/over/there?name=ferret#nose
         \_/   \________________________/\_________/ \_________/ \__/
          |              |                    |            |       |
       scheme        authority              path        query   fragment
          |   _________________|________________
         / \ /                                  \
         urn:example:animal:ferret:nose
```

The authority component breaks down into:

```
         userinfo       host          port
         +--+---+ +------+------+ +---+---+
         user:pass@www.example.com:8080
```

## Documentation

- [API Reference](docs/API.md) - Complete API documentation
- [RFC Compliance](docs/RFC_COMPLIANCE.md) - Detailed RFC compliance status

## Roadmap

### [v0.1.0 - Foundation](https://gitlab.com/devnw/zig/uri/-/milestones/1) ✅

Core URI parsing and manipulation functionality.

- [x] RFC 3986 URI parsing ([#1](https://gitlab.com/devnw/zig/uri/-/issues/1))
- [x] URI reference resolution ([#2](https://gitlab.com/devnw/zig/uri/-/issues/2))
- [x] Basic normalization ([#3](https://gitlab.com/devnw/zig/uri/-/issues/3))
- [x] Percent encoding/decoding ([#4](https://gitlab.com/devnw/zig/uri/-/issues/4))
- [x] URN support - RFC 8141 ([#5](https://gitlab.com/devnw/zig/uri/-/issues/5))
- [x] Resource registry ([#6](https://gitlab.com/devnw/zig/uri/-/issues/6))
- [x] Debug utilities ([#7](https://gitlab.com/devnw/zig/uri/-/issues/7))

### [v0.2.0 - Enhanced Parsing](https://gitlab.com/devnw/zig/uri/-/milestones/2)

Improved validation and encoding options.

- [ ] ParseOptions implementation ([#8](https://gitlab.com/devnw/zig/uri/-/issues/8))
- [ ] Component-specific encoding rules ([#9](https://gitlab.com/devnw/zig/uri/-/issues/9))
- [ ] Enhanced percent-encoding normalization ([#10](https://gitlab.com/devnw/zig/uri/-/issues/10))
- [ ] Query string parsing ([#11](https://gitlab.com/devnw/zig/uri/-/issues/11))
- [ ] URI builder API ([#12](https://gitlab.com/devnw/zig/uri/-/issues/12))

### [v0.3.0 - IRI Support](https://gitlab.com/devnw/zig/uri/-/milestones/3)

RFC 3987 Internationalized Resource Identifiers.

- [ ] Unicode support in path/query ([#13](https://gitlab.com/devnw/zig/uri/-/issues/13))
- [ ] IRI ↔ URI conversion ([#14](https://gitlab.com/devnw/zig/uri/-/issues/14))
- [ ] Unicode normalization ([#15](https://gitlab.com/devnw/zig/uri/-/issues/15))

### [v0.4.0 - IPv6 Enhancements](https://gitlab.com/devnw/zig/uri/-/milestones/4)

RFC 6874 IPv6 Zone ID support.

- [ ] Zone ID parsing ([#16](https://gitlab.com/devnw/zig/uri/-/issues/16))
- [ ] IPv6 address validation ([#17](https://gitlab.com/devnw/zig/uri/-/issues/17))
- [ ] IPvFuture support ([#18](https://gitlab.com/devnw/zig/uri/-/issues/18))

### [v1.0.0 - Stable Release](https://gitlab.com/devnw/zig/uri/-/milestones/5)

Production-ready release.

- [ ] WHATWG URL Standard compatibility ([#19](https://gitlab.com/devnw/zig/uri/-/issues/19))
- [ ] Complete documentation ([#20](https://gitlab.com/devnw/zig/uri/-/issues/20))
- [ ] Performance benchmarks ([#21](https://gitlab.com/devnw/zig/uri/-/issues/21))
- [ ] CI/CD pipeline ([#22](https://gitlab.com/devnw/zig/uri/-/issues/22))
- [ ] Zig package registry ([#23](https://gitlab.com/devnw/zig/uri/-/issues/23))
- [ ] Scheme-based normalization ([#24](https://gitlab.com/devnw/zig/uri/-/issues/24))
- [ ] Streaming parser ([#25](https://gitlab.com/devnw/zig/uri/-/issues/25))
- [ ] WebAssembly target ([#26](https://gitlab.com/devnw/zig/uri/-/issues/26))

## RFC Compliance

| RFC | Title | Status | Details |
|-----|-------|--------|---------|
| RFC 3986 | URI Generic Syntax | **Implemented** | [#1](https://gitlab.com/devnw/zig/uri/-/issues/1), [#2](https://gitlab.com/devnw/zig/uri/-/issues/2), [#3](https://gitlab.com/devnw/zig/uri/-/issues/3) |
| RFC 8141 | URN Syntax | **Implemented** | [#5](https://gitlab.com/devnw/zig/uri/-/issues/5) |
| RFC 3987 | IRI Syntax | Planned | [#13](https://gitlab.com/devnw/zig/uri/-/issues/13), [#14](https://gitlab.com/devnw/zig/uri/-/issues/14), [#15](https://gitlab.com/devnw/zig/uri/-/issues/15) |
| RFC 6874 | IPv6 Zone ID | Planned | [#16](https://gitlab.com/devnw/zig/uri/-/issues/16), [#17](https://gitlab.com/devnw/zig/uri/-/issues/17), [#18](https://gitlab.com/devnw/zig/uri/-/issues/18) |
| WHATWG | URL Standard | Partial | [#19](https://gitlab.com/devnw/zig/uri/-/issues/19) |

See [RFC_COMPLIANCE.md](docs/RFC_COMPLIANCE.md) for detailed compliance information.

## Building

```bash
# Build
zig build

# Run tests
zig build test

# Run RFC test vectors
zig build test-vectors

# Run acceptance tests
zig build test-accept

# Run dataset tests (500+ URIs)
zig build test-dataset

# Run all tests
zig build test-all
```

Or use Make:

```bash
make          # Build and test
make test     # Run tests
make dev      # Development workflow (fmt + check + test)
make help     # Show all targets
```

## Development

### With Nix

```bash
nix develop
make dev
```

### Requirements

- Zig 0.15.1 or compatible

## Cross-Platform Support

The library supports all Zig target platforms:

- Linux (x86_64, ARM64, ARM, RISC-V)
- macOS (x86_64, ARM64)
- Windows (x86_64, ARM64)
- FreeBSD, NetBSD, OpenBSD
- And more...

## License

Apache-2.0 License - see [LICENSE](LICENSE) file.

## Contributing

Contributions are welcome! Please see our [open issues](https://gitlab.com/devnw/zig/uri/-/issues) for areas where help is needed.

### Getting Started

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Ensure all tests pass (`zig build test-all`)
5. Submit a merge request

### Guidelines

1. Code follows Zig style guidelines (`zig fmt`)
2. All tests pass
3. New features include tests
4. RFC compliance is maintained
5. Reference relevant issues in your MR

### Priority Areas

- [ParseOptions implementation](https://gitlab.com/devnw/zig/uri/-/issues/8)
- [Component-specific encoding](https://gitlab.com/devnw/zig/uri/-/issues/9)
- [IRI support](https://gitlab.com/devnw/zig/uri/-/issues/13)
- [WHATWG compatibility](https://gitlab.com/devnw/zig/uri/-/issues/19)

## Related RFCs

- [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986) - Uniform Resource Identifier (URI): Generic Syntax
- [RFC 8141](https://www.rfc-editor.org/rfc/rfc8141) - Uniform Resource Names (URNs)
- [RFC 3987](https://www.rfc-editor.org/rfc/rfc3987) - Internationalized Resource Identifiers (IRIs)
- [RFC 6874](https://www.rfc-editor.org/rfc/rfc6874) - Representing IPv6 Zone Identifiers in URIs
- [WHATWG URL Standard](https://url.spec.whatwg.org/) - Living Standard for URLs
