# Failure Handling and Recovery

- [Hooks that rewrite files](#hooks-that-rewrite-files)
- [Hooks that rewrite the message](#hooks-that-rewrite-the-message)
- [Hook rejection](#hook-rejection)
- [Signing failure](#signing-failure)
- [Empty commit](#empty-commit)
- [Partial batch failure](#partial-batch-failure)
- [Amending](#amending)
- [Edge cases](#edge-cases)

## Hooks that rewrite files

Formatters run as `pre-commit` hooks — prettier, black, `eslint --fix`, gofmt — modify files on disk *after* the index snapshot was taken. The commit succeeds, the committed content is the **unformatted** version, and the working tree is left dirty with no warning. In batch mode the leftover modification then gets swept into a later, unrelated group.

Detect it: after each commit, files the hook touched show as modified in `git status` when the tree should be clean.

Recovery depends on which stack is present, because the two behave differently:

- **lint-staged** (`hook_runners.lint_staged`) re-stages formatter output automatically, so the committed content can differ from what was reviewed. Check `git diff HEAD~1` after such a commit.
- **pre-commit** (`hook_runners.pre_commit`) does not. It fails with "Files were modified by this hook" and leaves the fixes unstaged. The correct sequence is: read the hook output, review the automatic fixes with `git diff`, `git add` the modified files, and re-run the same commit. The hooks now pass because the staged content already satisfies them.

Never answer "Files were modified by this hook" with `--no-verify`. That commits the pre-fix content while the fixed content sits unstaged — precisely the divergence the hook existed to prevent.

If lint-staged was interrupted mid-run, the working state may be in a stash it created. Check `git stash list` before concluding anything was lost.

## Hooks that rewrite the message

A `commit-msg` hook is allowed to edit the message file in place, so the message that landed is not necessarily the one written. Always verify:

```bash
git log -1 --format=%B
```

Note that `prepare-commit-msg` is the one commit hook `--no-verify` does **not** bypass.

## Hook rejection

Report the hook's own output verbatim — it names what to fix. Do not retry, and do not rerun with `--no-verify`.

When the rejection is a message-format failure and commitlint is present, regenerate the message against the resolved config from `repo-conventions.md` and dry-run it with `printf '%s' "$MSG" | npx commitlint` before trying again.

When a commit has already been made and a later hook run fails, create a **new** commit with the fix rather than amending — amending changes the SHA, which is only safe on unpublished commits.

## Signing failure

With `commit.gpgsign` enabled and a missing or invalid key, `git commit` fails with `error: gpg failed to sign the data` and no commit is created. The files stay staged, which reads exactly like "nothing happened yet" if only `git status` is checked — this is why Step 6 checks the exit code rather than the status output.

The preflight output reports `git_config.gpgsign`, `gpg_format`, and `signingkey`. On failure, report it and stop; do not retry with `--no-gpg-sign`, which quietly produces an unsigned commit in a repository that requires signatures.

## Empty commit

`git commit` with nothing staged exits 1. In batch mode this happens when a group's files were already consumed — for instance after a rename decomposed, or after a hook shuffled content. Skip empty groups explicitly rather than letting the commit fail.

## Partial batch failure

When commit 3 of 5 fails, commits 1 and 2 are already in history, the index holds group 3, and groups 4 and 5 are untouched. Stop and report all three states explicitly:

```
Committed:
  abc1234 feat(pricing): add discount calculation
  def5678 fix(db): correct balance view

Failed:
  chore: update dependencies — commit-msg hook rejected: type-enum

Staged now:  package.json, package-lock.json
Not staged:  src/docs/pricing.md
```

Then offer, without doing it unprompted: fix and retry the failed group, or unwind with `git reset --soft HEAD~2` to put everything back in the index with nothing lost.

Capture the short SHA with `git rev-parse --short HEAD` after each commit as it happens. It cannot be reconstructed afterwards.

## Amending

`--amend` replaces the tip commit with a new one, so the SHA changes. Check `head.ahead` from the preflight output first: if the commit is already pushed, amending rewrites published history and anyone who pulled it will conflict. Warn and confirm.

For a commit further back, `git commit --fixup=<sha>` followed by `git rebase -i --autosquash <base>` is the safe path — it keeps the history clean without rewriting anything until the rebase runs.

## Edge cases

| Situation | Handling |
|---|---|
| Binary files | Include them, do not analyze content. Describe as adding or updating assets. |
| Lock files | Always with their manifest, never alone. Do not base the message on their contents. |
| Very large diffs | Read `--stat` first, then the diffs of the files that matter. Do not pull a whole large diff into context before knowing its size. |
| Submodules | Note the pointer moved; do not analyze the submodule's internals. |
| Deleted files | `git add -- <path>` stages a deletion correctly; `git rm` is not needed. |
| Paths starting with `-` | Always stage after `--`, or git parses the path as options. |
| Unborn repo | `git log` exits 128 — normal, not a failure. There is simply no history to learn from. |
| Only untracked files | Screen them first, then stage and commit normally. |
