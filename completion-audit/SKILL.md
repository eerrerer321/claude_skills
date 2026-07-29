---
name: completion-audit
description: >-
  Run a bounded, self-iterating "completion / launch-readiness audit" loop on a software project:
  systematically hunt down and fix the gaps that keep a system from being production-ready — dead
  buttons, fake/illusion pages backed by mock data, stub service methods, frontend↔backend wiring
  mismatches, and missing steps in each user role's core flows. Use this whenever the user asks to
  "audit the project for completeness", "find unfinished / half-done features", "check every button
  goes to a real page", "push this toward launchable quality", "run the completion loop / 補全循環 /
  稽核循環", or asks for a multi-hour self-improving pass over a codebase — even across different
  projects. Sets up a time-boxed recurring schedule, rotates through every user role, and runs a
  MANDATORY multi-advisor AI deliberation each iteration: Opus chairs and implements, while a
  roster of advisors — GPT-5.6 terra (via codex), DeepSeek-V4-Flash (via opencode), Grok 4.5 (via
  the `grok` CLI), and Gemini 3.6 Flash (via the Antigravity `agy` CLI) — give independent opinions
  that Opus synthesizes and decides on. Asks the owner up front which advisors still have quota,
  then spends the rationed ones where coverage is thinnest.
---

# Completion / Launch-Readiness Audit Loop (multi-advisor AI council)

This skill drives a project toward **launchable quality** by iterating: each cycle finds one
genuine completeness gap and fixes it properly, rotating through every user role, until the
time-box ends. It is the opposite of a one-shot review — the value is in the loop.

Every iteration runs a **multi-advisor AI deliberation** (chair + the advisors you selected) before the fix
is decided. You (Opus) are the **chair**: you frame the problem, collect independent opinions
from the advisors, synthesize them, resolve disagreements, make the final call, and do all the
actual editing and verifying yourself. The advisors advise; they never touch the real repo.

The user invokes this roughly weekly, for a few hours, on whatever project they point you at.
Nothing here is project-specific: detect the stack from the repo and adapt.

## The AI council — roles & tooling (prerequisites)

| Role | Who | How it's invoked | Can edit repo? |
|------|-----|------------------|----------------|
| **Chair / implementer / decider** | **Opus (you)** | this session | **Yes — the only one** |
| Advisor A | **GPT-5.6 terra** | `codex` CLI, read-only | No (read-only flag) |
| Advisor B | **DeepSeek-V4-Flash** | `opencode` CLI, read-only `audit-advisor` agent | No (locked-down agent) |
| Advisor C | **Gemini 3.6 Flash (High)** | Antigravity `agy -p`, headless, via `agy_advisor.sh` | No — **only** because it runs against a disposable copy / tool-free prompt (see warning) |
| Advisor D | **Grok 4.5** | `grok --prompt-file`, headless single-turn | No — **only** because cwd is pinned to a disposable bundle dir (see below) |

### ⚠️ FIRST STEP OF EVERY RUN — ask the owner which advisors are usable today

**Before invoking any advisor, ask the owner which models currently have quota.** Several of these
are free-but-metered and rotate through exhaustion; probing a dead one burns wall-clock on a call
that returns a quota error. One short question up front (offer the roster, let them deselect) saves
that. *(Owner instruction, 2026-07-27.)* Skip the question only if the owner already said in this
session who to use.

### Picking who to call (quota discipline — owner's standing guidance)

| Advisor | Cost profile | Use it for |
|---|---|---|
| **DeepSeek** | Free, generous → **use liberally** | Broad sweeps, every round, both areas. False positives are fine — the chair verifies anyway. Weakest at contract/route claims: when it can't see the definition it guesses from naming and still asserts "Critical". |
| **GPT-5.6 terra** | **Subscribed — quota is ample → use it freely** *(owner, 2026-07-27)* | Cross-file consistency, state-machine guards, "is this coherent with the rest of the system". **Highest hit-rate of the roster** — it repeatedly caught regressions the chair introduced. Call it on every area, and again after implementing (post-fix review). Don't artificially limit to one call. |
| **Grok 4.5** | **Free but low quota → ration like GPT** | Self-contained logic/contract questions (arithmetic limits, timezone math, single-file concurrency). One call, aimed at whichever area has the least existing coverage. |
| **Gemini (agy)** | Free, but agentic & unsafe by construction | Breadth on a **disposable copy** only. Heaviest setup cost. |

**Overlap is valuable where it matters** — when two advisors independently converge on the same
finding, that is the strongest signal available (verified 2026-07-27: GPT and DeepSeek
independently caught the same unwired-code P1).

