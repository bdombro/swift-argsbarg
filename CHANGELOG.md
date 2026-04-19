# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/bdombro/swift-argsbarg/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/bdombro/swift-argsbarg/releases/tag/v0.1.0
[0.0.3]: https://github.com/bdombro/swift-argsbarg/releases/tag/v0.0.3
[0.0.2]: https://github.com/bdombro/swift-argsbarg/releases/tag/v0.0.2
[0.0.1]: https://github.com/bdombro/swift-argsbarg/releases/tag/v0.0.1