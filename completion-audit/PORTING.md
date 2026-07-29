# Porting the `completion-audit` skill to another computer

This skill is a **chair + four-advisor council**. The chair (Opus, in Claude Code) does all
editing; four external CLIs give read-only second opinions:

| Advisor | CLI | Model |
|---|---|---|
| A | `codex` | GPT-5.6 terra |
| B | `opencode` | DeepSeek-V4-Flash (`audit-advisor` agent) |
| C | `agy` (Antigravity CLI) | Gemini 3.6 Flash (High) |
| D | `grok` | Grok 4.5 |

Moving the skill = **copy 3 files** + **install & log in to 4 CLIs** + **2 runtime prereqs**.
Copying files alone is NOT enough — the CLIs carry their own auth and cannot be copied.

Not every advisor runs every time: the skill asks the owner up front which models still have quota
that day. C and D are the rationed ones — see "Picking who to call" in `SKILL.md`.

`~` below means the new machine's home dir: `C:\Users\<username>\` (in Git Bash: `/c/Users/<username>`).

---

## 1. Files to copy (keep the SAME relative paths)

| Copy from (this machine) | To (new machine) |
|---|---|
| `~\.claude\skills\completion-audit\SKILL.md` | same path |
| `~\.claude\skills\completion-audit\agy_advisor.sh` | same path |
| `~\.config\opencode\agent\audit-advisor.md` | same path |

Easiest: copy the whole `~\.claude\skills\completion-audit\` folder (contains `SKILL.md`,
`agy_advisor.sh`, and this `PORTING.md`), then separately copy the one opencode agent file.

- `codex` and `grok` need **no** config file — both are driven entirely by inline flags.
- `agy_advisor.sh` derives all paths from `$HOME`, so a different Windows username is fine. It does
  NOT contain any machine-specific hardcoding anymore.
- **Line endings:** keep `agy_advisor.sh` as **LF** (not CRLF) or the `#!/usr/bin/env bash` shebang
  can break. Copying via `git` preserves this; copying via a Windows editor may not.

---

## 2. CLIs to install + authenticate (cannot be copied)

| CLI | Install | Auth on the new machine |
|---|---|---|
| **codex** (GPT-5.6 terra) | npm global (`npm i -g …`); ends up on PATH e.g. `~\AppData\Roaming\npm\codex` | log in to OpenAI/codex |
| **opencode** (DeepSeek) | npm global; PATH e.g. `~\AppData\Roaming\npm\opencode` | log in; model `opencode/deepseek-v4-flash-free` (pinned in the agent file) |
| **agy** (Gemini) | Antigravity CLI installer → installs to `~\AppData\Local\agy\bin\agy.exe` | **run `agy` once interactively** to do Google OAuth, then set model to **`Gemini 3.6 Flash (High)`** (the wrapper passes `--model gemini-3.6-flash-high` explicitly) |
| **grok** (Grok 4.5) | xAI's own installer — a self-updating standalone binary at `~\.grok\bin\grok.exe` (`installer = "internal"`, `auto_update = true` in `~\.grok\config.toml`); it puts itself on PATH. **Not** npm | `grok login` (or run `grok` once interactively). Credentials land in `~\.grok\auth.json` — **don't copy that file, log in on the new machine** |

After installing, confirm each is reachable (Git Bash):
```bash
command -v codex; command -v opencode; command -v grok
ls "$HOME/AppData/Local/agy/bin/agy.exe"
```

---

## 3. Runtime prerequisites

- **Git Bash** — the skill calls the wrapper via `bash agy_advisor.sh`.
- **Python 3** on PATH — the wrapper uses it to parse agy's JSON output.

```bash
bash --version | head -1
python --version
```

---

## 4. agy specifics (the hard-won parts — already handled by the wrapper)

**The wrapper requires Antigravity CLI >= 1.1.8** (`agy --version`). Check this first: the two
stdout/stdin bugs it used to work around were fixed in 1.1.8, and the current wrapper depends on
the fixed behavior. If you land on an older build, upgrade the CLI — the wrapper no longer carries
the old transcript-scraping fallback.

`agy` is still a Bubble Tea **TUI** and a full autonomous agent, so it needs a thin wrapper — but
on 1.1.8 (verified 2026-07-29) only one trap is left:

