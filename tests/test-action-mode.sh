#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$root/skills/project-profile/scripts/action-mode.sh"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
unset MAINTAINER_ACTIONS MAINTAINER_PROFILE
export XDG_CONFIG_HOME="$tmp/config"
cd "$tmp"
[[ $("$script" pr_merge --repo example/repo) == 'draft default' ]]
cat >profile.md <<'EOF'
## Actions
| Action | Mode | Notes |
|---|---|---|
| * | off | |
| pr_review | ask | Exact head only |
| pr_merge | auto | |
EOF
[[ $("$script" issue_close --profile profile.md) == 'off profile' ]]
[[ $("$script" pr_review --profile profile.md) == 'ask profile Exact head only' ]]
[[ $(MAINTAINER_ACTIONS='*=draft,pr_review=off' "$script" pr_review --profile profile.md) == 'off env' ]]
[[ $(MAINTAINER_ACTIONS='*=draft,pr_review=off' "$script" pr_merge --profile profile.md) == 'draft env' ]]
if MAINTAINER_ACTIONS='pr_merge=typo' "$script" pr_merge --profile profile.md; then exit 1; fi
printf '## Actions\n| pr_merge | | auto |\n' > malformed.md
if "$script" pr_merge --profile malformed.md; then exit 1; fi
git init -q
git remote add origin https://github.com/example/repo.git
cp profile.md MAINTAINER_PROFILE.md
[[ $("$script" pr_merge) == 'draft default' ]]
if MAINTAINER_ACTIONS='*=auto,pr_reveiw=off' "$script" pr_review; then exit 1; fi
if "$script" pr_merge --profile missing.md; then exit 1; fi
echo 'Action modes: default, profile, precedence and invalid config passed'
