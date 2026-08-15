#!/usr/bin/env bash
# preflight.sh - repository state, change inventory and safety screens for /commit.
#
# Emits one JSON object on stdout. Exits non-zero only when the directory is not a
# git repository; every other problem is reported as a field so the caller decides
# what to do instead of the workflow dying halfway through.
#
# Targets bash 3.2 (the version macOS ships): no associative arrays, no ${var,,}.

set -uo pipefail

# 10 MB. Above this a blob is worth a human decision: git history is append-only,
# so a large file bloats every future clone forever, and GitHub hard-rejects >100 MB
# at push time - after the commits already exist.
LARGE_FILE_BYTES=${COMMIT_SKILL_LARGE_FILE_BYTES:-10485760}

# Only files below this are scanned for secret content. Above it the scan costs more
# than it returns, and real credential files are small.
SCAN_MAX_BYTES=${COMMIT_SKILL_SCAN_MAX_BYTES:-1048576}

# 300 subjects is enough to measure a convention and to build a scope histogram with
# a stable tail; 50 would miss scopes used a few times a month.
HISTORY_DEPTH=${COMMIT_SKILL_HISTORY_DEPTH:-300}

json_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

jstr() { printf '"%s"' "$(json_escape "$1")"; }
jbool() { if [ -n "$1" ]; then printf 'true'; else printf 'false'; fi; }

# ---------------------------------------------------------------- repository ---

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  printf '{"is_repo":false,"error":"not a git repository"}\n'
  exit 1
fi

GIT_DIR=$(git rev-parse --absolute-git-dir 2>/dev/null)
TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null)

# An unborn branch is a normal state, not a failure: `git log` exits 128 here, so
# every history-derived field has to tolerate its absence.
UNBORN=""
git rev-parse --verify HEAD >/dev/null 2>&1 || UNBORN=1

# git branch --show-current prints an empty string on detached HEAD, which is easy
# to misread as "no branch name available" rather than "do not commit here".
DETACHED=""
git symbolic-ref -q HEAD >/dev/null 2>&1 || DETACHED=1
BRANCH=$(git branch --show-current 2>/dev/null)

UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)
AHEAD=0; BEHIND=0
if [ -n "$UPSTREAM" ]; then
  set -- $(git rev-list --left-right --count "${UPSTREAM}...HEAD" 2>/dev/null)
  BEHIND=${1:-0}; AHEAD=${2:-0}
fi

