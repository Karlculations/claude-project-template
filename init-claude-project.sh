#!/usr/bin/env bash
# init-claude-project.sh
# Usage:
#   bash init-claude-project.sh              — full project init or smart upgrade
#   bash init-claude-project.sh --upgrade    — re-run merge on existing CLAUDE.md only
#   bash init-claude-project.sh --sync       — refresh agent bodies + commands + CLAUDE.md, seed changelogs
#   bash init-claude-project.sh --update-readme  — rebuild README agents table

set -e

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$(pwd)"
README_PATH="$TEMPLATE_DIR/README.md"
TARGET_CLAUDE="$TARGET_DIR/CLAUDE.md"
TEMPLATE_CLAUDE="$TEMPLATE_DIR/CLAUDE.md"

# ─── Stack Catalog Locations ──────────────────────────────────────────────────
# Overridable so tests never touch the real ~/.claude or templates/.
STACK_CATALOG="${CLAUDE_STACK_CATALOG:-$TEMPLATE_DIR/templates/catalog.json}"
STACK_SKILLS_DIR="${CLAUDE_STACK_SKILLS_DIR:-$TEMPLATE_DIR/templates/skills}"

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

# ─── Collect Installed Agents ─────────────────────────────────────────────────
# Populate the global INSTALLED_AGENTS array from the target project's
# .claude/agents/ directory. Used by both --upgrade and --sync so they operate
# on exactly the agents this project selected at init time.
collect_installed_agents() {
  INSTALLED_AGENTS=()
  if [[ -d "$TARGET_DIR/.claude/agents" ]]; then
    for f in "$TARGET_DIR/.claude/agents"/*.md; do
      [[ -f "$f" ]] && INSTALLED_AGENTS+=("$(basename "$f")")
    done
  fi
}

# ─── Sync Agent Bodies ────────────────────────────────────────────────────────
# Refresh the file *contents* of agents the project already has from the
# template. Iterates over INSTALLED_AGENTS (the project's selection), so it
# never adds an agent the project deliberately left out. A project-local agent
# with no template source is reported and left as-is.
sync_agent_bodies() {
  local count=0
  for agent in "${INSTALLED_AGENTS[@]}"; do
    if [[ -f "$TEMPLATE_DIR/.claude/agents/$agent" ]]; then
      cp "$TEMPLATE_DIR/.claude/agents/$agent" "$TARGET_DIR/.claude/agents/$agent"
      echo "    ✓ Synced agent: ${agent%.md}"
      count=$((count + 1))
    else
      echo "    ⚠ ${agent%.md} has no template source — left as-is (project-local agent)"
    fi
  done
  echo "    → $count agent file(s) refreshed from template"
}

# ─── Sync Commands ────────────────────────────────────────────────────────────
# Refresh every template-owned command into the project. Commands are universal
# infrastructure (not opt-in like agents), so all of them are kept current.
sync_commands() {
  mkdir -p "$TARGET_DIR/.claude/commands"
  local count=0
  for cmd in "$TEMPLATE_DIR/.claude/commands"/*.md; do
    [[ -f "$cmd" ]] || continue
    cp "$cmd" "$TARGET_DIR/.claude/commands/$(basename "$cmd")"
    echo "    ✓ Synced command: /$(basename "${cmd%.md}")"
    count=$((count + 1))
  done
  echo "    → $count command file(s) refreshed from template"
}

# ─── Sync Autonomy Layer ──────────────────────────────────────────────────────
# Hook scripts + autopilot are template-owned and overwritten like commands.
# settings.json is merged additively: created if absent; statusLine added only
# when missing; hook entries appended per-event only when no existing entry
# references the same script basename — existing entries never modified.
sync_autonomy() {
  mkdir -p "$TARGET_DIR/.claude/hooks"
  local f count=0
  for f in "$TEMPLATE_DIR/.claude/hooks"/*.sh; do
    [[ -f "$f" ]] || continue
    cp "$f" "$TARGET_DIR/.claude/hooks/$(basename "$f")"
    chmod +x "$TARGET_DIR/.claude/hooks/$(basename "$f")"
    count=$((count + 1))
  done
  cp "$TEMPLATE_DIR/.claude/autopilot.sh" "$TARGET_DIR/.claude/autopilot.sh"
  chmod +x "$TARGET_DIR/.claude/autopilot.sh"
  echo "    → $count hook script(s) + autopilot refreshed"

  local tgt="$TARGET_DIR/.claude/settings.json" src="$TEMPLATE_DIR/.claude/settings.json"
  if [[ ! -f "$tgt" ]]; then
    cp "$src" "$tgt"
    echo "    ✓ settings.json created (statusline + autonomy hooks)"
  elif ! command -v jq >/dev/null 2>&1; then
    echo "    ⚠ settings.json exists and jq is unavailable — merge hooks/statusLine manually from $src"
  elif ! jq -e . "$tgt" >/dev/null 2>&1; then
    echo "    ⚠ settings.json exists but is not valid JSON — fix it, then merge hooks/statusLine manually from $src"
  else
    # Additive, idempotent hooks merge: a template hook entry is appended only
    # when no existing entry for that event already references the same script
    # basename. Existing entries (user-modified or older-version) are NEVER
    # touched, so template updates that add a new hook reach synced projects.
    # Opt out of a guard with CLAUDE_AUTONOMY=off — deleting its entry means
    # the next --sync re-adds it.
    local before after
    before=$(jq '[.hooks // {} | .[][]] | length' "$tgt")
    if jq -s '.[1] as $tpl | .[0]
              | (if has("statusLine") then . else . + {statusLine: $tpl.statusLine} end)
              | (.hooks // {}) as $th
              | .hooks = (reduce ($tpl.hooks | to_entries[]) as $e ($th;
                  ([ ($th[$e.key] // [])[] | .hooks[]?.command // empty | split("/") | last ]) as $have
                  | .[$e.key] = (($th[$e.key] // [])
                      + ($e.value | map(select(
                          [ .hooks[]?.command // empty | split("/") | last ] | inside($have) | not
                        ))))
                ))' \
         "$tgt" "$src" > "$tgt.tmp" && mv "$tgt.tmp" "$tgt"; then
      after=$(jq '[.hooks // {} | .[][]] | length' "$tgt")
      if (( after > before )); then
        echo "    ✓ settings.json merged — $(( after - before )) autonomy hook entr$( (( after - before == 1 )) && echo y || echo ies) added (existing hooks preserved)"
      else
        echo "    ✓ settings.json up to date (existing keys preserved)"
      fi
    else
      rm -f "$tgt.tmp"
      echo "    ⚠ settings.json merge failed — file left unchanged; wire hooks manually from $src"
    fi
  fi
}

# ─── Stack Catalog Capture ────────────────────────────────────────────────────
# --capture: refresh templates/catalog.json + templates/skills/ from THIS
# machine's user-level Claude Code config. Curated fields (group/description)
# survive refreshes; new items land in "ungrouped"; items no longer on the
# machine are kept and reported, never auto-removed. MCP env/header values are
# ALWAYS redacted to ${SERVERID_KEY} placeholders — a credential must never
# reach the repo.
capture_stack() {
  local user_dir="${CLAUDE_USER_DIR:-$HOME/.claude}"
  local user_config="${CLAUDE_USER_CONFIG:-$HOME/.claude.json}"

  if ! command -v jq >/dev/null 2>&1; then
    echo "❌ --capture requires jq"
    exit 1
  fi

  echo "Capturing stack from: $user_dir"

  # Plugins: user-level object {"x@y": true} → [{id, group, description}],
  # enabled entries only.
  local plugins='[]'
  if [[ -f "$user_dir/settings.json" ]]; then
    plugins=$(jq '[.enabledPlugins // {} | to_entries[] | select(.value == true)
                   | {id: .key, group: "ungrouped", description: ""}]' \
              "$user_dir/settings.json" 2>/dev/null) || plugins='[]'
  fi

  # Marketplaces: keep only the source ref — install paths and timestamps are
  # machine-local noise.
  local marketplaces='{}'
  if [[ -f "$user_dir/plugins/known_marketplaces.json" ]]; then
    marketplaces=$(jq 'with_entries(.value |= {source: .source})' \
                   "$user_dir/plugins/known_marketplaces.json" 2>/dev/null) || marketplaces='{}'
  fi

  # MCP servers (user scope only), env/header values redacted at the source.
  local mcps='[]'
  if [[ -f "$user_config" ]]; then
    mcps=$(jq '
      def slug: ascii_upcase | gsub("[^A-Z0-9]"; "_");
      [.mcpServers // {} | to_entries[]
       | .key as $id
       | {id: $id, group: "ungrouped", description: "",
          config: (.value
            | if .env then .env = (.env
                | with_entries(.value = "${\($id | slug)_\(.key | slug)}")) else . end
            | if .headers then .headers = (.headers
                | with_entries(.value = "${\($id | slug)_\(.key | slug)}")) else . end)}]
    ' "$user_config" 2>/dev/null) || mcps='[]'
  fi

  # Skills: catalog entry (description scraped from frontmatter) + body snapshot.
  local skills='[]' d name desc
  if [[ -d "$user_dir/skills" ]]; then
    mkdir -p "$STACK_SKILLS_DIR"
    for d in "$user_dir/skills"/*/; do
      [[ -f "${d}SKILL.md" ]] || continue
      name="$(basename "$d")"
      desc="$(awk '/^description:/ { sub(/^description:[[:space:]]*/, ""); print; exit }' "${d}SKILL.md")"
      skills=$(jq --arg id "$name" --arg desc "$desc" \
        '. + [{id: $id, group: "ungrouped", description: $desc}]' <<<"$skills")
      rm -rf "$STACK_SKILLS_DIR/$name"
      # -L: dereference. A user-level skill dir is often itself a symlink (e.g.
      # into a dotfiles checkout); plain `cp -r` would copy the symlink as-is,
      # carrying its (often relative) target — which resolves to nothing once
      # relocated into this repo. -L copies the real content instead.
      cp -rL "${d%/}" "$STACK_SKILLS_DIR/$name"
    done
  fi

  local old='{}'
  if [[ -f "$STACK_CATALOG" ]]; then
    old=$(jq . "$STACK_CATALOG" 2>/dev/null) || old='{}'
  fi

  mkdir -p "$(dirname "$STACK_CATALOG")"
  if ! jq -n \
      --argjson old "$old" \
      --argjson plugins "$plugins" \
      --argjson skills "$skills" \
      --argjson mcps "$mcps" \
      --argjson marketplaces "$marketplaces" \
      --arg today "$(date +%Y-%m-%d)" '
    # Curation survives refreshes: an item already in the catalog keeps its
    # group and (non-empty) description; scraped facts are refreshed.
    def curated($olditems):
      ($olditems | map({key: .id, value: .}) | from_entries) as $o
      | map(
          if $o[.id] == null then .
          else . + {group: ($o[.id].group // "ungrouped")}
                 + (if (($o[.id].description // "") != "")
                    then {description: $o[.id].description} else {} end)
          end);
    # A hand-renamed ${...} env reference in the old catalog wins over the
    # freshly derived one (same key, both are placeholders — never a literal).
    def keep_env_refs($olditems):
      ($olditems | map({key: .id, value: .}) | from_entries) as $o
      | map(. as $item
          | if ($o[$item.id].config.env? // null) == null
               or ($item.config.env? // null) == null then $item
            else $item | .config.env |= with_entries(
              ($o[$item.id].config.env[.key] // "") as $prev
              | if ($prev | test("^\\$\\{[A-Z0-9_]+\\}$"))
                then .value = $prev else . end)
            end);
    def keep_missing($olditems; $newitems):
      ($newitems | map(.id)) as $ids
      | [$olditems[] | select(.id as $i | $ids | index($i) | not)];
    {
      capturedAt: $today,
      marketplaces: $marketplaces,
      groups: ($old.groups // [
        {id: "core-quality",    name: "Core Quality & Workflow", description: "Review, commits, TDD, process guardrails"},
        {id: "frontend-design", name: "Frontend & Design",       description: "Figma, Playwright, UI generation"},
        {id: "cloudflare",      name: "Cloudflare Stack",        description: "Workers, Wrangler, DO, CF email"},
        {id: "email",           name: "Email Stack",             description: "Resend, React Email, deliverability"},
        {id: "backend-data",    name: "Backend & Data",          description: "Supabase, Postman, Laravel"},
        {id: "cms-commerce",    name: "CMS & Commerce",          description: "WordPress, Shopify Liquid"},
        {id: "diagrams",        name: "Diagrams",                description: "Infra + architecture diagram generators"},
        {id: "planning",        name: "Planning & PRDs",         description: "PRD writing, issue breakdown"},
        {id: "workflow-extras", name: "Workflow Extras",         description: "Memory, output styles, misc tooling"}
      ]),
      plugins:    (($plugins | curated($old.plugins // []))
                   + keep_missing($old.plugins // []; $plugins)),
      skills:     (($skills | curated($old.skills // []))
                   + keep_missing($old.skills // []; $skills)),
      mcpServers: (($mcps | curated($old.mcpServers // []) | keep_env_refs($old.mcpServers // []))
                   + keep_missing($old.mcpServers // []; $mcps)),
      connectors: ($old.connectors // [])
    }' > "$STACK_CATALOG.tmp.$$"; then
    rm -f "$STACK_CATALOG.tmp.$$"
    echo "❌ catalog build failed — $STACK_CATALOG left unchanged"
    exit 1
  fi
  mv "$STACK_CATALOG.tmp.$$" "$STACK_CATALOG"

  # Summary + curation/hygiene warnings.
  local total ungrouped missing suspicious
  total=$(jq '[.plugins, .skills, .mcpServers] | map(length) | add' "$STACK_CATALOG")
  echo "  ✓ catalog written: $STACK_CATALOG ($total items)"
  ungrouped=$(jq -r '[.plugins[], .skills[], .mcpServers[]
                      | select(.group == "ungrouped") | .id] | join(", ")' "$STACK_CATALOG")
  [[ -n "$ungrouped" ]] && echo "  ⚠ ungrouped (edit the catalog to curate): $ungrouped"
  missing=$(jq -nr --argjson old "$old" --argjson p "$plugins" --argjson s "$skills" --argjson m "$mcps" '
    [($p + $s + $m)[] | .id] as $now
    | [(($old.plugins // []) + ($old.skills // []) + ($old.mcpServers // []))[]
       | .id | select(. as $i | $now | index($i) | not)] | join(", ")')
  [[ -n "$missing" ]] && echo "  ⚠ in catalog but not on this machine (kept): $missing"
  # Flags credentials two ways: "key=..." style embedded in a url/args string,
  # and credentials passed as a separate argv element right after a flag like
  # --api-key (no "=" to grep for). Warn-only — never auto-rewrite url/args.
  suspicious=$(jq -r '[.mcpServers[] | .id as $i
    | ( ((.config.url // ""), ((.config.args // [])[]))
        | select(test("(key|token|secret|password)="; "i")) | $i ),
      ( (.config.args // []) as $a
        | range(0; ($a | length) - 1) as $ix
        | select($a[$ix] | test("^(-H|--header|--token|--key|--api-key|--secret|--password)$"))
        | $i )
    ] | unique | join(", ")' "$STACK_CATALOG")
  [[ -n "$suspicious" ]] && echo "  ⚠ possible inline credential in url/args of: $suspicious — review before committing"
  return 0
}

# ─── Stack Picker ─────────────────────────────────────────────────────────────
# Grouped selection: one [a]ll/[n]one/[p]ick prompt per non-empty catalog
# group, "ungrouped" offered last. Fills the STACK_SEL_* globals; sync_stack
# writes them into the target. All read -p calls consume stdin (tests pipe
# scripted answers) — jq output is loaded via mapfile first so loops never
# steal the prompts' stdin.
STACK_SEL_PLUGINS=()
STACK_SEL_SKILLS=()
STACK_SEL_MCPS=()
STACK_SEL_GROUPS=()

stack_add() {  # $1 = kind (plugin|skill|mcp), $2 = id
  case "$1" in
    plugin) STACK_SEL_PLUGINS+=("$2") ;;
    skill)  STACK_SEL_SKILLS+=("$2") ;;
    mcp)    STACK_SEL_MCPS+=("$2") ;;
  esac
}

pick_stack() {
  if [[ ! -f "$STACK_CATALOG" ]]; then
    echo "  ↷ no stack catalog ($STACK_CATALOG) — skipping stack selection"
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "  ⚠ jq unavailable — skipping stack selection"
    return 0
  fi

  echo ""
  echo "Select the tooling stack for this project (plugins / skills / MCP servers):"

  local group_lines item_lines gline line gid gname gdesc count anp kind id desc yn picked
  mapfile -t group_lines < <(jq -r '
    ((.groups // []) + [{id: "ungrouped", name: "Ungrouped (needs curation)", description: ""}])[]
    | [.id, .name, .description] | @tsv' "$STACK_CATALOG")

  for gline in "${group_lines[@]}"; do
    IFS=$'\t' read -r gid gname gdesc <<< "$gline"
    mapfile -t item_lines < <(jq -r --arg g "$gid" '
      ((.plugins    // [])[] | select(.group == $g) | ["plugin", .id, .description]),
      ((.skills     // [])[] | select(.group == $g) | ["skill",  .id, .description]),
      ((.mcpServers // [])[] | select(.group == $g) | ["mcp",    .id, .description])
      | @tsv' "$STACK_CATALOG")
    (( ${#item_lines[@]} > 0 )) || continue
    count=${#item_lines[@]}
    echo ""
    echo "  ── $gname${gdesc:+ — $gdesc} ($count items)"
    # `|| anp=n`: EOF (Ctrl-D, or a piped answer script running dry) means
    # "none" — never let a read failure kill the run under set -e.
    read -p "     [a]ll / [n]one / [p]ick: " anp || anp="n"
    case "$anp" in
      a|A)
        for line in "${item_lines[@]}"; do
          IFS=$'\t' read -r kind id desc <<< "$line"
          stack_add "$kind" "$id"
        done
        STACK_SEL_GROUPS+=("$gid")
        echo "     ✓ all $count added"
        ;;
      p|P)
        picked=0
        for line in "${item_lines[@]}"; do
          IFS=$'\t' read -r kind id desc <<< "$line"
          read -p "       Include [$kind] $id${desc:+ — $desc}? (y/n): " yn || yn="n"
          if [[ "$yn" == "y" || "$yn" == "Y" ]]; then
            stack_add "$kind" "$id"
            picked=$((picked + 1))
          fi
        done
        (( picked > 0 )) && STACK_SEL_GROUPS+=("$gid")
        echo "     ✓ $picked of $count added"
        ;;
      *) echo "     ↷ skipped" ;;
    esac
  done

  # Connectors are account-bound (claude.ai settings) — recommend, never prompt.
  if (( ${#STACK_SEL_PLUGINS[@]} + ${#STACK_SEL_SKILLS[@]} + ${#STACK_SEL_MCPS[@]} > 0 )); then
    local selg='[]' notes
    (( ${#STACK_SEL_GROUPS[@]} > 0 )) \
      && selg=$(printf '%s\n' "${STACK_SEL_GROUPS[@]}" | jq -R . | jq -s .)
    notes=$(jq -r --argjson sel "$selg" '
      [(.connectors // [])[]
       | select((.group == null) or (.group as $g | $sel | index($g)))
       | "       - \(.id): \(.note // "enable in claude.ai account settings")"]
      | join("\n")' "$STACK_CATALOG")
    if [[ -n "$notes" ]]; then
      echo ""
      echo "     ℹ claude.ai connectors that pair with this selection (account-level — not project-configurable):"
      echo "$notes"
    fi
  fi
}

# ─── Stack Distribution ───────────────────────────────────────────────────────
# Writes the picker's selection into the target as declarative config Claude
# Code natively installs from: enabledPlugins + extraKnownMarketplaces into
# .claude/settings.json (additive), MCP servers into .mcp.json (additive),
# vendored skill bodies into .claude/skills/. No installs are scripted —
# opening Claude Code in the project triggers its own trust/install prompts.
sync_stack() {
  if (( ${#STACK_SEL_PLUGINS[@]} + ${#STACK_SEL_SKILLS[@]} + ${#STACK_SEL_MCPS[@]} == 0 )); then
    echo "    ↷ no stack items selected"
    return 0
  fi

  # 1. Plugins → .claude/settings.json (project-level ARRAY format).
  if (( ${#STACK_SEL_PLUGINS[@]} > 0 )); then
    local tgt="$TARGET_DIR/.claude/settings.json" sel mkts
    sel=$(printf '%s\n' "${STACK_SEL_PLUGINS[@]}" | jq -R . | jq -s .)
    mkts=$(jq --argjson sel "$sel" \
      '($sel | map(split("@")[1]) | unique) as $names
       | (.marketplaces // {}) | with_entries(select(.key as $k | $names | index($k)))' \
      "$STACK_CATALOG")
    mkdir -p "$TARGET_DIR/.claude"
    if [[ ! -f "$tgt" ]]; then
      jq -n --argjson sel "$sel" --argjson m "$mkts" \
        '{enabledPlugins: ($sel | unique), extraKnownMarketplaces: $m}' > "$tgt"
      echo "    ✓ settings.json created (${#STACK_SEL_PLUGINS[@]} plugin(s))"
    elif ! jq -e . "$tgt" >/dev/null 2>&1; then
      echo "    ⚠ settings.json is not valid JSON — add enabledPlugins manually"
    elif [[ "$(jq -r '.enabledPlugins | type' "$tgt")" == "object" ]]; then
      echo "    ⚠ settings.json has object-shaped enabledPlugins (user-level format) — not rewriting; add plugins manually"
    else
      if jq --argjson sel "$sel" --argjson m "$mkts" \
           '.enabledPlugins = ((.enabledPlugins // []) + $sel | unique)
            | .extraKnownMarketplaces = ($m + (.extraKnownMarketplaces // {}))' \
           "$tgt" > "$tgt.tmp.$$" && mv "$tgt.tmp.$$" "$tgt"; then
        echo "    ✓ settings.json: ${#STACK_SEL_PLUGINS[@]} plugin(s) merged additively (existing entries preserved)"
      else
        rm -f "$tgt.tmp.$$"
        echo "    ⚠ plugin merge failed — settings.json left unchanged"
      fi
    fi
  fi

  # 2. MCP servers → .mcp.json (existing keys always win).
  if (( ${#STACK_SEL_MCPS[@]} > 0 )); then
    local mcpf="$TARGET_DIR/.mcp.json" selm cfgs refs
    selm=$(printf '%s\n' "${STACK_SEL_MCPS[@]}" | jq -R . | jq -s .)
    cfgs=$(jq --argjson sel "$selm" \
      '[(.mcpServers // [])[] | select(.id as $i | $sel | index($i))]
       | map({key: .id, value: .config}) | from_entries' "$STACK_CATALOG")
    if [[ ! -f "$mcpf" ]]; then
      jq -n --argjson c "$cfgs" '{mcpServers: $c}' > "$mcpf"
      echo "    ✓ .mcp.json created (${#STACK_SEL_MCPS[@]} server(s))"
    elif ! jq -e . "$mcpf" >/dev/null 2>&1; then
      echo "    ⚠ .mcp.json is not valid JSON — add servers manually"
    else
      if jq --argjson c "$cfgs" '.mcpServers = ($c + (.mcpServers // {}))' \
           "$mcpf" > "$mcpf.tmp.$$" && mv "$mcpf.tmp.$$" "$mcpf"; then
        echo "    ✓ .mcp.json: server(s) merged (existing entries preserved)"
      else
        rm -f "$mcpf.tmp.$$"
        echo "    ⚠ .mcp.json merge failed — left unchanged"
      fi
    fi
    refs=$(jq -nr --argjson c "$cfgs" \
      '[$c | .. | strings | scan("\\$\\{[A-Z0-9_]+\\}")] | unique | join(", ")')
    [[ -n "$refs" ]] && echo "    ℹ set these env vars for the MCP server(s): $refs"
  fi

  # 3. Skills → .claude/skills/ (vendored bodies, template-owned).
  if (( ${#STACK_SEL_SKILLS[@]} > 0 )); then
    mkdir -p "$TARGET_DIR/.claude/skills"
    local s scount=0
    for s in "${STACK_SEL_SKILLS[@]}"; do
      if [[ -d "$STACK_SKILLS_DIR/$s" ]]; then
        rm -rf "$TARGET_DIR/.claude/skills/$s"
        cp -rL "$STACK_SKILLS_DIR/$s" "$TARGET_DIR/.claude/skills/$s"
        scount=$((scount + 1))
      else
        echo "    ⚠ skill '$s' not found in $STACK_SKILLS_DIR — skipped"
      fi
    done
    echo "    → $scount skill(s) vendored into .claude/skills/"
  fi
  return 0
}

# ─── Sync Skills ──────────────────────────────────────────────────────────────
# Mirror of sync_agent_bodies for vendored skills: refresh the bodies of
# skills the project already has from templates/skills/; a skill with no
# template source is project-local and never touched. Never adds skills —
# re-run the full init picker to add stack items.
collect_installed_skills() {
  INSTALLED_SKILLS=()
  local d
  if [[ -d "$TARGET_DIR/.claude/skills" ]]; then
    for d in "$TARGET_DIR/.claude/skills"/*/; do
      [[ -d "$d" ]] || continue
      INSTALLED_SKILLS+=("$(basename "$d")")
    done
  fi
}

sync_skill_bodies() {
  collect_installed_skills
  if (( ${#INSTALLED_SKILLS[@]} == 0 )); then
    echo "    ↷ no project skills to refresh"
    return 0
  fi
  local s count=0
  for s in "${INSTALLED_SKILLS[@]}"; do
    if [[ -d "$STACK_SKILLS_DIR/$s" ]]; then
      rm -rf "$TARGET_DIR/.claude/skills/$s"
      cp -rL "$STACK_SKILLS_DIR/$s" "$TARGET_DIR/.claude/skills/$s"
      echo "    ✓ Synced skill: $s"
      count=$((count + 1))
    else
      echo "    ⚠ $s has no template source — left as-is (project-local skill)"
    fi
  done
  echo "    → $count skill(s) refreshed from template"
}

# ─── Changelog Seeding ────────────────────────────────────────────────────────
# Deterministic layer for public-facing changelogs. Seeds an empty Keep a
# Changelog scaffold at the repo root and in every detected sub-project, and
# NEVER rewrites existing content — the reasoning layer (/end-session) owns
# entries. See docs/superpowers/specs/2026-06-29-changelog-design.md.

# Emit a Keep a Changelog scaffold. Empty scope => root changelog; a non-empty
# scope label produces a scoped header (e.g. "# Changelog — web").
changelog_scaffold() {
  local scope="$1"
  if [[ -z "$scope" ]]; then
    printf '%s\n' \
      "# Changelog" \
      "" \
      "All notable changes to this project are documented in this file." \
      "The format is based on [Keep a Changelog](https://keepachangelog.com/)," \
      "and this project adheres to [Semantic Versioning](https://semver.org/)." \
      "" \
      "## [Unreleased]"
  else
    printf '%s\n' \
      "# Changelog — $scope" \
      "" \
      "Changes to the \`$scope\` part of this project." \
      "The format is based on [Keep a Changelog](https://keepachangelog.com/)," \
      "and this project adheres to [Semantic Versioning](https://semver.org/)." \
      "" \
      "## [Unreleased]"
  fi
}

# Echo a newline-separated, deduped list of sub-project directories (relative to
# target). A directory is a sub-project if it directly contains a marker file.
# Mirrors build_existing_files_block()'s maxdepth + exclusion philosophy.
# Searches from inside $target (relative paths) so an ancestor directory named
# build/dist/node_modules/etc. can never match the exclusion globs.
detect_subprojects() {
  local target="$1"
  (
    cd "$target" 2>/dev/null || exit 0
    local m
    for m in package.json Cargo.toml go.mod pyproject.toml composer.json pom.xml build.gradle Gemfile "*.csproj"; do
      find . -maxdepth 3 -type f -name "$m" \
        ! -path "*/.claude/*" ! -path "*/node_modules/*" \
        ! -path "*/vendor/*" ! -path "*/.git/*" \
        ! -path "*/dist/*" ! -path "*/build/*" 2>/dev/null
    done
    find . -maxdepth 3 -type f -path "*/supabase/config.toml" \
      ! -path "*/.claude/*" ! -path "*/node_modules/*" \
      ! -path "*/vendor/*" ! -path "*/.git/*" \
      ! -path "*/dist/*" ! -path "*/build/*" 2>/dev/null
  ) | while IFS= read -r marker; do
    dir="$(dirname "${marker#./}")"
    if [[ -n "$dir" && "$dir" != "." ]]; then printf '%s\n' "$dir"; fi
  done | sort -u
}

# Return 0 if the file already has an Unreleased section heading, ignoring code
# fences. Matches the same near-canonical variants insert_unreleased would create
# (case-insensitive, optional brackets, optional leading space) so the seeder's
# "already present?" check and its insert trigger can never disagree.
has_unreleased() {
  awk '
    /^[[:space:]]*(```|~~~)/ {
      m = ($0 ~ /```/) ? "`" : "~"
      if (!fence)         { fence = 1; fc = m }
      else if (m == fc)   { fence = 0 }
      next
    }
    fence { next }
    tolower($0) ~ /^[[:space:]]*##[[:space:]]*\[?unreleased\]?/ { found = 1; exit }
    END { exit !found }
  ' "$1"
}

# Insert an empty "## [Unreleased]" above the first real "## " heading (skipping
# any inside a code fence). If there is no such heading, place it just after the
# leading title/intro block (first blank line) rather than at EOF. Existing lines
# are printed verbatim — never rewritten.
insert_unreleased() {
  local file="$1"
  awk '
    { line[NR] = $0 }
    /^[[:space:]]*(```|~~~)/ {
      m = ($0 ~ /```/) ? "`" : "~"
      if (!fence)         { fence = 1; fc = m }
      else if (m == fc)   { fence = 0 }
      next
    }
    fence { next }
    !h2  && /^## /            { h2 = NR }
    !blk && /^[[:space:]]*$/  { blk = NR }
    END {
      ip = h2 ? h2 : (blk ? blk + 1 : NR + 1)
      for (i = 1; i <= NR; i++) {
        if (i == ip) { print "## [Unreleased]"; print "" }
        print line[i]
      }
      if (ip == NR + 1) { print ""; print "## [Unreleased]" }
    }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# Seed root + each detected sub-project with a changelog. Create when missing;
# otherwise preserve completely, adding only a missing [Unreleased] section.
seed_changelogs() {
  local target="$1"
  local created=0 inserted=0 intact=0
  local scopes=( "" )

  local sp
  while IFS= read -r sp; do
    if [[ -n "$sp" ]]; then scopes+=( "$sp" ); fi
  done < <(detect_subprojects "$target")

  local scope dir file label
  for scope in "${scopes[@]}"; do
    if [[ -z "$scope" ]]; then
      dir="$target"; label="root"
    else
      dir="$target/$scope"; label="$scope"
    fi
    file="$dir/CHANGELOG.md"

    if [[ ! -f "$file" ]]; then
      changelog_scaffold "$scope" > "$file.tmp" && mv "$file.tmp" "$file"
      echo "    ✓ created CHANGELOG.md ($label)"
      created=$((created + 1))
    elif has_unreleased "$file"; then
      echo "    ↷ CHANGELOG.md exists ($label) — left intact"
      intact=$((intact + 1))
    else
      insert_unreleased "$file"
      echo "    + added [Unreleased] section ($label)"
      inserted=$((inserted + 1))
    fi
  done

  echo "    → changelogs: $created created, $inserted updated, $intact left intact"
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

if [[ "$1" == "--capture" ]]; then
  capture_stack
  exit 0
fi

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

  collect_installed_agents

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
  echo "  ℹ  To also pull in updated agent definitions and commands, run: bash init-claude-project.sh --sync"
  exit 0
fi

# ─── Sync Mode ────────────────────────────────────────────────────────────────
# Everything --upgrade does (refresh CLAUDE.md's anchored sections), PLUS refresh
# the agent file bodies and commands from the template. Never touches the
# knowledge base or your custom CLAUDE.md content.

if [[ "$1" == "--sync" ]]; then
  echo ""
  echo "╔══════════════════════════════════════════╗"
  echo "║        Claude Project — Sync Mode        ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""
  echo "Target: $TARGET_DIR"
  echo ""

  collect_installed_agents

  if [[ ${#INSTALLED_AGENTS[@]} -eq 0 ]]; then
    echo "  ⚠ No agents found in .claude/agents/ — run full init first"
    exit 1
  fi

  echo "  Syncing agent definitions..."
  sync_agent_bodies
  echo ""
  echo "  Syncing vendored skills..."
  sync_skill_bodies
  echo ""
  echo "  Syncing commands..."
  sync_commands
  echo ""
  echo "  Syncing autonomy layer (hooks + autopilot + settings)..."
  sync_autonomy
  echo ""
  echo "  Updating CLAUDE.md anchored sections..."
  PROJECT_NAME="" PROJECT_TYPE="" PROJECT_STACK=""
  merge_claude_md "${INSTALLED_AGENTS[@]}"
  echo ""
  echo "  Seeding changelogs (root + sub-projects)..."
  seed_changelogs "$TARGET_DIR"
  echo ""
  echo "✓ Sync complete — agent bodies, skills, commands, autonomy layer, CLAUDE.md, and changelogs are current."
  echo "  Knowledge base and custom CLAUDE.md content untouched; existing changelog entries were preserved (an [Unreleased] section was added only where missing)."
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

# ─── Stack Selection ──────────────────────────────────────────────────────────

pick_stack

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

sync_commands

# ─── Autonomy Layer ───────────────────────────────────────────────────────────

echo ""
echo "Installing autonomy layer (statusline + guard hooks + autopilot)..."
sync_autonomy

# ─── Stack Distribution ───────────────────────────────────────────────────────

echo ""
echo "Writing tooling stack (plugins / MCP servers / skills)..."
sync_stack

# ─── Initialize Knowledge Base ────────────────────────────────────────────────

TODAY=$(date +"%Y-%m-%d")

for file in components.md mistakes.md patterns.md session-log.md; do
  if [[ ! -f "$TARGET_DIR/.claude/knowledge/$file" ]]; then
    cp "$TEMPLATE_DIR/templates/knowledge/$file" "$TARGET_DIR/.claude/knowledge/$file"
    sed -i "s/\[DATE\]/$TODAY/g" "$TARGET_DIR/.claude/knowledge/$file"
    echo "  ✓ Initialized knowledge/$file"
  else
    echo "  ↷ Skipped knowledge/$file (already exists)"
  fi
done

# ─── Seed Changelogs ──────────────────────────────────────────────────────────

echo ""
echo "Seeding changelogs (root + sub-projects)..."
seed_changelogs "$TARGET_DIR"

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
echo "  3. Run /end-session before exiting each session — it also drafts CHANGELOG.md entries"
echo "  4. Commit .claude/, CLAUDE.md, and CHANGELOG.md to version control"
echo ""
echo "Agents installed (${#SELECTED_AGENTS[@]}):"
for agent in "${SELECTED_AGENTS[@]}"; do
  echo "  - ${agent%.md}"
done
echo ""
echo "Stack installed: ${#STACK_SEL_PLUGINS[@]} plugin(s), ${#STACK_SEL_MCPS[@]} MCP server(s), ${#STACK_SEL_SKILLS[@]} skill(s)"
echo ""
echo "Useful commands:"
echo "  bash init-claude-project.sh --upgrade        — re-merge CLAUDE.md after adding agents"
echo "  bash init-claude-project.sh --sync           — pull updated agent bodies + commands + CLAUDE.md, and seed changelogs"
echo "  bash init-claude-project.sh --update-readme  — rebuild README agents table"
echo ""
