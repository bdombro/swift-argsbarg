#!/usr/bin/env python3
"""

Publish a new release: bump semver, edit docs, commit, tag, push, and open a GitHub Release.

Workflow:
  1. Resolve ``owner/repo`` via ``gh repo view`` (for changelog links and ``gh release``).
  2. Read the latest **GitHub Release** tag with ``gh release view`` (bare git tags without a
     Release are ignored). If none exists, treat the current version as ``0.0.0``.
  3. Strip a leading ``v`` and any prerelease suffix (``-…``) from that tag, bump
     **major**, **minor**, or **patch** per the CLI argument, and produce ``X.Y.Z``.
  4. Insert ``## [X.Y.Z] - YYYY-MM-DD`` immediately under ``## [Unreleased]`` in
     ``CHANGELOG.md``; refresh the footer compare link for ``[Unreleased]`` and add a
     ``[X.Y.Z]: …/releases/tag/vX.Y.Z`` link after the ``[Unreleased]:`` line.
  5. Update the SPM snippet in ``README.md`` (``.package(..., from: \"X.Y.Z\")``).
  6. ``git add`` / ``git commit`` for ``CHANGELOG.md`` and ``README.md``.
  7. Create annotated tag ``vX.Y.Z`` with message ``ArgsBarg X.Y.Z``, push the current branch
     and that tag to ``origin``.
  8. ``gh release create`` for ``vX.Y.Z`` with title ``ArgsBarg X.Y.Z`` and the new version’s
     changelog body (markdown under ``## [X.Y.Z]``).

Run from the repository root (paths are resolved relative to this script). Typical invocation:
``just release-prep patch`` or ``python3 scripts/release.py patch``.

Requires: ``git``, ``gh`` CLI (https://cli.github.com), authenticated for the repo.
"""
from __future__ import annotations

import datetime as _dt
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
README_PACKAGE_RE = re.compile(
    r'(\.package\(url: "https://github\.com/bdombro/swift-argsbarg\.git", from: ")[^"]+("\),)',
)
UNRELEASED_COMPARE_RE = re.compile(
    r"(\[Unreleased\]: https://github\.com/[^\s]+/compare/)v\d+\.\d+\.\d+(\.{3}HEAD)",
)
UNRELEASED_HEADER = "## [Unreleased]\n"


