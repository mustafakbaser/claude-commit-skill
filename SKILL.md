---
name: commit
description: Creates safe, convention-accurate git commits. Reads the repository's own convention (commitlint, commitizen, gitmoji, or the style of its git history) instead of imposing one, screens for secrets and repository states where re-staging destroys work, and writes Conventional Commits messages with correct BREAKING CHANGE and issue footers. Offers a single commit or a batch mode that splits unrelated work into several logical commits, previewed and approved before anything is written. Use this skill whenever the user wants to commit, stage, or record changes in git — "/commit", "/commit --all", "commit my changes", "commit this", "git commit", "değişiklikleri commit et", "commit at" — and whenever the user asks for a commit message, even when they never use the word "commit".
license: MIT
argument-hint: "[--all] [--amend] [--dry-run] [--push] [--signoff] [--lang=xx] [--yes]"
allowed-tools: Bash(git:*) Bash(${CLAUDE_SKILL_DIR}/scripts/preflight.sh) Bash(npx commitlint:*) Read Write
metadata:
  version: "2.0.0"
---

# Intelligent Commit

Commits are append-only and, once pushed, effectively permanent. The costly mistakes are not badly-worded messages — they are commits that contain content the author never reviewed, credentials that are now compromised, and merges silently converted into ordinary commits. Guard against those first; write a good message second.

## Step 1: Preflight

Run the bundled script. It returns one JSON object with repository state, a correctly-parsed file inventory, line counts, safety screens, and the repo's detected conventions:

```bash
"${CLAUDE_SKILL_DIR}/scripts/preflight.sh"
```

Read its output rather than re-deriving any of it by hand. It exists because `git status --porcelain` is not a list of paths: `core.quotepath` octal-escapes non-ASCII names, untracked directories collapse to a single entry that hides every file inside, and a rename is one line carrying two paths. Parsing that in prose gets it wrong.

If it exits non-zero, the directory is not a git repository — say so and stop.

## Step 2: Safety gates

Evaluate in order. Each is a full stop, not a warning to pass along with the work already done.

**Operation in progress** (`in_progress.any`) — refuse batch mode outright. A mixed `git reset` deletes `MERGE_HEAD`, and the commit that follows records one parent: the merge disappears from history while the branch still reads as unmerged, and the next merge re-conflicts. The same reset mid-rebase strands the rebase's own commits on a detached HEAD. Nothing in the file list reveals this — once the conflict is resolved and staged, status reads `M  file` like any ordinary change. Offer only a plain `git commit` that preserves the operation, and let git supply its default message.

**Conflicts unresolved** (`counts.conflicted > 0`) — stop. Resolve first.

**Detached HEAD** (`head.detached`) — stop unless the user confirms. Commits here are unreachable from any branch and are lost at the next checkout.

**Secrets** (`screens.secrets`) — stop and list them. Never stage a flagged path without an explicit instruction naming that file. A pushed credential is compromised regardless of what happens next: rewriting history does not un-leak it, because forks, clones, CI caches, and cached views keep serving the blob. The remedy order is rotate the credential first, rewrite history second. Offer to add the path to `.gitignore` instead.

**Large files** (`screens.large_files`) — stop and confirm. Git history is append-only, so the blob is in every future clone forever, and hosts reject oversized files at push time, once the commits already exist.

**Protected branch** (`head.protected`) — say which branch and offer to create a feature branch first. Proceed if the user wants it; this is a warning, not a veto.

**Junk and force-added files** (`screens.junk`, `screens.force_added_ignored`) — mention them. Junk (`.DS_Store`, `node_modules/`, build output) usually belongs in `.gitignore`. Force-added ignored files were staged deliberately, so preserve them: they are the files a blanket re-stage would silently drop.

## Step 3: Decide mode

| State | Mode |
|---|---|
| `--all` passed | Batch |
| `--amend` passed | Amend (see below) |
| Only staged changes | Single |
| Only unstaged or untracked | Batch |
| Both staged and unstaged | Ask |

When both exist, ask with AskUserQuestion: commit only what is staged, or everything grouped into logical commits.

**Before offering "everything", check `partially_staged`.** A non-empty list means hunks were hand-picked with `git add -p`. There is no index reflog, so that selection cannot be recovered — name the affected files and confirm before touching the index. Never resolve this by re-staging whole files: that commits the hunks the author deliberately withheld, under a message describing something else.

