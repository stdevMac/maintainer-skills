#!/usr/bin/env bash
# Print the facts a maintainer profile needs, from a local checkout (and GitHub with --gh).
# Usage: detect-project.sh [DIR=.] [--gh]
#   --gh   also query GitHub (read-only): default branch, merge methods, branch rules, required checks
# Output is Markdown. Nothing is written or executed from the repository.
set -euo pipefail

usage() { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; }
dir="."; gh_mode=0
for a in "$@"; do
  case "$a" in
    --gh) gh_mode=1 ;;
    -h|--help) usage; exit 0 ;;
    *) dir="$a" ;;
  esac
done
cd "$dir"
top="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$top"

prune=( -name .git -o -name node_modules -o -name target -o -name bin -o -name obj -o -name artifacts
        -o -name dist -o -name build -o -name .venv -o -name venv -o -name vendor -o -name .next )
# find_files MAXDEPTH NAME_PATTERN... : paths relative to the top, build outputs pruned
find_files() {
  local depth="$1"; shift
  local expr=() first=1
  for p in "$@"; do
    [ $first = 1 ] || expr+=( -o ); expr+=( -name "$p" ); first=0
  done
  find . -maxdepth "$depth" \( "${prune[@]}" \) -prune -o -type f \( "${expr[@]}" \) -print 2>/dev/null \
    | sed 's#^\./##' | sort | head -40
}
section() { printf '\n## %s\n\n' "$1"; }
item() { printf -- '- %s\n' "$*"; }

echo "# Project facts: $(basename "$top")"
echo
echo "Generated $(date -u +%FT%TZ) from \`$top\`."

