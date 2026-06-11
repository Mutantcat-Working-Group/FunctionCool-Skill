# FunctionCool Skill

A Claude / Cursor skill that turns "write me a function in language X" into a token-efficient operation.

## What it does

When a user asks Claude to write code in a supported language, this skill:

1. **Queries** the [FunctionCool](https://www.functioncool.xyz) function library for relevant function metadata (name, signature, description, complexity scores, tags).
2. **Strips the bulky `code` field** from the response — the model only sees the *index*, not the source.
3. **Writes the implementation itself**, citing the index it referenced.

The result: more reliable code, less hallucination, lower per-call cost. The function library content is stable, so repeated queries hit the model's prompt cache and cost almost nothing.

Supported languages: `C`, `C++`, `Go`, `Python`, `Java`, `JavaScript`, `Rust`, `MATLAB`, `PHP`, `Ruby`, `Verilog`.

## Why this exists (the math)

| Approach | What gets shipped to the model | Cost shape |
|---|---|---|
| Naive | Full function source code in output | Expensive **output** tokens per call |
| This skill | Method index (name, signature, complexity) in input | Cheap **input** tokens, cached on repeat |

Output tokens cost ~5× more than input tokens on most providers. Indexing first inverts the cost.

## Install

### Claude Code / Cursor

**macOS / Linux:**
```bash
git clone https://github.com/Mutantcat-Working-Group/FunctionCool-Skill.git \
  ~/.claude/skills/functioncool
```

**Windows (PowerShell):**
```powershell
git clone https://github.com/Mutantcat-Working-Group/FunctionCool-Skill.git `
  "$env:USERPROFILE\.claude\skills\functioncool"
```

Restart Claude / Cursor so the skill is discovered. The skill will appear in the available-skills list as `functioncool`.

### Manual install

Copy `SKILL.md`, `scripts/`, and `evals/` into your skills directory at the same relative paths.

## Usage

Just ask a coding question in a normal way. The skill triggers on phrases like:

- "用 Python 写个归并排序"
- "give me a Go HTTP server that returns hello"
- "How do I do binary search in Java?"
- "写个 C 的 Modbus CRC16 校验"
- "sort an array of numbers in Rust"

The user doesn't need to fetch any token, configure any URL, or run any commands. The skill's helper script handles everything silently.

The model will reply with the requested function, prefixed by a citation tag like:

```python
# [FunctionCool: PYTHON / Merge Sort / O(n log n) / timer 80]
def merge_sort(arr):
    ...
```

## Repository layout

```
.
├── SKILL.md            the skill body (loaded when triggered)
├── scripts/
│   ├── query.py        ★ cross-platform implementation (Windows / macOS / Linux, pure stdlib)
│   ├── query.sh        bash shim that forwards to query.py (kept for backward compatibility)
│   └── query.ps1       Windows PowerShell-native fallback (no Python required)
├── evals/
│   └── evals.json      test prompts for regression / iteration
└── README.md           this file
```

## How the helper works

[`scripts/query.py`](scripts/query.py) is the canonical, cross-platform implementation
(pure Python 3 stdlib — no third-party deps). It:

1. Calls `https://www.functioncool.xyz/skillapi?token=mutantcat&q=…&lang=…`.
2. Strips the `code` field from each result.
3. Returns a slim JSON of just the index (name, signature, complexity, tags).

`scripts/query.sh` is a thin bash shim that forwards to `query.py` (kept so that
older `bash query.sh …` invocations keep working). `scripts/query.ps1` is the
parallel PowerShell-native implementation for Windows users without Python —
same contract, different runtime.

The hardcoded token is a permanent, public, low-privilege key — **do not change it without coordinating with the FunctionCool maintainer**.

## API contract

```
GET https://www.functioncool.xyz/skillapi
    ?token=mutantcat
    &q={url-encoded query}
    &lang={C|CPP|GO|PYTHON|JAVA|JAVASCRIPT|RUST|MATLAB|PHP|RUBY|VERILOG|all}
```

Response (slimmed by the helper):

```json
{
  "query": "binary search",
  "lang": "JAVA",
  "count": 1,
  "results": [
    {
      "name": "Binary Search",
      "name_zh": "二分查找",
      "lang": "JAVA",
      "desc": "Binary search in sorted array, return index or -1",
      "desc_zh": "有序数组二分查找，返回索引或 -1",
      "input": ["arr", "target"],
      "input_type": ["int[]", "int"],
      "return": ["index"],
      "return_type": ["int"],
      "tags": ["search", "algorithm"],
      "timer_score": 95,
      "memory_score": 100
    }
  ]
}
```

## Local development / testing

Run the helper directly to inspect the slim index:

**macOS / Linux:**
```bash
python3 scripts/query.py "merge sort" "PYTHON"
# or the legacy shim, still works:
bash scripts/query.sh "merge sort" "PYTHON"
```

**Windows (PowerShell + Python):**
```powershell
python "$env:USERPROFILE\.claude\skills\functioncool\scripts\query.py" "merge sort" "PYTHON"
```

**Windows (PowerShell native — no Python required):**
```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\skills\functioncool\scripts\query.ps1" -Query "merge sort" -Lang "PYTHON"
```

## Iteration / improving the skill

The skill body and helper are intentionally small. If you want to tune the trigger description, add new lang codes, or change the citation format:

1. Edit `SKILL.md` and/or `scripts/query.py` (the canonical implementation).
2. Add a test prompt to `evals/evals.json` that exercises the change.
3. Test the helper against the live API: `python3 scripts/query.py "your query" "LANG"`.
4. Re-install by re-copying the files into your skills directory.

## License

MIT, by [Mutantcat Working Group](https://www.mutantcat.org).
