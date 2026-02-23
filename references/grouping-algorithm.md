# Batch Commit Grouping Algorithm

## Input

Changed files from `git status --porcelain`, each with status code and file path.

## Phase 1: Build Affinity Pairs

Files that must be committed together:

### Implementation + Test
- `src/foo.ts` ↔ `src/foo.test.ts`, `src/foo.spec.ts`, `tests/foo.test.ts`, `__tests__/foo.test.ts`
- Match by base name with test/spec suffix or `__tests__/` directory

### Component Bundles
- `Component.tsx` ↔ `Component.module.css`, `Component.styles.ts`, `Component.stories.tsx`
- Match by base name, different extensions, same directory

### Manifest + Lock
- `package.json` ↔ `package-lock.json`
- `Cargo.toml` ↔ `Cargo.lock`
- `Gemfile` ↔ `Gemfile.lock`
- `pyproject.toml` ↔ `poetry.lock`, `uv.lock`
- `requirements.txt` ↔ `requirements.lock`

### Migration + Rollback
- Migration files pair with rollback counterparts
- Match by timestamp prefix or sequential numbering

### Type Definition + Implementation
- `.d.ts` files pair with their `.ts` implementation
- `types.ts` or `schema.ts` pairs with files importing from them

## Phase 2: Directory Clustering

Group remaining files by directory proximity:

1. Extract first 2 path segments: `src/components/wizard/Step.tsx` → `src/components`
2. Files sharing the same 2-segment prefix form a cluster
3. If a cluster exceeds 10 files, split by 3rd segment

## Phase 3: Semantic Separation

Within each cluster, separate by change intent:

| Category | Indicators |
|----------|-----------|
| Feature | New files (status `A` or `??`) in feature directories |
| Fix | Modified files (status `M`) with small diffs (<50 lines) |
| Refactor | Renamed files (status `R`), large modifications (>100 lines) |
| Config | Root directory files, dotfiles, CI configs, build configs |
| Documentation | `.md`, `.txt`, files in `docs/` directory |
| Database | Migration files, SQL files, schema changes |

## Phase 4: Merge & Balance

After initial grouping:

- **Single-file groups**: Merge into the most related adjacent group
  - Exception: standalone migration files stay as own commit
- **Oversized groups** (>15 files): Split further by subdirectory
- **Too many groups** (>7): Merge the smallest groups by proximity
- **Only 1 group**: Fall back to single commit mode

## Phase 5: Order Commits

Sort for clean, logical history:

1. Infrastructure/config (dependencies, CI, build tooling)
2. Database/schema changes (migrations, type definitions)
3. Feature implementations (new code, new files)
4. Bug fixes (corrections to existing code)
5. Tests (new or updated test files)
6. Documentation/style (docs, formatting)
