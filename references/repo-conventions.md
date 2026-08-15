# Repository Conventions

Read this when the preflight output has any non-null field under `conventions`, `release_tooling`, or `hook_runners`.

- [commitlint](#commitlint)
- [commitizen and cz-git](#commitizen-and-cz-git)
- [gitmoji](#gitmoji)
- [commit.template](#committemplate)
- [Release tooling](#release-tooling)
- [Repos that do not use Conventional Commits](#repos-that-do-not-use-conventional-commits)
- [Monorepo scopes](#monorepo-scopes)

## commitlint

When `conventions.commitlint` is set, the repo's config is authoritative — its `commit-msg` hook decides whether the message is accepted at all. Read the resolved config rather than the config file, since `extends` chains matter:

```bash
npx commitlint --print-config json
```

Take from it:

| Key | Use |
|---|---|
| `rules.type-enum[2]` | The allowed types. Use this list, not the default table. |
| `rules.header-max-length[2]` | Hard subject cap (100 under config-conventional, 72 under config-angular) |
| `rules.scope-enum[2]` | Allowed scopes, when present |
| `rules.subject-case` | Forbidden cases — a `never` rule listing what the subject must not be |
| `parserPreset` | Whether `!` is understood. `conventional-changelog-conventionalcommits` handles it; `angular` does not. |

Then dry-run the candidate before committing:

```bash
printf '%s' "$MESSAGE" | npx commitlint
```

That closes the loop: a rejected message costs one retry here instead of a failed commit mid-batch. If `npx` is unavailable or the command errors, fall back to the config file's visible `rules` block and say the check was skipped.

commitlint ignores several message shapes by default, so no formatting effort is needed for them: merge commits, `Revert`/`Reapply`, `fixup!`/`squash!`/`amend!`, and bare semver subjects.

## commitizen and cz-git

`.czrc` and `.cz.json` hold the whole config at the top level with no wrapper key; `package.json` nests it under `config.commitizen`. `cz.config.js` and a `prompt` block inside a commitlint config are cz-git's homes.

Worth honoring when present: `types` (a custom type list, often with emoji), `scopes`, `maxHeaderLength` / `maxSubjectLength`, `defaultScope`, `issuePrefixes`, `useEmoji`, and `emojiAlign`.

## gitmoji

Default to no emoji. Add one only when the repo already uses them — `conventions.gitmoji` is set, `useEmoji: true` appears in a cz config, or the recent subjects visibly start with emoji.

**Position decides whether the message lints.** A leading emoji (`✨ feat: add x`), which is what the gitmoji specification itself prescribes, does not match `@commitlint/config-conventional`'s header pattern: `^(\w*)` cannot match an emoji, so the type parses as empty and `type-empty` fires, cascading into `type-enum` and `type-case`. Emit a leading emoji only when the repo extends `commitlint-config-gitmoji` or uses gitmoji-cli directly. cz-git's default places it after the colon (`feat: ✨ add x`), which is commitlint-safe.

Take the emoji from the repo's own configured mapping when it has one. There is no single canonical type-to-emoji map — cz-git, commitlint's prompt block, and gitmoji itself all differ.

## commit.template

`git_config.commit_template` points at a file, conventionally `.gitmessage`, that documents the project's expected structure. Read it and follow it.

It does not apply itself: `git commit -m` and `git commit -F` both bypass the template entirely. Since this skill commits with `-F`, honoring the template means reproducing its structure in the generated message.

Also check `git_config.comment_char` (default `#`). Under `-F` the effective cleanup mode keeps comment lines rather than stripping them, but a body line beginning with that character is still a hazard worth avoiding — start such lines with a word instead.

## Release tooling

Which types ship a release differs sharply between tools, and the difference is invisible in the message itself. When one of these is detected, say what the chosen type will do:

| Type | semantic-release | release-please | commit-and-tag-version | nx |
|---|---|---|---|---|
| `feat` | minor | minor | minor | minor |
| `fix` | patch | patch | patch | patch |
| `perf` | patch | patch | patch (hidden) | **none** |
| `docs` `chore` `style` `refactor` `test` `build` `ci` | **no release** | patch (hidden from changelog) | patch (hidden) | none |
| unknown type | no release | patch | patch | none |
| `feat!` / `BREAKING CHANGE:` | major | major | major | major |

The practical consequence: under **semantic-release**, labeling a user-visible fix as `chore` ships nothing. Under **release-please**, the same commit still bumps a patch but stays out of the changelog. These are opposite behaviors, so name the tool when explaining the effect.

**changesets is the exception that changes the whole workflow.** It does not parse commit messages at all — versioning comes entirely from markdown files in `.changeset/`. A perfectly-formed `feat!:` releases nothing. When `release_tooling.changesets` is set, offer to write a changeset alongside the commit:

```md
---
"@scope/package-name": minor
---

Short summary of the user-visible change.
```

Package names **must** be quoted — an unquoted `@scope/name` is invalid YAML. Valid bumps are `major`, `minor`, `patch`, `none`. Derive the package from the changed paths and its `package.json` name, and skip private packages and pure-CI or docs-only commits. Many repositories gate pull requests on `changeset status`, so a missing changeset fails CI.

**git-cliff** (`cliff.toml`) declares the project's real type vocabulary in `commit_parsers`. Read it — it also reveals which prefixes are deliberately skipped from the changelog, and `filter_unconventional` decides whether a non-conforming commit disappears entirely.

**release-please body hazard:** a body line shaped like `type(scope): subject` is promoted into an additional changelog entry. Keep bullets in the body from starting with something that parses as a conventional header.

## Repos that do not use Conventional Commits

Plenty of projects use `[JIRA-123] Foo`, kernel-style `subsys: foo`, gitmoji alone, or plain sentences. Imposing Conventional Commits on them produces a history that does not match its own repository.

Score `history.recent_subjects` against the house patterns. If fewer than roughly 60% of recent subjects are conventional, match what the repository actually does and say which convention was detected. Note that merge commits are already excluded from that sample, which matters — they would otherwise dominate the count and skew the result.

## Monorepo scopes

Where the scope actually routes a release:

- **nx** — the scope must be an exact project name. Several are allowed, comma-separated. An ambiguous scope raises a hard error, and only `feat` and `fix` bump versions.
- **release-please** — routing is by changed file path against the `packages` keys. The scope is decorative; correct paths matter, a correct scope does not save wrong ones.
- **lerna** — attribution is by file path. `feat(package-name):` is a readability convention only. Note that lerna's default preset is angular, so `!` alone is not treated as breaking there either.
- **changesets** — the changeset file decides everything; the scope is irrelevant.

Either way, split batch commits at package boundaries in a monorepo — a commit spanning two packages produces a changelog entry that belongs to neither.
