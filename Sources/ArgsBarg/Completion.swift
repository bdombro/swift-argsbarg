// Shell completion script generation for bash and zsh, aligned with the C++ ArgsBarg emitters.
// Keeps tab-completion behavior consistent with the same CLI schema used at runtime.
// Walks the command tree into scopes, then emits shell functions that simulate argv parsing.

import Foundation

// Generated bash/zsh scripts match cpp-argsbarg (`completion_*_inline.hpp`).
// `collectScopes` order: root scope, then each top-level command subtree (depth-first, declaration order).

// MARK: - Shared (matches cpp-argsbarg detail/completion_shared.hpp)

/// One completion scope: subcommands, options, path key, and whether file completion applies.
private struct ScopeRec {
    var kids: [CliCommand]
    var opts: [CliOption]
    var path: String
    var wantsFiles: Bool
}


/// Returns whether the command expects any positional arguments (for file completion).
private func hasPositionalArguments(_ cmd: CliCommand) -> Bool {
    cmd.positionals.contains { $0.positional }
}


/// Depth-first walk that appends one `ScopeRec` per command node.
private func walkScopes(cmdPath: String, cmd: CliCommand, acc: inout [ScopeRec]) {
    acc.append(
        ScopeRec(
            kids: cmd.children,
            opts: cmd.options,
            path: cmdPath,
            wantsFiles: hasPositionalArguments(cmd)
        ))
    for ch in cmd.children {
        let nextPath = cmdPath.isEmpty ? ch.name : "\(cmdPath)/\(ch.name)"
        walkScopes(cmdPath: nextPath, cmd: ch, acc: &acc)
    }
}


/// Lists all completion scopes: synthetic root plus each subtree in declaration order.
private func collectScopes(schema: CliCommand) -> [ScopeRec] {
    var acc: [ScopeRec] = []
    acc.append(
        ScopeRec(
            kids: schema.children,
            opts: schema.options,
            path: "",
            wantsFiles: hasPositionalArguments(schema)
        ))
    for c in schema.children {
        walkScopes(cmdPath: c.name, cmd: c, acc: &acc)
    }
    return acc
}


/// Sanitizes the binary name into a bash-safe identifier fragment.
private func identToken(_ s: String) -> String {
    var r = ""
    r.reserveCapacity(s.count)
    for ch in s {
        if ch.isASCII && (ch.isLetter || ch.isNumber) {
            r.append(ch)
        } else {
            r.append("_")
        }
    }
    return r
}


/// Escapes a string for use inside single quotes in generated shell scripts.
private func escShellSingleQuoted(_ s: String) -> String {
    var r = ""
    r.reserveCapacity(s.count + 8)
    for ch in s {
        if ch == "'" {
            r += "'\\''"
        } else if ch == "\n" {
            r += " "
        } else {
            r.append(ch)
        }
    }
    return r
}

private let kHelpLong = "--help"
private let kHelpShort = "-h"

/// Bash function name derived from the program name (hyphens become underscores).
private func mainName(from schemaName: String) -> String {
    String(schemaName.map { $0 == "-" ? Character("_") : $0 })
}

// MARK: - Bash (completion_bash_inline.hpp)

/// Emits bash `_nac_consume_long` for long options across scopes.
private func emitConsumeLong(ident: String, scopes: [ScopeRec]) -> String {
    var o = ""
    o += "_\(ident)_nac_consume_long() {\n"
    o += "  local sid=\"$1\" w=\"$2\" nw=\"$3\"\n"
    o += "  case $sid in\n"
    for (i, sc) in scopes.enumerated() {
        o += "    \(i))\n"
        o += "      case $w in\n"
        o += "        \(kHelpLong)|\(kHelpLong)=*|\(kHelpShort)) echo 1 ;;\n"
        for op in sc.opts where !op.positional {
            let base = "--\(op.name)"
            switch op.kind {
            case .presence:
                o += "        \(base)|\(base)=*) echo 1 ;;\n"
            case .string, .number:
                o += "        \(base)=*) echo 1 ;;\n"
                o += "        \(base)) echo 2 ;;\n"
            }
        }
        o += "        *) echo 0 ;;\n"
        o += "      esac\n"
        o += "      ;;\n"
    }
    o += "    *) echo 0 ;;\n"
    o += "  esac\n"
    o += "}\n"
    return o
}


