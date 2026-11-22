"""Grade evals/run-headless.sh runs: hidden tests (the score), commits, dirty files,
and the pipeline summaries (agents, FINAL, timings, tokens) found in each trace.

usage: python3 evals/grade.py <run root>"""
import json, os, re, shutil, subprocess, sys, tempfile
ROOT = sys.argv[1]
EV = os.path.dirname(os.path.abspath(__file__))
def sh(cmd, cwd):
    p = subprocess.run(cmd, cwd=cwd, shell=True, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr
for case in sorted(d for d in os.listdir(ROOT) if not d.endswith(".out") and os.path.isdir(os.path.join(ROOT, d, ".git"))):
    w, o = os.path.join(ROOT, case), os.path.join(ROOT, case + ".out")
    base = re.sub(r"-neon$", "", case)
    meta = open(os.path.join(o, "meta.txt")).read().strip() if os.path.exists(os.path.join(o, "meta.txt")) else "running?"
    rc, log = sh("git log --oneline | wc -l", w); commits = int(log.strip() or 0) - 1
    rc, st = sh("git status --short | grep -v __pycache__", w)
    hidden = "-"
    if base != "readonly-bug-investigation":
        t = tempfile.mkdtemp(); c = os.path.join(t, "w"); shutil.copytree(w, c, ignore=shutil.ignore_patterns(".git", "node_modules"))
        if base == "two-task-plan-python":
            shutil.copy(os.path.join(EV, base, "hidden/test_hidden.py"), os.path.join(c, "test_hidden.py"))
            rc, out = sh("python3 -m unittest test_hidden -v", c)
        else:
            shutil.copy(os.path.join(EV, base, "hidden/hidden.test.js"), os.path.join(c, "test/hidden.test.js"))
            rc, out = sh("node --test test/hidden.test.js", c)
        npass = len(re.findall(r"\.\.\. ok$|^# pass \d+", out, re.M))
        m = re.search(r"Ran (\d+) tests", out); n = m.group(1) if m else None
        if base == "two-task-plan-python":
            fails = len(re.findall(r"\.\.\. (FAIL|ERROR)", out)); hidden = f"{int(n or 0)-fails}/{n}" if n else "error"
        else:
            p = re.search(r"# pass (\d+)", out); f = re.search(r"# fail (\d+)", out)
            hidden = f"{p.group(1)}/{int(p.group(1))+int(f.group(1))}" if p and f else "error"
        shutil.rmtree(t)
    # trace facts
    tr = open(os.path.join(o, "trace.jsonl")).read() if os.path.exists(os.path.join(o, "trace.jsonl")) else ""
    agents = sorted(set(re.findall(r"agents: implement=([\w./-]+) review=([\w./-]+)", tr)))
    finals = re.findall(r"FINAL ([A-Z_]{4,})", tr)
    rundirs = sorted(set(re.findall(r"run_dir=([^\\\s\"]+)", tr)) | set(re.findall(r"--run-dir[ =]([^\\\s\"]+)", tr)))
    summ = []
    for d in rundirs:
        f = os.path.join(os.path.expandvars(d), "summary.txt")
        if os.path.exists(f):
            t = open(f).read()
            summ.append((os.path.basename(d.rstrip("/")), re.findall(r"^(?:FINAL|stage)\s.*$", t, re.M), re.findall(r"^agents:.*$", t, re.M), re.findall(r"^elapsed_seconds=\d+", t, re.M), re.findall(r"^agent_tokens:.*$", t, re.M)))
    fixes = len(re.findall(r"stage fix-\d", tr))
    last = tr.strip().splitlines()[-1] if tr.strip() else "{}"
    try: r = json.loads(last)
    except ValueError: r = {}
    print(f"== {case}: {meta} cost=${r.get('total_cost_usd', 0):.2f} turns={r.get('num_turns')}")
    print(f"   hidden={hidden} commits={commits} dirty={len(st.splitlines())} finals={finals} fix_stages={fixes}")
    print(f"   agents={agents}")
    for x in summ: print("   run", x)
