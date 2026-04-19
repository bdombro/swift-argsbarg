set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# List all recipes (default when you run `just` with no arguments).
_:
    @just --list

# Compile the library and example executables (debug).
build:
    swift build

# Compile everything in release mode (optimized binaries under `.build/release/`).
build-release:
    swift build -c release

# Run unit tests (`ArgsBargTests`). On macOS, XCTest needs the full Xcode app selected (`xcode-select`), not Command Line Tools only.
test:
    swift test

# Build then run tests — quick pre-push check.
ci: build test

# Delete SwiftPM’s `.build` directory (forces a clean rebuild next time).
clean:
    rm -rf .build

# Resolve and fetch package dependencies (updates `Package.resolved` when versions change).
resolve:
    swift package resolve

# Describe the package graph (targets, products, dependencies).
describe:
    swift package describe

# Run the Minimal demo CLI; pass arguments after the recipe name (use `--` before flags if `just` would eat them).
run-minimal *ARGS:
    swift run ArgsBargMinimal {{ARGS}}

# Run the Nested demo CLI; pass arguments after the recipe name (use `--` before flags if `just` would eat them).
run-nested *ARGS:
    swift run ArgsBargNested {{ARGS}}

# Show root help for the Minimal demo (same as `swift run ArgsBargMinimal --help`).
example-minimal-help:
    swift run ArgsBargMinimal --help

# Show leaf help for the Nested demo’s `lookup` command.
example-nested-lookup-help:
    swift run ArgsBargNested stat owner lookup --help

# Print the bash completion script for the Nested example (pipe to a file or source directly).
completion-bash:
    swift run ArgsBargNested completion bash

# Print the zsh completion script for the Nested example (`--print` avoids installing to ~/.zsh/).
completion-zsh:
    swift run ArgsBargNested completion zsh --print