1. **Headless output works now.** `agy -p "<prompt>" --output-format json </dev/null` prints one
   JSON object (`{"status":"SUCCESS","response":"…"}`) to stdout and exits on its own. `</dev/null`
   no longer truncates the answer, and there is no more scraping of
   `~/.gemini/antigravity-cli/brain/<conv-id>/.system_generated/logs/transcript.jsonl`. The wrapper
   just parses the `response` field. `<wait>` is passed to agy as `--print-timeout <wait>s` and also
   used for an outer `timeout <wait+30>` kill switch — budget tool-free per-fix prompt ≈ 40 s,
   agentic seeding scan **~300 s+** (run in background; the Bash tool caps foreground at 120 s).
2. **It is agentic and auto-permissioned.** In `-p` mode agy auto-grants itself every permission
   (`command(*): allowed`, file edit) and WILL run shell/git unprompted. **There is no read-only
   flag.** Safety is by isolation only: seeding scans run against a **disposable copy** of the repo;
   per-fix prompts say "do not use tools/files/commands — answer only from the snippet."

**Env override** (only if agy was installed somewhere non-default):
```bash
export AGY_BIN_DIR="/c/custom/path/agy/bin"          # dir containing agy.exe
```

---

## 5. grok specifics (no wrapper — containment comes from `--tools` + `--cwd` + the prompt)

`grok` is headless-friendly out of the box, so it needs no wrapper. It has no `--pure` equivalent,
but it **does** have a real tool filter (`--tools`), so containment = that flag + a disposable
`--cwd`. Verified 2026-07-27/28, plus a 6-call `--tools` test on 2026-07-29 (CLI 0.2.112):

