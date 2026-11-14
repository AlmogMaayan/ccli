<#
.SYNOPSIS
    Opens the current folder in VS Code and starts claude in a VS Code terminal, with a short
    model and effort selector.

.DESCRIPTION
    vsrun [-m:<model>,<effort>] [claude arguments...]

    Run it from the project folder. vsrun writes a small VS Code workspace file outside the
    project (under %LOCALAPPDATA%\vsrun) that points at the current folder and carries one
    task, "vsrun: claude", set to run when the workspace opens. It then opens that workspace
    with `code`. The task runs ccli.ps1 (which sits next to this script) with the same
    selector and arguments, so claude starts in a VS Code terminal.

    The selector must be the first argument: -m:f,h, -m:f:h or -m f,h. Both parts are
    optional and case-insensitive.

    Model letters:  h=haiku s=sonnet o=opus f=fable
    Effort letters: l=low m=medium h=high x=xhigh mx=max a=auto u=ultracode

    Notes:
    - The first time, VS Code asks whether to trust the workspace and allow automatic tasks.
    - If that workspace window is already open, VS Code only focuses it and the task does not
      start again. Run it by hand there: Terminal > Run Task > "vsrun: claude" (it uses the
      newest selector), or close the window and run vsrun again.

    -Help and -Version are recognised only as the first argument.

.EXAMPLE
    vsrun -m:s,h
.EXAMPLE
    vsrun -m:o:x --resume
.EXAMPLE
    vsrun
#>

# Bump on every change to this script (semver: fix -> patch, new behaviour -> minor, breaking -> major).
$VsrunVersion = '1.0.0'

$first = if ($args.Count -gt 0) { [string]$args[0] } else { '' }
if ($first -ieq '-Help') { Get-Help $PSCommandPath -Detailed; return }
if ($first -ieq '-Version') { "vsrun $VsrunVersion"; return }

# Keep in sync with the selector tables in ccli.ps1; ccli does the real mapping, this only fails early.
$models = 'h', 's', 'o', 'f'
$efforts = 'l', 'm', 'h', 'x', 'mx', 'u', 'a', 'low', 'medium', 'high', 'xhigh', 'max'
$legend = 'Model: h=haiku s=sonnet o=opus f=fable. Effort: l=low m=medium h=high x=xhigh mx=max a=auto u=ultracode'

function Stop-Vsrun([string]$Message) {
    Write-Error $Message -ErrorAction Continue
    exit 1
}

$ccliArgs = [System.Collections.Generic.List[string]]::new()
$rest = $args

if ($first -match '^-m:?$') {
    if ($args.Count -lt 2) { Stop-Vsrun "vsrun: -m needs a value like f,h. $legend"; return }
    $raw = (@($args[1]) | ForEach-Object { [string]$_ }) -join ','
    $parts = @($raw -split '[,:]')
    if ($parts.Count -gt 2) { Stop-Vsrun "vsrun: bad selector '$raw': at most <model>,<effort>. $legend"; return }
    $m = $parts[0].Trim().ToLowerInvariant()
    $e = if ($parts.Count -eq 2) { $parts[1].Trim().ToLowerInvariant() } else { '' }
    if ($m -and $models -notcontains $m) { Stop-Vsrun "vsrun: unknown model '$m'. $legend"; return }
    if ($e -and $efforts -notcontains $e) { Stop-Vsrun "vsrun: unknown effort '$e'. $legend"; return }
    $ccliArgs.Add('-m'); $ccliArgs.Add("$m,$e")
    $rest = @()
    if ($args.Count -gt 2) { $rest = @($args[2..($args.Count - 1)]) }
}

foreach ($a in $rest) { $ccliArgs.Add((@($a) | ForEach-Object { [string]$_ }) -join ',') }

$ccli = Join-Path $PSScriptRoot 'ccli.ps1'
if (-not (Test-Path $ccli)) { Stop-Vsrun "vsrun: ccli.ps1 was not found next to vsrun.ps1 ($PSScriptRoot)."; return }
if (-not (Get-Command code -CommandType Application -ErrorAction SilentlyContinue)) {
    Stop-Vsrun "vsrun: the 'code' command (VS Code) was not found on PATH."
    return
}

$folder = (Get-Location -PSProvider FileSystem).ProviderPath
$sha = [System.Security.Cryptography.SHA256]::Create()
$hash = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($folder.ToLowerInvariant()))[0..3] | ForEach-Object { $_.ToString('x2') })
$sha.Dispose()

$home_ = if ($env:VSRUN_HOME) { $env:VSRUN_HOME } else { Join-Path $env:LOCALAPPDATA 'vsrun' }
$wsDir = Join-Path $home_ $hash
$name = Split-Path $folder -Leaf
if (-not $name -or $name -match '[\\/:]') { $name = 'root' }
$wsFile = Join-Path $wsDir "$name.code-workspace"

$workspace = [ordered]@{
    folders = @([ordered]@{ path = $folder })
    tasks   = [ordered]@{
        version = '2.0.0'
        tasks   = @([ordered]@{
                label          = 'vsrun: claude'
                type           = 'process'
                command        = (Get-Process -Id $PID).Path
                args           = @('-NoLogo', '-NoProfile', '-File', $ccli) + $ccliArgs.ToArray()
                options        = [ordered]@{ cwd = $folder }
                runOptions     = [ordered]@{ runOn = 'folderOpen' }
                presentation   = [ordered]@{ reveal = 'always'; focus = $true; panel = 'dedicated' }
                problemMatcher = @()
            })
    }
}

New-Item -ItemType Directory -Path $wsDir -Force | Out-Null
$workspace | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $wsFile -Encoding utf8

$global:LASTEXITCODE = 0
& code $wsFile
exit $LASTEXITCODE
