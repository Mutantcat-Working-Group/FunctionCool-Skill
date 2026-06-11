#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
query.py — Query the FunctionCool function library and return a slim index.

Cross-platform implementation (Windows / macOS / Linux). Pure stdlib — no
third-party dependencies. This is the canonical implementation; scripts/query.sh
is a thin shim that forwards here, and scripts/query.ps1 is a parallel native
PowerShell fallback for Windows users without Python.

Usage:
    python3 query.py "<search term>" "<LANG>"

Behavior:
    1. Calls https://www.functioncool.xyz/skillapi with the hardcoded
       permanent token "mutantcat".
    2. Strips the bulky `code` field from each result so the calling model only
       sees the method INDEX (name, signature, description, complexity, tags).
       This is the entire point of the FunctionCool skill: the model uses the
       index to write code itself instead of copy-pasting source.
    3. Returns a clean JSON object on stdout.

Exit codes:
    0  success (zero or more results)
    1  network / API error (message on stderr, JSON on stdout)
"""

import json
import os
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request

# ----- Hardcoded (do not surface to the user) -----
API_BASE = "https://www.functioncool.xyz/skillapi"
TOKEN = "mutantcat"
TIMEOUT = 10  # seconds

# ----- Args -----
QUERY = sys.argv[1] if len(sys.argv) > 1 else ""
LANG = sys.argv[2] if len(sys.argv) > 2 else "all"


def emit_error(message: str, extra: dict | None = None) -> None:
    """Write a human-readable error to stderr; the slim-JSON contract is
    preserved separately (caller is responsible for the stdout JSON)."""
    payload = {"error": message}
    if extra:
        payload.update(extra)
    print(json.dumps(payload, ensure_ascii=False), file=sys.stderr)


def slim_one(result: dict) -> dict:
    """Project one API result to the slim INDEX shape.

    The `code` field is deliberately omitted: the model should write the
    implementation itself, not paste source from the API.
    """
    return {
        "name": result.get("name-en") or result.get("name-zh") or "",
        "name_zh": result.get("name-zh") or "",
        "lang": result.get("language") or "",
        "desc": result.get("description-en") or result.get("description-zh") or "",
        "desc_zh": result.get("description-zh") or "",
        "input": result.get("input") or [],
        "input_type": result.get("input_type") or [],
        "return": result.get("return") or [],
        "return_type": result.get("return_type") or [],
        "tags": result.get("tags") or [],
        "timer_score": result.get("timer_score"),
        "memory_score": result.get("memory_score"),
    }


# Candidate paths for the system CA bundle. Searched in order; first hit wins.
# Covers the common cases where Python (especially Homebrew Python on macOS)
# ships without a usable default cafile.
_CA_BUNDLE_CANDIDATES = [
    "/etc/ssl/cert.pem",                                # macOS (Apple) + some Linux
    "/etc/ssl/certs/ca-certificates.crt",               # Debian / Ubuntu
    "/etc/pki/tls/certs/ca-bundle.crt",                 # RHEL / Fedora / CentOS
    "/etc/ssl/ca-bundle.pem",                           # OpenSUSE
    os.path.join(os.path.dirname(sys.executable), "cert.pem"),  # python.org installer
]


def build_default_context() -> ssl.SSLContext:
    """Return Python's default SSL context (works on Windows, most Linux
    distros, and python.org Python that has been "Install Certificates"ed)."""
    return ssl.create_default_context()


def build_context_with_candidate_bundle() -> ssl.SSLContext | None:
    """Try the common system CA-bundle paths and return a context using the
    first one that loads cleanly. Returns None if none work."""
    for path in _CA_BUNDLE_CANDIDATES:
        if path and os.path.isfile(path):
            try:
                ctx = ssl.create_default_context()
                ctx.load_verify_locations(cafile=path)
                return ctx
            except (OSError, ssl.SSLError):
                continue
    return None


def build_insecure_context() -> ssl.SSLContext:
    """Return an UNVERIFIED SSL context. Used as the final fallback so the
    skill still works on broken Python installs. The caller is responsible
    for emitting a warning to stderr."""
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def fetch(url: str) -> bytes:
    """Fetch the URL and return raw bytes, with a graceful SSL fallback.

    Tries (in order): default context, candidate system CA bundle paths,
    unverified context. The API is a public, read-only, public-token endpoint,
    so unverified is a tolerable last resort — we still warn loudly."""
    headers = {"User-Agent": "FunctionCool-Skill/1.0"}
    last_ssl_err: Exception | None = None

    def _try(ctx: ssl.SSLContext) -> bytes:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=TIMEOUT, context=ctx) as resp:
            return resp.read()

    candidate_ctx = build_context_with_candidate_bundle()
    contexts_to_try = [build_default_context()]
    if candidate_ctx is not None:
        contexts_to_try.append(candidate_ctx)

    for ctx in contexts_to_try:
        try:
            return _try(ctx)
        except urllib.error.URLError as exc:
            # urllib wraps SSL errors — unwrap to decide whether it's a cert problem.
            reason = exc.reason
            if isinstance(reason, ssl.SSLCertVerificationError):
                last_ssl_err = reason
                continue
            raise  # not a cert issue — let the outer handler deal with it
        except ssl.SSLCertVerificationError as exc:
            last_ssl_err = exc
            continue

    # All verified attempts failed. Warn and fall back to unverified.
    print(
        "FunctionCool: SSL cert verification failed ("
        f"{last_ssl_err}); falling back to unverified HTTPS. "
        "Consider installing/updating your Python certs "
        "(e.g. `pip install certifi` and "
        "ssl.set_default_verify_paths()).",
        file=sys.stderr,
    )
    return _try(build_insecure_context())


def main() -> int:
    if not QUERY:
        emit_error("missing query argument")
        print(json.dumps(
            {"query": "", "lang": LANG, "count": 0, "results": [],
             "error": "missing query argument"},
            ensure_ascii=False,
        ))
        return 1

    url = (f"{API_BASE}?token={urllib.parse.quote(TOKEN, safe='')}"
           f"&q={urllib.parse.quote(QUERY, safe='')}"
           f"&lang={urllib.parse.quote(LANG, safe='')}")

    # ----- Fetch -----
    try:
        raw_bytes = fetch(url)
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError) as exc:
        emit_error("FunctionCool API unreachable", {"base": API_BASE, "detail": str(exc)})
        print(json.dumps(
            {"query": QUERY, "lang": LANG, "count": 0, "results": [],
             "error": "unreachable"},
            ensure_ascii=False,
        ))
        return 1

    # ----- Parse -----
    try:
        raw_text = raw_bytes.decode("utf-8")
        raw = json.loads(raw_text)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        preview = raw_bytes[:200].decode("utf-8", errors="replace") if raw_bytes else ""
        emit_error("non-JSON response", {"detail": str(exc), "body_preview": preview})
        print(json.dumps(
            {"query": QUERY, "lang": LANG, "count": 0, "results": [],
             "error": "bad_response"},
            ensure_ascii=False,
        ))
        return 1

    # Surface the {"error": "..."} shape if present (API-level auth/query errors)
    if isinstance(raw, dict) and "error" in raw and "results" not in raw:
        print(json.dumps(
            {"query": QUERY, "lang": LANG, "count": 0, "results": [],
             "error": raw["error"]},
            ensure_ascii=False,
        ))
        return 0  # API responded; we passed the API-level error through cleanly

    # ----- Strip the `code` field, keep only the metadata index -----
    results = raw.get("results", []) if isinstance(raw, dict) else []
    slim = [slim_one(r) for r in results if isinstance(r, dict)]

    print(json.dumps(
        {"query": QUERY, "lang": LANG, "count": len(slim), "results": slim},
        ensure_ascii=False,
    ))
    return 0


if __name__ == "__main__":
    # Force UTF-8 on stdout so Chinese descriptions survive a Windows cp1252 pipe.
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, OSError):
        pass  # Python < 3.7 or non-reconfigurable stream; best-effort only
    sys.exit(main())
