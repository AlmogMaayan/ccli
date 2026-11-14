# End-to-end tests for vsrun.ps1 against a fake code.cmd (VS Code is never started).
# Run: pwsh -NoProfile -File tests\vsrun.tests.ps1
$ErrorActionPreference = 'Continue'
$scriptDir = Split-Path $PSScriptRoot -Parent
$vsrunPath = Join-Path $scriptDir 'vsrun.ps1'
$ccliPath = Join-Path $scriptDir 'ccli.ps1'
$oldPath = $env:PATH
$oldLocation = Get-Location

$sandbox = Join-Path ([IO.Path]::GetTempPath()) "vsrun-test-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = 0
$checks = 0
$expectedChecks = 27
function Check([string]$what, [bool]$ok) {
    $script:checks++
    if ($ok) { Write-Host "PASS  $what" -ForegroundColor Green }
    else { Write-Host "FAIL  $what" -ForegroundColor Red; $script:failures++ }
}

# Runs a vsrun invocation; returns the workspace file the fake code was given (parsed), or $null.
function Run([scriptblock]$Invoke) {
    Remove-Item $script:out -ErrorAction SilentlyContinue
    & $Invoke *> $null
    if (-not (Test-Path $script:out)) { return $null }
    $file = (Get-Content $script:out -Raw).Trim().Trim('"')
    [pscustomobject]@{ File = $file; Json = (Get-Content -LiteralPath $file -Raw | ConvertFrom-Json) }
}
# The arguments the task hands to ccli (everything after -File <ccli.ps1>), joined with spaces.
function TaskArgs($run) {
    $a = @($run.Json.tasks.tasks[0].args)
    $i = [array]::IndexOf($a, '-File')
    if ($a.Count -le $i + 2) { return '' }
    $a[($i + 2)..($a.Count - 1)] -join ' '
}
function Reject([scriptblock]$Invoke) {
    Remove-Item $script:out -ErrorAction SilentlyContinue
    $text = (& $Invoke *>&1 | Out-String)
    [pscustomobject]@{ Code = $LASTEXITCODE; Text = $text; Started = (Test-Path $script:out) }
}

