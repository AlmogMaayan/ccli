# End-to-end tests for ccli.ps1 against a fake claude.cmd (no real claude is ever started).
# Run: pwsh -NoProfile -File tests\ccli.tests.ps1
$ErrorActionPreference = 'Continue'
$scriptDir = Split-Path $PSScriptRoot -Parent
$ccliPath = Join-Path $scriptDir 'ccli.ps1'
$oldPath = $env:PATH

$sandbox = Join-Path ([IO.Path]::GetTempPath()) "ccli-test-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$failures = 0
$checks = 0
$expectedChecks = 53
function Check([string]$what, [bool]$ok) {
    $script:checks++
    if ($ok) { Write-Host "PASS  $what" -ForegroundColor Green }
    else { Write-Host "FAIL  $what" -ForegroundColor Red; $script:failures++ }
}

# Runs a ccli invocation; returns the text the fake claude recorded, or $null when it never started.
function Rec([scriptblock]$Invoke) {
    Remove-Item $script:out -ErrorAction SilentlyContinue
    & $Invoke *> $null
    if (Test-Path $script:out) { (Get-Content $script:out -Raw).TrimEnd("`r", "`n") } else { $null }
}
# Runs a ccli invocation expected to be rejected; returns exit code, error text, and whether claude started.
function Reject([scriptblock]$Invoke) {
    Remove-Item $script:out -ErrorAction SilentlyContinue
    $text = (& $Invoke *>&1 | Out-String)
    [pscustomobject]@{ Code = $LASTEXITCODE; Text = $text; Started = (Test-Path $script:out) }
}

