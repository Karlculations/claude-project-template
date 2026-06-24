# CLAUDE.md — Project Intelligence File
# Project: [PROJECT_NAME]
# Type: [PROJECT_TYPE]
# Stack: [PROJECT_STACK]
# Last Updated: [DATE]

---

<!-- CLAUDE_READ_FIRST_START -->
## 🔴 READ FIRST — Every Session

Before doing anything, read these files in order:

1. `.claude/knowledge/mistakes.md` — patterns to avoid, past failures
2. `.claude/knowledge/components.md` — existing components/modules registry
3. `.claude/knowledge/patterns.md` — established architectural patterns for this project
4. `.claude/knowledge/session-log.md` — what happened in recent sessions

If any of these files are missing or empty, note it and continue — do not skip this step.
<!-- CLAUDE_READ_FIRST_END -->

---

<!-- CLAUDE_EXISTING_FILES_START -->
<!-- CLAUDE_EXISTING_FILES_END -->

---

<!-- CLAUDE_PROTOCOLS_START -->
## 🧠 Core Behavioral Protocols

### Before Making Any Change
- Read the relevant section of `components.md` to understand what already exists
- Check `mistakes.md` for known failure patterns related to what you are about to do
- If modifying an existing component, state what it currently does before changing it

### While Working
- After completing each distinct feature or fix, update `components.md` with what changed
- If you encounter an error you cannot resolve in 2 attempts, log it to `mistakes.md` immediately with the context and what was tried
- Never report a feature as "done" until you have written and run tests for it

### On Failure / Errors
1. Read the error message fully — do not guess
2. Check `mistakes.md` for a matching pattern
3. Attempt fix #1 with reasoning stated
4. If fix #1 fails: attempt fix #2 with a different approach (not a variation of #1)
5. If fix #2 fails: STOP. Report the blocker clearly. Do not attempt fix #3 without user input
6. Log both failed attempts to `mistakes.md` with the exact error, context, and what was tried

### Testing Protocol
- Write tests BEFORE marking anything done
- Run existing test suite after every change — fix regressions immediately
- If no test suite exists: write at minimum a smoke test for the feature
- Do not suppress or skip failing tests without explicit user approval

### Before Ending Any Session
Run `/end-session` or manually do the following:
1. Update `components.md` with anything created or modified this session
2. Update `mistakes.md` with any new errors or patterns discovered
3. Append a summary entry to `session-log.md`
4. Update this file's "Last Updated" date if project structure changed
<!-- CLAUDE_PROTOCOLS_END -->

---

<!-- CLAUDE_AGENTS_START -->
## 🤖 Agent Roster

Agents for this project live in `.claude/agents/`. Each agent reads this CLAUDE.md and the knowledge base on initialization.

| Agent | File | When to Use |
|---|---|---|

**Add agents as needed. Run the init script to regenerate this table.**
<!-- CLAUDE_AGENTS_END -->

**Every agent carries a `## ✅ Non-Negotiables` block** — its Must Do / Must Never / Definition of Done. These are the hard rules the agent applies on every task, regardless of what it is asked, and they are tuned to the tools that agent actually has. Skim an agent's file to see the bar it holds itself to.

---

## 📁 Project Structure

```
[Fill this in once project is initialized]
e.g.
app/
  Http/Controllers/
  Models/
resources/
  js/
    components/
tests/
.claude/
  agents/
  commands/
  knowledge/
```

---

## ⚙️ Environment & Stack Notes

```
# Fill in project-specific commands
Run dev server:    [e.g. php artisan serve]
Run tests:         [e.g. php artisan test]
Build assets:      [e.g. npm run dev]
Database:          [e.g. PostgreSQL 15, local via Docker]
Key env vars:      [list any non-obvious ones]
```

---

## 🚫 Known Hard Rules for This Project

> Things that were explicitly decided and must not be reversed without discussion.

- [ ] Add rules here as the project evolves

---

## 📌 Ongoing Context

> Decisions made, approaches agreed on, things the user has repeatedly had to correct.

- [ ] Fill in as project evolves
