#!/usr/bin/env bash
# query.sh — Query the FunctionCool function library and return a slim index.
#
# Usage:
#   query.sh "search term" "LANG"
#
# The script:
#   1. Calls the API at https://www.functioncool.xyz/skillapi with the hardcoded
#      permanent token "mutantcat".
#   2. Strips the bulky `code` field from each result so the calling model only
#      sees the method INDEX (name, signature, description, complexity, tags).
#      This is the entire point of the FunctionCool skill: the model uses the
#      index to write code itself instead of copy-pasting source.
#   3. Returns a clean JSON object on stdout.
#
# Exit codes:
#   0  success (zero or more results)
#   1  network / API error (message on stderr, JSON on stdout)

set -euo pipefail

# ----- Hardcoded (do not surface to the user) -----
API_BASE="https://www.functioncool.xyz/skillapi"
TOKEN="mutantcat"
TIMEOUT=10

# ----- Args -----
QUERY="${1:-}"
LANG="${2:-all}"

if [[ -z "$QUERY" ]]; then
    echo '{"error": "missing query argument"}' >&2
    exit 1
fi

# ----- URL-encode (works on macOS + Linux; falls back to python) -----
encode() {
    local raw="$1"
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$raw"
    else
        # last-ditch: use sed; works for simple ASCII + spaces
        printf '%s' "$raw" | sed 's/ /%20/g; s|/|%2F|g; s|?|%3F|g; s|&|%26|g; s|=|%3D|g'
    fi
}

ENCODED_QUERY=$(encode "$QUERY")
ENCODED_LANG=$(encode "$LANG")
URL="${API_BASE}?token=${TOKEN}&q=${ENCODED_QUERY}&lang=${ENCODED_LANG}"

# ----- Fetch -----
RAW=""
if ! RAW=$(curl -sS --max-time "$TIMEOUT" "$URL" 2>/dev/null); then
    echo "{\"error\":\"FunctionCool API unreachable\",\"base\":\"$API_BASE\"}" >&2
    echo '{"results":[],"count":0,"error":"unreachable"}'
    exit 1
fi

# ----- Validate it's JSON and check for the error field -----
if ! echo "$RAW" | python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1; then
    echo "{\"error\":\"non-JSON response\",\"body_preview\":$(printf '%s' "$RAW" | head -c 200 | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')}" >&2
    echo '{"results":[],"count":0,"error":"bad_response"}'
    exit 1
fi

# ----- Strip the `code` field, keep only the metadata index -----
echo "$RAW" | python3 -c '
import json, sys
raw = json.load(sys.stdin)

# Surface the {"error": "..."} shape if present
if isinstance(raw, dict) and "error" in raw and "results" not in raw:
    print(json.dumps({"query": sys.argv[1], "lang": sys.argv[2], "count": 0, "results": [], "error": raw["error"]}, ensure_ascii=False))
    sys.exit(0)

results = raw.get("results", []) if isinstance(raw, dict) else []
slim = []
for r in results:
    if not isinstance(r, dict):
        continue
    slim.append({
        "name": r.get("name-en") or r.get("name-zh") or "",
        "name_zh": r.get("name-zh") or "",
        "lang": r.get("language") or "",
        "desc": r.get("description-en") or r.get("description-zh") or "",
        "desc_zh": r.get("description-zh") or "",
        "input": r.get("input") or [],
        "input_type": r.get("input_type") or [],
        "return": r.get("return") or [],
        "return_type": r.get("return_type") or [],
        "tags": r.get("tags") or [],
        "timer_score": r.get("timer_score"),
        "memory_score": r.get("memory_score"),
        # NOTE: deliberately omit `code` to keep the response small and
        # to force the model to write the implementation itself.
    })

print(json.dumps({
    "query": sys.argv[1],
    "lang": sys.argv[2],
    "count": len(slim),
    "results": slim,
}, ensure_ascii=False))
' "$QUERY" "$LANG"
