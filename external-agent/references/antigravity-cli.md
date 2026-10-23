# Antigravity CLI (`agy`) notes (verified against agy 1.4.5 on macOS, 1.4.6 on Windows 11)

## How the script drives it

| Step | Invocation (run from the project dir; prompt passed as the `-p` value) |
|---|---|
| Implement / fix | `agy -p "<brief>" --model M [--effort E] --dangerously-skip-permissions --sandbox --output-format json --json-schema implementer.schema.json --print-timeout 30m` |
| Resume | same, plus `--conversation <conversation_id>` |
| Review | same flags with `review.schema.json`, run **in a disposable copy**, with the diff pasted into the prompt |
| Read-only investigation | implement flags, run **in a disposable copy** |
| Models | `agy models` → `id<TAB>display name` per line |

- `--output-format json` prints one object: `conversation_id`, `status` (`SUCCESS`
  on success), `response` (the agent's final text), `usage` (`input_tokens`,
  `output_tokens`, `thinking_tokens`, `cache_read_tokens`), `denied_actions`. With
  `--json-schema`, the structured answer is in `structured_output` and also inside
  `response`, sometimes after prose. The script takes `structured_output` (even when a
  late transient API error set `status` to `ERROR`), else the last complete object
  in `response`.
- agy has no stdin prompt mode, and Windows caps a command line at 32,767 characters.
  Prompts over ~24 KB (reviews with a big diff) stay in their file in the run dir; the
  `-p` value tells agy to read it, and `--add-dir` gives it that folder.
- **Headless permission model.** Without `--dangerously-skip-permissions`, any write
  or command is auto-denied, and the turn then **ends with an empty response**. So
  `--mode plan` is no use as a read-only mode, and with the bypass on, plan mode did
  edit files in testing. `--mode accept-edits` still denies commands. `--mode auto`
  isn't available on every account ("not available for this account").
- That's why work that must not touch the tree runs in a copy:
  `~/.cache/external-agent/external-agent-snap.XXXXXX`. `.git`, `node_modules`, `.venv`,
  `target`, `dist`, `build` and `.next` are excluded, and the copy is deleted afterwards.
  `EXTERNAL_AGENT_SNAP_ROOT` moves it. It must be inside a trusted workspace:
  a copy under `/var/folders` made a trivial investigation take ~8 minutes and
  3M cache tokens.
- **Every agy prompt ends with the full JSON schema and a scope rule** (stay in the
  current directory; no env vars or other tools' data). Without them, Gemini Flash
  found the answer in ~8 steps and then spent ~50 more searching `env`, `/tmp` and other
  apps' folders for "the schema" (308 s, 1.6M tokens; with the footer: 30 s, 36k).
  If you call agy directly, keep that footer.
- `--sandbox` (terminal sandbox): `.git` is read-only (commits fail with
  `index.lock: Operation not permitted`), `~/Library/Application Support` is
  unreadable, writes outside trusted workspaces fail, and network is allowed.
  File-edit tools work in trusted workspaces.
- Trusted workspaces live in `~/.gemini/antigravity-cli/settings.json`
  (`trustedWorkspaces`, e.g. `["/Users/<you>"]`). Projects outside them can't be
  edited from the terminal. On Windows (agy 1.4.6) that file doesn't exist and projects
  under `%USERPROFILE%` worked without setup.
- `--print-timeout` defaults to unlimited. The script sets 30m, and on expiry agy
  returns partial output with a warning.
- Exit codes: 0 ok, 2 usage error, 3 model/agent error with an `AGY_ERROR: {...}` line on
  stderr.
- **Quota.** agy fetches its quota internally (`GetG1Credits` / `doRefreshQuota` in
  `~/.gemini/antigravity-cli/cli.log`) but never writes the figures anywhere, and has no
  usage command, so there is no advance warning. A failed step whose error mentions
  `RESOURCE_EXHAUSTED`, `quota`, `429` or a rate limit counts as out of quota, and the
  script moves the role to Codex. The real message hasn't been seen yet: if agy runs
  out and the run ends `FAILED` instead, add its wording to `limit-check` in the script.
- The CLI auto-updates in the background: after one run, `agy --version` may already
  report a newer version.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `jetski: no output produced — a tool required the "…" permission` | Run without the permission bypass | Use the script (it sets the bypass plus sandbox) |
| `error: agy needs a model` (script exit 2) | No model chosen | Ask the user to pick from the printed list |
| `cannot read under ~/Library/Application Support` (script) | Project inside an app-data folder | Move the project or use Codex |
| Edits fail with `operation not permitted` | Folder not in `trustedWorkspaces` | User adds it in Antigravity, or use Codex |
| Very slow, huge token counts | Working in an untrusted dir (e.g. `/var/folders`) | Keep the project and snapshot root under `$HOME` |
| `warning: --mode auto is not available` | Account tier | Ignore; the script doesn't use auto mode |
| `stage … LIMITED agy: quota exhausted` | Antigravity quota used up | Automatic: Codex takes over. If `FINAL LIMITED`, do it yourself or tell the user |
