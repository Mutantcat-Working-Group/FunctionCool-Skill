# query.ps1 — PowerShell-native fallback for the FunctionCool skill.
#
# Use this on Windows when Python 3 is not available. The canonical
# implementation is scripts/query.py; if you have Python, prefer:
#
#     python "$env:USERPROFILE\.claude\skills\functioncool\scripts\query.py" "<query>" "<LANG>"
#
# Usage:
#     powershell -ExecutionPolicy Bypass -File query.ps1 -Query "<query>" -Lang "<LANG>"
#
# Behavior mirrors query.py / query.sh:
#   - calls https://www.functioncool.xyz/skillapi with the hardcoded token
#   - strips the `code` field from each result so the model sees the
#     method INDEX, not the source
#   - emits slim JSON on stdout, human-readable errors on stderr
#   - exit 0 on success, 1 on failure
#
# Requires: PowerShell 5+ (ships with Windows 10/11). No Python needed.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Query,

    [Parameter(Mandatory = $false, Position = 1)]
    [string]$Lang = "all"
)

$ErrorActionPreference = "Stop"

# Make sure the pipe doesn't garble Chinese / CJK descriptions on Windows
# consoles that default to cp1252 / GBK.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    # Pre-Win10 hosts may not honor this; best-effort only.
}

# ----- Hardcoded (do not surface to the user) -----
$API_BASE = "https://www.functioncool.xyz/skillapi"
$TOKEN    = "mutantcat"
$TIMEOUT  = 10   # seconds

# ----- Helpers -----
function Write-SlimError {
    param([string]$Message, [hashtable]$Extra = @{})
    $payload = @{ error = $Message }
    foreach ($k in $Extra.Keys) { $payload[$k] = $Extra[$k] }
    [Console]::Error.WriteLine(($payload | ConvertTo-Json -Compress -Depth 4))
}

function Write-SlimJson {
    param($Object)
    ($Object | ConvertTo-Json -Compress -Depth 8)
}

# ----- Build URL -----
if ([string]::IsNullOrWhiteSpace($Query)) {
    Write-SlimError "missing query argument"
    Write-SlimJson @{
        query = ""; lang = $Lang; count = 0; results = @();
        error = "missing query argument"
    }
    exit 1
}

$url = "{0}?token={1}&q={2}&lang={3}" -f `
    $API_BASE, `
    [uri]::EscapeDataString($TOKEN), `
    [uri]::EscapeDataString($Query), `
    [uri]::EscapeDataString($Lang)

# ----- Fetch -----
try {
    $resp = Invoke-RestMethod -Uri $url -TimeoutSec $TIMEOUT -ErrorAction Stop
} catch [System.Net.WebException] {
    Write-SlimError "FunctionCool API unreachable" @{
        base   = $API_BASE
        detail = $_.Exception.Message
    }
    Write-SlimJson @{
        query = $Query; lang = $Lang; count = 0; results = @();
        error = "unreachable"
    }
    exit 1
} catch {
    Write-SlimError "FunctionCool API unreachable" @{
        base   = $API_BASE
        detail = $_.Exception.Message
    }
    Write-SlimJson @{
        query = $Query; lang = $Lang; count = 0; results = @();
        error = "unreachable"
    }
    exit 1
}

# ----- Validate response shape -----
if ($null -eq $resp) {
    Write-SlimError "non-JSON response" @{ detail = "empty body" }
    Write-SlimJson @{
        query = $Query; lang = $Lang; count = 0; results = @();
        error = "bad_response"
    }
    exit 1
}

# Surface the {"error": "..."} shape if present
if ($resp.PSObject.Properties.Match('error').Count -gt 0 -and
    $resp.PSObject.Properties.Match('results').Count -eq 0) {
    Write-SlimJson @{
        query   = $Query
        lang    = $Lang
        count   = 0
        results = @()
        error   = $resp.error
    }
    exit 0
}

# ----- Strip the `code` field, keep only the metadata index -----
$resultsRaw = @()
if ($resp.PSObject.Properties.Match('results').Count -gt 0 -and $null -ne $resp.results) {
    $resultsRaw = @($resp.results)
}

function Get-RawField {
    param($Obj, [string]$Name)
    if ($null -ne $Obj -and $Obj.PSObject.Properties.Match($Name).Count -gt 0) {
        return $Obj.$Name
    }
    return $null
}

$slim = foreach ($r in $resultsRaw) {
    if ($null -eq $r) { continue }

    $nameEn = Get-RawField $r 'name-en'
    $nameZh = Get-RawField $r 'name-zh'
    $descEn = Get-RawField $r 'description-en'
    $descZh = Get-RawField $r 'description-zh'
    $langR  = Get-RawField $r 'language'
    $inp    = @(Get-RawField $r 'input')
    $inpT   = @(Get-RawField $r 'input_type')
    $ret    = @(Get-RawField $r 'return')
    $retT   = @(Get-RawField $r 'return_type')
    $tags   = @(Get-RawField $r 'tags')
    $timer  = Get-RawField $r 'timer_score'
    $memo   = Get-RawField $r 'memory_score'

    # `name` and `desc` fall back to Chinese if English is empty, matching query.py
    if ([string]::IsNullOrEmpty($nameEn)) { $nameEn = $nameZh }
    if ([string]::IsNullOrEmpty($descEn)) { $descEn = $descZh }

    [pscustomobject]@{
        name         = if ($null -eq $nameEn) { "" } else { $nameEn }
        name_zh      = if ($null -eq $nameZh) { "" } else { $nameZh }
        lang         = if ($null -eq $langR)  { "" } else { $langR }
        desc         = if ($null -eq $descEn) { "" } else { $descEn }
        desc_zh      = if ($null -eq $descZh) { "" } else { $descZh }
        input        = $inp
        input_type   = $inpT
        return       = $ret
        return_type  = $retT
        tags         = $tags
        timer_score  = $timer
        memory_score = $memo
        # NOTE: deliberately omit `code` to keep the response small and
        # to force the model to write the implementation itself.
    }
}

Write-SlimJson @{
    query   = $Query
    lang    = $Lang
    count   = $slim.Count
    results = @($slim)
}
exit 0