/// Emits bash `_nac_consume_short` for bundled short options.
private func emitConsumeShort(ident: String, scopes: [ScopeRec]) -> String {
    var o = ""
    o += "_\(ident)_nac_consume_short() {\n"
    o += "  local sid=\"$1\" w=\"$2\"\n"
    o += "  case $sid in\n"
    for (i, sc) in scopes.enumerated() {
        o += "    \(i))\n"
        o += "      local rest=${w#-}\n"
        o += "      local ch\n"
        o += "      local saw=0\n"
        o += "      while [[ -n $rest ]]; do\n"
        o += "        ch=${rest:0:1}\n"
        o += "        rest=${rest:1}\n"
        o += "        case $ch in\n"
        var boolChars = ""
        for op in sc.opts where !op.positional {
            guard let sn = op.shortName else { continue }
            if op.kind == .presence {
                boolChars.append(sn)
                boolChars.append("|")
            } else {
                o += "          \(sn))\n"
                o += "            if [[ $saw -ne 0 || -n $rest ]]; then echo 0; return; fi\n"
                o += "            echo 2; return ;;\n"
            }
        }
        if !boolChars.isEmpty {
            boolChars.removeLast()
            o += "          \(boolChars)) ;;\n"
        }
        o += "          *) echo 0; return ;;\n"
        o += "        esac\n"
        o += "        saw=1\n"
        o += "      done\n"
        o += "      echo 1\n"
        o += "      ;;\n"
    }
    o += "    *) echo 0 ;;\n"
    o += "  esac\n"
    o += "}\n"
    return o
}


/// Emits bash to map a token to a child scope id when entering a subcommand.
private func emitMatchChild(
    ident: String, scopes: [ScopeRec], pathIndex: [String: Int]
) -> String {
    var o = ""
    o += "_\(ident)_nac_match_child() {\n"
    o += "  local sid=\"$1\" w=\"$2\"\n"
    o += "  case $sid in\n"
    for (sid, sc) in scopes.enumerated() {
        if sc.kids.isEmpty { continue }
        o += "    \(sid))\n"
        o += "      case $w in\n"
        for ch in sc.kids {
            let childPath =
                sc.path.isEmpty ? ch.name : "\(sc.path)/\(ch.name)"
            let cid = pathIndex[childPath] ?? 0
            o += "        \(ch.name)) echo \(cid); return 0 ;;\n"
        }
        o += "      esac\n"
        o += "      ;;\n"
    }
    o += "  esac\n"
    o += "  return 1\n"
    o += "}\n"
    return o
}


/// Emits bash that replays argv up to the current word and prints the active scope id.
private func emitSimulate(ident: String) -> String {
    var o = ""
    o += "_\(ident)_nac_simulate() {\n"
    o += "  local i=1 sid=0 w steps next\n"
    o += "  while (( i < cword )); do\n"
    o += "    w=${words[i]}\n"
    o += "    if [[ $w == \(kHelpShort) || $w == \(kHelpLong) ]]; then\n"
    o += "      ((i++)); continue\n"
    o += "    fi\n"
    o += "    if [[ $w == --* ]]; then\n"
    o += "      steps=$(_\(ident)_nac_consume_long \"$sid\" \"$w\" \"${words[i+1]}\")\n"
    o += "      case $steps in\n"
    o += "        0) break ;;\n"
    o += "        1) ((i++)) ;;\n"
    o += "        2) ((i+=2)) ;;\n"
    o += "        *) break ;;\n"
    o += "      esac\n"
    o += "      continue\n"
    o += "    fi\n"
    o += "    if [[ $w == -* ]]; then\n"
    o += "      steps=$(_\(ident)_nac_consume_short \"$sid\" \"$w\")\n"
    o += "      case $steps in\n"
    o += "        0) break ;;\n"
    o += "        1) ((i++)) ;;\n"
    o += "        2) ((i++)); break ;;\n"
    o += "        *) break ;;\n"
    o += "      esac\n"
    o += "      continue\n"
    o += "    fi\n"
    o += "    next=$(_\(ident)_nac_match_child \"$sid\" \"$w\") || break\n"
    o += "    sid=$next\n"
    o += "    ((i++))\n"
    o += "  done\n"
    o += "  printf '%s\\n' \"$sid\"\n"
    o += "}\n"
    return o
}


