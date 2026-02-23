# claude-commit-skill

A Claude Code skill that analyzes your git changes and creates well-structured commits following the [Conventional Commits](https://www.conventionalcommits.org/) specification.

## Features

- **Automatic mode detection** — staged changes trigger a single commit; if nothing is staged, all changes are analyzed and grouped into multiple logical commits
- **Conventional Commits** — generates `type(scope): description` messages with proper type selection (`feat`, `fix`, `refactor`, `perf`, `chore`, etc.)
- **Batch commit grouping** — splits unrelated changes into separate commits by module, file affinity, and change intent
- **Smart file pairing** — keeps related files together (implementation + test, component + styles, manifest + lock file)
- **Edge case handling** — binary files, large diffs, lock files, merge conflicts, pre-commit hook failures

## Installation

Clone the repository and copy the skill to your Claude Code skills directory:

```bash
git clone https://github.com/mustafakbaser/claude-commit-skill.git
mkdir -p ~/.claude/skills/commit
cp -r claude-commit-skill/SKILL.md claude-commit-skill/references ~/.claude/skills/commit/
```

After copying, restart Claude Code. The `/commit` command will be available globally across all projects.

## Usage

| Command | Behavior |
|---------|----------|
| `/commit` | Staged changes → single commit. Nothing staged → auto batch mode. |
| `/commit --all` | Analyze all changes, group related ones into multiple logical commits. |

### Single Commit Mode

When you have staged changes, `/commit` analyzes the diff and generates an optimal commit message:

```
feat(wizard): add discount calculation to pricing step
```

### Batch Mode

When there are no staged changes (or you use `--all`), the skill groups all modified files by logical affinity, presents a commit plan for your approval, then executes each commit sequentially:

```
Proposed commits:

1. feat(wizard): add discount calculation to pricing step
   - src/components/wizard/PricingStep.tsx
   - src/lib/pricing.ts

2. fix(db): correct meeting balance view
   - supabase/migrations/20250102_fix_balance.sql

3. chore: update dependencies
   - package.json
   - package-lock.json
```

## Commit Message Rules

- Follows [Conventional Commits](https://www.conventionalcommits.org/) format
- Imperative mood, max 72 characters
- Scope derived from the primary module affected
- No trailing periods, no emoji
- Optional body for complex changes (5+ files or non-obvious reasoning)

## How Batch Grouping Works

The grouping algorithm runs in five phases:

1. **Affinity pairing** — implementation + test, component + styles, manifest + lock file
2. **Directory clustering** — files in the same module/directory
3. **Semantic separation** — feature vs fix vs refactor vs config vs docs
4. **Balancing** — merge small groups, split oversized ones (target: 2–5 commits, max 7)
5. **Ordering** — infrastructure → schema → features → fixes → docs

See [references/grouping-algorithm.md](references/grouping-algorithm.md) for the full specification.

## License

MIT
