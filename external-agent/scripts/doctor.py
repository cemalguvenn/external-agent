"""agent_run.sh doctor: is this skill still in step with the CLIs and their models?

Checks, per agent (codex, agy):
  1. CLI version against the latest release (network; "unknown" when offline).
  2. The models the CLI offers against models.tsv: a recommended model that is no longer
     offered, or an offered model the skill has never heard of, means the routing in
     SKILL.md is stale.
  3. A tiny probe run ("reply OK") with each recommended model, because a model can be
     listed and still be rejected by an older CLI. Successful probes are cached per CLI
     version for 14 days, so this costs quota only after an update or a change.

Prints `doctor ...` lines, then `DOCTOR OK` (exit 0) or `DOCTOR ATTENTION` plus `next:`
lines (exit 1). Never updates anything itself.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
KNOWN_FILE = os.path.join(HERE, "models.tsv")
CACHE_ROOT = os.environ.get("EXTERNAL_AGENT_SNAP_ROOT") or os.path.expanduser("~/.cache/external-agent")
CACHE_FILE = os.path.join(CACHE_ROOT, "doctor-probes.json")
PROBE_TTL = 14 * 24 * 3600
EFFORT_SUFFIX = re.compile(r"-(low|medium|high|xhigh|max)$")
LIMIT_WORDS = re.compile(r"usage limit|RESOURCE_EXHAUSTED|quota|\b429\b|rate.?limit", re.I)
PROMPT = "Reply with exactly the word OK and nothing else. Do not run any tools."


def run(cmd, timeout=30, cwd=None, stdin=None):
    cmd = [shutil.which(cmd[0]) or cmd[0]] + list(cmd[1:])  # Windows: npm/codex are .cmd shims
    try:
        p = subprocess.run(cmd, cwd=cwd, input=stdin, capture_output=True, text=True,
                           timeout=timeout, encoding="utf-8", errors="replace")
        return p.returncode, p.stdout, p.stderr
    except (OSError, subprocess.TimeoutExpired) as e:
        return 124, "", str(e)


def vtuple(v):
    return tuple(int(x) for x in re.findall(r"\d+", v or "")[:3])


def first_version(text):
    m = re.search(r"\d+\.\d+\.\d+", text or "")
    return m.group(0) if m else ""


def load_known():
    known = {"codex": {}, "agy": {}}
    with open(KNOWN_FILE, encoding="utf-8") as f:
        for line in f:
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 3 and parts[0] in known:
                known[parts[0]][parts[1]] = parts[2]
    return known


def load_cache():
    try:
        with open(CACHE_FILE, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_cache(cache):
    try:
        os.makedirs(CACHE_ROOT, exist_ok=True)
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(cache, f, indent=1, sort_keys=True)
    except OSError:
        pass


# ---- per-CLI facts ---------------------------------------------------------------------

def codex_latest():
    if shutil.which("npm"):
        rc, out, _ = run(["npm", "view", "@openai/codex", "version"], timeout=20)
        if rc == 0 and first_version(out):
            return first_version(out)
    try:
        import urllib.request
        req = urllib.request.Request("https://api.github.com/repos/openai/codex/releases/latest",
                                     headers={"User-Agent": "external-agent-doctor"})
        with urllib.request.urlopen(req, timeout=15) as r:
            return first_version(json.load(r).get("tag_name", ""))
    except Exception:
        return ""


def codex_cache():
    p = os.path.join(os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex"), "models_cache.json")
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def codex_models():
    d = codex_cache()
    if d is None:
        return None
    return {m.get("slug") for m in d.get("models", d) if isinstance(m, dict) and m.get("slug")}


def codex_cache_version():
    d = codex_cache()
    return d.get("client_version", "") if isinstance(d, dict) else ""


def agy_latest():
    # agy updates itself in the background; its changelog starts with the newest version
    # it knows about, which may already be downloaded and waiting for a restart.
    rc, out, _ = run(["agy", "changelog"], timeout=20)
    return first_version(out.splitlines()[0]) if rc == 0 and out.strip() else ""


def agy_models():
    rc, out, _ = run(["agy", "models"], timeout=60)
    if rc != 0:
        return None
    ids = [l.split("\t")[0].strip() for l in out.splitlines()
           if l.strip() and not l.startswith("Fetching")]
    return ids


def short_error(text):
    # Codex nests the API error as a JSON string inside "message"; pull out the innermost.
    for m in reversed(re.findall(r'"message"\s*:\s*"((?:[^"\\]|\\.)*)"', text or "")):
        msg = m.encode().decode("unicode_escape", errors="replace")
        inner = re.findall(r'"message"\s*:\s*"((?:[^"\\]|\\.)*)"', msg)
        msg = inner[-1] if inner else msg
        if "deprecated" not in msg and "metadata" not in msg.lower():
            return msg[:200]
    lines = [l for l in (text or "").splitlines() if l.strip()]
    return (lines[-1] if lines else "no output")[:200]


def probe_codex(model, workdir):
    rc, out, err = run(["codex", "exec", "-m", model, "-c", 'model_reasoning_effort="low"',
                        "-s", "read-only", "--skip-git-repo-check", "-C", workdir, "--json", "-"],
                       timeout=240, stdin=PROMPT)
    if rc == 0 and '"turn.completed"' in out and '"turn.failed"' not in out:
        return "OK", ""
    why = short_error(out + "\n" + err)
    return ("LIMITED" if LIMIT_WORDS.search(why) else "FAIL"), why


def probe_agy(model, workdir):
    rc, out, err = run(["agy", "-p", PROMPT, "--model", model, "--output-format", "json",
                        "--print-timeout", "3m"], timeout=240, cwd=workdir)
    try:
        d = json.loads(out[out.index("{"):]) if "{" in out else {}
    except ValueError:
        d = {}
    if rc == 0 and d.get("status") == "SUCCESS":
        return "OK", ""
    why = short_error(err + "\n" + out) if not d else (str(d.get("error") or d.get("status")))[:200]
    return ("LIMITED" if LIMIT_WORDS.search(why + err) else "FAIL"), why


# ---- main ------------------------------------------------------------------------------

def resolve(argv):
    """resolve codex MODEL -> MODEL if the installed CLI offers it, else the fallback.

    Codex's models_cache.json is refreshed by the installed CLI and lists only models it
    can run, so a recommended model missing from it means the CLI is too old for it."""
    agent, model = (argv + ["", ""])[:2]
    offered = codex_models() if agent == "codex" else None
    fallback = next((m for m, r in load_known().get(agent, {}).items() if r == "fallback"), "")
    if offered and model not in offered and fallback in offered:
        print(f"note: this {agent} CLI doesn't offer {model}; using {fallback} "
              f"(update the CLI, see `agent_run.sh doctor`)", file=sys.stderr)
        model = fallback
    print(model)
    return 0


def main(argv):
    if argv[:1] == ["resolve"]:
        return resolve(argv[1:])
    agents, do_probe, reprobe = ["codex", "agy"], True, False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--agent":
            v = argv[i + 1] if i + 1 < len(argv) else ""
            agents = ["codex", "agy"] if v in ("both", "all") else [v]
            i += 2
            continue
        if a == "--no-probe":
            do_probe = False
        elif a == "--reprobe":
            reprobe = True
        else:
            print(f"error: unknown doctor option '{a}' (--agent codex|agy|both, --no-probe, --reprobe)", file=sys.stderr)
            return 2
        i += 1
    for a in agents:
        if a not in ("codex", "agy"):
            print(f"error: unknown agent '{a}'", file=sys.stderr)
            return 2

    known = load_known()
    cache = load_cache()
    attention, nexts, infos = False, [], []
    os.makedirs(CACHE_ROOT, exist_ok=True)
    workdir = tempfile.mkdtemp(prefix="doctor-", dir=CACHE_ROOT)  # under $HOME: agy trusts it

    try:
        for agent in agents:
            if not shutil.which(agent):
                print(f"doctor {agent}: not installed")
                continue
            installed = first_version(run([agent, "--version"], timeout=30)[1])
            latest = codex_latest() if agent == "codex" else agy_latest()
            if not latest:
                state = "latest unknown (offline?)"
            elif vtuple(installed) < vtuple(latest):
                state = f"OUTDATED, latest {latest}"
                if agent == "codex":
                    infos.append("a Codex update is available; mention it to the user once "
                                 "(`codex update`, or `brew upgrade --cask codex` / `npm i -g @openai/codex`)")
                else:
                    state += " (agy updates itself in the background; the next run may already use it)"
            else:
                state = "up to date"
            print(f"doctor {agent}: cli {installed or '?'} {state}")

            if agent == "codex" and do_probe and installed and codex_cache_version() not in ("", installed):
                # The cache lists what the CLI that wrote it could run. After an update it is
                # stale until the new CLI runs once, so run one probe to refresh it.
                was = codex_cache_version()
                fb = next((m for m, r in known["codex"].items() if r == "fallback"), "gpt-6.1-sol")
                res, why = probe_codex(fb, workdir)
                print(f"doctor codex: model list was from cli {was}; refreshed with a probe of {fb}: {res}"
                      f"{(': ' + why) if why else ''}")
                if res == "OK":
                    cache[f"codex|{fb}|{installed}"] = {"ok": True, "at": int(time.time())}
            offered = codex_models() if agent == "codex" else agy_models()
            if offered is None:
                print(f"doctor {agent}: models unavailable (run the CLI once, check login)")
                attention = True
                continue
            if agent == "agy":
                full_ids = list(offered)
                offered = {EFFORT_SUFFIX.sub("", m) for m in offered}
            k = known[agent]
            new = sorted(m for m in offered if m not in k)
            gone = sorted(m for m, r in k.items() if r == "recommended" and m not in offered)
            print(f"doctor {agent}: models new={','.join(new) or '-'} "
                  f"recommended-missing={','.join(gone) or '-'}")
            fallback = next((m for m, r in k.items() if r == "fallback"), "")
            if gone and "OUTDATED" in state:
                # The server only lists models the installed CLI can run, so an old CLI
                # hides newer models: that is the CLI's problem, not the routing's.
                attention = True
                nexts.append(f"{agent} CLI {installed} is too old for {', '.join(gone)}: ask the user to "
                             f"run `codex update`; until then the script uses {fallback or 'another listed model'} "
                             f"as the default, and pass --model/--review-model {fallback or '<listed model>'} "
                             "where you would have named a missing one")
                gone = []
            if new or gone:
                attention = True
                nexts.append(f"{agent} routing may be stale ({'new: ' + ', '.join(new) if new else ''}"
                             f"{'; ' if new and gone else ''}{'gone: ' + ', '.join(gone) if gone else ''}): "
                             "tell the user and offer to refresh the skill (SKILL.md section 1, "
                             "scripts/models.tsv, README.md)")

            if not do_probe:
                continue
            to_probe = sorted(m for m, r in k.items() if r == "recommended" and m in offered)
            if fallback and fallback in offered and len(to_probe) < sum(r == "recommended" for r in k.values()):
                to_probe.append(fallback)  # a recommended model is missing: check the stand-in works
            for base in to_probe:
                model = base
                if agent == "agy":  # probe the cheapest effort variant on offer
                    variants = [m for m in full_ids if EFFORT_SUFFIX.sub("", m) == base]
                    order = ["low", "medium", "high", "xhigh", "max"]
                    variants.sort(key=lambda m: order.index(EFFORT_SUFFIX.search(m).group(1))
                                  if EFFORT_SUFFIX.search(m) else -1)
                    model = variants[0] if variants else base
                key = f"{agent}|{model}|{installed}"
                hit = cache.get(key)
                if hit and hit.get("ok") and not reprobe and time.time() - hit.get("at", 0) < PROBE_TTL:
                    print(f"doctor {agent}: probe {model} OK (cached)")
                    continue
                t0 = time.time()
                res, why = (probe_codex if agent == "codex" else probe_agy)(model, workdir)
                secs = int(time.time() - t0)
                print(f"doctor {agent}: probe {model} {res} {secs}s{(': ' + why) if why else ''}")
                if res == "OK":
                    cache[key] = {"ok": True, "at": int(time.time())}
                elif res == "LIMITED":
                    nexts.append(f"{agent} is out of quota; route its work to the other agent for now")
                    attention = True
                    break
                else:
                    attention = True
                    hint = f"pass --model/--review-model {fallback}" if fallback else "use the other agent"
                    if agent == "codex" and "OUTDATED" in state:
                        hint = "ask the user to run `codex update`; until then " + hint + \
                            " (an old CLI rejects newer models)"
                    nexts.append(f"{agent} {model} unusable: {hint}; tell the user")
        save_cache(cache)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    print("DOCTOR ATTENTION" if attention else "DOCTOR OK")
    for n in dict.fromkeys(nexts):
        print(f"next: {n}")
    if not attention:
        for n in dict.fromkeys(infos):
            print(f"info: {n}")
    return 1 if attention else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