/// Emits the main completion function and `complete -F` registration for bash.
private func emitMainBody(schema: CliCommand, ident: String, scopes: [ScopeRec]) -> String {
    let main = mainName(from: schema.name)
    var o = ""
    o += "_\(main)() {\n"
    o += "  local cur prev words cword split=false\n"
    o += "  _init_completion -s || return\n"
    for (i, sc) in scopes.enumerated() {
        let sortedKids = sc.kids.sorted { $0.name < $1.name }
        o += "  local -a _\(ident)_cmds_\(i)=("
        for (k, kid) in sortedKids.enumerated() {
            if k > 0 { o += " " }
            o += "'\(escShellSingleQuoted(kid.name))'"
        }
        o += ")\n"

        let sortedOpts = sc.opts.filter { !$0.positional }.sorted { $0.name < $1.name }
        o += "  local -a _\(ident)_opts_\(i)=(('\(escShellSingleQuoted(kHelpLong))' '\(escShellSingleQuoted(kHelpShort))'"
        for op in sortedOpts {
            o += " "
            if op.kind == .presence {
                o += "'\(escShellSingleQuoted("--\(op.name)"))'"
            } else {
                o += "'\(escShellSingleQuoted("--\(op.name)="))'"
            }
            if let sn = op.shortName {
                o += " '\(escShellSingleQuoted("-\(sn)"))'"
            }
        }
        o += ")\n"
        o += "  local _\(ident)_leaf_\(i)=\(sc.kids.isEmpty ? "1" : "0")\n"
        o += "  local _\(ident)_pos_\(i)=\(sc.wantsFiles ? "1" : "0")\n"
    }
    o += "  local sid\n"
    o += "  sid=$(_\(ident)_nac_simulate)\n"
    o += "  if [[ $cur == -* ]]; then\n"
    o += "    case $sid in\n"
    for i in scopes.indices {
        o += "      \(i)) COMPREPLY=( $(compgen -W \"${_\(ident)_opts_\(i)[*]}\" -- \"$cur\") ) ;;\n"
    }
    o += "    esac\n"
    o += "  else\n"
    o += "    case $sid in\n"
    for i in scopes.indices {
        o += "      \(i))\n"
        o += "        if [[ ${_\(ident)_leaf_\(i)} -eq 0 ]]; then\n"
        o += "          COMPREPLY=( $(compgen -W \"${_\(ident)_cmds_\(i)[*]}\" -- \"$cur\") )\n"
        o += "        fi\n"
        o += "        if [[ ${_\(ident)_pos_\(i)} -eq 1 ]]; then\n"
        o += "          COMPREPLY+=( $(compgen -f -- \"$cur\") )\n"
        o += "        fi ;;\n"
    }
    o += "    esac\n"
    o += "  fi\n"
    o += "}\n\n"
    o += "complete -F _\(main) \(schema.name)\n"
    return o
}


/// Builds a complete bash completion script for `schema.name`.
func completionBashScript(schema: CliCommand) -> String {
    let ident = identToken(schema.name)
    let scopes = collectScopes(schema: schema)
    var pathIndex: [String: Int] = [:]
    for (i, s) in scopes.enumerated() {
        pathIndex[s.path] = i
    }
    var out = ""
    out += "# Generated bash completion for \(schema.name).\n\n"
    out += emitConsumeLong(ident: ident, scopes: scopes)
    out += emitConsumeShort(ident: ident, scopes: scopes)
    out += emitMatchChild(ident: ident, scopes: scopes, pathIndex: pathIndex)
    out += emitSimulate(ident: ident)
    out += emitMainBody(schema: schema, ident: ident, scopes: scopes)
    return out
}

// MARK: - Zsh (completion_zsh_inline.hpp)

/// zsh `_describe` label for an option, including value placeholders when needed.
private func zshOptionLabel(_ op: CliOption) -> String {
    let base = "--\(op.name)"
    switch op.kind {
    case .presence: return base
    case .number: return "\(base)=<number>"
    case .string: return "\(base)=<string>"
    }
}