DEFAULT_BRANCH=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
[ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH=""

PROTECTED=""
case "$BRANCH" in
  main|master|develop|development|trunk|release|release/*|prod|production) PROTECTED=1 ;;
esac
[ -n "$DEFAULT_BRANCH" ] && [ "$BRANCH" = "$DEFAULT_BRANCH" ] && PROTECTED=1

# --------------------------------------------------- in-progress operations ---
#
# These are the states where re-staging destroys work. A mixed `git reset` deletes
# MERGE_HEAD, and the commit that follows records ONE parent - a merge that silently
# vanishes from history while the branch still reads as unmerged. Resolving the
# conflict and staging is exactly when a human types /commit, and at that point
# status reads "M  file" like any ordinary change, so the file list cannot warn you.

MERGE=""; REBASE=""; CHERRY=""; REVERT=""; BISECT=""
[ -f "$GIT_DIR/MERGE_HEAD" ] && MERGE=1
{ [ -d "$GIT_DIR/rebase-merge" ] || [ -d "$GIT_DIR/rebase-apply" ]; } && REBASE=1
[ -f "$GIT_DIR/CHERRY_PICK_HEAD" ] && CHERRY=1
[ -f "$GIT_DIR/REVERT_HEAD" ] && REVERT=1
[ -f "$GIT_DIR/BISECT_LOG" ] && BISECT=1

IN_PROGRESS=""
{ [ -n "$MERGE" ] || [ -n "$REBASE" ] || [ -n "$CHERRY" ] || [ -n "$REVERT" ] || [ -n "$BISECT" ]; } && IN_PROGRESS=1

# ------------------------------------------------------------------ signing ---

GPGSIGN=$(git config --get commit.gpgsign 2>/dev/null)
GPGFORMAT=$(git config --get gpg.format 2>/dev/null)
SIGNINGKEY=$(git config --get user.signingkey 2>/dev/null)
HOOKSPATH=$(git config --get core.hooksPath 2>/dev/null)
COMMIT_TEMPLATE=$(git config --get --path commit.template 2>/dev/null)
COMMENT_CHAR=$(git config --get core.commentString 2>/dev/null)
[ -z "$COMMENT_CHAR" ] && COMMENT_CHAR=$(git config --get core.commentChar 2>/dev/null)
[ -z "$COMMENT_CHAR" ] && COMMENT_CHAR='#'

# ---------------------------------------------------------------- inventory ---
#
# core.quotepath=false stops git octal-escaping non-ASCII paths; -z gives NUL framing
# so paths containing spaces, quotes or newlines survive; -uall expands untracked
# directories, which otherwise collapse to a single "dir/" entry and hide every file
# inside a brand-new feature directory.

FILES_JSON=""
PARTIAL_JSON=""
UNTRACKED_LIST=""
STAGED_COUNT=0
UNSTAGED_COUNT=0
UNTRACKED_COUNT=0
CONFLICT_COUNT=0

while IFS= read -r -d '' entry; do
  [ -z "$entry" ] && continue
  x=${entry:0:1}
  y=${entry:1:1}
  path=${entry:3}
  orig=""
  # A rename or copy record emits new-path NUL old-path NUL, in that order.
  if [ "$x" = "R" ] || [ "$x" = "C" ]; then
    IFS= read -r -d '' orig || orig=""
  fi

  if [ "$x" = "U" ] || [ "$y" = "U" ] || { [ "$x" = "A" ] && [ "$y" = "A" ]; } || { [ "$x" = "D" ] && [ "$y" = "D" ]; }; then
    CONFLICT_COUNT=$((CONFLICT_COUNT + 1))
  fi
  if [ "$x" = "?" ]; then
    UNTRACKED_COUNT=$((UNTRACKED_COUNT + 1))
    UNTRACKED_LIST="${UNTRACKED_LIST}${path}"$'\n'
  else
    [ "$x" != " " ] && STAGED_COUNT=$((STAGED_COUNT + 1))
    [ "$y" != " " ] && UNSTAGED_COUNT=$((UNSTAGED_COUNT + 1))
  fi

  # Staged AND unstaged content in the same file means hand-picked hunks (git add -p).
  # There is no index reflog, so re-staging the whole file is unrecoverable and would
  # commit the hunks the author deliberately withheld under a message describing
  # something else.
  if [ "$x" != " " ] && [ "$x" != "?" ] && [ "$y" != " " ]; then
    PARTIAL_JSON="${PARTIAL_JSON},$(jstr "$path")"
  fi

  entry_json="{\"x\":$(jstr "$x"),\"y\":$(jstr "$y"),\"path\":$(jstr "$path")"
  [ -n "$orig" ] && entry_json="${entry_json},\"orig_path\":$(jstr "$orig")"
  entry_json="${entry_json}}"
  FILES_JSON="${FILES_JSON},${entry_json}"
done < <(git -c core.quotepath=false status --porcelain=v1 -z -uall 2>/dev/null)

FILES_JSON="[${FILES_JSON#,}]"
PARTIAL_JSON="[${PARTIAL_JSON#,}]"

# Line counts per path. Phase 3 of the grouping algorithm needs these and nothing
# else collects them. Kept as separate arrays because bash 3.2 has no associative
# arrays; the caller joins on path.
numstat_json() {
  local mode=${1:-}
  local out="" added deleted rest p
  while IFS= read -r -d '' rec; do
    [ -z "$rec" ] && continue
    added=${rec%%$'\t'*}
    rest=${rec#*$'\t'}
    deleted=${rest%%$'\t'*}
    p=${rest#*$'\t'}
    # A rename record ends after the counts and emits old-path NUL new-path NUL;
    # read both so the frames stay aligned and report the new path.
    if [ -z "$p" ]; then
      IFS= read -r -d '' p || continue
      IFS= read -r -d '' p || continue
    fi
    # Binary files report "-" for both counts, so these stay strings.
    out="${out},{\"path\":$(jstr "$p"),\"added\":$(jstr "$added"),\"deleted\":$(jstr "$deleted")}"
  done < <(git diff --numstat -z $mode 2>/dev/null)
  printf '[%s]' "${out#,}"
}

if [ -n "$UNBORN" ]; then
  NUMSTAT_STAGED='[]'
else
  NUMSTAT_STAGED=$(numstat_json --cached)
fi
NUMSTAT_UNSTAGED=$(numstat_json)

# ------------------------------------------------------------------ screens ---
#
# The default batch behaviour is to stage files the author never reviewed, so these
# run before anything is staged. A pushed credential is compromised: rewriting
# history does not un-leak it, and forks, clones and cached views keep serving it.
# Rotate first, rewrite second.

SECRET_NAME_RE='(^|/)(\.env(\..*)?|\.envrc|credentials(\.json)?|serviceaccount.*\.json|service-account.*\.json|id_(rsa|dsa|ecdsa|ed25519)|\.npmrc|\.pypirc|\.netrc|kubeconfig|terraform\.tfstate(\.backup)?|\.pgpass|secring\.gpg)$|\.(pem|key|p12|pfx|jks|keystore|ppk)$'
SECRET_CONTENT_RE='-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{35}|glpat-[A-Za-z0-9_-]{20,}|SG\.[A-Za-z0-9_-]{20,}|(secret|token|passwd|password|api_?key|private_?key)[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9/+_-]{16,}["'"'"']'
JUNK_RE='(^|/)(\.DS_Store|Thumbs\.db|desktop\.ini|\.idea/|\.vscode/|__pycache__/|\.pytest_cache/|\.ruff_cache/|node_modules/|\.next/|\.turbo/|\.gradle/|coverage/|dist/|build/|target/|\.venv/|venv/)|\.(pyc|pyo|swp|swo|log|orig|rej|bak)$|~$'

SECRETS_JSON=""; LARGE_JSON=""; JUNK_JSON=""

file_size() {
  # stat is not portable between BSD and GNU; try both rather than assume a platform.
  stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || printf '0'
}

# Screen everything not yet in HEAD: untracked files plus anything staged. Tracked
# unchanged files are already in history and screening them again is noise.
SCREEN_LIST=$(
  { printf '%s' "$UNTRACKED_LIST"
    if [ -n "$UNBORN" ]; then
      git diff --cached --name-only 2>/dev/null
    else
      git diff --cached --name-only --diff-filter=ACMR 2>/dev/null
    fi
  } | sort -u
)

while IFS= read -r p; do
  [ -z "$p" ] && continue
  full="$TOPLEVEL/$p"
  # -e is required, not stylistic: these patterns can begin with "-" (the private-key
  # header does), and grep would otherwise parse the pattern as a bundle of options,
  # fail, and report "no match" - a screen that silently never fires.
  named=""
  if printf '%s' "$p" | grep -Eqi -e "$SECRET_NAME_RE"; then
    named=1
    SECRETS_JSON="${SECRETS_JSON},{\"path\":$(jstr "$p"),\"reason\":\"filename\"}"
  fi
  if printf '%s' "$p" | grep -Eq -e "$JUNK_RE"; then
    JUNK_JSON="${JUNK_JSON},$(jstr "$p")"
  fi
  if [ -f "$full" ]; then
    sz=$(file_size "$full")
    if [ "$sz" -gt "$LARGE_FILE_BYTES" ] 2>/dev/null; then
      LARGE_JSON="${LARGE_JSON},{\"path\":$(jstr "$p"),\"bytes\":${sz}}"
    fi
    # Skip the content scan when the name already flagged it - one finding per path
    # keeps the report actionable.
    if [ -z "$named" ] && [ "$sz" -le "$SCAN_MAX_BYTES" ] 2>/dev/null && [ "$sz" -gt 0 ] 2>/dev/null; then
      # -I skips binaries; a match on a compiled blob is noise, not a credential.
      if grep -I -Eq -e "$SECRET_CONTENT_RE" "$full" 2>/dev/null; then
        SECRETS_JSON="${SECRETS_JSON},{\"path\":$(jstr "$p"),\"reason\":\"content\"}"
      fi
    fi
  fi
done <<EOF
$SCREEN_LIST
EOF

# Tracked files matching an ignore rule were force-added on purpose. A mixed reset
# drops them silently, so the caller has to know they exist before re-staging.
FORCED_JSON=""
while IFS= read -r p; do
  [ -z "$p" ] && continue
  FORCED_JSON="${FORCED_JSON},$(jstr "$p")"
done < <(git ls-files -i -c --exclude-standard 2>/dev/null)

SECRETS_JSON="[${SECRETS_JSON#,}]"
LARGE_JSON="[${LARGE_JSON#,}]"
JUNK_JSON="[${JUNK_JSON#,}]"
FORCED_JSON="[${FORCED_JSON#,}]"

# ------------------------------------------------------------------- config ---
#
# The repo's own tooling outranks any built-in default: its commit-msg hook is what
# actually accepts or rejects the message.

first_existing() {
  local f
  for f in "$@"; do
    [ -e "$TOPLEVEL/$f" ] && { printf '%s' "$f"; return 0; }
  done
  return 1
}

COMMITLINT=$(first_existing \
  commitlint.config.js commitlint.config.cjs commitlint.config.mjs \
  commitlint.config.ts commitlint.config.cts commitlint.config.mts \
  .commitlintrc .commitlintrc.json .commitlintrc.yaml .commitlintrc.yml \
  .commitlintrc.js .commitlintrc.cjs .commitlintrc.mjs \
  .commitlintrc.ts .commitlintrc.cts .commitlintrc.mts || true)
if [ -z "$COMMITLINT" ] && [ -f "$TOPLEVEL/package.json" ]; then
  grep -q '"commitlint"[[:space:]]*:' "$TOPLEVEL/package.json" 2>/dev/null && COMMITLINT="package.json#commitlint"
fi

CZ=$(first_existing .czrc .cz.json cz.config.js cz.config.cjs cz.config.mjs cz.config.ts || true)
CHANGESETS=$(first_existing .changeset/config.json || true)
RELEASE_PLEASE=$(first_existing release-please-config.json .release-please-manifest.json || true)
SEMANTIC_RELEASE=$(first_existing .releaserc .releaserc.json .releaserc.yaml .releaserc.yml \
  .releaserc.js .releaserc.cjs .releaserc.mjs .releaserc.ts \
  release.config.js release.config.cjs release.config.mjs release.config.ts || true)
if [ -z "$SEMANTIC_RELEASE" ] && [ -f "$TOPLEVEL/package.json" ]; then
  grep -q '"release"[[:space:]]*:' "$TOPLEVEL/package.json" 2>/dev/null && SEMANTIC_RELEASE="package.json#release"
fi
VERSIONRC=$(first_existing .versionrc .versionrc.json .versionrc.js .versionrc.cjs .versionrc.mjs || true)
CLIFF=$(first_existing cliff.toml .cliff.toml .config/cliff.toml || true)
NX=$(first_existing nx.json || true)
LERNA=$(first_existing lerna.json || true)
GITMESSAGE=$(first_existing .gitmessage .gitmessage.txt .github/.gitmessage.txt .git-commit-template || true)
CONTRIBUTING=$(first_existing CONTRIBUTING.md .github/CONTRIBUTING.md docs/CONTRIBUTING.md || true)
GITMOJI=$(first_existing .gitmojirc.json || true)
HUSKY=$(first_existing .husky || true)
LEFTHOOK=$(first_existing lefthook.yml lefthook.yaml lefthook.json lefthook.toml .lefthook.yml .lefthook.yaml || true)
PRECOMMIT=$(first_existing .pre-commit-config.yaml || true)
LINTSTAGED=$(first_existing .lintstagedrc .lintstagedrc.json .lintstagedrc.js lint-staged.config.js || true)
if [ -z "$LINTSTAGED" ] && [ -f "$TOPLEVEL/package.json" ]; then
  grep -q '"lint-staged"[[:space:]]*:' "$TOPLEVEL/package.json" 2>/dev/null && LINTSTAGED="package.json#lint-staged"
fi

jopt() { if [ -n "$1" ]; then jstr "$1"; else printf 'null'; fi; }

# ------------------------------------------------------------------ history ---

SUBJECTS_JSON=""
SCOPES_JSON=""
if [ -z "$UNBORN" ]; then
  n=0
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    n=$((n + 1))
    [ "$n" -le 20 ] && SUBJECTS_JSON="${SUBJECTS_JSON},$(jstr "$s")"
  done < <(git log --no-merges --pretty=%s -n "$HISTORY_DEPTH" 2>/dev/null)

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    cnt=${line%% *}
    sc=${line#* }
    SCOPES_JSON="${SCOPES_JSON},{\"scope\":$(jstr "$sc"),\"count\":${cnt}}"
  done < <(git log --no-merges --pretty=%s -n "$HISTORY_DEPTH" 2>/dev/null \
    | sed -nE 's/^[a-zA-Z]+\(([^)]+)\)!?:.*/\1/p' | sort | uniq -c | sort -rn | head -15 | sed 's/^ *//')
fi
SUBJECTS_JSON="[${SUBJECTS_JSON#,}]"
SCOPES_JSON="[${SCOPES_JSON#,}]"

# ------------------------------------------------------------------- output ---

cat <<JSON
{
  "is_repo": true,
  "root": $(jstr "$TOPLEVEL"),
  "head": {
    "unborn": $(jbool "$UNBORN"),
    "detached": $(jbool "$DETACHED"),
    "branch": $(jopt "$BRANCH"),
    "default_branch": $(jopt "$DEFAULT_BRANCH"),
    "protected": $(jbool "$PROTECTED"),
    "upstream": $(jopt "$UPSTREAM"),
    "ahead": ${AHEAD:-0},
    "behind": ${BEHIND:-0}
  },
  "in_progress": {
    "any": $(jbool "$IN_PROGRESS"),
    "merge": $(jbool "$MERGE"),
    "rebase": $(jbool "$REBASE"),
    "cherry_pick": $(jbool "$CHERRY"),
    "revert": $(jbool "$REVERT"),
    "bisect": $(jbool "$BISECT")
  },
  "counts": {
    "staged": ${STAGED_COUNT},
    "unstaged": ${UNSTAGED_COUNT},
    "untracked": ${UNTRACKED_COUNT},
    "conflicted": ${CONFLICT_COUNT}
  },
  "files": ${FILES_JSON},
  "partially_staged": ${PARTIAL_JSON},
  "numstat": { "staged": ${NUMSTAT_STAGED}, "unstaged": ${NUMSTAT_UNSTAGED} },
  "screens": {
    "secrets": ${SECRETS_JSON},
    "large_files": ${LARGE_JSON},
    "junk": ${JUNK_JSON},
    "force_added_ignored": ${FORCED_JSON}
  },
  "git_config": {
    "gpgsign": $(jopt "$GPGSIGN"),
    "gpg_format": $(jopt "$GPGFORMAT"),
    "signingkey": $(jopt "$SIGNINGKEY"),
    "hooks_path": $(jopt "$HOOKSPATH"),
    "commit_template": $(jopt "$COMMIT_TEMPLATE"),
    "comment_char": $(jstr "$COMMENT_CHAR")
  },
  "conventions": {
    "commitlint": $(jopt "$COMMITLINT"),
    "commitizen": $(jopt "$CZ"),
    "gitmoji": $(jopt "$GITMOJI"),
    "gitmessage": $(jopt "$GITMESSAGE"),
    "contributing": $(jopt "$CONTRIBUTING")
  },
  "release_tooling": {
    "changesets": $(jopt "$CHANGESETS"),
    "release_please": $(jopt "$RELEASE_PLEASE"),
    "semantic_release": $(jopt "$SEMANTIC_RELEASE"),
    "standard_version": $(jopt "$VERSIONRC"),
    "git_cliff": $(jopt "$CLIFF"),
    "nx": $(jopt "$NX"),
    "lerna": $(jopt "$LERNA")
  },
  "hook_runners": {
    "husky": $(jopt "$HUSKY"),
    "lefthook": $(jopt "$LEFTHOOK"),
    "pre_commit": $(jopt "$PRECOMMIT"),
    "lint_staged": $(jopt "$LINTSTAGED")
  },
  "history": { "recent_subjects": ${SUBJECTS_JSON}, "top_scopes": ${SCOPES_JSON} }
}
JSON
