I built a scaffolding system for Claude Code that gives it persistent memory, specialized agents, and a self-updating knowledge base — and it's open sourced.

Here's the problem it solves:

Claude Code is powerful, but every session starts from zero. It doesn't know what components it already built last week, what approaches failed and why, or what architectural decisions were made. The result is repeated mistakes, redundant questions, and time wasted re-explaining context that should already exist.

This template fixes that with four things:

1. A structured knowledge base
Four markdown files Claude reads at the start of every session: a component registry (what exists and where), a mistakes log (what failed and why), an established patterns file (project-specific conventions), and a session log (where we left off). It's not magic — it's structured context injection.

2. Ten specialized sub-agents
Senior Developer, QA Engineer, Project Manager, Data Analyst, UI Designer, DevOps, Security Engineer, Performance Engineer, Technical Writer, and Code Reviewer. Each has a focused system prompt, explicit initialization steps, and role-specific behavioral standards. The QA agent alone runs a two-phase check: first verifying the implementation is 1:1 with your specs and designs, then stress testing it adversarially. Nothing ships without passing both.

3. Existing file awareness
If your project already has design docs, specs, or architecture notes, the init script scans your folder and injects those file paths directly into CLAUDE.md. Claude reads them automatically from session one, without you having to point them out every time. It also handles existing CLAUDE.md files intelligently — it never overwrites your custom content, only updates the sections it owns.

4. A session-end command
/end-session triggers Claude to update all four knowledge files before you exit: new components, failed attempts, patterns, session summary. Run it consistently and the knowledge base gets genuinely useful over time. Skip it and the system degrades.

To use it on a new or existing project:
bash init-claude-project.sh

It asks what you're building, what stack you're using, and which agents you actually need. Only installs what's relevant. Adding a new agent later? Drop in the file, add one line to the registry, and run --update-readme to keep the docs current automatically.

The whole thing lives in .claude/ alongside your code and commits to git — versioned, portable, and survives machine changes.

Full breakdown of every feature, agent, and command is in the README.

Repo: https://github.com/Karlculations/claude-project-template

#ClaudeCode #AITooling #DeveloperTools #Anthropic #OpenSource #ByteHiveBB #AIAgents #SoftwareDevelopment #DevTools #ProductivityTools #WebDevelopment #FullStackDevelopment #BackendDevelopment #FrontendDevelopment #DevOps #SoftwareEngineering #AIWorkflow #BuildInPublic #IndieHacker #TechStartup #CodeSmarter #Laravel #NextJS #React #Django #PostgreSQL #AWS
