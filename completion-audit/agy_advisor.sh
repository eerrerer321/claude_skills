#!/usr/bin/env bash
# agy_advisor.sh — invoke Antigravity CLI (Gemini, headless) as an audit advisor and print
# ONLY the model's final text answer to stdout.
#
# Requires Antigravity CLI >= 1.1.8. That version's `agy -p ... --output-format json </dev/null`
# writes a clean JSON blob straight to stdout and exits cleanly on its own (verified 2026-07-29:
# no hang, no truncation, works with stdin closed). Older builds (<=1.0.13) had a real bug where
# the answer never reached stdout in a headless shell and stdin EOF truncated the stream instead —
# if you're pinned to an old build, see git history for the transcript.jsonl-scraping version.
#
# !!! STILL NOT READ-ONLY — DO NOT TRUST THIS PROCESS WITH A LIVE REPO !!!
# In headless -p mode agy auto-grants itself ALL permissions (no human to approve prompts).
# VERIFIED on 1.1.8 (2026-07-29): asked to "create AGY_TEST_WRITE.txt", it did so via its
# CODE_ACTION tool with no permission prompt. Relative write paths resolve to agy's own
# ~/.gemini/antigravity-cli/scratch dir (NOT a safety boundary — it reads/writes ABSOLUTE paths
# it discovers while exploring, so a path inside a live repo is reachable). Safety is by
# ISOLATION only, enforced by the CALLER:
#   * Seeding scan (agy explores the tree) -> pass a DISPOSABLE COPY as <repo-abs-path>, never the
#     live working tree.
#   * Per-fix call -> the prompt must say "do not use tools/files/commands; answer only from the
#     snippet", so it has nothing to act on.
# Treat its output as advice; only Opus edits the real repo.
#
# Usage:  agy_advisor.sh <repo-abs-path> <prompt-file> [wait-seconds]
#   prints the model answer to stdout; diagnostics to stderr; nonzero exit on failure.

set -u
# Portable: derive from $HOME so the skill works under any Windows username.
AGY_BIN="${AGY_BIN_DIR:-$HOME/AppData/Local/agy/bin}"
export PATH="$PATH:$AGY_BIN"

REPO="${1:?usage: agy_advisor.sh <repo-abs-path> <prompt-file> [wait-seconds]}"
PROMPT_FILE="${2:?need a prompt file}"
WAIT="${3:-60}"

[ -x "$AGY_BIN/agy.exe" ] || { echo "agy.exe not found at $AGY_BIN" >&2; exit 3; }
[ -f "$PROMPT_FILE" ]     || { echo "prompt file not found: $PROMPT_FILE" >&2; exit 3; }

PROMPT="$(cat "$PROMPT_FILE")"
echo "[agy_advisor] cwd=$REPO wait=${WAIT}s prompt=${#PROMPT} chars" >&2

# prompt passed via env to avoid quoting/escaping issues with code excerpts
export AGY_PROMPT="$PROMPT"
RAW="$(cd "$REPO" && timeout $((WAIT+30)) agy -p "$AGY_PROMPT" --model gemini-3.7-flash-high \
    --output-format json --print-timeout "${WAIT}s" </dev/null)"
RC=$?

if [ $RC -ne 0 ] || [ -z "$RAW" ]; then
    echo "[agy_advisor] agy exited rc=$RC with no output (hang, crash, or timed out — safe to retry once with a larger wait-seconds)" >&2
    exit 4
fi

# extract the "response" field from the single JSON object agy printed.
# (RAW goes through a temp file, not a pipe: `python -` already uses stdin for the heredoc
# script source, so piping data into the same stdin would just get eaten by that.)
RAW_FILE="$(mktemp)"
printf '%s' "$RAW" > "$RAW_FILE"

PYTHONIOENCODING=utf-8 python - "$RAW_FILE" <<'PY'
import json, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
    raw = f.read()
try:
    o = json.loads(raw)
except Exception as e:
    sys.stderr.write(f"[agy_advisor] could not parse agy output as JSON: {e}\n")
    sys.exit(5)
if o.get("status") != "SUCCESS":
    sys.stderr.write(f"[agy_advisor] agy status={o.get('status')!r} (not SUCCESS)\n")
    sys.exit(6)
resp = o.get("response", "")
if not resp.strip():
    sys.stderr.write("[agy_advisor] empty response field\n")
    sys.exit(5)
print(resp)
PY
PY_RC=$?
rm -f "$RAW_FILE"
exit $PY_RC
