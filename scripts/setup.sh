#!/usr/bin/env bash
set -euo pipefail

# ─── Clara Setup Script ───
# Creates Turso tables, seeds prompts, imports n8n workflows
#
# Required env vars:
#   TURSO_URL       — e.g. https://org-db.turso.io
#   TURSO_AUTH_TOKEN — Turso API token
#   N8N_BASE_URL    — e.g. http://localhost:5678 (default)
#   N8N_API_KEY     — n8n API key (Settings > API > Create API Key)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

TURSO_URL="${TURSO_URL:?TURSO_URL not set}"
TURSO_AUTH_TOKEN="${TURSO_AUTH_TOKEN:?TURSO_AUTH_TOKEN not set}"
N8N_BASE_URL="${N8N_BASE_URL:-http://localhost:5678}"
N8N_API_KEY="${N8N_API_KEY:?N8N_API_KEY not set}"

# ─── Colors ───
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
info() { echo -e "${YELLOW}→${NC} $1"; }

# ─── Step 1: Create tables ───
info "Creating database tables..."

SCHEMA=$(cat "$PROJECT_DIR/schema.sql")

# Escape schema for JSON
SCHEMA_ESCAPED=$(echo "$SCHEMA" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

TURSO_PAYLOAD=$(cat <<EOF
{
  "requests": [
    {
      "type": "execute",
      "stmt": { "sql": ${SCHEMA_ESCAPED} }
    }
  ]
}
EOF
)

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${TURSO_URL}/v2/pipeline" \
  -H "Authorization: Bearer ${TURSO_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${TURSO_PAYLOAD}")

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  ok "Tables created"
else
  fail "Turso returned HTTP $HTTP_CODE — check TURSO_URL and TURSO_AUTH_TOKEN"
fi

# ─── Step 2: Seed prompts ───
info "Seeding prompts..."

seed_prompt() {
  local key="$1"
  local file="$2"
  local content
  content=$(cat "$file")
  # Escape for JSON
  local escaped
  escaped=$(echo "$content" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

  local payload
  payload=$(cat <<EOF
{
  "requests": [
    {
      "type": "execute",
      "stmt": {
        "sql": "INSERT OR REPLACE INTO prompts (key, role, content) VALUES (?, 'system', ?)",
        "args": [
          { "type": "text", "value": "${key}" },
          { "type": "text", "value": ${escaped} }
        ]
      }
    }
  ]
}
EOF
)

  curl -s -X POST "${TURSO_URL}/v2/pipeline" \
    -H "Authorization: Bearer ${TURSO_AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${payload}" > /dev/null
}

seed_prompt "soul"             "$PROJECT_DIR/prompts/soul.md"
ok "Soul prompt seeded"

seed_prompt "extractor"        "$PROJECT_DIR/prompts/extractor.md"
ok "Extractor prompt seeded"

seed_prompt "emotion_tracker"  "$PROJECT_DIR/prompts/emotion_tracker.md"
ok "Emotion tracker prompt seeded"

seed_prompt "fact_manager"     "$PROJECT_DIR/prompts/fact_manager.md"
ok "Fact manager prompt seeded"

# ─── Step 3: Import workflows into n8n ───
info "Importing workflows into n8n..."

import_workflow() {
  local file="$1"
  # Strip read-only fields (active, tags) before importing
  local cleaned
  cleaned=$(python3 -c "
import json, sys
wf = json.load(open('$file'))
wf.pop('active', None)
wf.pop('tags', None)
json.dump(wf, sys.stdout)
")
  local name
  name=$(echo "$cleaned" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")

  # Check if workflow already exists
  local existing
  existing=$(curl -s -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    "${N8N_BASE_URL}/api/v1/workflows" | \
    python3 -c "import sys,json; ws=json.load(sys.stdin).get('data',[]); print(next((w['id'] for w in ws if w['name']=='${name}'), ''))" 2>/dev/null || echo "")

  if [ -n "$existing" ]; then
    info "  Updating existing workflow: ${name} (id: ${existing})"
    curl -s -X PATCH "${N8N_BASE_URL}/api/v1/workflows/${existing}" \
      -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
      -H "Content-Type: application/json" \
      -d "$cleaned" > /dev/null
  else
    info "  Creating new workflow: ${name}"
    curl -s -X POST "${N8N_BASE_URL}/api/v1/workflows" \
      -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
      -H "Content-Type: application/json" \
      -d "$cleaned" > /dev/null
  fi
}

for wf in "$PROJECT_DIR"/workflows/*.json; do
  import_workflow "$wf"
  ok "Imported: $(basename "$wf")"
done

# ─── Step 4: Activate workflows ───
info "Activating workflows..."

activate_workflow() {
  local name="$1"
  local id
  id=$(curl -s -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    "${N8N_BASE_URL}/api/v1/workflows" | \
    python3 -c "
import sys,json
ws = json.load(sys.stdin).get('data',[])
target = '''${name}'''
for w in ws:
    if w['name'] == target:
        print(w['id'])
        break
" 2>/dev/null || echo "")

  if [ -n "$id" ]; then
    curl -s -X PATCH "${N8N_BASE_URL}/api/v1/workflows/${id}" \
      -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
      -H "Content-Type: application/json" \
      -d '{"active": true}' > /dev/null
    ok "Activated: ${name}"
  else
    echo -e "${YELLOW}⚠${NC} Could not find workflow: ${name}"
  fi
}

# Use python to activate by partial name match (handles em dashes)
python3 -c "
import json, urllib.request

API_KEY = '${N8N_API_KEY}'
BASE = '${N8N_BASE_URL}'

req = urllib.request.Request(f'{BASE}/api/v1/workflows', headers={'X-N8N-API-KEY': API_KEY})
data = json.loads(urllib.request.urlopen(req).read())
workflows = data.get('data', [])

targets = ['Chat', 'Cleanup', 'Extractor', 'Emotion']
for w in workflows:
    for t in targets:
        if t.lower() in w['name'].lower() and 'Clara' in w['name']:
            body = json.dumps({'active': True}).encode()
            req = urllib.request.Request(f'{BASE}/api/v1/workflows/{w[\"id\"]}', data=body, headers={'X-N8N-API-KEY': API_KEY, 'Content-Type': 'application/json'}, method='PATCH')
            urllib.request.urlopen(req)
            print(f'  ✓ Activated: {w[\"name\"]}')
            break
" 2>/dev/null || echo -e "${YELLOW}⚠${NC} Could not auto-activate workflows"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}Clara is ready.${NC}"
echo ""
echo "  Chat endpoint:  ${N8N_BASE_URL}/webhook/clara-chat"
echo "  Test command:"
echo ""
echo "  curl -X POST ${N8N_BASE_URL}/webhook/clara-chat \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"message\": \"hey clara\"}'"
echo ""
echo "  To start a new session, omit session_id."
echo "  To continue, include the session_id from the response."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
