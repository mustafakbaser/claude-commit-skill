# claude-commit-skill

A `/commit` skill for [Claude Code](https://claude.com/claude-code) that writes commits matching **your repository's** convention, and refuses to write ones that would cost you something.

Most commit tools generate a message from the diff. This one starts by asking whether committing is safe at all — then reads the repo's `commitlint` config, its `git log`, and its release tooling before deciding what a correct message even looks like here.

## Install

```bash
npx claude-commit-skill
```

Restart Claude Code, then use `/commit`.

Manual install: copy `SKILL.md`, `references/`, and `scripts/` into `~/.claude/skills/commit/`, and make `scripts/preflight.sh` executable.

## Usage

```
/commit                  analyze and commit
/commit --all            group everything into several logical commits
/commit --dry-run        show the message, commit nothing
/commit --amend          amend the last commit (warns if already pushed)
/commit --push           push after all commits succeed
/commit --signoff        add a DCO Signed-off-by trailer
/commit --lang=tr        force the description language
/commit --yes            skip confirmations (safety gates still apply)
```

It also triggers on plain language — "commit my changes", "değişiklikleri commit et".

## What it refuses to do

These are full stops, not warnings:

- **Commit during a merge or rebase.** Re-staging mid-merge deletes `MERGE_HEAD`, and the resulting commit records one parent — the merge silently vanishes from history while the branch still reads as unmerged. Nothing in `git status` reveals this: once the conflict is resolved and staged, it looks like an ordinary modified file.
- **Stage a credential.** `.env`, private keys, `serviceAccount.json`, and files containing AWS/GitHub/Slack/OpenAI/Stripe key patterns are flagged before anything is staged. A pushed secret is compromised — rewriting history does not un-leak it.
- **Silently discard hand-picked hunks.** If you staged part of a file with `git add -p`, batch mode names the file and asks first. There is no index reflog; that selection is not recoverable.
- **Commit to a detached HEAD** without confirmation, or write a >10 MB blob into history without confirmation.

It warns, but proceeds, on protected branches, junk files, and force-added ignored files.

## What it reads before writing

| Source | Used for |
|---|---|
| `commitlint --print-config json` | Allowed types, header length, scope enum, whether `!` is parsed |
| `.czrc`, `cz.config.js` | Custom type lists, emoji settings, length limits |
| `git log` (300 commits) | House convention, and the repo's real scope vocabulary |
| `.gitmessage` | Project message template |
| `.changeset/`, `release-please-config.json`, `.releaserc`, `cliff.toml`, `nx.json` | Whether the chosen type actually ships a release |

If the repo doesn't use Conventional Commits, the skill matches what the repo actually does instead of imposing a convention on it.

## Things it gets right that are easy to get wrong

**Breaking changes are written twice.** Both `feat!:` and a `BREAKING CHANGE:` footer. Under semantic-release's default preset, `feat!:` alone produces **no release at all** — the header pattern has no `!` in it, so the type parses as null and the commit is dropped. The footer alone is missed by other parsers. Writing both is spec-legal and safe everywhere.

**Release impact is stated.** Under semantic-release a `chore:` ships nothing; under release-please the same commit bumps a patch. The skill names the tool and says which happens.

**changesets repos get a changeset.** There, commit messages don't affect versioning at all — versions come from `.changeset/*.md`. The skill offers to write one.

**Filenames survive.** `git status --porcelain` octal-escapes non-ASCII names, collapses new directories to a single entry, and puts two paths on one line for renames. The bundled `scripts/preflight.sh` parses it with NUL framing and `core.quotepath=false`, so `türkçe-ödeme.txt`, `日本語.txt`, `my dir/file with space.txt`, and renames all come through intact.

**The message can't inject shell.** Commits go through `git commit -F <file>`, never a heredoc. A body line reading `EOF` would otherwise truncate the message and execute the rest as shell — while the commit still succeeded.

**Hook side effects are caught.** Formatters that rewrite files during `pre-commit` leave the committed content unformatted and the tree dirty. `commit-msg` hooks can rewrite the message entirely. Both are detected and verified after the fact with `git log -1 --format=%B`.

## Batch mode

Groups related files into 2–5 commits, shows the full plan, and waits for approval before writing anything. Each group is staged by explicit pathspec — there is no blanket `git reset` between commits.

If a commit fails mid-batch, it stops immediately and reports what landed, what is staged, and what remains, with an offer to unwind.

Grouping is honest about its limits: it has no import-graph analysis, so intermediate commits may not build. That's stated in the plan.

## Structure

```
SKILL.md                            decision tree, safety gates, execution
scripts/preflight.sh                repo state + inventory + screens, as JSON
references/message-format.md        types, subject/body, BREAKING CHANGE, footers
references/repo-conventions.md      config detection, release tooling behavior
references/grouping-algorithm.md    batch grouping
references/recovery.md              hook failures, partial batches, amending
```

`preflight.sh` is plain POSIX-ish bash targeting bash 3.2 (what macOS ships) with no dependencies.

## License

MIT © Mustafa Kürşad Başer