Non-interactive sessions have no one to ask: default to staged-only, and to English, and say which defaults were used.

## Step 4: Resolve the convention

The repository's own tooling outranks any default here — its `commit-msg` hook is what actually accepts or rejects the message. Read `references/repo-conventions.md` when `conventions` or `release_tooling` in the preflight output has any non-null field. It covers reading commitlint's resolved config, non-Conventional-Commits repositories, and which types do and do not trigger a release under each release tool.

With no configuration present, infer from `history.recent_subjects`: if most subjects match `^type(scope)?!?: `, use Conventional Commits; otherwise match the house style rather than imposing one. Draw scope candidates from `history.top_scopes` — that is the repo's real vocabulary, not a guess.

## Step 5: Write the message

Read `references/message-format.md` for the type table, subject and body rules, BREAKING CHANGE syntax, and footers. Load it before writing any message; the breaking-change rules in particular are not intuitive and getting them wrong silently changes what version ships.

Two things the diff cannot tell you, which decide message quality:

- **The why.** A diff shows what changed; it cannot show why the change was chosen. When this conversation contains that reasoning — a bug reproduced, a constraint discovered, an approach rejected — put it in the body. It is the single most valuable thing available here and nowhere else. Research on commit quality finds the missing "why" to be the most common defect in real-world messages, and the "what" is the half the diff already covers.
- **Whether it should be one commit.** If the draft subject needs an "and", or the body grows to cover two unrelated justifications, it is two commits.

## Step 6: Execute

Write the message to a file and commit with `-F`. Do not use `-m` with a heredoc: a body line that happens to read `EOF` terminates the heredoc early, truncating the message and executing the remaining lines as shell commands — and the commit still succeeds, so the corruption is silent. Since the body is written from diff content, that is a content-driven injection path, not a formatting nit. The file form also avoids `-m "..."` breaking on any quote, backtick, or `$` in the message, and works under PowerShell.

1. Write the message with the Write tool to a scratch path.
2. Stage with an explicit path list, always after `--`: `git add -- <path> <path>`. Without the separator, a file named `-weird.txt` is parsed as options, and pathspec magic like `:(glob)` becomes an injection surface.
3. `git commit -F <message-file>`
4. Check the **exit code**. A clean `git status` does not mean success — a dirty tree is equally consistent with a hook rewriting files, a signing failure, or an empty commit.
5. Verify what actually landed: `git log -1 --format='%H %s'`. A `commit-msg` hook is allowed to rewrite the message in place, so the message committed is not necessarily the message written.
6. Compare the tree against the expected post-commit state. If files the hook touched are now dirty, a formatter rewrote them *after* the snapshot was taken, so the commit holds the unformatted version — read `references/recovery.md` and stop rather than sweeping the leftovers into the next commit.

Never pass `--no-verify` unless the user explicitly asks. It skips exactly the `pre-commit` and `commit-msg` gates the team installed on purpose, including local secret scanning, and does not skip server-side hooks — so it usually just relocates the failure to push time, after history is built on top.

## Batch mode

1. Group the files. Read `references/grouping-algorithm.md`.
2. Present the plan — every group, its files, and its proposed subject — and wait for approval. State plainly that intermediate commits may not build: grouping has no import-graph awareness, so a caller and callee can land in different commits.
3. Commit groups one at a time, staging each group by explicit pathspec. **Do not run a blanket `git reset` between groups.** Stage only that group's paths, and unstage with `git restore --staged -- <paths>` scoped to the same list.
4. Record the short SHA after each commit.
5. On any failure, stop immediately and report what landed, what is staged, and what remains — see `references/recovery.md`. Never continue to the next group.

Target 2–5 commits; more than 7 means the grouping is too fine. One group means single mode.

## Flags

| Flag | Effect |
|---|---|
| `--all` | Batch mode over every change |
| `--amend` | Amend the last commit. Check `head.ahead` first — amending a pushed commit rewrites published history; warn and confirm. |
| `--dry-run` | Show the message and file list, commit nothing |
| `--push` | Offer to push after all commits succeed |
| `--signoff` | Add `Signed-off-by`. Only on request or when the repo requires DCO — it is a legal attestation in the committer's name, not a formatting option. |
| `--lang=xx` | Description language. Otherwise inferred from history. |
| `--yes` | Skip confirmations. Safety gates in Step 2 still apply. |
