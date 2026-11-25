#!/usr/bin/env bash
# Check the repository: skill frontmatter, relative links, scripts, and that skills stay generic.
# Usage: scripts/validate.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fail=0
err() { echo "FAIL: $*"; fail=1; }

for d in skills/*/; do
  s="${d%/}"; name="$(basename "$s")"; f="$s/SKILL.md"
  [ -f "$f" ] || { err "$s has no SKILL.md"; continue; }
  [ "$(head -1 "$f")" = "---" ] || err "$f: no frontmatter"
  fm="$(awk 'NR==1{next} /^---$/{exit} {print}' "$f")"
  [ "$(sed -n 's/^name: *//p' <<<"$fm")" = "$name" ] || err "$f: name must be '$name'"
  desc="$(sed -n 's/^description: *//p' <<<"$fm")"
  [ ${#desc} -ge 80 ] || err "$f: description missing or too short"
  [ ${#desc} -le 1024 ] || err "$f: description over 1024 characters"
done

for f in agents/*.md; do
  fm="$(awk 'NR==1{next} /^---$/{exit} {print}' "$f")"
  [ "$(sed -n 's/^name: *//p' <<<"$fm")" = "$(basename "$f" .md)" ] || err "$f: name must match the file name"
  grep -q '^description: ' <<<"$fm" || err "$f: no description"
done

# Relative Markdown links must resolve.
while IFS= read -r f; do
  while IFS= read -r link; do
    target="${link%%#*}"
    [ -z "$target" ] && continue
    case "$target" in http*|mailto:*|/*|'<'*) continue ;; esac
    [ -e "$(dirname "$f")/$target" ] || err "$f: broken link $link"
  done < <(grep -oE '\]\([^)]+\)' "$f" | sed -E 's/^\]\((.*)\)$/\1/')
done < <(find . -name '*.md' -not -path './.git/*')

# Scripts: executable, parse, answer -h.
for s in install.sh scripts/*.sh skills/*/scripts/*.sh; do
  [ -f "$s" ] || continue
  [ -x "$s" ] || err "$s is not executable"
  bash -n "$s" || err "$s does not parse"
  [ "$s" = scripts/validate.sh ] || "./$s" -h >/dev/null 2>&1 || err "$s -h failed"
  if command -v shellcheck >/dev/null; then shellcheck -S warning "$s" || err "$s: shellcheck"; fi
done

# Skills and agents stay generic: no personal paths, accounts or specific repositories.
if grep -rnE '/home/[a-z]|NethermindEth|stdevMac' skills agents; then
  err "project-specific text in skills/ or agents/ (move it to a profile)"
fi

# Profiles stay private: only profiles/README.md may be tracked.
if git rev-parse --git-dir >/dev/null 2>&1; then
  tracked="$(git ls-files profiles | grep -vx 'profiles/README.md' || true)"
  [ -z "$tracked" ] || err "tracked profile files (profiles are private): $tracked"
fi

[ $fail = 0 ] && echo "OK" || exit 1
