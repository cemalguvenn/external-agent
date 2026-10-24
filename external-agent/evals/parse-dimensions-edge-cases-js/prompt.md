---
tags: [skill-creator]
max_turns: 80
timeout_seconds: 2400
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Have Codex write the parseDimensions function described in TASK.md; I use gpt-6.1-sol. Players enter all kinds of nonsensical input, so check the result thoroughly and have Codex fix any edge cases it missed. Do not commit.

Input files: TASK.md, package.json, src/, test/
