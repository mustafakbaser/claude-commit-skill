# Commit Message Format

- [Structure](#structure)
- [Types](#types)
- [Scope](#scope)
- [Subject](#subject)
- [Body](#body)
- [Breaking changes](#breaking-changes)
- [Footers](#footers)
- [Language](#language)
- [Never include](#never-include)
- [Examples](#examples)

## Structure

```
<type>[(<scope>)][!]: <description>

[body]

[footer(s)]
```

The colon and the space after it are required. The body is separated from the subject by exactly one blank line, and the footers from the body by another. Without that first blank line the whole message becomes the commit title everywhere git displays it.

## Types

Use the repo's own `type-enum` when one exists (see `repo-conventions.md`). Absent that, these eleven are `@commitlint/config-conventional`'s default set and the safest baseline:

| Type | When |
|---|---|
| `feat` | New functionality or capability |
| `fix` | Bug fix or error correction |
| `refactor` | Restructuring with no behavior change |
| `perf` | Performance improvement |
| `docs` | Documentation only |
| `style` | Formatting, whitespace — no logic change |
| `test` | Adding or updating tests |
| `build` | Build system, dependencies, packaging |
| `ci` | CI/CD pipeline |
| `chore` | Tooling and maintenance that fits nothing above |
| `revert` | Reverting a previous commit |

Notes that matter in practice:

- **There is no `security` type.** It is absent from the standard enum, so a `commit-msg` hook rejects it. Use `fix` and say what was hardened in the body.
- **`config-angular` is different from `config-conventional`**: it forbids `chore` entirely and caps the header at 72 rather than 100. Check which one the repo extends.
- When `fix` and `feat` both fit, choose `fix`. Reserve `feat` for a capability that did not exist before.
- The type is a claim about the change, and release tooling acts on it. Mislabeling a bug fix as `chore` does not just misfile it — under semantic-release it ships nothing at all.

## Scope

A noun naming the part of the codebase affected: `db`, `api`, `auth`, `wizard`, `pdf`. Lowercase, one word where possible.

Prefer a scope that already appears in `history.top_scopes` from the preflight output. If the repo defines `scope-enum`, that list is authoritative. Omit the scope when a change genuinely spans the whole codebase — but a group spanning several unrelated modules is usually a sign the grouping was too coarse, so re-split before dropping the scope.

In an **nx** monorepo the scope is load-bearing rather than decorative: it must be an exact project name, and an ambiguous one is a hard error. Everywhere else (lerna, release-please, changesets) attribution comes from file paths or a separate file, and the scope is documentation.

## Subject

- Imperative mood: "add", "fix", "remove" — not "added", "fixes", "updates". The test is that "If applied, this commit will _____" reads grammatically. Git's own generated messages are imperative (`Merge branch…`, `Revert "…"`).
- Lowercase first letter after the colon. `config-conventional`'s `subject-case` rule forbids sentence-case, start-case, pascal-case and upper-case.
- No trailing period.
- Target **72 characters** for the whole line including type and scope. The hard cap is the repo's `header-max-length` (100 under `config-conventional`, 72 under `config-angular`).
- Be specific. "add retry logic for failed API calls" beats "update API code" — a subject that only names the area it touched is not a description of the change.

The 50-character figure from git's own documentation predates the type prefix; `feat(auth): ` alone spends twelve characters. 72 is the number that satisfies the kernel, Karma, and the original terminal-width reasoning at once, and it fits GitHub's UI without truncation.

## Body

Include a body when the reason for the change is not obvious from the subject. File and line counts are a hint toward that, not a rule — a two-file rename needs no body, and a one-line change that removes a security check needs one.

- Wrap at 72 characters.
- Explain **why**, not how. The diff already shows how. State the problem in the present tense — the status quo is understood to be the code without this change, so do not write "Currently".
- Use `-` bullets when there are several distinct points.
- A body that grows long enough to cover two unrelated justifications is telling you this should be two commits.

Always include a body, regardless of size, for breaking changes, security fixes, data migrations, and reverts. Those are the commits someone will be reading under pressure years later.

## Breaking changes

**Emit both the `!` marker and the `BREAKING CHANGE:` footer.** Not one or the other.

The specification permits either alone, but real parsers disagree about which they honor, and the failure is silent:

| Written | semantic-release (default preset) | release-please |
|---|---|---|
| `feat!: drop node 14` | **no release at all** | major |
| `feat:` + `BREAKING CHANGE: …` | major | major |
| `feat:` + `BREAKING-CHANGE: …` | minor — token not recognized | major |
| `feat!:` + `BREAKING CHANGE: …` | major | major |

semantic-release's default Angular preset uses a header pattern with no `!` in it, so `feat!: x` fails to match at all — the type parses as null, no rule fires, and the commit is dropped from the release entirely. Writing both forms is spec-legal and immune to every parser variant.

```
feat(api)!: require an explicit region on client construction

The client silently defaulted to us-east-1, which routed EU customer
data through the wrong region.

BREAKING CHANGE: ApiClient now requires a `region` option. Callers
relying on the implicit us-east-1 default must pass it explicitly.
```

`BREAKING CHANGE` must be uppercase — it is the one case-sensitive token in the specification. `BREAKING-CHANGE` is the only permitted variant. **Never write `BREAKING CHANGES:`** (plural): no tool recognizes it.

Signals worth checking for: removed or renamed exports, changed function signatures, deleted routes or endpoints, dropped database columns, renamed configuration keys, raised minimum runtime versions. When one is present and the user has not called it breaking, ask rather than deciding silently — the answer changes which version ships.

## Footers

One blank line after the body. Each footer is `Token: value`, with `-` replacing any whitespace in the token.

| Footer | Use |
|---|---|
| `Closes #123` | Closes the issue on merge to the default branch |
| `Fixes owner/repo#123` | Cross-repository close |
| `Refs: PROJ-123` | Links without closing — for Jira and similar trackers |
| `BREAKING CHANGE: …` | See above |
| `Signed-off-by: …` | DCO attestation. Only when asked or required. |

Repeat the keyword for each issue: `Closes #10, closes #11`. A bare `Closes #10, #11` closes only the first. The keywords are case-insensitive and an optional colon is allowed; `close/closes/closed`, `fix/fixes/fixed`, and `resolve/resolves/resolved` all work on both GitHub and GitLab.

When the branch name carries a ticket — `feature/PROJ-123-discount`, `fix/GH-42-timeout` — extract it into `Refs: PROJ-123` or `Closes #42`. The preflight output has the branch name.

**Never fabricate attribution.** `Reviewed-by`, `Acked-by`, `Tested-by`, and `Co-authored-by` name real people and assert they did something. They require that person's explicit permission. `Signed-off-by` is a legal certification made in the committer's name under the Developer Certificate of Origin; add it only when the user asks or the repository enforces DCO.

## Language

Type, scope, footer tokens, and `BREAKING CHANGE` are **always ASCII English**, in every repository. This is mechanical, not stylistic: git's trailer parser rejects whitespace inside a token, GitHub's and GitLab's closing keywords only match English, and every changelog generator pattern-matches those exact ASCII strings. A translated prefix silently disables all release automation.

The description and body follow the repository's language, inferred from `history.recent_subjects`. Ask only when history is genuinely mixed or absent. The specification places no constraint on the description's language — an English subject is this skill's default, not a requirement, and `--lang=xx` overrides it.

The imperative-mood rule is a fact about English grammar. Do not force it onto languages that do not mark the distinction the same way; consistency within the repository matters more.

## Never include

- `Co-Authored-By` or any AI/tool attribution, unless the user's own configuration asks for it
- Emoji, unless the repo already uses gitmoji (see `repo-conventions.md` — position matters, and a leading emoji breaks stock commitlint)
- Customer names, user emails, support-ticket contents, internal URLs, or any other personal data. Describe the technical symptom instead. Commit messages are permanent and usually public.
- Vague subjects: "update code", "fix stuff", "minor changes", "wip", or a subject that merely restates the filename

## Examples

Single-file fix, why not obvious from the subject:

```
fix(auth): reject tokens whose audience does not match the client

Tokens issued for the mobile client were accepted by the web client
because the audience claim was parsed but never compared.
```

Feature spanning several files, body in the repository's language:

```
feat(contracts): add PDF generation for contract renewals

- Sözleşme yenileme işlemleri için PDF oluşturma desteği eklendi
- Yeni şablon sistemi ile 7 farklı sözleşme tipi destekleniyor
- Edge Function üzerinden asenkron PDF üretimi yapılıyor

Refs: PROJ-412
```

Trivial change, no body needed:

```
docs: fix broken link in the installation section
```
