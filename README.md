# claude-commit-skill

A Claude Code skill that analyzes your git changes and creates well-structured commits following the [Conventional Commits](https://www.conventionalcommits.org/) specification.

## Features

- **Interactive flow** — asks what to commit and in which language before proceeding
- **Language support** — commit messages in English or Turkish (subject line always English per Conventional Commits, body in chosen language)
- **Rich commit messages** — detailed body with bullet points for multi-file changes, not just one-liners
- **Smart scope detection** — when both staged and unstaged changes exist, asks whether to commit only staged or everything
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
| `/commit` | Analyze changes → ask preferences → commit. |
| `/commit --all` | Force batch mode for all changes. |

### Interactive Flow

1. The skill analyzes `git status`
2. If both staged and unstaged changes exist → asks: **"Only staged"** or **"All changes"**
3. Asks language preference: **EN** or **TR**
4. Generates commit(s) and executes

### Single Commit Mode

When committing staged changes (or when all changes belong to a single logical group):

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

### Batch Mode

When there are no staged changes, or you use `--all`, the skill groups all modified files by logical affinity, presents a commit plan for your approval, then executes each commit sequentially:

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
- Subject line always in English, imperative mood, max 72 characters
- Body in chosen language (EN or TR) with bullet points
- Body included when changes touch 2+ files or diff exceeds 30 lines
- Scope derived from the primary module affected
- No trailing periods, no emoji, no AI attribution

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
