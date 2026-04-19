![Logo](logo.png)
<!-- Big money NE - https://patorjk.com/software/taag/#p=testall&f=Bulbhead&t=shebangsy&x=none&v=4&h=4&w=80&we=false> -->

# ArgsBarg

[![GitHub](https://img.shields.io/badge/GitHub-bdombro%2Fswift--argsbarg-181717?logo=github)](https://github.com/bdombro/swift-argsbarg)

[![CI](https://github.com/bdombro/swift-argsbarg/actions/workflows/ci.yml/badge.svg)](https://github.com/bdombro/swift-argsbarg/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[![Swift Package Index platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fbdombro%2Fswift-argsbarg%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/bdombro/swift-argsbarg) [![Swift Package Index Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fbdombro%2Fswift-argsbarg%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/bdombro/swift-argsbarg)

Build beautiful, well-behaved CLI apps in Swift — **no third-party runtime dependencies**, just add the **ArgsBarg** package.

Vs. [Swift ArgumentParser](https://github.com/apple/swift-argument-parser), **ArgsBarg** is *schema-first* -- define your entire CLI’s structure, commands, options, and help in a single, explicit data model, making the command-line interface centralized, clear and self-describing upfront.

## What is it?

Everything you need for a first-class CLI:

- Nested subcommands (`CliCommand` with `children` for groups, `handler` for leaves)
- POSIX-style options (`-x`, `--long`, `--long=value`)
- Bundled presence flags (`-abc`)
- Positional arguments and varargs tails (`CliOption` with `positional: true`)
- Scoped help at any routing depth (`-h` / `--help`)
- Default-command fallback (`CliFallbackMode`)
- Rich help: rounded UTF-8 boxes, tables, terminal width via `TIOCGWINSZ`, colors when stdout/stderr is a TTY

## Platforms and stability

- **Platforms:** macOS (see `Package.swift` `platforms`). The implementation uses POSIX APIs (`ioctl`, `isatty`) matching the C++ library. Linux builds are not declared in the manifest but may work when built with Swift on Linux.
- **Swift:** 5.9+
- **API stability:** pre-1.0 SemVer — minor versions may include breaking changes. See [`CHANGELOG.md`](CHANGELOG.md).

---

## Usage

```swift
import ArgsBarg

cliRun(
    CliCommand(
        name: "helloapp",
        description: "Tiny demo.",
        children: [
            CliCommand(
                name: "hello",
                description: "Say hello.",
                options: [
                    CliOption(
                        name: "name",
                        description: "Who to greet.",
                        kind: .string,
                        shortName: "n"
                    ),
                    CliOption(
                        name: "verbose",
                        description: "Enable extra logging.",
                        shortName: "v"
                    ),
                ],
                handler: { ctx in
                    let name = ctx.stringOpt("name") ?? "world"
                    if ctx.flag("verbose") { print("verbose mode") }
                    print("hello \(name)")
                }
            )
        ],
        fallbackCommand: "hello",
        fallbackMode: .missingOrUnknown
    ))
```

`cliRun` parses `CommandLine.arguments`, prints help or errors, dispatches the leaf handler, and **exits the process** (like the C++ `run()`).

---

## Built-ins

Every app gets:

- `-h` / `--help` at any routing depth (scoped help).
- **`completion bash` / `completion zsh`** — print or install shell completion scripts (injected by `cliRun`).
- **`--generate-completion-script=<bash|zsh>`** — root-level alias: same output as `completion bash` / `completion zsh` (zsh prints to stdout; use `completion zsh` without `--print` to install under `~/.zsh/completions/`).

Do not declare a top-level command named **`completion`** or a root **`CliOption`** named **`generate-completion-script`** — both are reserved for these built-ins.

### Shell completions

```bash
myapp completion bash                             > ~/.bash_completion.d/myapp
# or: source <(myapp completion bash)
myapp completion zsh --print                      # inspect / redirect
myapp completion zsh                              # install under ~/.zsh/completions/
myapp --generate-completion-script=bash           # root alias (= completion bash)
myapp --generate-completion-script=zsh             # root alias (= completion zsh --print)
```

---


## Install (Swift Package Manager)

In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/bdombro/swift-argsbarg.git", from: "0.0.3"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "ArgsBarg", package: "swift-argsbarg"),
        ]
    ),
]
```

---

## How it works

1. Build a **program root** `CliCommand`: `name` is the app/binary name, `children` are top-level subcommands, `options` are global flags. The root must not set `handler` or declare `positionals` (validated at startup). Use `fallbackCommand` / `fallbackMode` on the root only for default top-level routing.
2. Call `cliRun(_:)` with that root — validates, parses argv, renders help or errors, invokes the leaf handler, `exit`s with status **0** on success, **1** on implicit help or error (explicit `--help` → **0**).
3. From a handler, `cliErrWithHelp(ctx, "message")` prints a red error line plus contextual help on stderr and exits **1**.

### Fallback modes (`CliFallbackMode`)

| Mode | Empty argv | Unknown first token |
| --- | --- | --- |
| `missingOnly` | Default command | Error |
| `missingOrUnknown` | Default command | Default command (token becomes argv for the default) |
| `unknownOnly` | Root help (exit 1) | Default command |

With `missingOrUnknown` / `unknownOnly`, unrecognized **root** flags stop root-flag consumption and the remainder is passed to the default command (same as cpp-argsbarg §5.3).

### Positionals (help labels)

Use `CliOption` with `positional: true`. With `argMax == 0`, the tail accepts at least `argMin` tokens and has no upper bound unless you set `argMax` > 0.

| Fields | Label |
| --- | --- |
| `positional: true`, default `argMin`/`argMax` | `<n>` |
| `positional: true`, `argMin: 0`, `argMax: 1` | `[n]` |
| `positional: true`, `argMin: 0`, `argMax: 0` | `[n...]` |
| `positional: true`, `argMin: 1`, `argMax: 0` | `<n...>` |

### Reading values (`CliContext`)

- `ctx.flag("verbose")` — presence options.
- `ctx.stringOpt("name")` / `ctx.numberOpt("count")` — `String?` / `Double?`.
- `ctx.args` — positional words in order.
- `ctx.schema` — merged program root (`CliCommand`) for contextual help.

---

## Examples

Shipped executable targets (see `Package.swift`):

| Target | Directory | Shows |
| --- | --- | --- |
| `ArgsBargMinimal` | `Examples/Minimal/` | String + presence flags, `missingOrUnknown` fallback. |
| `ArgsBargNested` | `Examples/Nested/` | Nested `CliCommand` tree, positional tails, `unknownOnly` fallback. |

```bash
swift run ArgsBargMinimal --help
swift run ArgsBargMinimal --name world
swift run ArgsBargNested stat owner lookup -u alice ./README.md
swift run ArgsBargNested ./README.md
```

---

## Public API overview

| Symbol | Role |
| --- | --- |
| `CliCommand`, `CliOption`, `CliOptionKind`, `CliFallbackMode` | Schema types (`Cli*`-prefixed public types). |
| `CliContext`, `CliHandler` | Handler context and closure type. |
| `cliRun(_:)` | Parse argv, dispatch, exit. |
| `cliErrWithHelp(_:_:)` | Error + scoped help, exit 1. |
| `cliHelpRender(schema:helpPath:useStderr:)` | Render help (`schema` is the program root `CliCommand`). |
| `cliArgsBargVersion` | Semver string. |

Reserved identifiers (validated at startup): root command **`completion`**, root option **`generate-completion-script`**.

Internal parsing (`parse`, `postParseValidate`, `cliValidateRoot`) is `internal`; use `@testable import ArgsBarg` in tests. Nested commands must not set `fallbackCommand` or a non-default `fallbackMode` until per-group fallback is implemented.

---

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Security: [`SECURITY.md`](SECURITY.md). Code of conduct: [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

---

## License

MIT — see [`LICENSE`](LICENSE).
