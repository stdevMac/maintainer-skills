#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CODEX_HOME="$tmp/codex" XDG_CONFIG_HOME="$tmp/config"
mkdir -p "$HOME" "$tmp/repo"
if "$root/install.sh" --check; then echo 'missing install passed check' >&2; exit 1; fi
"$root/install.sh" >/dev/null
"$root/install.sh" --check
printf '%s\n' '# user replacement' > "$CODEX_HOME/agents/fixer.toml"
if "$root/install.sh" --check; then echo 'foreign role passed check' >&2; exit 1; fi
"$root/install.sh" --uninstall >/dev/null
[[ -f "$CODEX_HOME/agents/fixer.toml" && ! -L "$HOME/.agents/skills/fix-issue" ]]

facts="$root/skills/project-profile/scripts/detect-project.sh"
git -C "$tmp/repo" init -q
printf '%s\n' 'go 1.23' > "$tmp/repo/go.mod"
"$facts" "$tmp/repo" > "$tmp/facts.md"
"$facts" --check "$tmp/facts.md" "$tmp/repo"
printf '%s\n' 'go 1.24' > "$tmp/repo/go.mod"
if "$facts" --check "$tmp/facts.md" "$tmp/repo" > "$tmp/diff"; then
  echo 'changed toolchain passed facts check' >&2; exit 1
fi
grep -Fq 'go 1.24' "$tmp/diff"
echo 'Install ownership, uninstall and toolchain drift passed'