/// Emits zsh `typeset` arrays of commands and options per scope.
private func emitScopeArrays(ident: String, scopes: [ScopeRec]) -> String {
    var lines = ""
    for (i, sc) in scopes.enumerated() {
        let sortedKids = sc.kids.sorted { $0.name < $1.name }
        lines += "typeset -g -a A_\(ident)_\(i)_cmds\n"
        lines += "A_\(ident)_\(i)_cmds=("
        for (k, kid) in sortedKids.enumerated() {
            if k > 0 { lines += " " }
            lines +=
                "'\(escShellSingleQuoted(kid.name)):\(escShellSingleQuoted(kid.description))'"
        }
        lines += ")\n"

        let sortedOpts = sc.opts.filter { !$0.positional }.sorted { $0.name < $1.name }
        lines += "typeset -g -a A_\(ident)_\(i)_opts\n"
        lines += "A_\(ident)_\(i)_opts=("
        lines +=
            "'\(escShellSingleQuoted(kHelpLong)):\(escShellSingleQuoted("Show help for this command."))' '\(escShellSingleQuoted(kHelpShort)):\(escShellSingleQuoted("Show help for this command."))'"
        for o in sortedOpts {
            let lab = zshOptionLabel(o)
            lines +=
                " '\(escShellSingleQuoted(lab)):\(escShellSingleQuoted(o.description))'"
            if let sn = o.shortName {
                lines +=
                    " '\(escShellSingleQuoted("-\(sn)")):\(escShellSingleQuoted(o.description))'"
            }
        }
        lines += ")\n"
        lines += "typeset -g A_\(ident)_\(i)_leaf=\(sc.kids.isEmpty ? "1" : "0")\n"
        lines += "typeset -g A_\(ident)_\(i)_pos=\(sc.wantsFiles ? "1" : "0")\n"
    }
    return lines
}


/// zsh variant of long-option consumption helper.
private func emitConsumeLongZsh(ident: String, scopes: [ScopeRec]) -> String {
    var o = ""
    o += "_\(ident)_nac_consume_long() {\n"
    o += "  local sid=\"$1\" w=\"$2\" nw=\"$3\"\n"
    o += "  case $sid in\n"
    for (i, sc) in scopes.enumerated() {
        o += "    \(i))\n"
        o += "      case $w in\n"
        o += "        \(kHelpLong)|\(kHelpLong)=*|\(kHelpShort)) echo 1 ;;\n"
        for op in sc.opts where !op.positional {
            let base = "--\(op.name)"
            switch op.kind {
            case .presence:
                o += "        \(base)|\(base)=*) echo 1 ;;\n"
            case .string, .number:
                o += "        \(base)=*) echo 1 ;;\n"
                o += "        \(base)) echo 2 ;;\n"
            }
        }
        o += "        *) echo 0 ;;\n"
        o += "      esac\n"
        o += "      ;;\n"
    }
    o += "    *) echo 0 ;;\n"
    o += "  esac\n"
    o += "}\n"
    return o
}


/// zsh variant of short-option consumption helper.
private func emitConsumeShortZsh(ident: String, scopes: [ScopeRec]) -> String {
    var o = ""
    o += "_\(ident)_nac_consume_short() {\n"
    o += "  local sid=\"$1\" w=\"$2\"\n"
    o += "  case $sid in\n"
    for (i, sc) in scopes.enumerated() {
        o += "    \(i))\n"
        o += "      local rest=${w#-}\n"
        o += "      local ch\n"
        o += "      local saw=0\n"
        o += "      while [[ -n $rest ]]; do\n"
        o += "        ch=${rest[1,1]}\n"
        o += "        rest=${rest[2,-1]}\n"
        o += "        case $ch in\n"
        var boolChars = ""
        for op in sc.opts where !op.positional {
            guard let sn = op.shortName else { continue }
            if op.kind == .presence {
                boolChars.append(sn)
                boolChars.append("|")
            } else {
                o += "          \(sn))\n"
                o += "            if [[ $saw -ne 0 || -n $rest ]]; then echo 0; return; fi\n"
                o += "            echo 2; return ;;\n"
            }
        }
        if !boolChars.isEmpty {
            boolChars.removeLast()
            o += "          \(boolChars)) ;;\n"
        }
        o += "          *) echo 0; return ;;\n"
        o += "        esac\n"
        o += "        saw=1\n"
        o += "      done\n"
        o += "      echo 1\n"
        o += "      ;;\n"
    }
    o += "    *) echo 0 ;;\n"
    o += "  esac\n"
    o += "}\n"
    return o
}


/// zsh variant of subcommand routing helper.
private func emitMatchChildZsh(
    ident: String, scopes: [ScopeRec], pathIndex: [String: Int]
) -> String {
    var o = ""
    o += "_\(ident)_nac_match_child() {\n"
    o += "  local sid=\"$1\" w=\"$2\"\n"
    o += "  case $sid in\n"
    for (sid, sc) in scopes.enumerated() {
        if sc.kids.isEmpty { continue }
        o += "    \(sid))\n"
        o += "      case $w in\n"
        for ch in sc.kids {
            let childPath =
                sc.path.isEmpty ? ch.name : "\(sc.path)/\(ch.name)"
            let cid = pathIndex[childPath] ?? 0
            o += "        \(ch.name)) echo \(cid); return 0 ;;\n"
        }
        o += "      esac\n"
        o += "      ;;\n"
    }
    o += "  esac\n"
    o += "  return 1\n"
    o += "}\n"
    return o
}


