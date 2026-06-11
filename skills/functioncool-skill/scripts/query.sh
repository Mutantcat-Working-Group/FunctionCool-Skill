#!/usr/bin/env bash
# query.sh — Compatibility shim for the FunctionCool skill.
#
# The canonical implementation is now scripts/query.py (cross-platform:
# works on Windows, macOS, and Linux with no third-party dependencies).
# This bash wrapper is kept so that any existing
#
#     bash ~/.claude/skills/functioncool/scripts/query.sh "<query>" "<LANG>"
#
# invocations — including the ones hardcoded in older SKILL.md revisions,
# custom wrappers, or muscle memory — continue to work unchanged. It
# forwards the call to query.py using whichever `python3` / `python` it
# can find on PATH.
#
# For new code, call query.py directly:
#   python3 ~/.claude/skills/functioncool/scripts/query.py "<query>" "<LANG>"
#
# On Windows, prefer:
#   python  "$env:USERPROFILE\.claude\skills\functioncool\scripts\query.py" ...
# or the PowerShell-native fallback scripts/query.ps1.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v python3 >/dev/null 2>&1; then
    exec python3 "$DIR/query.py" "$@"
elif command -v python >/dev/null 2>&1; then
    exec python "$DIR/query.py" "$@"
else
    # No Python on PATH. Emit the slim-JSON contract on stdout and a clear
    # stderr message so the model (and the user) know exactly what's wrong.
    echo '{"query":"","lang":"all","count":0,"results":[],"error":"python not found"}'
    echo "FunctionCool: python3 or python is required but was not found on PATH." >&2
    echo "FunctionCool: install Python 3, or on Windows use scripts/query.ps1." >&2
    exit 1
fi
