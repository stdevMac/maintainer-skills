#!/usr/bin/env bash
# Owned git worktrees for maintainer tasks: create, list, and remove without losing work.
# Usage:
#   worktree.sh new CLONE NAME [--base REF] [--branch BRANCH] [--min-free-gb N]
#   worktree.sh list
#   worktree.sh remove PATH [--discard-unpushed]
# Root: $MAINTAINER_WORKTREES, default ${MAINTAINER_STATE:-${XDG_STATE_HOME:-~/.local/state}/maintainer-skills}/worktrees
# new     fetches REF (default: origin's default branch), checks free disk (default floor 20 GB), creates
#         ROOT/NAME on BRANCH (default wt/NAME), registers it, prints the path.
# remove  only registered paths under ROOT. Refuses a dirty tree. Refuses commits that no remote has,
#         unless --discard-unpushed, which first saves them as ROOT/backups/NAME-<UTC>.bundle.
set -euo pipefail

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }
state="${MAINTAINER_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/maintainer-skills}"
root="${MAINTAINER_WORKTREES:-$state/worktrees}"
reg="$root/registry.tsv"; lock="$root/.registry.lock"
now() { date -u +%Y%m%dT%H%M%SZ; }
die() { echo "worktree.sh: $1" >&2; exit "${2:-1}"; }

reg_add() { ( flock 9; printf '%s\n' "$1" >> "$reg" ) 9>"$lock"; }
reg_set_state() {  # path state
  ( flock 9; t="$(mktemp "$root/.reg.XXXXXX")"
    awk -F'\t' -v OFS='\t' -v p="$1" -v s="$2" '$2==p {$7=s} {print}' "$reg" > "$t" && mv "$t" "$reg" ) 9>"$lock"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  new)
    clone="${1:?CLONE}"; name="${2:?NAME}"; shift 2
    base=""; branch=""; min_free=20
    while [ $# -gt 0 ]; do
      case "$1" in
        --base) base="${2:?}"; shift ;;
        --branch) branch="${2:?}"; shift ;;
        --min-free-gb) min_free="${2:?}"; shift ;;
        *) die "unknown argument $1" 2 ;;
      esac
      shift
    done
    [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "NAME must match [A-Za-z0-9._-]+" 2
    clone="$(cd "$clone" && git rev-parse --show-toplevel)" || die "not a git checkout: $clone" 2
    mkdir -p "$root"; touch "$reg"
    free="$(df -BG --output=avail "$root" | tail -1 | tr -dc 0-9)"
    [ "$free" -ge "$min_free" ] || die "only ${free} GB free under $root (floor ${min_free} GB); clean up first" 3
    if [ -z "$base" ]; then
      base="$(git -C "$clone" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
      [ -n "$base" ] || { git -C "$clone" remote set-head origin --auto >/dev/null 2>&1 || true
                          base="$(git -C "$clone" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)"; }
    fi
    remote="${base%%/*}"
    if [ "$remote" != "$base" ] && git -C "$clone" remote | grep -qx "$remote"; then
      git -C "$clone" fetch -q "$remote" "${base#*/}"
    fi
    sha="$(git -C "$clone" rev-parse --verify "$base^{commit}")" || die "cannot resolve $base" 2
    branch="${branch:-wt/$name}"
    git -C "$clone" show-ref --verify --quiet "refs/heads/$branch" && die "branch $branch exists; pass --branch" 2
    path="$root/$name"
    [ -e "$path" ] && die "$path exists" 2
    git -C "$clone" worktree add -q -b "$branch" "$path" "$sha"
    reg_add "$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$name" "$path" "$clone" "$branch" "$sha" "$(now)" active)"
    echo "$path"
    echo "branch $branch from $base ($sha), ${free} GB free" >&2
    ;;
  list)
    [ -s "$reg" ] || { echo "no worktrees registered under $root"; exit 0; }
    printf 'NAME\tSTATE\tBRANCH\tCREATED\tSTATUS\tPATH\n'
    while IFS=$'\t' read -r name path _clone branch _sha created st; do
      status="gone"
      if [ -d "$path" ]; then
        if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then status="dirty"
        elif [ "$(git -C "$path" rev-list --count HEAD --not --remotes 2>/dev/null || echo 0)" != 0 ]; then status="unpushed"
        else status="clean"; fi
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$st" "$branch" "$created" "$status" "$path"
    done < "$reg"
    ;;
  remove)
    target="${1:?PATH}"; shift; discard=0
    [ "${1:-}" = "--discard-unpushed" ] && discard=1
    real="$(realpath -m "$target")"
    case "$real" in "$root"/*) ;; *) die "$real is not under $root" 2 ;; esac
    line="$(awk -F'\t' -v p="$real" '$2==p && $7!="removed"' "$reg" 2>/dev/null | tail -1)"
    [ -n "$line" ] || die "$real is not registered (not created by worktree.sh); remove it by hand after checking ownership" 2
    IFS=$'\t' read -r name _ clone branch _ _ _ <<<"$line"
    if [ -d "$real" ]; then
      [ -z "$(git -C "$real" status --porcelain)" ] || die "$real has uncommitted changes; commit or save a patch first" 4
      ahead="$(git -C "$real" rev-list --count HEAD --not --remotes)"
      if [ "$ahead" != 0 ]; then
        [ $discard = 1 ] || die "$real has $ahead commit(s) on no remote; push them or pass --discard-unpushed" 4
        mkdir -p "$root/backups"
        bundle="$root/backups/$name-$(now).bundle"
        git -C "$real" bundle create "$bundle" HEAD --not --remotes >/dev/null 2>&1
        echo "saved unpushed commits to $bundle" >&2
      fi
      git -C "$clone" worktree remove --force "$real"
    fi
    git -C "$clone" worktree prune
    if git -C "$clone" show-ref --verify --quiet "refs/heads/$branch"; then
      git -C "$clone" branch -D "$branch" >/dev/null && echo "deleted local branch $branch" >&2
    fi
    reg_set_state "$real" removed
    echo "removed $real"
    ;;
  -h|--help|"") usage ;;
  *) die "unknown command $cmd" 2 ;;
esac