try {
    New-Item -ItemType Directory $sandbox | Out-Null
    $fake = Join-Path $sandbox 'fake'
    $proj = Join-Path $sandbox 'My Project'
    $vsHome = Join-Path $sandbox 'home'
    New-Item -ItemType Directory $fake, $proj | Out-Null
    $out = Join-Path $sandbox 'out.txt'
    Set-Content (Join-Path $fake 'code.cmd') -Encoding ascii -Value @(
        '@echo off'
        '>"%VSRUN_TEST_OUT%" echo(%*'
        'exit /b %VSRUN_TEST_EXIT%'
    )
    $env:PATH = "$fake;$scriptDir;$env:SystemRoot\System32"
    $env:VSRUN_TEST_OUT = $out
    $env:VSRUN_HOME = $vsHome
    Remove-Item Env:VSRUN_TEST_EXIT -ErrorAction SilentlyContinue
    Set-Location $proj

    # --- help and version
    $help = (vsrun -Help *>&1 | Out-String)
    Check 'help shows SYNOPSIS' ($help -match 'SYNOPSIS')
    Check 'help does not start code' (-not (Test-Path $out))
    $src = Get-Content $vsrunPath -Raw
    $declared = [regex]::Match($src, '\$VsrunVersion\s*=\s*''([^'']+)''').Groups[1].Value
    $ver = (vsrun -Version *>&1 | Out-String).Trim()
    Check 'version equals vsrun + declared version' ($declared -ne '' -and $ver -eq "vsrun $declared")

    # --- workspace file
    $r = Run { vsrun -m:s,h }
    Check 'code was started with a workspace file' ($null -ne $r -and $r.File -like '*.code-workspace')
    Check 'workspace file is under VSRUN_HOME' ($r.File.StartsWith($vsHome, [StringComparison]::OrdinalIgnoreCase))
    Check 'workspace file is named after the folder' ((Split-Path $r.File -Leaf) -eq 'My Project.code-workspace')
    Check 'nothing written into the project' (@(Get-ChildItem $proj -Force).Count -eq 0)
    Check 'workspace folder is the current folder' ($r.Json.folders[0].path -eq $proj)
    $t = $r.Json.tasks.tasks[0]
    Check 'task runs on folder open' ($t.runOptions.runOn -eq 'folderOpen')
    Check 'task label' ($t.label -eq 'vsrun: claude')
    Check 'task runs ccli.ps1 via -File' ((@($t.args) -join '|') -match [regex]::Escape("-File|$ccliPath"))
    Check 'task cwd is the current folder' ($t.options.cwd -eq $proj)
    Check 'task command is a PowerShell host' ((Split-Path $t.command -Leaf) -match '^(pwsh|powershell)\.exe$')

    # --- selector forms
    Check '-m:s,h' ((TaskArgs $r) -eq '-m s,h')
    Check '-m:s:h colon separator' ((TaskArgs (Run { vsrun -m:s:h })) -eq '-m s,h')
    Check '-m:s model only' ((TaskArgs (Run { vsrun -m:s })) -eq '-m s,')
    Check '-m f,x space form' ((TaskArgs (Run { vsrun -m f,x })) -eq '-m f,x')
    Check 'upper case' ((TaskArgs (Run { vsrun -m:O,MX })) -eq '-m o,mx')
    Check 'extra args pass through' ((TaskArgs (Run { vsrun -m:o,x --resume })) -eq '-m o,x --resume')
    Check 'no selector' ((TaskArgs (Run { vsrun })) -eq '')
    $again = Run { vsrun -m:f }
    Check 'same folder reuses the same workspace file' ($again.File -eq $r.File)

    # --- the generated task really reaches claude through ccli
    $rec = Join-Path $sandbox 'claude.txt'
    Set-Content (Join-Path $fake 'claude.cmd') -Encoding ascii -Value @('@echo off', '>"%CCLI_TEST_OUT%" echo(%*')
    $env:CCLI_TEST_OUT = $rec
    $t = (Run { vsrun -m:s:h --resume }).Json.tasks.tasks[0]
    & $t.command @($t.args) *> $null
    Check 'task command line starts claude with model and effort' ((Test-Path $rec) -and (Get-Content $rec -Raw).Trim() -eq '--model sonnet --effort high --resume')

    # --- rejections
    $x = Reject { vsrun -m:z }
    Check '-m:z exits 1, no code' ($x.Code -eq 1 -and -not $x.Started -and $x.Text -match "'z'")
    $x = Reject { vsrun -m:o,q }
    Check '-m:o,q exits 1, no code' ($x.Code -eq 1 -and -not $x.Started -and $x.Text -match "'q'")
    $x = Reject { vsrun -m:f,h,x }
    Check '-m:f,h,x exits 1, no code' ($x.Code -eq 1 -and -not $x.Started)
    $x = Reject { vsrun -m }
    Check 'bare -m exits 1, no code' ($x.Code -eq 1 -and -not $x.Started)
    $env:PATH = "$scriptDir;$env:SystemRoot\System32"
    $x = Reject { vsrun -m:s }
    Check 'missing code exits 1 and names code' ($x.Code -eq 1 -and $x.Text -match "'code'")
}
finally {
    $env:PATH = $oldPath
    Remove-Item Env:VSRUN_TEST_OUT, Env:VSRUN_TEST_EXIT, Env:VSRUN_HOME, Env:CCLI_TEST_OUT -ErrorAction SilentlyContinue
    Set-Location $oldLocation
    Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

if ($checks -ne $expectedChecks) {
    Write-Host "FAIL  ran $checks checks, expected $expectedChecks" -ForegroundColor Red
    $failures++
}
if ($failures -gt 0) { Write-Host "$failures check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All checks passed' -ForegroundColor Green
exit 0
