# Profiles

A profile tells the skills everything specific to one repository: rules files, toolchain, build and test
commands, e2e and live environments, CI and its flakes, and what the agent may do without asking. Draft
one with the `project-profile` skill; the format is
[`profile-template.md`](../skills/project-profile/references/profile-template.md).

Profiles are **not committed here**. They usually hold things that do not belong in a public repository:
machine names, private mirrors, internal tooling, accounts, signing identities. `.gitignore` excludes every
file in this directory except this README, and `scripts/validate.sh` fails if one is tracked.

Where to keep yours (the skills look in this order):

1. `$MAINTAINER_PROFILE`, any path.
2. `<repo>/.agents/maintainer-profile.md` or `<repo>/MAINTAINER_PROFILE.md`, when the project's
   maintainers want to share it with every contributor.
3. `${XDG_CONFIG_HOME:-~/.config}/maintainer-skills/profiles/<owner>__<repo>.md`, for a personal one.
   `install.sh` links `profiles/<owner>__<repo>.md` from this directory there, so you can keep personal
   profiles next to your clone (ignored by git) or in a private repository of your own.

`<owner>__<repo>.facts.md` next to a profile holds the raw output of
`skills/project-profile/scripts/detect-project.sh`; regenerate it instead of editing it. The installer
does not link facts files into your profile directory.
