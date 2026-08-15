# Batch Grouping

Splitting one working tree into several commits. The goal is commits that are each independently reviewable and revertable — not the smallest possible diffs.

- [Input](#input)
- [Step 1: Bind files that must ship together](#step-1-bind-files-that-must-ship-together)
- [Step 2: Classify by intent](#step-2-classify-by-intent)
- [Step 3: Cluster by ownership](#step-3-cluster-by-ownership)
- [Step 4: Balance](#step-4-balance)
- [Step 5: Order](#step-5-order)
- [What this cannot do](#what-this-cannot-do)

## Input

Use the preflight output, not a fresh `git status`. Specifically:

- `files[]` — each with `x` (index status), `y` (worktree status), `path`, and `orig_path` for renames
- `numstat.staged` / `numstat.unstaged` — added and deleted line counts per path, joined on `path`
- `partially_staged[]` — files whose index and worktree both differ

Read `x` and `y` separately. They are different columns: `M ` is staged, ` M` is unstaged, `MM` is both. A file listed in `partially_staged` holds hand-picked hunks — re-staging the whole file commits content the author withheld, so either commit only the staged half or confirm with the user first.

For any file whose intent is not obvious from its path, read its actual diff before classifying. Batch mode otherwise assigns a type and writes a message for files it has never looked at, which is exactly how vague commit messages get produced.

## Step 1: Bind files that must ship together

These pairs go in the same commit regardless of everything below.

| Binding | Match on |
|---|---|
| Implementation + its test | Same base name with a `.test`/`.spec` suffix, or the same base name under `__tests__/` or `tests/` |
| Component bundle | Same base name, same directory, different extension — `.tsx` with `.module.css`, `.styles.ts`, `.stories.tsx` |
| Manifest + lock | `package.json`+`package-lock.json`/`pnpm-lock.yaml`/`yarn.lock`, `Cargo.toml`+`Cargo.lock`, `pyproject.toml`+`poetry.lock`/`uv.lock`, `Gemfile`+`Gemfile.lock`, `go.mod`+`go.sum` |
| Migration + rollback | Same timestamp or sequence prefix, or a sibling differing only by `up`/`down` |
| Generated + source | A generated file and whatever generates it — schema output, compiled protos, API clients |

A lock file never forms its own commit; it belongs with the manifest that moved it.

Renames need both halves in one commit. Stage the rename with both paths — the new path and `orig_path` — or the commit records a deletion without the corresponding addition and the tree is broken at that point in history.

## Step 2: Classify by intent

One category per group, drawn from this list and no other. Every later step uses these same names.

| Category | Signals |
|---|---|
| `deps` | Manifest and lock files, vendored dependency directories |
| `ci` | Workflow files, pipeline configuration, `.github/`, `.gitlab-ci.yml` |
| `build` | Bundler, compiler, packaging and tooling configuration |
| `db` | Migrations, schema definitions, seed data |
| `feat` | New capability — read the diff to confirm it adds behavior that did not exist |
| `fix` | Corrects wrong behavior — read the diff to confirm there was a defect |
| `refactor` | Restructuring with no behavior change |
| `style` | Formatting only, no semantic change |
| `test` | Test files with no accompanying implementation change |
| `docs` | Markdown, `docs/`, comments-only changes |
| `chore` | Anything genuinely fitting none of the above |

**Classify from the diff, not from file status or size.** A new file is as likely to be a test, fixture, doc, or config as a feature. A three-line change adding a feature flag is a `feat`; a three-hundred-line null-safety sweep is a `fix`. Line counts tell you how much to read, not what the change means.

When several categories fit one file, take the first match in the order listed above. When a file's category disagrees with the group it is bound to by Step 1, Step 1 wins — a test committed with its implementation is part of that commit, not a `test` commit of its own.

## Step 3: Cluster by ownership

Within each category, group by what owns the code.

1. In a monorepo, cluster by workspace package — the nearest ancestor directory containing a `package.json`, `Cargo.toml`, `go.mod`, or `pyproject.toml`. Never merge packages into one commit.
2. Otherwise cluster by feature, following imports rather than directory depth. A change touching `src/components/Pricing.tsx`, `src/lib/pricing.ts`, and `src/hooks/usePricing.ts` is one feature and one commit — splitting it by directory produces three commits that each fail to build.
3. Root-level files (`package.json`, `README.md`, dotfiles) have no directory to cluster by; they join the group matching their category.

## Step 4: Balance

- A group of one file merges into the group it shares the most imports with. Standalone migrations are the exception — they stay separate.
- A group above 15 files splits by subdirectory, unless splitting would break Step 1 bindings.
- More than 7 groups means the split is too fine; merge the smallest by import proximity until at most 7 remain. Target 2–5.
- Exactly one group means this is not a batch — fall back to single-commit mode.

## Step 5: Order

Commit in this order, using the same category names from Step 2:

1. `deps`, `build`, `ci`
2. `db`
3. `refactor`
4. `feat`
5. `fix`
6. `style`, `docs`

Tests are never their own position here — Step 1 already bound them to the code they cover.

One caveat on `db`: schema changes belong first when they are additive, because the code that follows depends on them. A destructive migration — dropping a column, removing a table — belongs *after* the code that stopped reading it, or the tree is broken at that commit. Check which kind it is rather than applying the order mechanically.

## What this cannot do

Grouping has no import-graph analysis deep enough to guarantee that each commit builds. A caller and its callee can land in different commits, and the intermediate states will not compile. Say this plainly in the plan presented for approval, because it is the cost of a multi-commit split: the history reads better and bisects worse.

If a clean split is not achievable — the changes are genuinely entangled — say so and propose one commit. An honest single commit beats an artificial split that produces commits nobody can revert independently.
