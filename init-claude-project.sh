#!/usr/bin/env bash
# init-claude-project.sh
# Usage:
#   bash init-claude-project.sh              — full project init or smart upgrade
#   bash init-claude-project.sh --upgrade    — re-run merge on existing CLAUDE.md only
#   bash init-claude-project.sh --update-readme  — rebuild README agents table

set -e

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$(pwd)"
README_PATH="$TEMPLATE_DIR/README.md"
TARGET_CLAUDE="$TARGET_DIR/CLAUDE.md"
TEMPLATE_CLAUDE="$TEMPLATE_DIR/CLAUDE.md"

# ─── Agent Registry ───────────────────────────────────────────────────────────
# Source of truth for all available agents.
# Format: "filename.md|Display Name|Short description"
# After adding a new agent: bash init-claude-project.sh --update-readme

AGENT_REGISTRY=(
  "senior-dev.md|Senior Developer|Architecture decisions, complex logic, implementation, refactoring"
  "qa-engineer.md|QA Engineer|Spec compliance verification, design matching, stress testing, acceptance criteria"
  "project-manager.md|Project Manager|Scope, task breakdown, acceptance criteria definition, requirements"
  "data-analyst.md|Data Analyst|Query design, data modeling, metrics and reporting"
  "ui-designer.md|UI Designer|Component layout, UX decisions, design-to-code fidelity, accessibility"
  "devops.md|DevOps|Infrastructure, CI/CD, deployment, env configuration"
  "security-engineer.md|Security Engineer|Auth review, secrets exposure, vulnerability checks, OWASP"
  "technical-writer.md|Technical Writer|READMEs, API docs, inline comments, changelogs"
  "code-reviewer.md|Code Reviewer|Pre-completion review, pattern consistency, maintainability"
  "performance-engineer.md|Performance Engineer|Load testing, query profiling, caching, response time, scalability"
)

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Extract content between two anchor comments from a file
# Usage: extract_section <file> <START_ANCHOR> <END_ANCHOR>
extract_section() {
  local file="$1" start="$2" end="$3"
  awk "/<!-- ${start} -->/{found=1; next} /<!-- ${end} -->/{found=0} found{print}" "$file"
}

