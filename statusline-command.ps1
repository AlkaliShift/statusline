# Claude Code statusLine command
# Format: folder | branch | model | context%
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Read stdin as raw UTF-8 bytes so Chinese in the JSON decodes correctly,
# regardless of the console code page (GBK/936).
$raw = ""
try {
    $stdin = [Console]::OpenStandardInput()
    $reader = New-Object System.IO.StreamReader($stdin, [System.Text.Encoding]::UTF8)
    $raw = $reader.ReadToEnd()
    $reader.Dispose()
} catch {}

# DEBUG: log raw JSON to temp file for troubleshooting
try { $raw | Out-File -Append -Encoding utf8 "$env:TEMP\claude-statusline-debug.log" } catch {}

$inputData = $null
try { $inputData = $raw | ConvertFrom-Json } catch {}

$cwdFull = if ($inputData.workspace.current_dir) { $inputData.workspace.current_dir } `
           elseif ($inputData.cwd)               { $inputData.cwd }                   `
           else                                  { "" }
$basename = if ($cwdFull) { Split-Path -Leaf $cwdFull } else { "unknown" }

$branchPart = ""
if ($cwdFull) {
    try {
        $null = & git -C $cwdFull rev-parse --git-dir 2>$null
        if ($LASTEXITCODE -eq 0) {
            $b = & git -C $cwdFull --no-optional-locks symbolic-ref --short HEAD 2>$null
            if ($b) { $branchPart = "$([char]0xE0A0) $b" }
        }
    } catch {}
}

$displayName = if ($inputData.model.display_name) { $inputData.model.display_name } else { "" }
$shortModel  = $displayName -replace '^[Cc]laude[- ]', ''

$used = $inputData.context_window.used_percentage

$bolt   = [System.Char]::ConvertFromUtf32(0x26A1)
$brain  = [System.Char]::ConvertFromUtf32(0x1F9E0)
$folder = [System.Char]::ConvertFromUtf32(0x1F4C1)

$parts = @("$folder $basename")
if ($branchPart) { $parts += $branchPart }
if ($shortModel) { $parts += "$bolt $shortModel" }
if ($null -ne $used) { $parts += "$brain $([math]::Round($used))%" }

$out = ($parts -join "  $([char]0x00B7)  ")
[Console]::Out.Write($out)