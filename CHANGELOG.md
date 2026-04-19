# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Shell completion generation: `completion bash` / `completion zsh` subcommands injected by `cliRun`; `--generate-completion-script=<bash|zsh>` root alias. Root identifiers **`completion`** (child name) and **`generate-completion-script`** (root option) are reserved.
- `cliValidateRoot(_:)` replaces `cliSchemaValidate`; `cliRootMergedWithBuiltins` replaces `cliSchemaMergedWithBuiltins` (test / tooling).

### Changed

- **Breaking:** Removed `CliSchema`. Pass a program-root `CliCommand` to `cliRun(_:)` (`name` = app, `children` = top-level commands, `options` = global flags, `fallbackCommand` / `fallbackMode` on the root only). Former `commands:` becomes `children:` at the root.
- **Breaking:** `parse(root:argv:)`, `postParseValidate(root:pr:)`.
- `CliContext.schema` is now typed as `CliCommand` (merged root after built-ins).

### Removed

- `CliLeaf` and `CliGroup` builder types — use `CliCommand` directly (`children` for routing, `handler` for leaves).
- `CliOpt` and `CliArg` builders — construct `CliOption` values directly.

## [0.1.0] - 2026-04-18

### Added

- Swift library **ArgsBarg** — nested subcommands, POSIX-style options, positional tails, scoped help with UTF-8 box drawing and ANSI styling (parity with **cpp-argsbarg** help output).
- `CliSchema`, `CliCommand`, `CliOption`, `CliContext`, `cliRun(schema:)`, `cliErrWithHelp`, `cliHelpRender`.
- Example executables **ArgsBargMinimal** and **ArgsBargNested** under `Examples/`.
- Unit tests under `Tests/ArgsBargTests/`.
- Documentation: README, this changelog, contributing and security notes.

### Notes

- No `completion` subcommand (unlike the C++ library’s built-ins).

[Unreleased]: https://github.com/bdombro/swift-argsbarg/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/bdombro/swift-argsbarg/releases/tag/v0.1.0
