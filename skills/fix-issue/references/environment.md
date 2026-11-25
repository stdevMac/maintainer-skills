# Preparing an environment

The goal: an environment where the agent can do anything, that nobody else depends on, that can be
rebuilt from scratch, and that leaves nothing behind.

## Isolation

- **One worktree per task**, created from a freshly fetched base:
  `scripts/worktree.sh new <clone> <name> --base origin/<default> [--branch fix/<n>-<slug>]`.
  The main clone stays read-only; other agents and the user work there.
- **Never `git stash`** in a worktree. The stash list is shared by every worktree of a clone, so one
  agent can pop another agent's stash. Park work as a local commit or `git diff > <state>/evidence/<n>/wip.patch`.
- **Never discard changes you did not make** (`git checkout -- .`, `git reset --hard`, `git clean -fdx`)
  outside your own worktree.
- **Name everything you start** with a run ID: container names and labels
  (`--label maintainer-run=<run-id>`), compose project names (`-p <run-id>`), temp dirs, cloud resource
  labels. Teardown and leak checks then find exactly your resources and nothing else.
- **Unique ports and paths.** Tests and services that bind fixed ports or write to fixed paths collide
  when two agents run them. Pick free ports, set data dirs under the worktree, and serialize anything
  the profile lists as a singleton.
- **Shared caches are read-mostly.** Package caches (NuGet, npm, cargo, Go modules, pip) are shared
  across worktrees; never clear them. Build servers and compiler daemons can hold locks and memory after
  a build; the profile says how to disable or stop only your own.

## Toolchain and dependencies

1. Read the pins (`global.json`, `.tool-versions`, `rust-toolchain.toml`, `.nvmrc`, `go.mod`, ...).
2. Missing version: install it into a user directory with the vendor's installer, and put it on `PATH`
   for this shell only. Never upgrade a system toolchain.
3. Restore dependencies with the lockfile (`npm ci`, `cargo fetch --locked`, `uv sync --frozen`,
   `dotnet restore`). A lockfile change is a separate, deliberate decision.
4. Submodules and large fixtures: initialize only what the tests you will run need. Note the size.
5. Build once before editing. A failure here is environment, not your change.

## Services and data

- Prefer what the project already uses: its compose file, devcontainer, test fixtures, emulator,
  testcontainers, local devnet scripts. The profile lists which are allowed on the workstation.
- Seed data from the project's fixtures or a generated dataset. Never copy production data or secrets.
- Remote environments (CI dispatch, cloud VMs, staging) follow the profile Policy: some are free to use,
  some need approval, all need a recorded run ID and a verified teardown.

## Resources

- Check free disk before creating a worktree and before each build; builds of large projects take tens
  of GB. Stop at the profile's floor.
- **Disk-full and out-of-memory failures look like code bugs**: a crash with no output, "N errors" with
  no diagnostics, truncated logs, a killed test host. Check `df` and `dmesg` before debugging code.
- Serialize heavy builds and test runs with the lock the profile names (`flock <lock> <cmd>`).
- Long jobs run in the background with output to a log under `<state>/evidence/<n>/`; check the log,
  do not rerun to see output.

## Teardown checklist

- [ ] Every process, container, compose project, VM and cloud resource with your run ID is gone
      (list by label, do not trust the stop command's exit code).
- [ ] For remote environments: the destroy run succeeded and a fresh inventory query by label returns
      nothing.
- [ ] Worktree removed only after the branch is pushed or its work saved as a patch:
      `scripts/worktree.sh remove <path>`. The script refuses dirty or unpushed trees.
- [ ] Evidence logs kept. Temporary probes deleted (their output is already saved).