1. **Always single-turn from a file.** Bare `grok` opens an interactive TUI. Use `--prompt-file`
   (preferred over inline `-p/--single`: no shell-quoting breakage on code excerpts, no "Argument
   list too long"), and keep `< /dev/null`.
2. **`grok models` prints "You are not authenticated." even when calls succeed.** Ignore it — don't
   treat it as a blocker and don't try to log in again.
3. **`--sandbox <PROFILE>` is NOT a safety boundary.** An invalid profile name is accepted silently
   instead of erroring, so you can't rely on it. Contain it the same way as agy: pin `--cwd` to a
   **disposable bundle dir** holding only the changeset text.
4. **⚠️ It wanders off to read the skill directory** — exactly like opencode without `--pure`, and
   there is no `--pure` for grok. Told to review a file in the bundle dir, it once emitted only a
   101-byte preamble and exited 0, having gone looking for the audit *skill* instead.
   **Fix: inline the code into the prompt file and forbid tools** (and back it with `--tools`, next).
5. **`--tools` IS a real boundary — always pass it.** The README says the flag is `-p`-only, but it
   works with `--prompt-file` too. Proven by test: without it, "run `echo … > f.txt`" created the
   file; with `--tools "read_file"` the file was **not** created and grok said it had no shell — while
   still reading and correctly reviewing a file in the bundle dir.
6. **⚠️ `--tools ""` is a silent no-op.** An empty allowlist = *no filter*; grok then listed all **26**
   of its tools. To get near-tool-free, pass a minimal allowlist (`--tools "read_file"`), never `""`.
7. **Prefer an allowlist over a denylist.** The README's tool-ID table lists 9 IDs; the live agent has
   26 (incl. `spawn_subagent`, `write`, `workflow`, `scheduler_*`, `image_*`), and the shell tool is
   really `run_terminal_command` — the README's `run_terminal_cmd` still works as an alias, but a
   denylist fails **open** on any name you get wrong, while an allowlist fails **closed**.
8. **`search_tool` / `use_tool` survive any allowlist — inert today.** They resolve **MCP** tools only,
   and `grok mcp list` reports none configured. **If you ever add an MCP server to grok, re-test:**
   that would be a hole in `--tools`.

The invocation the skill uses:
```bash
cd <bundle-dir> && "$HOME/.grok/bin/grok.exe" \
  --cwd <bundle-dir> --prompt-file <bundle-dir>/PROMPT.md \
  --tools "read_file" \
  --reasoning-effort high --output-format plain < /dev/null > <tmp/grok.md> 2>&1
```

---

## 6. Validate each advisor on the new machine

Run these from Git Bash after install + login. Each should print a real answer.

**codex (GPT-5.6 terra):**
```bash
codex exec -m gpt-5.6-terra -c model_reasoning_effort="xhigh" -s read-only "Reply with exactly: CODEX_OK" < /dev/null
```

**opencode (DeepSeek, read-only agent):**
```bash
opencode run --pure --agent audit-advisor --variant max "Reply with exactly: OPENCODE_OK"
```

**agy (Gemini 3.6 Flash High) — via the wrapper:**
```bash
printf '%s\n' 'Do NOT use any tools/files/commands. Reply with exactly: AGY_OK' > /tmp/agy_smoke.txt
bash ~/.claude/skills/completion-audit/agy_advisor.sh "$(pwd)" /tmp/agy_smoke.txt 40
```
Expect `AGY_OK` within a few seconds on CLI 1.1.8. If the wrapper exits non-zero it prints a
one-line reason to stderr (no output/timed out, unparseable JSON, or `status != SUCCESS`) — re-run
once with a larger wait (e.g. `… 60`).

**grok (Grok 4.5):** *(costs quota — this one is metered, keep the smoke test to one line)*
```bash
printf '%s\n' 'Do not use any tools or read any files. Reply with exactly: GROK_OK' > /tmp/grok_smoke.md
grok --prompt-file /tmp/grok_smoke.md --output-format plain < /dev/null
```

---

## 7. Troubleshooting (symptoms seen during setup)

| Symptom | Cause | Fix |
|---|---|---|
| `agy: command not found` in a script | agy's bin dir not on PATH in non-interactive shells | wrapper adds it from `$HOME/AppData/Local/agy/bin`; if installed elsewhere set `AGY_BIN_DIR` |
| agy call hangs forever / empty answer with `</dev/null` | Antigravity CLI older than 1.1.8 (pre-fix stdout+stdin bugs) | check `agy --version`; upgrade to >= 1.1.8 (the wrapper has no fallback for older builds) |
| bare `agy "prompt"` opens a TUI or blocks | not the headless form | always go through the wrapper (`-p … --output-format json </dev/null`) |
| wrapper: `agy exited rc=… with no output` | agentic loop didn't finish within `<wait>`, or agy crashed | increase wait-seconds (per-fix tool-free ~40 s; seeding ~300 s+ in background); never use a partial result |
| wrapper: `could not parse agy output as JSON` / `status=… (not SUCCESS)` | agy errored (quota, auth) or changed its output shape | read the raw run manually: `agy -p "hi" --output-format json </dev/null` |
| agy ran git/PowerShell, or created/edited a file | `-p` auto-grants ALL permissions; **verified** agy writes files via `CODE_ACTION` and runs `RUN_COMMAND` with no prompt | expected — agy is NOT read-only; only ever point it at a **disposable copy** for seeding |
| agy "scanned" but found nothing / listed an empty dir | `-p` ignores the shell cwd; `cd "$REPO"` does not root it | **name the absolute path to scan inside the prompt** ("Audit the repo at `C:\…\copy`"); don't rely on cwd |
| agy created a file but it's not in the repo dir | `-p` resolves **relative** write paths to `~/.gemini/antigravity-cli/scratch`, not cwd | not a safety boundary — agy can still write **absolute** paths it discovers; rely on the disposable copy, not on this |
| `You are not logged into Antigravity` | OAuth token missing/expired on this machine | run `agy` interactively once to re-login |
| opencode recurses / hangs, spawns subagents | `--pure` omitted → it auto-loaded the skill | always pass `--pure --agent audit-advisor` |
| opencode continue uses wrong (write) agent | `--continue`/`--session` silently revert to `build` | always re-pass `--pure --agent audit-advisor` when continuing |
| codex hangs at "Reading additional input from stdin" | background codex reads stdin with no EOF | always append `< /dev/null` |
| grok opens a TUI / never returns | no `--prompt-file` / `-p`, or no stdin redirect | always single-turn: `--prompt-file <file> … < /dev/null` |
| grok returns ~100 bytes of preamble, exit 0 | it went off to read the skill directory (no `--pure` equivalent exists) | inline the code into the prompt file and forbid tools — never point it at a file to read |
| `grok models` → "You are not authenticated." but calls work | known cosmetic bug | ignore it; do not re-login |