# Replace an anchored section in a file with new content
# Usage: replace_section <file> <START_ANCHOR> <END_ANCHOR> <new_content>
replace_section() {
  local file="$1" start="$2" end="$3" new_content="$4"
  awk -v start="<!-- ${start} -->" \
      -v end="<!-- ${end} -->" \
      -v new="$new_content" '
    $0 == start { print; printf "%s\n", new; skip=1; next }
    $0 == end   { skip=0 }
    !skip        { print }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# Check if a file contains a given anchor
has_anchor() {
  grep -q "<!-- $2 -->" "$1" 2>/dev/null
}

# ─── Build Agent Table ────────────────────────────────────────────────────────

build_agent_table() {
  local selected_agents=("$@")
  local table="## 🤖 Agent Roster\n\n"
  table+="Agents for this project live in \`.claude/agents/\`. Each agent reads this CLAUDE.md and the knowledge base on initialization.\n\n"
  table+="| Agent | File | When to Use |\n"
  table+="|---|---|---|\n"

  for entry in "${AGENT_REGISTRY[@]}"; do
    IFS='|' read -r file name description <<< "$entry"
    for selected in "${selected_agents[@]}"; do
      if [[ "$selected" == "$file" ]]; then
        table+="| $name | \`$file\` | $description |\n"
        break
      fi
    done
  done

  printf "%b" "$table"
}

# ─── Build Existing Files Block ───────────────────────────────────────────────

build_existing_files_block() {
  local target="$1"
  local existing_docs=()
  local doc_folders=()

  while IFS= read -r -d '' file; do
    rel="${file#$target/}"
    existing_docs+=("$rel")
  done < <(find "$target" \
    -maxdepth 3 \
    \( -name "*.md" -o -name "*.txt" -o -name "*.rst" \) \
    ! -path "*/.claude/*" \
    ! -path "*/node_modules/*" \
    ! -path "*/vendor/*" \
    ! -path "*/.git/*" \
    ! -name "CLAUDE.md" \
    ! -name "README.md" \
    -print0 2>/dev/null | sort -z)

  for folder in docs doc design designs specs requirements planning; do
    if [[ -d "$target/$folder" ]]; then
      doc_folders+=("$folder/")
    fi
  done

  if [[ ${#existing_docs[@]} -eq 0 && ${#doc_folders[@]} -eq 0 ]]; then
    echo ""
    return
  fi

  local block="## 📂 Existing Project Files — Read Before Working\n\n"
  block+="These files were present when the project was initialized.\n"
  block+="Read them at the start of every session before touching any code.\n"
  block+="They define intent, design decisions, and context that takes precedence over assumptions.\n\n"

  if [[ ${#doc_folders[@]} -gt 0 ]]; then
    block+="**Documentation folders (read all files inside):**\n"
    for folder in "${doc_folders[@]}"; do
      block+="- \`$folder\`\n"
    done
    block+="\n"
  fi

  if [[ ${#existing_docs[@]} -gt 0 ]]; then
    block+="**Specific files:**\n"
    for doc in "${existing_docs[@]}"; do
      block+="- \`$doc\`\n"
    done
    block+="\n"
  fi

  block+="If a file here contradicts something you would otherwise assume, follow the file.\n"
  block+="If a file is missing or has moved, note it — do not silently skip."

  printf "%b" "$block"
}

# ─── Smart CLAUDE.md Merge ────────────────────────────────────────────────────

merge_claude_md() {
  local selected_agents=("$@")
  local today
  today=$(date +"%Y-%m-%d")

  local agent_table
  agent_table=$(build_agent_table "${selected_agents[@]}")

  local existing_files_block
  existing_files_block=$(build_existing_files_block "$TARGET_DIR")

  if [[ ! -f "$TARGET_CLAUDE" ]]; then
    # ── Case 1: No CLAUDE.md exists — create from template ──────────────────
    echo "  Creating CLAUDE.md from template..."
    cp "$TEMPLATE_CLAUDE" "$TARGET_CLAUDE"
    sed -i "s/\[PROJECT_NAME\]/$PROJECT_NAME/g" "$TARGET_CLAUDE"
    sed -i "s/\[PROJECT_TYPE\]/$PROJECT_TYPE/g" "$TARGET_CLAUDE"
    sed -i "s/\[PROJECT_STACK\]/$PROJECT_STACK/g" "$TARGET_CLAUDE"
    sed -i "s/\[DATE\]/$today/g" "$TARGET_CLAUDE"
    replace_section "$TARGET_CLAUDE" "CLAUDE_AGENTS_START" "CLAUDE_AGENTS_END" "$agent_table"
    replace_section "$TARGET_CLAUDE" "CLAUDE_EXISTING_FILES_START" "CLAUDE_EXISTING_FILES_END" "$existing_files_block"
    echo "  ✓ CLAUDE.md created"

  elif has_anchor "$TARGET_CLAUDE" "CLAUDE_PROTOCOLS_START"; then
    # ── Case 2: Existing CLAUDE.md with our anchors — surgical update ────────
    echo "  Existing CLAUDE.md detected (previously initialized) — upgrading anchored sections..."

    # Refresh protocols (these never change, but keep them current)
    local protocols_content
    protocols_content=$(extract_section "$TEMPLATE_CLAUDE" "CLAUDE_PROTOCOLS_START" "CLAUDE_PROTOCOLS_END")
    replace_section "$TARGET_CLAUDE" "CLAUDE_PROTOCOLS_START" "CLAUDE_PROTOCOLS_END" "$protocols_content"
    echo "    ✓ Behavioral protocols refreshed"

    # Refresh read-first block
    local read_first_content
    read_first_content=$(extract_section "$TEMPLATE_CLAUDE" "CLAUDE_READ_FIRST_START" "CLAUDE_READ_FIRST_END")
    replace_section "$TARGET_CLAUDE" "CLAUDE_READ_FIRST_START" "CLAUDE_READ_FIRST_END" "$read_first_content"
    echo "    ✓ Read-first block refreshed"

    # Update agent roster with currently selected agents
    replace_section "$TARGET_CLAUDE" "CLAUDE_AGENTS_START" "CLAUDE_AGENTS_END" "$agent_table"
    echo "    ✓ Agent roster updated"

    # Re-scan and update existing files block
    replace_section "$TARGET_CLAUDE" "CLAUDE_EXISTING_FILES_START" "CLAUDE_EXISTING_FILES_END" "$existing_files_block"
    echo "    ✓ Existing files list re-scanned and updated"

    # Update last-modified date in header
    sed -i "s/# Last Updated: .*/# Last Updated: $today/" "$TARGET_CLAUDE"
    echo "    ✓ Last updated date refreshed"
    echo "  ✓ CLAUDE.md upgraded — your custom content was preserved"

  else
    # ── Case 3: Foreign CLAUDE.md (no anchors) — append, never overwrite ─────
    echo "  Existing CLAUDE.md detected (no anchors — external/handwritten)..."
    echo "  Preserving all existing content and appending claude-project-template sections..."

    # Inject anchor markers into the template sections we'll append
    local append_block="\n\n---\n"
    append_block+="<!-- Added by claude-project-template on $today -->\n\n"

    # Read first
    append_block+="<!-- CLAUDE_READ_FIRST_START -->\n"
    append_block+="$(extract_section "$TEMPLATE_CLAUDE" "CLAUDE_READ_FIRST_START" "CLAUDE_READ_FIRST_END")\n"
    append_block+="<!-- CLAUDE_READ_FIRST_END -->\n\n---\n\n"

    # Existing files
    if [[ -n "$existing_files_block" ]]; then
      append_block+="<!-- CLAUDE_EXISTING_FILES_START -->\n"
      append_block+="${existing_files_block}\n"
      append_block+="<!-- CLAUDE_EXISTING_FILES_END -->\n\n---\n\n"
    else
      append_block+="<!-- CLAUDE_EXISTING_FILES_START -->\n"
      append_block+="<!-- CLAUDE_EXISTING_FILES_END -->\n\n---\n\n"
    fi

    # Protocols
    append_block+="<!-- CLAUDE_PROTOCOLS_START -->\n"
    append_block+="$(extract_section "$TEMPLATE_CLAUDE" "CLAUDE_PROTOCOLS_START" "CLAUDE_PROTOCOLS_END")\n"
    append_block+="<!-- CLAUDE_PROTOCOLS_END -->\n\n---\n\n"

    # Agent roster
    append_block+="<!-- CLAUDE_AGENTS_START -->\n"
    append_block+="${agent_table}\n"
    append_block+="<!-- CLAUDE_AGENTS_END -->\n"

    printf "%b" "$append_block" >> "$TARGET_CLAUDE"
    echo "  ✓ Sections appended — original content untouched"
    echo "  ℹ  Re-run anytime with: bash init-claude-project.sh --upgrade"
  fi
}

# ─── README Update Mode ───────────────────────────────────────────────────────

update_readme_agents_table() {
  if [[ ! -f "$README_PATH" ]]; then
    echo "❌ README.md not found at: $README_PATH"
    exit 1
  fi

  echo "Rebuilding agents table in README.md..."

  local new_block
  new_block="<!-- AGENTS_TABLE_START -->"$'\n'
  new_block+="### Available Agents"$'\n\n'
  new_block+="| Agent | File | Best Used For |"$'\n'
  new_block+="|---|---|---|"$'\n'

  for entry in "${AGENT_REGISTRY[@]}"; do
    IFS='|' read -r file name description <<< "$entry"
    new_block+="| $name | \`$file\` | $description |"$'\n'
  done

  new_block+="<!-- AGENTS_TABLE_END -->"

  awk -v new="$new_block" '
    /<!-- AGENTS_TABLE_START -->/ { printing=1; print new; next }
    /<!-- AGENTS_TABLE_END -->/   { printing=0; next }
    !printing { print }
  ' "$README_PATH" > "$README_PATH.tmp" && mv "$README_PATH.tmp" "$README_PATH"

  echo "  ✓ README.md agents table updated (${#AGENT_REGISTRY[@]} agents)"
}

# ─── Upgrade Mode ─────────────────────────────────────────────────────────────

if [[ "$1" == "--update-readme" ]]; then
  update_readme_agents_table
  exit 0
fi

if [[ "$1" == "--upgrade" ]]; then
  echo ""
  echo "╔══════════════════════════════════════════╗"
  echo "║       Claude Project — Upgrade Mode      ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""
  echo "Target: $TARGET_DIR"
  echo ""

  # Collect currently installed agents
  INSTALLED_AGENTS=()
  if [[ -d "$TARGET_DIR/.claude/agents" ]]; then
    for f in "$TARGET_DIR/.claude/agents"/*.md; do
      [[ -f "$f" ]] && INSTALLED_AGENTS+=("$(basename "$f")")
    done
  fi

  if [[ ${#INSTALLED_AGENTS[@]} -eq 0 ]]; then
    echo "  ⚠ No agents found in .claude/agents/ — run full init first"
    exit 1
  fi

  echo "  Detected installed agents:"
  for a in "${INSTALLED_AGENTS[@]}"; do echo "    - ${a%.md}"; done
  echo ""

  PROJECT_NAME="" PROJECT_TYPE="" PROJECT_STACK=""
  merge_claude_md "${INSTALLED_AGENTS[@]}"
  echo ""
  echo "✓ Upgrade complete."
  exit 0
fi

# ─── Full Init Mode ───────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     Claude Project Structure Init        ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Target directory: $TARGET_DIR"
echo ""

# ─── Project Info ─────────────────────────────────────────────────────────────

read -p "Project name: " PROJECT_NAME
read -p "Project type (dashboard / api / full-stack / cli / other): " PROJECT_TYPE
read -p "Tech stack (e.g. Laravel + React + PostgreSQL): " PROJECT_STACK

echo ""
echo "Select the agents you need for this project:"
echo ""

# ─── Agent Selection ──────────────────────────────────────────────────────────

SELECTED_AGENTS=()

for entry in "${AGENT_REGISTRY[@]}"; do
  IFS='|' read -r file name description <<< "$entry"
  read -p "  Include $name — $description? (y/n): " yn
  if [[ "$yn" == "y" || "$yn" == "Y" ]]; then
    SELECTED_AGENTS+=("$file")
    echo "    ✓ $name added"
  fi
done

echo ""

# ─── Create Directory Structure ───────────────────────────────────────────────

echo "Creating .claude/ structure..."
mkdir -p "$TARGET_DIR/.claude/agents"
mkdir -p "$TARGET_DIR/.claude/commands"
mkdir -p "$TARGET_DIR/.claude/knowledge"

# ─── Copy Selected Agents ─────────────────────────────────────────────────────

for agent in "${SELECTED_AGENTS[@]}"; do
  if [[ -f "$TEMPLATE_DIR/.claude/agents/$agent" ]]; then
    cp "$TEMPLATE_DIR/.claude/agents/$agent" "$TARGET_DIR/.claude/agents/$agent"
    echo "  ✓ Copied agent: $agent"
  else
    echo "  ⚠ Agent file not found: $agent (skipping)"
  fi
done

# ─── Copy Commands ────────────────────────────────────────────────────────────

cp "$TEMPLATE_DIR/.claude/commands/end-session.md" "$TARGET_DIR/.claude/commands/end-session.md"
echo "  ✓ Copied command: /end-session"

# ─── Initialize Knowledge Base ────────────────────────────────────────────────

TODAY=$(date +"%Y-%m-%d")

for file in components.md mistakes.md patterns.md session-log.md; do
  if [[ ! -f "$TARGET_DIR/.claude/knowledge/$file" ]]; then
    cp "$TEMPLATE_DIR/.claude/knowledge/$file" "$TARGET_DIR/.claude/knowledge/$file"
    sed -i "s/\[DATE\]/$TODAY/g" "$TARGET_DIR/.claude/knowledge/$file"
    echo "  ✓ Initialized knowledge/$file"
  else
    echo "  ↷ Skipped knowledge/$file (already exists)"
  fi
done

# ─── Smart CLAUDE.md Merge ────────────────────────────────────────────────────

echo ""
echo "Processing CLAUDE.md..."
merge_claude_md "${SELECTED_AGENTS[@]}"

# ─── .gitignore ───────────────────────────────────────────────────────────────

GITIGNORE="$TARGET_DIR/.gitignore"
if [[ -f "$GITIGNORE" ]]; then
  if ! grep -q ".claude/knowledge" "$GITIGNORE" 2>/dev/null; then
    echo "" >> "$GITIGNORE"
    echo "# Claude knowledge base — commit these for team continuity" >> "$GITIGNORE"
    echo "# .claude/knowledge/  ← Uncomment to exclude from git" >> "$GITIGNORE"
  fi
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║              Setup Complete              ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "  1. Open CLAUDE.md and fill in Project Structure and Stack Notes"
echo "  2. Start a Claude Code session — it reads CLAUDE.md automatically"
echo "  3. Run /end-session before exiting each session"
echo "  4. Commit .claude/ to version control"
echo ""
echo "Agents installed (${#SELECTED_AGENTS[@]}):"
for agent in "${SELECTED_AGENTS[@]}"; do
  echo "  - ${agent%.md}"
done
echo ""
echo "Useful commands:"
echo "  bash init-claude-project.sh --upgrade        — re-merge CLAUDE.md after adding agents"
echo "  bash init-claude-project.sh --update-readme  — rebuild README agents table"
echo ""