Practical default: **GPT + DeepSeek on everything** (both are cheap for this owner — GPT is
subscribed, DeepSeek is free), then spend the genuinely rationed ones (**Grok**, and **Gemini**
which also carries the disposable-copy setup cost) on whichever area has the thinnest coverage.

**⚠️ Advisor C is NOT read-only by construction — it is a full autonomous coding agent.** Unlike
codex (`-s read-only`) and opencode (tool-disabled `audit-advisor`), `agy` in headless `-p` mode
**auto-grants itself every permission** because non-interactive mode has no human to approve
prompts. There is no read-only flag. Both write paths are **empirically verified** on this machine:
it ran PowerShell + `git` (`RUN_COMMAND`) while answering a trivial audit question, and when told to
"create AGENT_WROTE_HERE.txt" it created the file via its `CODE_ACTION` tool with **no prompt**.
Its safety therefore comes from **physical isolation**, not a setting:
- **Seeding scan** (agy explores the tree) → point `agy` at a **disposable copy** of the repo (the
  sanitized copy the skill already builds, or a throwaway `git worktree`/copy), never the live repo.
  Any command/edit it runs then hits the copy; the real repo is safe by construction.
  *(Note: `-p` mode resolves **relative** write paths to agy's own `~/.gemini/antigravity-cli/scratch`
  dir, not the shell cwd — do NOT mistake that for a safety boundary: agy reads and writes **absolute**
  paths it discovers while exploring, so any path inside a live repo is reachable. Isolation is the
  only guarantee.)*
- **Per-fix deliberation** (code is pasted into the prompt) → instruct agy **"do not use any tools,
  files, or commands — answer only from the snippet below."** With nothing to act on it stays a
  one-shot reasoner. (Validated: tool-free SQL-injection prompt returned a correct one-shot answer.)

#### Verified agy behavior — 2026-06-30 (CLI 1.0.13), re-verified 2026-07-29 (CLI 1.1.8)

These were established by direct test in an isolated throwaway dir; trust them, don't re-burn quota:

1. **It writes, unprompted.** Told "create a file", agy did so via its `CODE_ACTION` tool with no
   permission prompt; it also runs arbitrary `RUN_COMMAND` (PowerShell/git). Definitively **not
   read-only**. → isolation (disposable copy) is the only safety boundary. Re-confirmed on 1.1.8.
