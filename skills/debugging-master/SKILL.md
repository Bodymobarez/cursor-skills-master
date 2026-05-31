---
name: debugging-master
description: Master hub for Debugging & runtime diagnostics. Use to debug runtime issues: crashes, port conflicts, profiling, and diagnostics. Bundles 8 specialized skills (in skills/<name>/GUIDE.md). Use this for any debugging task.
---

# Debugging & runtime diagnostics — Master Hub

Use to debug runtime issues: crashes, port conflicts, profiling, and diagnostics.

## How to use this hub

This single skill bundles **all 8 debugging skills**. Each bundled skill's full instructions live in `skills/<name>/GUIDE.md` (plus any `scripts/`, `data/`, `references/` next to it).

**Workflow:**
1. Match the user's request to one or more skills in the list below.
2. Read that skill's `skills/<name>/GUIDE.md` for full instructions before acting.
3. Combine multiple bundled skills when a task spans several areas.

## Bundled skills

- **detecting-port-conflicts** — Detect EADDRINUSE and port conflicts, find what's using the port, and resolve it by killing the process or suggesting an alternative port.  
  → `skills/detecting-port-conflicts/GUIDE.md`
- **finding-dev-server-url** — Scan running terminals for dev server URLs (localhost ports), report them, and optionally open the app in Cursor's built-in browser.  
  → `skills/finding-dev-server-url/GUIDE.md`
- **grinding-until-pass** — Keep iterating on code changes until the tests pass, the build succeeds, or linting is clean. Runs in a tight loop of fix → run → check → repeat. Use when you want the agent to autonomously grind t...  
  → `skills/grinding-until-pass/GUIDE.md`
- **mattpocock-diagnose** — Disciplined diagnosis loop for hard bugs and performance regressions. Reproduce → minimise → hypothesise → instrument → fix → regression-test. Use when user says "diagnose this" / "debug this", rep...  
  → `skills/mattpocock-diagnose/GUIDE.md`
- **monitoring-terminal-errors** — Watch running terminal processes for crashes and stack traces. When an error appears, navigate to the failing file and line, diagnose, and fix it automatically.  
  → `skills/monitoring-terminal-errors/GUIDE.md`
- **profiling-performance** — Profile a running web application's CPU performance using Cursor's built-in browser profiler. Captures call stacks, identifies slow functions, and suggests optimizations. Use when a page feels slow...  
  → `skills/profiling-performance/GUIDE.md`
- **systematic-debugging** — Structured debugging methodology — reproduce, isolate, hypothesize, verify. Covers git bisect, binary search, logging, and minimal reproduction.  
  → `skills/systematic-debugging/GUIDE.md`
- **tailing-build-output** — Monitor a build process (webpack, turbo, docker) for warnings and errors as they stream. Summarize issues and fix them before the build finishes.  
  → `skills/tailing-build-output/GUIDE.md`

## Note

These bundled skills are intentionally not registered as separate Cursor skills (their files are `GUIDE.md`, not `SKILL.md`) so only this master appears in the skills list. Read the relevant `GUIDE.md` on demand.