def _run_git(args: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    """Run ``git`` with ``args`` in ``REPO_ROOT``; capture stdout/stderr and optionally raise on failure."""
    return subprocess.run(
        ["git", *args],
        cwd=REPO_ROOT,
        check=check,
        text=True,
        capture_output=True,
    )


def _run_gh(args: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    """Run ``gh`` with ``args`` in ``REPO_ROOT``; capture stdout/stderr and optionally raise on failure."""
    return subprocess.run(
        ["gh", *args],
        cwd=REPO_ROOT,
        check=check,
        text=True,
        capture_output=True,
    )


def _latest_release_tag() -> str | None:
    """Return the tag name of the latest GitHub Release, or ``None`` if there is no release."""
    r = _run_gh(["release", "view", "--json", "tagName", "--jq", ".tagName"], check=False)
    if r.returncode != 0 or not (r.stdout or "").strip():
        return None
    return (r.stdout or "").strip()


def _repo_slug() -> str:
    """Return ``owner/name`` for the current repo (e.g. ``bdombro/swift-argsbarg``). Exits on failure."""
    r = _run_gh(["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"])
    out = (r.stdout or "").strip()
    if not out:
        sys.stderr.write("release.py: gh repo view returned empty nameWithOwner\n")
        sys.exit(1)
    return out


def _parse_version(tag: str) -> tuple[int, int, int]:
    """Parse a release tag into ``(major, minor, patch)``; supports optional ``v`` prefix and strips ``-prerelease`` tail."""
    s = tag.removeprefix("v").split("-", maxsplit=1)[0].strip()
    parts = (s.split(".") + ["0", "0", "0"])[:3]
    try:
        return int(parts[0]), int(parts[1]), int(parts[2])
    except ValueError as e:
        sys.stderr.write(f"release.py: cannot parse semver from tag {tag!r}: {e}\n")
        sys.exit(1)


def _bump(kind: str, major: int, minor: int, patch: int) -> tuple[int, int, int]:
    """Return the next ``(major, minor, patch)`` tuple after applying a major, minor, or patch bump."""
    if kind == "major":
        return major + 1, 0, 0
    if kind == "minor":
        return major, minor + 1, 0
    if kind == "patch":
        return major, minor, patch + 1
    raise ValueError(kind)


def _update_changelog(new_ver: str, today: str, repo_slug: str) -> None:
    """Edit ``CHANGELOG.md``: new version section under Unreleased, compare link, and release link in the footer."""
    path = REPO_ROOT / "CHANGELOG.md"
    changelog = path.read_text(encoding="utf-8")

    if UNRELEASED_HEADER not in changelog:
        sys.stderr.write("CHANGELOG.md: expected line ## [Unreleased]\n")
        sys.exit(1)

    block = UNRELEASED_HEADER + "\n## [{}] - {}\n".format(new_ver, today)
    changelog = changelog.replace(UNRELEASED_HEADER, block, 1)

    changelog, n = UNRELEASED_COMPARE_RE.subn(
        r"\1v" + new_ver + r"\2",
        changelog,
        count=1,
    )
    if n != 1:
        sys.stderr.write(
            "CHANGELOG.md: could not update [Unreleased] compare link (expected one match)\n"
        )
        sys.exit(1)

    tag_line = "[{}]: https://github.com/{}/releases/tag/v{}\n".format(
        new_ver,
        repo_slug,
        new_ver,
    )
    lines = changelog.splitlines(keepends=True)
    out: list[str] = []
    inserted = False
    for line in lines:
        out.append(line)
        if line.startswith("[Unreleased]:") and not inserted:
            out.append(tag_line)
            inserted = True
    if not inserted:
        sys.stderr.write("CHANGELOG.md: missing [Unreleased]: footer link\n")
        sys.exit(1)

    path.write_text("".join(out), encoding="utf-8")


def _update_readme(new_ver: str) -> None:
    """Edit ``README.md``: set the SPM ``from:`` version in the documented ``.package`` dependency line."""
    path = REPO_ROOT / "README.md"
    readme = path.read_text(encoding="utf-8")

    def repl_from(m: re.Match[str]) -> str:
        """Substitute the captured ``from:`` version with ``new_ver``."""
        return m.group(1) + new_ver + m.group(2)

    readme_new, n = README_PACKAGE_RE.subn(repl_from, readme, count=1)
    if n != 1:
        sys.stderr.write(
            "README.md: could not find SPM .package from: line to update\n",
        )
        sys.exit(1)

    path.write_text(readme_new, encoding="utf-8")


def _changelog_body_for_version(changelog: str, version: str) -> str:
    """Return markdown under ``## [version]`` up to (but not including) the next ``## [`` heading."""
    prefix = f"## [{version}]"
    lines = changelog.splitlines()
    start = None
    for i, line in enumerate(lines):
        if line.startswith(prefix):
            start = i + 1
            break
    if start is None:
        sys.stderr.write(
            f"release.py: CHANGELOG.md: could not find section ## [{version}] for release notes\n",
        )
        sys.exit(1)
    body_lines: list[str] = []
    for line in lines[start:]:
        if line.startswith("## ["):
            break
        body_lines.append(line)
    return "\n".join(body_lines).strip()


def _git_commit_release(version: str) -> None:
    """Stage ``CHANGELOG.md`` / ``README.md`` and create a release commit for ``version``."""
    for p in ("CHANGELOG.md", "README.md"):
        r = _run_git(["add", p])
        if r.returncode != 0:
            sys.stderr.write((r.stderr or r.stdout or "git add failed") + "\n")
            sys.exit(1)
    msg = f"Release {version}"
    r = _run_git(["commit", "-m", msg])
    if r.returncode != 0:
        sys.stderr.write((r.stderr or r.stdout or "git commit failed") + "\n")
        sys.exit(1)


def _git_tag_annotated_push(tag_name: str, version: str) -> None:
    """Create annotated ``tag_name`` with message ``ArgsBarg {version}``, push current HEAD and ``tag_name``."""
    r = _run_git(
        ["tag", "-a", tag_name, "-m", f"ArgsBarg {version}"],
    )
    if r.returncode != 0:
        sys.stderr.write((r.stderr or r.stdout or "git tag failed") + "\n")
        sys.exit(1)
    r = _run_git(["push", "origin", "HEAD", tag_name])
    if r.returncode != 0:
        sys.stderr.write((r.stderr or r.stdout or "git push failed") + "\n")
        sys.exit(1)


def _gh_release_create(tag_name: str, version: str, notes: str) -> None:
    """Create a GitHub Release for ``tag_name`` with title and body from the changelog section."""
    r = _run_gh(
        [
            "release",
            "create",
            tag_name,
            "--title",
            f"ArgsBarg {version}",
            "--notes",
            notes,
        ],
    )
    if r.returncode != 0:
        sys.stderr.write((r.stderr or r.stdout or "gh release create failed") + "\n")
        sys.exit(1)


def main() -> None:
    """CLI entry: bump version, edit files, commit, tag, push, and publish a GitHub Release."""
    if len(sys.argv) != 2 or sys.argv[1] not in ("major", "minor", "patch"):
        sys.stderr.write("usage: release.py <major|minor|patch>\n")
        sys.exit(1)

    if not shutil.which("git"):
        sys.stderr.write("release.py: git not found\n")
        sys.exit(1)

    if not shutil.which("gh"):
        sys.stderr.write("release.py: gh CLI not found (https://cli.github.com)\n")
        sys.exit(1)

    g = _run_git(["rev-parse", "--git-dir"], check=False)
    if g.returncode != 0:
        sys.stderr.write("release.py: not a git repository (run from repo root)\n")
        sys.exit(1)

    kind = sys.argv[1]
    repo_slug = _repo_slug()

    cur = _latest_release_tag()
    if cur is None:
        major, minor, patch = 0, 0, 0
    else:
        major, minor, patch = _parse_version(cur)

    major, minor, patch = _bump(kind, major, minor, patch)
    new_ver = f"{major}.{minor}.{patch}"
    today = _dt.date.today().isoformat()

    _update_changelog(new_ver, today, repo_slug)
    _update_readme(new_ver)

    changelog_text = (REPO_ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    notes = _changelog_body_for_version(changelog_text, new_ver)
    tag_name = f"v{new_ver}"

    _git_commit_release(new_ver)
    _git_tag_annotated_push(tag_name, new_ver)
    _gh_release_create(tag_name, new_ver, notes)

    print(
        f"Published release {new_ver} ({today}): commit, tag {tag_name}, pushed, GitHub Release created.",
    )


if __name__ == "__main__":
    main()