try {
    New-Item -ItemType Directory $sandbox | Out-Null
    $fake = Join-Path $sandbox 'fake'
    New-Item -ItemType Directory $fake | Out-Null
    $out = Join-Path $sandbox 'out.txt'
    Set-Content (Join-Path $fake 'claude.cmd') -Encoding ascii -Value @(
        '@echo off'
        '>"%CCLI_TEST_OUT%" echo(%*'
        'exit /b %CCLI_TEST_EXIT%'
    )
    $env:PATH = "$fake;$scriptDir;$oldPath"
    $env:CCLI_TEST_OUT = $out
    Remove-Item Env:CCLI_TEST_EXIT -ErrorAction SilentlyContinue

    # --- 2.1 skeleton
    $src = if (Test-Path $ccliPath) { Get-Content $ccliPath -Raw } else { '' }
    Check 'script exists' ($src -ne '')
    Check 'script has no param( block' ($src -notmatch '(?i)param\s*\(')
    Check 'script has no CmdletBinding' ($src -notmatch 'CmdletBinding')
    Remove-Item $out -ErrorAction SilentlyContinue
    $help = (ccli -Help *>&1 | Out-String)
    Check 'help shows SYNOPSIS' ($help -match 'SYNOPSIS')
    Check 'help shows example ccli -m:f,h' ($help -match [regex]::Escape('ccli -m:f,h'))
    Check 'help shows PATH step' ($help -match 'PATH')
    Check 'help does not start claude' (-not (Test-Path $out))
    $declared = [regex]::Match($src, '\$CcliVersion\s*=\s*''([^'']+)''').Groups[1].Value
    $ver = (ccli -version *>&1 | Out-String).Trim()
    Check 'version equals ccli + declared version' ($declared -ne '' -and $ver -eq "ccli $declared")
    Check 'version does not start claude' (-not (Test-Path $out))

    # --- 2.2 pass-through
    Check 'no args records empty line' ((Rec { ccli }) -eq '')
    Check '--resume passes through' ((Rec { ccli --resume }) -eq '--resume')
    Check 'quoted arg with space' ((Rec { ccli -p "hello world" }) -eq '-p "hello world"')
    Check 'unquoted comma list re-joined' ((Rec { ccli -p a,b }) -eq '-p a,b')
    Check '-h reaches claude' ((Rec { ccli -h }) -eq '-h')
    Check '--help reaches claude' ((Rec { ccli --help }) -eq '--help')
    Check '-v reaches claude' ((Rec { ccli -v }) -eq '-v')
    Check '--version reaches claude' ((Rec { ccli --version }) -eq '--version')

    # --- 2.3 exit code and missing claude
    $env:CCLI_TEST_EXIT = '7'
    ccli *> $null
    Check 'claude exit code 7 propagates' ($LASTEXITCODE -eq 7)
    Remove-Item Env:CCLI_TEST_EXIT
    $env:PATH = "$scriptDir;$env:SystemRoot\System32"
    $r = Reject { ccli }
    Check 'missing claude exits 1' ($r.Code -eq 1)
    Check 'missing claude error names claude' ($r.Text -match 'claude')
    $env:PATH = "$fake;$scriptDir;$oldPath"

    # --- 3.1 model map
    Check '-m:h haiku' ((Rec { ccli -m:h }) -eq '--model haiku')
    Check '-m:s sonnet' ((Rec { ccli -m:s }) -eq '--model sonnet')
    Check '-m:o opus' ((Rec { ccli -m:o }) -eq '--model opus')
    Check '-m:f fable' ((Rec { ccli -m:f }) -eq '--model fable')
    Check '-m:O upper-case model' ((Rec { ccli -m:O }) -eq '--model opus')

    # --- 3.2 effort map
    Check 'effort l' ((Rec { ccli -m:o,l }) -eq '--model opus --effort low')
    Check 'effort m' ((Rec { ccli -m:o,m }) -eq '--model opus --effort medium')
    Check 'effort h' ((Rec { ccli -m:o,h }) -eq '--model opus --effort high')
    Check 'effort x' ((Rec { ccli -m:o,x }) -eq '--model opus --effort xhigh')
    Check 'effort MX' ((Rec { ccli -m:o,MX }) -eq '--model opus --effort max')
    Check 'effort u' ((Rec { ccli -m:o,u }) -eq '--model opus --effort ultracode')
    Check 'effort word low' ((Rec { ccli -m:o,low }) -eq '--model opus --effort low')
    Check 'effort word medium' ((Rec { ccli -m:o,medium }) -eq '--model opus --effort medium')
    Check 'effort word high' ((Rec { ccli -m:o,high }) -eq '--model opus --effort high')
    Check 'effort word xhigh' ((Rec { ccli -m:o,xhigh }) -eq '--model opus --effort xhigh')
    Check 'effort word max' ((Rec { ccli -m:o,max }) -eq '--model opus --effort max')
    Check 'effort a sends no --effort' ((Rec { ccli -m:o,a }) -eq '--model opus')
    Check 'effort-only selector' ((Rec { ccli -m:',h' }) -eq '--effort high')
    Check 'upper-case S,MX' ((Rec { ccli -m:S,MX }) -eq '--model sonnet --effort max')

    # --- 3.3 forms
    Check 'space form -m f,h' ((Rec { ccli -m f,h }) -eq '--model fable --effort high')
    Check 'selector plus extra args' ((Rec { ccli -m:o,x --resume }) -eq '--model opus --effort xhigh --resume')
    Check 'colon form f,h' ((Rec { ccli -m:f,h }) -eq '--model fable --effort high')
    Check 'pwsh -File form' ((Rec { pwsh -NoProfile -File $ccliPath -m:f,h }) -eq '--model fable --effort high')
    Check 'selector then lone comma list re-joined' ((Rec { ccli -m:o a,b }) -eq '--model opus a,b')
    Check 'selector then arg and comma list' ((Rec { ccli -m:o x a,b }) -eq '--model opus x a,b')

    # --- 3.4 invalid selectors
    $r = Reject { ccli -m:z }
    Check '-m:z exits 1, no claude' ($r.Code -eq 1 -and -not $r.Started)
    Check '-m:z names z and lists letters' ($r.Text -match "'z'" -and $r.Text -match 'h=haiku' -and $r.Text -match 'mx=max')
    $r = Reject { ccli -m:o,q }
    Check '-m:o,q exits 1, no claude' ($r.Code -eq 1 -and -not $r.Started)
    Check '-m:o,q names q and lists letters' ($r.Text -match "'q'" -and $r.Text -match 'h=haiku' -and $r.Text -match 'mx=max')
    $r = Reject { ccli -m:f,h,x }
    Check '-m:f,h,x exits 1, no claude' ($r.Code -eq 1 -and -not $r.Started)
    Check '-m:f,h,x names input and lists letters' ($r.Text -match 'f,h,x' -and $r.Text -match 'h=haiku' -and $r.Text -match 'mx=max')
    $r = Reject { ccli -m }
    Check 'bare -m exits 1, no claude' ($r.Code -eq 1 -and -not $r.Started)
    Check 'bare -m lists letters' ($r.Text -match 'h=haiku' -and $r.Text -match 'mx=max')
}
finally {
    $env:PATH = $oldPath
    Remove-Item Env:CCLI_TEST_OUT, Env:CCLI_TEST_EXIT -ErrorAction SilentlyContinue
    Set-Location $PSScriptRoot
    Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

if ($checks -ne $expectedChecks) {
    Write-Host "FAIL  ran $checks checks, expected $expectedChecks" -ForegroundColor Red
    $failures++
}
if ($failures -gt 0) { Write-Host "$failures check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All checks passed' -ForegroundColor Green
exit 0