/// zsh variant of argv simulation; stores result in `REPLY_SID`.
private func emitSimulateZsh(ident: String) -> String {
    var o = ""
    o += "_\(ident)_nac_simulate() {\n"
    o += "  local i=2 sid=0 w steps next\n"
    o += "  while (( i < CURRENT )); do\n"
    o += "    w=$words[i]\n"
    o += "    if [[ $w == \(kHelpShort) || $w == \(kHelpLong) ]]; then\n"
    o += "      ((i++)); continue\n"
    o += "    fi\n"
    o += "    if [[ $w == --* ]]; then\n"
    o += "      steps=$(_\(ident)_nac_consume_long \"$sid\" \"$w\" \"${words[i+1]}\")\n"
    o += "      case $steps in\n"
    o += "        0) break ;;\n"
    o += "        1) ((i++)) ;;\n"
    o += "        2) ((i+=2)) ;;\n"
    o += "        *) break ;;\n"
    o += "      esac\n"
    o += "      continue\n"
    o += "    fi\n"
    o += "    if [[ $w == -* ]]; then\n"
    o += "      steps=$(_\(ident)_nac_consume_short \"$sid\" \"$w\")\n"
    o += "      case $steps in\n"
    o += "        0) break ;;\n"
    o += "        1) ((i++)) ;;\n"
    o += "        2) ((i++)); break ;;\n"
    o += "        *) break ;;\n"
    o += "      esac\n"
    o += "      continue\n"
    o += "    fi\n"
    o += "    next=$(_\(ident)_nac_match_child \"$sid\" \"$w\") || break\n"
    o += "    sid=$next\n"
    o += "    ((i++))\n"
    o += "  done\n"
    o += "  REPLY_SID=$sid\n"
    o += "}\n"
    return o
}


/// Emits the zsh completion widget and `compdef` line.
private func emitMainBodyZsh(schema: CliCommand, ident: String) -> String {
    let main = mainName(from: schema.name)
    var o = ""
    o += "_\(main)() {\n"
    o += "  local curcontext=\"$curcontext\" ret=1\n"
    o += "  _\(ident)_nac_simulate\n"
    o += "  local sid=$REPLY_SID\n"
    o += "  if [[ $PREFIX == -* ]]; then\n"
    o += "    local -a optsarr\n"
    o += "    local oname=\"A_\(ident)_${sid}_opts\"\n"
    o += "    optsarr=(${(P@)oname})\n"
    o += "    _describe -t options 'option' optsarr && ret=0\n"
    o += "  else\n"
    o += "    local lname=\"A_\(ident)_${sid}_leaf\"\n"
    o += "    if [[ ${(P)lname} -eq 0 ]]; then\n"
    o += "      local -a cmdsarr\n"
    o += "      local cname=\"A_\(ident)_${sid}_cmds\"\n"
    o += "      cmdsarr=(${(P@)cname})\n"
    o += "      _describe -t commands 'command' cmdsarr && ret=0\n"
    o += "    fi\n"
    o += "    local pname=\"A_\(ident)_${sid}_pos\"\n"
    o += "    if [[ ${(P)pname} -eq 1 ]]; then\n"
    o += "      _files && ret=0\n"
    o += "    fi\n"
    o += "  fi\n"
    o += "  return ret\n"
    o += "}\n\n"
    o += "compdef _\(main) \(schema.name)\n"
    return o
}


/// Builds a complete zsh completion script for `schema.name`.
func completionZshScript(schema: CliCommand) -> String {
    let ident = identToken(schema.name)
    let scopes = collectScopes(schema: schema)
    var pathIndex: [String: Int] = [:]
    for (i, s) in scopes.enumerated() {
        pathIndex[s.path] = i
    }
    var out = ""
    out += "#compdef \(schema.name)\n\n"
    out += emitScopeArrays(ident: ident, scopes: scopes)
    out += emitConsumeLongZsh(ident: ident, scopes: scopes)
    out += emitConsumeShortZsh(ident: ident, scopes: scopes)
    out += emitMatchChildZsh(ident: ident, scopes: scopes, pathIndex: pathIndex)
    out += emitSimulateZsh(ident: ident)
    out += emitMainBodyZsh(schema: schema, ident: ident)
    return out
}
