# claude-commit-skill

A Claude Code skill that analyzes git changes, asks your preferences, and creates well-structured commits following the [Conventional Commits](https://www.conventionalcommits.org/) specification.

## Features

- **Interactive scope selection** — when both staged and unstaged changes exist, asks whether to commit only staged or all changes
- **Language support (EN / TR)** — always asks your preferred language before generating messages. Subject line stays English per Conventional Commits standard; body is written in the chosen language
- **Rich commit messages** — generates detailed body with bullet points when changes touch 2+ files or diff exceeds 30 lines
- **Batch commit grouping** — in batch mode, groups unrelated changes into separate logical commits by module, file affinity, and change intent
- **Smart file pairing** — keeps related files together: implementation + test, component + styles, manifest + lock file, migration + rollback
- **Conventional Commits** — proper type selection (`feat`, `fix`, `refactor`, `perf`, `chore`, `docs`, `test`, `ci`, `security`, `revert`, `style`)
- **Edge case handling** — binary files, large diffs, lock files, merge conflicts, pre-commit hook failures, submodule changes

## Installation

Clone the repository and copy the skill into your Claude Code skills directory:

```bash
git clone https://github.com/mustafakbaser/claude-commit-skill.git
mkdir -p ~/.claude/skills/commit
cp -r claude-commit-skill/SKILL.md claude-commit-skill/references ~/.claude/skills/commit/
```

Restart Claude Code. The `/commit` command will be available globally across all projects.

## How It Works

When you run `/commit`, the skill follows this flow:

```
1. Gather context (git status, diff, recent commits)
2. Determine scope:
   ├─ Only staged changes exist     → single commit mode
   ├─ Only unstaged changes exist   → batch mode
   ├─ Both staged & unstaged exist  → asks: "Only staged" or "All changes"
   ├─ No changes                    → abort
   └─ Merge conflicts               → abort
3. Ask language preference: EN or TR
4. Analyze changes and generate commit message(s)
5. Execute and verify
```

### Single Commit Mode

Commits staged changes with a detailed message:

**EN:**
```
feat(contracts): add PDF generation for contract renewals

- Add PDF generation support for contract renewal workflows
- New template system supports all 7 contract types
- PDF generation runs asynchronously via Edge Functions
- Upload generated files to Supabase Storage with signed URLs
```

**TR:**
```
feat(contracts): add PDF generation for contract renewals

- Sözleşme yenileme işlemleri için PDF oluşturma desteği eklendi
- Yeni şablon sistemi ile 7 farklı sözleşme tipi destekleniyor
- Edge Function üzerinden asenkron PDF üretimi yapılıyor
- Oluşturulan dosyalar signed URL ile Supabase Storage'a yükleniyor
```

### Batch Commit Mode

When nothing is staged or `--all` is passed, the skill groups all changes by logical affinity, presents a commit plan, and waits for your approval before executing:

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

Each commit in the batch follows the same message rules and language preference.

## Commit Message Format

| Rule | Detail |
|------|--------|
| Format | `type(scope): imperative description` |
| Subject | Always English, max 72 characters, imperative mood |
| Body | In chosen language (EN/TR), included when 2+ files or >30 line diff |
| Body style | Bullet points summarizing what changed and why |
| Scope | Derived from primary module (`db`, `ui`, `api`, `auth`, etc.) |
| Omitted scope | When changes span 3+ unrelated modules |

Supported types: `feat`, `fix`, `refactor`, `perf`, `style`, `docs`, `test`, `chore`, `ci`, `security`, `revert`

## Batch Grouping Algorithm

The grouping runs in five phases:

1. **Affinity pairing** — implementation + test, component + styles, manifest + lock file, migration + rollback
2. **Directory clustering** — group by shared path prefix (first 2 segments)
3. **Semantic separation** — feature vs fix vs refactor vs config vs docs vs database
4. **Balancing** — merge single-file groups, split oversized ones (target: 2–5 commits, max 7)
5. **Ordering** — infrastructure → database/schema → features → fixes → tests → docs

See [references/grouping-algorithm.md](references/grouping-algorithm.md) for the full specification.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Binary files | Included in commit, content not analyzed |
| Lock files | Always grouped with their manifest file |
| Large diffs (>1000 lines) | Uses `--stat` + partial read for context |
| Untracked files only | Staged and committed as `feat` or `chore` |
| Pre-commit hook failure | Reports error, does not retry or use `--no-verify` |
| Merge conflicts | Aborts with message to resolve first |

## License

MIT
