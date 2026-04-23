# End Session — Knowledge Base Update

Run this before `/exit` to persist session knowledge.

## Instructions for Claude

You are closing a work session. Complete the following steps in order. Do not skip any.

### Step 1: Update `components.md`

Review everything created, modified, or deleted this session.
For each component/module touched, ensure `.claude/knowledge/components.md` has an up-to-date entry covering:
- What it does
- Where it lives in the codebase
- Key dependencies
- Any important usage notes or caveats discovered this session

### Step 2: Update `mistakes.md`

Review every error, failed attempt, or wrong assumption that occurred this session.
For each one, add or update an entry in `.claude/knowledge/mistakes.md` with:
- The error or wrong assumption
- The context it occurred in
- What was tried that failed
- What actually resolved it (or that it is still unresolved)

### Step 3: Update `patterns.md`

If any new approach, convention, or architectural decision was established this session that should be repeated in the future, add it to `.claude/knowledge/patterns.md`.

### Step 4: Append to `session-log.md`

Add a new entry at the top of `.claude/knowledge/session-log.md` using this format:

```
## Session: [DATE] — [ONE LINE SUMMARY]

### Completed
- [list of things finished]

### In Progress / Left Off At
- [anything partially done]

### Blockers
- [anything that was stuck or needs user input]

### Key Decisions Made
- [architectural or product decisions]

### Watch Out For (Next Session)
- [anything that tripped us up, or needs attention next time]
```

### Step 5: Confirm

Report back: "Session knowledge updated. [N] components updated, [N] mistakes logged, [N] patterns added."
