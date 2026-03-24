# Makefile for URI library
#
# RFC 3986 compliant URI/URL parsing and manipulation library for Zig
#
# Usage:
#   make              - Build and run all tests
#   make test         - Run unit tests only
#   make test-vectors - Run RFC 3986 test vectors
#   make clean        - Clean build artifacts
#   make help         - Show this help message

.PHONY: all build test test-unit test-vectors test-all clean check fmt help docs

# Default target - build and run all tests
all: build test-unit test-vectors
	@echo ""
	@echo "All builds and tests completed successfully!"
	@echo ""

# Build the library
build:
	@echo "Building URI library..."
	@zig build

# Run all standard tests
test: test-unit test-vectors
	@echo ""
	@echo "Standard tests completed"

# Run unit tests for all modules
test-unit:
	@echo "Running unit tests..."
	@zig build test --summary all

# Run RFC 3986 test vectors
test-vectors:
	@echo "Running RFC 3986 test vectors..."
	@zig build test-vectors --summary all

# Run all tests including vectors
test-all:
	@echo "Running all tests..."
	@zig build test-all --summary all

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf zig-cache zig-out .zig-cache
	@echo "Clean complete"

# Check syntax without building
check:
	@echo "Checking syntax..."
	@find src tests -name "*.zig" -exec zig ast-check {} \;
	@echo "Syntax check complete"

# Format all Zig source files
fmt:
	@echo "Formatting source files..."
	@zig fmt src/ tests/ build.zig
	@echo "Format complete"

# Check formatting without modifying files
fmt-check:
	@echo "Checking formatting..."
	@zig build fmt
	@echo "Format check complete"

# Generate documentation
docs:
	@echo "Generating documentation..."
	@zig build docs
	@echo "Documentation generated in zig-out/docs/"

# Run tests with optimization levels
test-release-safe:
	@echo "Running tests with ReleaseSafe optimization..."
	@zig build test -Doptimize=ReleaseSafe --summary all

test-release-fast:
	@echo "Running tests with ReleaseFast optimization..."
	@zig build test -Doptimize=ReleaseFast --summary all

test-release-small:
	@echo "Running tests with ReleaseSmall optimization..."
	@zig build test -Doptimize=ReleaseSmall --summary all

# Run all optimization level tests
test-all-optimizations: test-unit test-release-safe test-release-fast test-release-small
	@echo "All optimization level tests completed"

# Continuous integration target
ci: clean build test test-vectors
	@echo ""
	@echo "CI pipeline completed successfully!"

# Development workflow - quick iteration
dev: fmt check test-unit
	@echo "Development checks passed"

# Show help message
help:
	@echo "URI Library - RFC 3986 Compliant Parser for Zig"
	@echo ""
	@echo "Usage:"
	@echo "  make [target]"
	@echo ""
	@echo "Main Targets:"
	@echo "  all              - Build and run all tests (default)"
	@echo "  build            - Build the library"
	@echo "  test             - Run unit tests and RFC vectors"
	@echo "  test-unit        - Run unit tests only"
	@echo "  test-vectors     - Run RFC 3986 test vectors"
	@echo "  test-all         - Run all tests including vectors"
	@echo ""
	@echo "Development Targets:"
	@echo "  clean            - Remove build artifacts"
	@echo "  check            - Check syntax without building"
	@echo "  fmt              - Format all Zig source files"
	@echo "  fmt-check        - Check formatting without modifying"
	@echo "  docs             - Generate documentation"
	@echo "  dev              - Quick development workflow (fmt + check + test-unit)"
	@echo ""
	@echo "Optimization Testing:"
	@echo "  test-release-safe  - Run tests with ReleaseSafe"
	@echo "  test-release-fast  - Run tests with ReleaseFast"
	@echo "  test-release-small - Run tests with ReleaseSmall"
	@echo "  test-all-optimizations - Run tests with all optimization levels"
	@echo ""
	@echo "CI/CD:"
	@echo "  ci               - Full CI pipeline (clean + build + all tests)"
	@echo ""
	@echo "Examples:"
	@echo "  make                    # Run everything"
	@echo "  make test               # Quick test iteration"
	@echo "  make dev                # Development workflow"
	@echo "  make clean build test   # Clean rebuild and test"
	@echo ""
	@echo "Requirements:"
	@echo "  - Zig 0.15.1 or compatible"
	@echo ""
	@echo "RFC Compliance:"
	@echo "  - RFC 3986 (URI Generic Syntax) - Implemented"
	@echo "  - RFC 8141 (URN Syntax) - Implemented"
	@echo "  - RFC 3987 (IRI) - Planned"
	@echo "  - RFC 6874 (IPv6 Zone ID) - Planned"
	@echo "  - WHATWG URL Standard - Planned"
