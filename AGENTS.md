# Working on maintainer-skills

- Skills stay generic. Anything that names a specific repository, language, CI system, machine, person or
  account belongs in a profile under `profiles/`, not in `skills/`. Examples inside skills are fine when
  they are labelled as examples and cover more than one stack.
- One skill per stage of the loop. A skill links to another by name (`the fix-issue skill`) or by a
  relative path inside this repo; never by an absolute path.
- `SKILL.md` is the entry point and stays short enough to read in one pass. Long checklists, templates and
  tables go to `references/`, which the SKILL.md names at the step that needs them.
- Frontmatter: `name` equals the directory name; `description` says what the skill does and when to use
  it, in one paragraph, with the trigger phrases a user would type.
- Scripts: bash with `set -euo pipefail`, `-h` prints usage, no hardcoded owner/repo/user/home paths,
  read-only by default with an explicit flag (`--post`, `--apply`, `--merge`) for any write. A script that
  writes to GitHub must refuse when its gate fails and must say why.
- Every new rule needs the failure that motivated it. Prefer "do X, because Y happened" over "always X".
- Run `scripts/validate.sh` before committing.