2. **`-p` ignores the shell cwd.** The wrapper's `cd "$REPO"` does NOT root agy there: a relative
   write still lands in `~/.gemini/antigravity-cli/scratch`, not the passed dir. agy finds its
   target by *exploring* (runs `pwd`/`ls`, then uses absolute paths). **Consequence — for a seeding
   scan you MUST name the absolute path to scan inside the prompt** (e.g. "Audit the repository at
   `C:\…\copy`"), or agy may scan the wrong place. Relative paths are NOT a containment boundary
   (point 1).
3. **Fixed on 1.1.8 — clean "done" signal, no more stdin/stdout traps.** On 1.0.13, `-p` had no
   headless stdout and no clean exit signal, which forced the wrapper to hold stdin open with a
   guessed `sleep` and scrape the answer out of `transcript.jsonl`. **On 1.1.8, `agy -p ...
   --output-format json </dev/null` writes a single JSON object straight to stdout and exits on its
   own** (verified: trivial prompts return in ~2s with `status:"SUCCESS"`; a file-write task
   completed the same way). The wrapper now reads that JSON directly — see `agy_advisor.sh`. What's
   *not* re-verified: behavior when a genuinely long agentic run hits `--print-timeout` mid-flight.
   Keep budgeting generously (`wait-seconds` ~40 for tool-free per-fix prompts, ~300+ for agentic
   seeding scans) until that edge is actually observed.

Exact commands (codex/opencode are read-only by construction; agy is contained by isolation):

- **GPT-5.6 terra (codex):**
  ```
  codex exec -m gpt-5.6-terra -c model_reasoning_effort="xhigh" -s read-only [--skip-git-repo-check] \
    -C <repo-abs-path> -o <tmp/gpt.md> "<prompt>" < /dev/null
  ```
  Use `model_reasoning_effort="xhigh"` for the heavy whole-repo seeding scan; you may drop to
  `"high"` for scoped per-fix deliberations to control credit spend. **Add `--skip-git-repo-check`
  whenever `-C` points at a non-git directory** (e.g. the sanitized copy below) — codex otherwise
  refuses to run outside a trusted/git dir. **Always redirect `< /dev/null`** (as shown): `codex
  exec` also reads stdin, and when launched in the background it can hang indefinitely at
  `Reading additional input from stdin...` on a pipe that never EOFs. (Verified: a per-fix call
  hung ~30 min at ~0% CPU until killed.)

- **DeepSeek-V4-Flash (opencode):**
  ```
  opencode run --pure --agent audit-advisor --variant max --dir <repo-abs-path> "<prompt>" > <tmp/deepseek.md> 2>&1
  ```
  The `audit-advisor` agent (at `~/.config/opencode/agent/audit-advisor.md`) pins the model to
  `opencode/deepseek-v4-flash-free`, **disables write/edit/patch/bash AND task/todo** while keeping
  read/grep/glob — so it scans independently but can never change the code or spawn subagents.
  `--variant max` is the "思考max" (max reasoning) setting. **`--pure` is REQUIRED**: without it,
  opencode auto-loads skills it finds in `~/.claude/skills` (including this very `completion-audit`
  skill) and the advisor recurses into *running the audit itself* (spawning Explore subagents)
  instead of giving a one-shot opinion — it hangs. `--pure` + the disabled `task` tool keep it a
  single-shot read-only advisor. (Verified: this exact failure happened on first run.)

- **Gemini 3.6 Flash (Antigravity `agy`):** invoke via the wrapper, never raw:
  ```
  bash ~/.claude/skills/completion-audit/agy_advisor.sh <repo-or-disposable-copy-abs-path> <prompt-file> [wait-seconds]
  ```
  `agy` is a Bubble Tea **TUI** app, not a scripting-first CLI, so it still needs a thin wrapper —
  but as of Antigravity CLI **1.1.8** (re-verified 2026-07-29), the two nastiest traps from 1.0.13
  are gone:
  1. **Headless stdout now works.** `agy -p "<prompt>" --output-format json </dev/null` writes a
     single JSON object (`{"status":"SUCCESS","response":"…",...}`) straight to stdout and exits on
     its own — no more rendering-through-a-TTY bug, no more scraping
     `~/.gemini/antigravity-cli/brain/<conv-id>/.system_generated/logs/transcript.jsonl`. The
     wrapper just parses that JSON's `response` field.
  2. **stdin EOF no longer truncates.** `</dev/null` used to kill the in-flight response early; on
     1.1.8 it doesn't — agy runs to completion and exits cleanly. `--print-timeout <wait-seconds>s`
     is agy's own internal wall-clock cap (default 5m); the wrapper also wraps the call in an outer
     `timeout $((wait-seconds+30))` as a belt-and-suspenders kill switch. Budget the same as before:
     tool-free per-fix prompt → `~40s`; agentic seeding scan → run it **`run_in_background: true`**
     (the Bash tool caps foreground at 120s) with `wait-seconds` **~300+** (not re-verified against
     the new timeout behavior — keep the generous budget until proven otherwise).
  3. **It is still agentic and auto-permissioned** (see warning above — unchanged on 1.1.8). For
     per-fix calls, the prompt MUST say "do not use tools/files/commands — answer only from the
     snippet"; for seeding, the `<repo-path>` you pass MUST be a disposable copy, not the live repo.
  Pass the prompt in a **file** (arg 2), not inline — code excerpts break shell quoting; the
  wrapper feeds it to agy via an env var. If the wrapper exits non-zero (it prints a one-line
  reason to stderr — no output/timeout, unparseable JSON, or `status != SUCCESS`), that is a real
  failure signal: re-run **once** with a larger `wait-seconds`.

- **Grok 4.5 (`grok` CLI):** binary at `C:\Users\User\.grok\bin\grok.exe` (also on PATH as `grok`).
  Default model `grok-4.5`.
  ```
  cd <bundle-dir> && "C:/Users/User/.grok/bin/grok.exe" \
    --cwd <bundle-dir> --prompt-file <bundle-dir>/PROMPT.md \
    --tools "read_file" \
    --reasoning-effort high --output-format plain < /dev/null > <tmp/grok.md> 2>&1
  ```
  Verified on this machine 2026-07-27 (`--tools` added 2026-07-29) — don't re-learn these:
  1. **`--prompt-file <PATH>` takes the prompt from a file.** Prefer it over inline `-p/--single`:
     no shell-quoting breakage on code excerpts, and no "Argument list too long" (the failure mode
     that bit opencode on a ~42 KB inline prompt).
  2. **`grok models` prints "You are not authenticated." even when calls succeed.** Ignore it —
     a single-turn call right after that message returned a correct answer, exit 0. Do not treat
     it as a blocker or try to log in (never enter credentials).
  3. **`--sandbox <PROFILE>` is not a safety boundary.** An invalid profile name is accepted
     silently rather than erroring, so you cannot rely on it. Safety comes from **pinning `--cwd`
     to a disposable bundle dir in scratchpad** that contains only the changeset text — same
     isolation principle as agy, cheaper to set up.
  4. Bare `grok` opens an interactive TUI — **always** pass `--prompt-file` or `-p`, and keep
     `< /dev/null`.
  5. **⚠️ It wanders into the skills directory, exactly like opencode without `--pure`.** Verified
     2026-07-28: pointed at a bundle dir and told to review `changeset.txt`, it emitted only the
     preamble *"先讀稽核技能與區域 B 的 changeset"* (101 bytes) and exited 0 — it went looking for
     the audit **skill** instead of doing the review. Grok has no `--pure` equivalent.
     **Fix: inline the code into the prompt file and forbid tools**, same shape as the agy per-fix
     rule:
     ```
     { cat PROMPT_B.md; echo; echo "**不要使用任何工具、不要讀取任何檔案、不要執行任何指令。"; \
       echo "所有需要的程式碼都在下方，直接根據它回答。**"; echo '```'; cat changeset_b.txt; echo '```'; \
     } > grokdir/PROMPT.md
     ```
     Re-run this way returned a full, high-quality review immediately. `--prompt-file` has no
     length limit worth worrying about, so inlining is free.
  6. **`--tools` is a REAL boundary — unlike `--sandbox`. Always pass it.** *(Verified 2026-07-29,
     CLI 0.2.112 — 6 direct tests.)* Despite the README saying the flag is "headless (`-p`) only",
     it **does** take effect with `--prompt-file`:
     - Baseline (no flag): told to run `echo … > shell_ran_a.txt`, grok ran it and the file appeared.
     - With `--tools "read_file"`: same prompt → **no file**, and it answered "我沒有 shell 工具".
       In the same call it read `changeset.txt` and correctly found an off-by-one plus a
       divide-by-zero. So a **read-only, file-reading** grok is now possible.
     - So keep rule 5's inlining as the default (it costs nothing), but pass `--tools "read_file"`
       as the hard belt underneath it — and if you *do* need it to read a bundle file, that is now
       safe enough to do deliberately.
  7. **⚠️ `--tools ""` is a silent no-op — never use it to mean "no tools".** An empty allowlist is
     treated as *no filter*: asked to list its tools, grok returned the full set of **26**. To get
     as close to tool-free as the CLI allows, pass a minimal allowlist (`--tools "read_file"`), not
     an empty one.
  8. **The README's tool-ID table is stale/incomplete — prefer an allowlist over a denylist.** It
     documents 9 IDs; the live agent actually has 26, including `spawn_subagent`, `write`,
     `workflow`, `scheduler_*`, `image_*`, and the real shell ID is **`run_terminal_command`**, not
     the README's `run_terminal_cmd` (the old name is still accepted as an alias — `--disallowed-tools
     "run_terminal_cmd"` did remove it — but you cannot count on that for names you guess).
     An allowlist fails **closed** on an unknown name; a denylist fails **open**. Use `--tools`.
  9. **`search_tool` / `use_tool` are always injected on top of your allowlist — currently inert.**
     With `--tools "read_file"` the surviving set was `read_file` + `search_tool` + `use_tool`.
     Told to use those meta-tools to reach a terminal, grok tried and failed: they only resolve
     **MCP** tools, and `grok mcp list` reports none configured. **If an MCP server is ever added to
     grok, re-test this — that would be a hole in the allowlist.**

  **Bundle completeness matters more than you think.** In the same run Grok flagged a possible
  wrong-clock bug in `AutoCompleteService`, correctly hedged as "需人工核對" — because the relevant
  repository method wasn't in the bundle (the chair had sliced the wrong line range). The claim was
  false, but the hedge was right. Slice repository/service excerpts by **symbol**, not line numbers.

  Quality note: given a `EcpayTradeNumber.Create` snippet plus "ECPay caps MerchantTradeNo at 20
  chars", it independently derived that the `SUB` prefix yields 21 chars and would be rejected —
  matching a real bug fixed that day — and flagged that `TX` sits exactly at 20 with no headroom.
  Precise, no filler. Good fit for self-contained logic/contract questions.

### Sensitive repos — scan a sanitized copy, never the secrets

Both advisors **upload the code they see to external services** (codex → OpenAI, opencode →
DeepSeek's servers). Before scanning any repo that may hold secrets (API keys, `.env`, wallet
keys, trading credentials, customer data), get the user's explicit consent, then **point the
advisors at a sanitized copy, not the live repo**: copy only source/docs into a temp dir,
excluding `.env`, `*state*.json`, credentials, caches, and `.git`; grep the copy to confirm no
secret survives; then `-C` / `--dir` that temp dir. Relative `file:line` paths still map 1:1 to
the real repo. This makes leakage *physically impossible* rather than relying on the model to
"not read" a file. (Remember: codex needs `--skip-git-repo-check` for the non-git copy.)

**agy is doubly bound by this.** Gemini/agy uploads to Google AND can run commands / edit files,
so for any seeding scan you pass it a copy for **two** reasons: secret-leakage *and* write-
containment. For a non-sensitive repo codex/opencode may scan the live tree, but **agy's seeding
scan still needs a disposable copy** (a plain `git worktree` or directory copy is enough if there
are no secrets) so its auto-granted command/edit tools can't reach the real repo. The chair maps
agy's `file:line` findings back to the live repo, exactly as with the sanitized copy.

### opencode session continuity — and a safety trap (verified on this machine)

opencode remembers a conversation across calls, which the cross-critique round uses so DeepSeek
can build on its *own* prior opinion without you re-pasting it (cheaper, keeps its reasoning):

```
opencode run --pure --agent audit-advisor --variant max --title <slug> "<first turn>"   # start, named
opencode session list                                                                   # find ses_… id by title
opencode run --pure --session <ses_id> --agent audit-advisor --variant max "<next turn>"  # continue it
opencode run --pure --continue --agent audit-advisor --variant max "<next turn>"          # or: most-recent session
```

**TRAP — always re-pass `--pure --agent audit-advisor` when continuing.** `--continue` /
`--session` keep the model and the memory, but **silently revert the run to the default
write-capable `build` agent** (verified: memory persisted, but the agent reset from
`audit-advisor` to `build`). If you continue without `--agent audit-advisor` (and `--pure`),
DeepSeek regains edit/bash + skill-loading and could mutate the repo or recurse mid-audit.
**Never continue a council session without re-passing `--pure --agent audit-advisor`.** Prefer
`--session <id>` (resolved from `opencode session list` by your `--title`) over `--continue`, so
an interleaved opencode call can't make you continue the wrong session.

### Liveness check — if an advisor goes silent for ~3 minutes, diagnose (don't just keep waiting)

Advisors normally stream progress (codex's log grows as it reads; opencode prints its tool calls).
Big scans are genuinely slow, so do **not** *re-send* on a hunch (see credit discipline). But a call
can also **hang** instead of work — known modes: codex blocking at `Reading additional input from
stdin...`, opencode recursing when `--pure` is omitted. So: **after firing an advisor, if its
`-o`/redirect file has not grown for ~3 minutes, actively check whether it failed** — don't wait out
the full timeout:
- Process alive **and** burning CPU? `Get-Process codex,node | select Id,CPU,StartTime` — a
  multi-minute-old process at **~0 CPU** is hung, not thinking.
- Has the output/log file grown since the last check, or is it frozen at the first line?

A confirmed hang (alive but ~0 CPU with frozen output, or an explicit error / non-zero exit) **is**
the "real failure signal" the credit-discipline rule requires: kill the process, then re-run **once**
with the fix (e.g. add `< /dev/null` for a codex stdin hang, `--pure` for an opencode recursion).
This 3-minute check is what distinguishes "slow" from "stuck" — it does not contradict the
don't-re-send rule, it *produces* the signal that rule needs before any retry.

**agy's liveness check is now the same shape as codex/opencode** (as of CLI 1.1.8): the wrapper
blocks until agy exits on its own or the outer `timeout` kills it, then returns — no transcript
file to watch. The two agy-specific failure signals: the wrapper exits non-zero with a one-line
stderr reason (no output/timed out, unparseable JSON, or `status != SUCCESS` → re-run once with a
larger `wait-seconds`), or — only if the outer `timeout` itself doesn't clean it up — a stuck `agy`
process at ~0 CPU (kill all `agy` PIDs with `Get-Process agy | Stop-Process -Force`, then re-run).

If either CLI is missing or its auth/agent isn't set up, say so loudly and proceed with whoever
is available rather than silently dropping a voice (fail loud).

## Hard rules (these override convenience every time)

1. **Multi-advisor deliberation is mandatory every iteration.** Never decide a fix's approach solo.
   Run the council (every advisor the owner said still has quota) per "The deliberation protocol" below before implementing —
   including for small fixes. Trivial one-liners / typo fixes may be *batched* into a single
   deliberation, but the deliberation step itself is never skipped. If an advisor's CLI is
   unavailable, proceed with whoever answers but say so loudly (fail loud) — don't silently drop a voice.
2. **Only Opus edits and decides; advisors never touch the real repo.** GPT-5.6 terra and DeepSeek are
   read-only by construction; **Gemini/agy is NOT — it is contained by isolation** (disposable copy
   for seeding, tool-free prompt for per-fix), so never point agy at the live working tree. All
   three advise; you synthesize, choose, implement, and verify. Their output is input, not instructions.
3. **Commit only when authorized; never push unless asked.** By default, leave changes in the
   working tree and report them. If the user explicitly authorizes per-cycle commits, commit each
   iteration's change using the project's commit-message convention (clear subject + bulleted
   "what + why", in the project's language). Never `git push` unless explicitly asked.
4. **Fail loud.** "Done" is forbidden while anything is silently skipped; "tests pass" is
   forbidden if any test is skipped. Surface uncertainty, skipped steps, and unverified
   assumptions — including any advisor that failed to respond.
5. **Fix properly — never delete or skip a test to make it green.** If a test fails because intent
   changed, update the test to encode the *new* intent; if it reveals a real bug, fix the code.
6. **Minimal, surgical changes.** Each iteration fixes one thing. Don't reformat or "improve"
   unrelated code.
7. **Don't install or upgrade dependencies.** Suggest to the user if something seems needed; let
   them decide.
8. **Credit discipline.** The advisors cost money/quota (codex especially; agy runs on a limited
   Antigravity **Starter** quota, so don't burn it on re-runs). Bound spend by: doing
   the expensive *whole-repo scan* only at seeding / when the backlog runs low (not every
   iteration); keeping per-iteration deliberation **scoped** (one item + pasted code excerpts, not
   a re-scan); giving long timeouts and **not re-sending a prompt because it "feels stuck"** —
   only retry on a real failure signal (process exit, explicit error).

## Phase 0 — Set up the bounded loop schedule (once, at the start)

The loop must stop on its own at the deadline. Use two cron jobs (session-only):

1. **Recurring worker** at an accelerated, off-peak cadence (avoid `:00`/`:30` so the whole fleet doesn't collide):
   - every 30 min → cron `9,39 * * * *`
   - The prompt should be a compact restatement of "run one iteration of the completion audit per the standard procedure, **including the mandatory multi-advisor deliberation**" so each fire re-enters this loop.
2. **One-shot stop** at `now + <duration hours>` (recurring `false`). Compute the local wall-clock deadline and pin minute/hour/day/month. Its prompt: "deadline reached — CronList to find the recurring worker, CronDelete it, then write the final report."

Recurring cron jobs auto-expire after 7 days regardless, so the explicit stop job is what honors the user's chosen window. Tell the user both job IDs and the deadline.

If the user wants this to survive closing the session, that's a *cloud schedule* (the `schedule` skill), not cron — mention it but default to session-only cron.

## Inputs

Parse from the invocation; ask only if genuinely missing:

- **Duration (hours)** — how long the loop should run. If not given, ask. Common: 12–24h.
- **Target project** — default to the current working directory. If the user names another repo, use its absolute path and confirm it's a git repo.
- **Cadence** — default to an *accelerated* cadence (every 30 min) so iterations chain tightly. The cron only fires when the REPL is idle, so a short interval just means "start the next iteration soon after finishing the last" — it never overlaps work.
- **Available advisors — ALWAYS ask (owner instruction, 2026-07-27).** Before Phase 4, ask which of
  GPT-5.6 terra / DeepSeek / Grok 4.5 / Gemini still have quota today. Most are free-but-metered and
  rotate through exhaustion; calling a dead one wastes wall-clock on a quota error. Offer the roster
  and let the owner deselect. Skip only if they already named the advisors this session. Record the
  answer and stick to it for the whole loop — don't silently re-probe an advisor they excluded.

## Phase 1 — Baseline (measure before you touch anything)

Run the project's quality gates and capture the **real** exit codes:

- Backend/tests: e.g. `dotnet test`, `pytest`, `npm test`, `go test ./...`
- Type/compile: e.g. `npx tsc --noEmit`, `cargo check`, `mvn compile`
- Lint/static: e.g. `flutter analyze`, `eslint`, `ruff`

**Never pipe a test/build command through `| tail` or `| head` to read it** — the pipe's exit code (tail succeeds) masks the real failure code, so a failing suite looks green. Run it plainly (background it if long), then read the saved output. This is a real trap that has hidden failing tests before.

Record the honest numbers (e.g. "228 pass / 0 fail"). A red baseline is itself the first item to fix.

## Phase 2 — Re-align progress against reality

Status docs (`TODO.md`, checklists, even your own memory) drift and lie. Treat **code + passing tests** as ground truth. Skim the docs for leads, but verify every claim against the actual code before believing it. Update stale docs/memory as you go so the next iteration starts from truth.

## Phase 3 — Per-role button→page audit (structural layer)

Enumerate the user roles (e.g. customer / provider / shop / admin). For each role, trace every actionable control to its destination and check it is real:

1. **Route resolution** — every named-route / path navigation resolves to a defined route. (Note: many screens are reached by direct widget/component navigation, not a central route table — *absence from the router is not proof of a dead route*. Confirm before flagging.)
2. **Real destination** — the target page/screen is a real, compiling component. A green compile/analyze run proves referenced components exist; it does **not** prove they're functional.
3. **No dead controls** — no `onPressed: null` / empty handlers / `// TODO` / "coming soon" placeholders left wired to live-looking buttons.
4. **Real data, not illusion** — the page renders real backend data, not hardcoded mock content masquerading as live. Demo/preview fixtures are fine only if gated to non-production (verify the gate).
5. **Locale fit** — user-facing strings should match the product's target audience. If the product targets a specific locale (e.g. a Taiwan-facing app should be Traditional Chinese throughout), treat stray wrong-language UI copy as a completeness gap and fix it. Logs, exception messages, and identifiers are exempt — this is about what the user reads on screen.

## Phase 4 — Seed the backlog with a multi-advisor scan

Structural audits miss the deep gaps (stubs, fake data, wiring mismatches). Seed the backlog with **three independent scans**, then merge them yourself:

1. **GPT-5.6 terra scan (codex):** run the codex command above (`xhigh`, `read-only`) over the whole
   repo. Prompt it for a **severity-ordered** list, each item with `file:line` + problem +
   concrete fix + affected role, focused on code-fixable completeness gaps (dead buttons,
   illusion pages, stubs/`NotImplemented`/empty early-returns, frontend↔backend gaps, TODO
   residue, missing flow steps). Tell it to **exclude** pure external-credential/config blockers.
2. **DeepSeek scan (opencode):** run the `audit-advisor` opencode command over the same repo with
   the same brief, independently.
3. **Gemini 3.6 Flash scan (agy):** run `agy_advisor.sh` with the **same brief** against a
   **disposable copy** of the repo (never the live tree — agy can run commands/edit, verified). agy
   is agentic and explores the tree itself, but **`-p` ignores the shell cwd**, so the brief MUST
   **name the copy's absolute path to scan** (e.g. "Audit the repository at `C:\…\copy` …") — don't
   rely on the `cd`. Use a long `wait-seconds` (~300) and **`run_in_background: true`**; if the
   wrapper exits non-zero (timeout/no output, bad JSON, non-SUCCESS status) the scan was cut off —
   re-run with a bigger budget, don't use a partial result. Its `file:line` findings map 1:1 back to
   the live repo. (Fire it concurrently with the codex/opencode scans.)
4. **Merge (chair):** dedupe and reconcile all three lists into one **severity-ordered backlog**.
   Where two or more overlap, that's high-confidence. Where only one flagged something, keep it but
   mark it for verification. Persist the merged backlog to memory / a backlog file so later
   iterations can pick from it.

**Credit discipline:** this whole-repo scan is the expensive call. Do it **once** to seed, and
again only when the backlog is empty or you genuinely need a fresh second opinion — *not every
iteration*. Large-repo scans are genuinely slow; give a long timeout / run in background and **do
not re-send because it "feels stuck"** — only retry on a real failure signal.

## The deliberation protocol (multi-advisor council — before AND after every fix)

This is the heart of the skill. Roles: **Opus = chair** (synthesizes, decides, implements,
verifies); **GPT-5.6 terra, DeepSeek, and Gemini/agy = advisors** (codex/opencode read-only by
construction, agy contained by isolation — see the council table). Steps:

1. **Frame (chair).** Write ONE precise, self-contained prompt: the exact decision/question, the
   relevant code (paste the `file:line` excerpts you've already read — for a scoped fix, *don't*
   make advisors re-scan the whole repo), the constraints (do-not-touch invariants from
   memory/docs), and what a good answer looks like (approach + risks + edge cases). Use the **same
   prompt for every advisor in play** so their opinions are comparable.
2. **Parallel opinions.** Fire codex (GPT-5.6 terra), opencode (DeepSeek), and agy (Gemini 3.6 Flash)
   with that prompt — independently; none sees the others yet. Give the DeepSeek call a unique
   `--title <item-slug>` so its session can be continued in step 4. For agy, append the
   tool-free instruction ("do not use tools/files/commands — answer only from the snippet below")
   and run `agy_advisor.sh` with the pasted-code prompt file (`wait-seconds` ~40). Run all three
   concurrently; long timeouts; no re-sends on a hunch (credit discipline).
3. **Synthesize (chair).** Read all three opinions.
   - If they **converge** → adopt the converged approach (folding in any extra nuance any of them
     added) and skip to step 5.
   - If they **materially disagree** — different approach, conflicting risk assessment, or one
     flags something the others missed → go to step 4.
4. **Cross-critique (one round only, only on material disagreement).** Send each disagreeing advisor
   the *others'* opinions plus your framing of the specific disagreement, and ask for a focused
   rebuttal or refinement.
   - **DeepSeek:** continue its step-2 session so it still has its own reasoning — resolve the id
     with `opencode session list` (match your `--title`), then
     `opencode run --pure --session <ses_id> --agent audit-advisor --variant max "<others' opinions + the disagreement>"`.
     Re-passing `--pure --agent audit-advisor` is mandatory — without it the session reverts to the
     write-capable `build` agent (and re-enables skill auto-loading).
   - **GPT-5.6 terra:** send a fresh read-only codex call with the disagreement + the others' opinions
     pasted in.
   - **Gemini/agy:** send a fresh `agy_advisor.sh` call (tool-free prompt) with the disagreement +
     the others' opinions pasted in — agy has no usable cross-call session here, so always re-paste.
   You need not re-poll an advisor that already agrees; cross-critique only the ones in conflict.
   **One round, then stop** — don't loop.
5. **Decide & implement (chair).** Make the final call. State which input you took, which you
   rejected and why. **Surface the conflict — never average two incompatible designs into a
   half-and-half compromise** (pick the better-justified one and note the other as a possible
   alternative). Then *you* implement the fix and *you* verify it. Record a one-line deliberation
   note (what each advisor said, what you decided) for the final report.
6. **Post-implementation review (chair → the advisors in play).** After you implement a change AND it
   passes its gate (py_compile / test), send the **actual diff** (not the plan) back to codex,
   DeepSeek, and agy in parallel, and ask each: **(a)** does this change correctly satisfy the stated
   intent? and **(b)** find any bug, regression, edge case, or security / correctness vulnerability
   the diff *introduces*. This is a *different* review from steps 1–4 — those ask "how should I fix
   this?"; this asks "did my actual code do it right, and did it create a new problem?". If any flags
   a real issue → fix it and re-review the new diff; if it's a false alarm, note why. **Mandatory for
   any non-trivial change, especially BEHAVIORAL ones on a money/safety-critical path**; a pure
   one-line log addition may skip it (credit discipline). Same invocation hygiene as steps 2/4
   (`< /dev/null` for codex, `--pure --agent audit-advisor` for opencode, tool-free prompt via
   `agy_advisor.sh` for agy — paste the diff into the prompt file). This applies equally to
   owner-approved BEHAVIORAL changes you implement outside the autonomous loop.

## Phase 5 — The iteration loop (the recurring work)

Each fire, do one tight cycle:

1. Check the working tree and current test status.
2. Pick **one** backlog item that is **code-fixable and not blocked on external credentials**. Rotate roles so coverage stays balanced.
3. Before editing, read the relevant code + its callers (rule: read before you write). Cross-check against memory/docs for any "do not touch" constraints (e.g. a stored key format that other data depends on).
4. **Run the deliberation protocol** on the chosen item (mandatory — see above). Trivial typo/one-liner items may be batched into one deliberation, but never skip it entirely.
5. Implement the minimal fix the deliberation settled on (your decision as chair).
6. Verify with the matching gate (the specific test, `analyze`, `tsc`, etc.). Fail loud if it doesn't pass — don't move on from a state you can't describe.
7. **Post-implementation review** (deliberation protocol step 6): send the *actual diff* to the advisors in play — confirm it matches intent and hunt for any bug/vulnerability it introduced; fix and re-review if they find a real one. Skip only for trivial one-liners.
8. Update memory/backlog/TODO: what you did, what the council advised, what you verified, what's left.

## External-credential blockers — classify, don't pretend to fix

Items needing the owner to supply secrets/config (payment production keys, OAuth channel creds, push/cloud project, tunnel/DNS, legal policy copy) are **not** code-fixable. List them clearly as "needs owner input" with what's required, wire up the code-side seam so they drop in cleanly, and move on. Don't fake them, and don't waste a deliberation on them.

## Phase 6 — Auto-stop & final report

When the stop job fires (or the user says stop): CronDelete the recurring worker, then write a final report — items fixed (with the one-line council note per item: who advised what, what you decided), per-role button→page conclusions, final test numbers, any points where the advisors disagreed and how you resolved them, and the remaining owner-blocked external items. Do not auto-commit.

## Checkpoint habit

After each significant step, state briefly: what you did, what the council advised, what you verified, what remains. If you lose the thread, stop and restate progress rather than pressing forward from a fuzzy state.