section "Git"
if git rev-parse --git-dir >/dev/null 2>&1; then
  item "HEAD: \`$(git rev-parse --short=12 HEAD 2>/dev/null || echo none)\` on \`$(git branch --show-current 2>/dev/null || echo detached)\`"
  def="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  item "origin default branch (local ref): \`${def:-unknown; run git remote set-head origin --auto}\`"
  git remote -v | awk '$3=="(push)"{print "- remote `"$1"`: "$2}'
  [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = true ] && item "SHALLOW clone: ancestry checks need the GitHub compare API"
  if [ -f .gitmodules ]; then
    git config -f .gitmodules --get-regexp '^submodule\..*\.path$' | while read -r _ p; do
      st="$(git submodule status -- "$p" 2>/dev/null | cut -c1)"
      case "$st" in -) s="not initialized" ;; +) s="checked out at a different commit" ;; *) s="initialized" ;; esac
      item "submodule \`$p\`: $s"
    done
  fi
  item "tracked files: $(git ls-files | wc -l | tr -d ' ')"
  echo
  echo "Top extensions:"
  git ls-files | sed -n 's/.*\.\([A-Za-z0-9]\{1,8\}\)$/\1/p' | sort | uniq -c | sort -rn | head -8 \
    | awk '{print "- ." $2 ": " $1}'
fi

section "Project instructions (read these before acting)"
for f in AGENTS.md CLAUDE.md GEMINI.md CONTRIBUTING.md CONTRIBUTING.rst SECURITY.md README.md \
         .github/copilot-instructions.md .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE.md \
         docs/pull_request_template.md .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS .editorconfig; do
  [ -f "$f" ] && item "\`$f\`"
done
for d in .agents/rules .agents/skills .claude/skills .claude/agents .cursor/rules .github/PULL_REQUEST_TEMPLATE .github/ISSUE_TEMPLATE docs/dev docs/development; do
  [ -d "$d" ] && item "\`$d/\` ($(find "$d" -maxdepth 2 -type f -o -maxdepth 2 -type l | wc -l | tr -d ' ') entries)"
done

section "Stacks and build files"
while IFS='|' read -r label patterns; do
  # shellcheck disable=SC2086
  hits="$(find_files 3 $patterns)"
  [ -n "$hits" ] && item "$label: $(echo "$hits" | head -6 | sed 's/.*/`&`/' | paste -sd' ' -)$( [ "$(echo "$hits" | wc -l)" -gt 6 ] && echo " ...")"
done <<'EOF'
.NET|*.sln *.slnx global.json Directory.Build.props Directory.Packages.props
Node|package.json pnpm-lock.yaml yarn.lock package-lock.json bun.lockb bun.lock deno.json
Rust|Cargo.toml rust-toolchain rust-toolchain.toml
Go|go.mod go.work
Python|pyproject.toml setup.py setup.cfg requirements*.txt tox.ini noxfile.py uv.lock poetry.lock
JVM|pom.xml build.gradle build.gradle.kts settings.gradle*
Ruby|Gemfile
PHP|composer.json
Elixir|mix.exs
C/C++|CMakeLists.txt meson.build configure.ac
Nix|flake.nix default.nix shell.nix
Task runners|Makefile justfile Taskfile.yml Taskfile.yaml magefile.go
Containers|Dockerfile* docker-compose*.yml docker-compose*.yaml compose.yml compose.yaml
Dev envs|devcontainer.json Tiltfile skaffold.yaml kurtosis.yml *.star
Kubernetes|Chart.yaml kustomization.yaml
EOF

if [ -f package.json ] && command -v jq >/dev/null; then
  echo; echo "package.json scripts:"
  jq -r '.scripts // {} | to_entries[] | "- `\(.key)`: `\(.value)`"' package.json | head -30
fi
if [ -f Makefile ]; then
  echo; echo "Makefile targets:"
  grep -E '^[A-Za-z0-9_.-]+:([^=]|$)' Makefile | cut -d: -f1 | grep -v '^\.' | sort -u | head -30 | sed 's/.*/- `&`/'
fi
if [ -f justfile ]; then
  echo; echo "justfile recipes:"
  grep -E '^[A-Za-z0-9_-]+( [^:=]*)?:' justfile | cut -d: -f1 | awk '{print "- `"$1"`"}' | head -30
fi

section "Toolchain pins"
for f in .tool-versions .nvmrc .node-version .python-version .ruby-version .java-version .sdkmanrc \
         rust-toolchain rust-toolchain.toml global.json .go-version; do
  [ -f "$f" ] && item "\`$f\`: $(tr '\n' ' ' < "$f" | tr -s ' ' | cut -c1-160)"
done
[ -f go.mod ] && item "go.mod: $(grep -E '^(go|toolchain) ' go.mod | tr '\n' ' ')"
[ -f package.json ] && command -v jq >/dev/null && item "package.json engines: $(jq -c '.engines // {}' package.json) packageManager: $(jq -r '.packageManager // "unset"' package.json)"

section "Test locations"
find . -maxdepth 4 \( "${prune[@]}" \) -prune -o -type d \
  \( -iname test -o -iname tests -o -iname __tests__ -o -iname spec -o -iname e2e -o -iname '*integration*' \
     -o -iname '*.Test' -o -iname '*.Tests' -o -iname '*IntegrationTests' -o -iname 'testdata' -o -iname fixtures \) -print 2>/dev/null \
  | sed 's#^\./##' | sort | head -40 | sed 's/.*/- `&`/'
n="$(find . \( "${prune[@]}" \) -prune -o -type d \( -name '*.Test' -o -name '*.Tests' \) -print 2>/dev/null | wc -l | tr -d ' ')"
[ "$n" -gt 0 ] && item "test projects named *.Test/*.Tests: $n"

section "CI"
if [ -d .github/workflows ]; then
  for f in .github/workflows/*.y*ml; do
    [ -f "$f" ] || continue
    name="$(grep -m1 -E '^name:' "$f" | sed 's/^name:[[:space:]]*//; s/["'\'']//g')"
    trig="$(grep -oE '^[[:space:]]{0,4}(push|pull_request|pull_request_target|merge_group|workflow_dispatch|workflow_call|workflow_run|schedule|issue_comment|pull_request_review|release|repository_dispatch):' "$f" \
      | tr -d ' :' | sort -u | paste -sd, -)"
    item "\`$(basename "$f")\` ${name:+($name) }triggers: ${trig:-?}"
  done
fi
for f in .gitlab-ci.yml .circleci/config.yml Jenkinsfile .buildkite/pipeline.yml azure-pipelines.yml .travis.yml; do
  [ -f "$f" ] && item "\`$f\`"
done

if [ $gh_mode = 1 ]; then
  section "GitHub (read-only)"
  if ! command -v gh >/dev/null; then
    item "gh not installed"
  else
    slug="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
    if [ -z "$slug" ]; then
      item "gh cannot resolve this repository"
    else
      item "repository: \`$slug\`, account: \`$(gh api user -q .login 2>/dev/null || echo unknown)\`"
      gh api "repos/$slug" --jq '"- default branch: `\(.default_branch)`; fork: \(.fork); visibility: \(.visibility)\n- merge methods: squash=\(.allow_squash_merge) merge=\(.allow_merge_commit) rebase=\(.allow_rebase_merge); delete branch on merge: \(.delete_branch_on_merge); auto-merge allowed: \(.allow_auto_merge)\n- your permissions: \(.permissions // {} | to_entries | map(select(.value)) | map(.key) | join(","))"' 2>/dev/null || item "repo metadata unavailable"
      b="$(gh api "repos/$slug" -q .default_branch 2>/dev/null || echo main)"
      rules="$(gh api "repos/$slug/rules/branches/$b" 2>/dev/null || true)"
      if [ -n "$rules" ] && [ "$rules" != "[]" ]; then
        echo "$rules" | jq -r '.[] | "- rule `\(.type)`" + (if .parameters then ": " + (.parameters | tostring | .[0:300]) else "" end)' 2>/dev/null
      fi
      req="$(gh api "repos/$slug/branches/$b/protection/required_status_checks" --jq '[.checks[].context] | join(", ")' 2>/dev/null || true)"
      [ -n "$req" ] && item "required checks (classic protection): $req"
      [ -z "$req" ] && { [ -z "$rules" ] || [ "$rules" = "[]" ]; } && item "no readable branch protection; check required checks on a recent PR with \`gh pr checks <n> --required\`"
      item "open PRs: $(gh pr list -R "$slug" --state open --limit 500 --json number -q length 2>/dev/null || echo ?), open issues: $(gh issue list -R "$slug" --state open --limit 1000 --json number -q length 2>/dev/null || echo ?)"
      echo; echo "Recent failed runs on \`$b\` (flake candidates):"
      gh run list -R "$slug" --branch "$b" --status failure --limit 15 --json workflowName,createdAt,databaseId \
        --jq '.[] | "- \(.createdAt[0:10]) \(.workflowName) (run \(.databaseId))"' 2>/dev/null || item "unavailable"
    fi
  fi
fi
