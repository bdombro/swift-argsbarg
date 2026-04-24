# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-04-24

## [0.3.0] - 2026-04-24

### Added

- `required: Bool` property on `CliOption` to enforce mandatory command-line flags at the parser level.
- `reqStringOpt(_ name: String)` to `CliContext` for convenient, non-optional access to guaranteed required options.
- Visual `(Required)` indicator in the help table for mandatory options.
- `ArgsBargOptionRequired` example showing mandatory option validation.
- Single-command CLI support: `CliCommand` program roots can now set a `handler` and declare `positionals` to execute as a leaf node without requiring subcommands.
- `ArgsBargSingleCommand` example demonstrating the new single-command CLI pattern.

### Changed
- Shell completion scripts (`completion bash` and `completion zsh`) now correctly emit file completion logic for single-command CLI roots, allowing file suggestions alongside the built-in `completion` subcommand.


## [0.2.0] - 2026-04-19

### Changed

- Help **Notes** rendering respects **newlines** in the source string; indented lines are kept as single rows (shell examples). Built-in **`completion bash`** / **`completion zsh`** notes use extra blank lines for readability.
- Built-in help **Notes** for **`completion bash`** / **`completion zsh`**: plainer wording, short intro lines, then concrete shell examples. **`completion zsh`** notes also cover **`eval "$(…)"`**, **`source <(…)`**, and file + **fpath**.

## [0.1.1] - 2026-04-19

### Added

- changed files that weren't in last release

## [0.1.0] - 2026-04-19

### Changed

- Built-in **`completion zsh`** help note shows the real zsh completion filename (from the app `name`, hyphens → `_`).
- **`completion zsh`** always prints the script to stdout; removed auto-install under `~/.zsh/completions` and the **`--print`** flag.
- Remove `--generate-completion-script`; use **`completion bash`** / **`completion zsh`** only.
- - Requested addition to SwiftPackageIndex --> https://github.com/SwiftPackageIndex/PackageList/issues/13227
- Update CI/CD
- Tighten Cursor changelog rule (short agent checklist; `[Unreleased]` + footer-link guard).

## [0.0.3] - 2026-04-19

### Changed

- Update Readme

## [0.0.2] - 2026-04-19

### Added

- Added comments to code for clarity and documentation.


## [0.0.1] - 2026-04-19

Initial release.

[Unreleased]: https://github.com/bdombro/swift-argsbarg/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/bdombro/swift-argsbarg/releases/tag/v0.4.0
[0.3.0]: https://github.com/bdombro/swift-argsbarg/releases/tag/v0.3.0
[0.2.0]: https://github.com/bdombro/swift-argsbarg/releases/tag/v0.2.0
[0.1.1]: https://github.com/bdombro/swift-argsbarg/releases/tag/v0.1.1
[0.1.0]: https://github.com/bdombro/swift-argsbarg/releases/tag/v0.1.0
[0.0.3]: https://github.com/bdombro/swift-argsbarg/releases/tag/v0.0.3
[0.0.2]: https://github.com/bdombro/swift-argsbarg/releases/tag/v0.0.2
[0.0.1]: https://github.com/bdombro/swift-argsbarg/releases/tag/v0.0.1