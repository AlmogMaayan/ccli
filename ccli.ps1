<#
.SYNOPSIS
    Launches claude with a short model and effort selector, passing every other argument through.

.DESCRIPTION
    ccli [-m:<model>,<effort>] [claude arguments...]

    The selector must be the first argument: -m:f,h or -m f,h. Both parts are optional and
    case-insensitive. It becomes --model <name> and --effort <name>, placed before the
    pass-through arguments. Everything else is passed to claude unchanged, in order, and ccli
    exits with claude's exit code.

    Model letters:  h=haiku s=sonnet o=opus f=fable
    Effort letters: l=low m=medium h=high x=xhigh mx=max a=auto u=ultracode
    (the words low, medium, high, xhigh and max also work; a sends no --effort flag)

    One-time PATH step: add the folder that holds ccli.ps1 to your PATH, then open a new
    terminal so that `ccli` resolves from anywhere.

    -Help and -Version are recognised only as the first argument.

.EXAMPLE
    ccli -m:f,h
.EXAMPLE
    ccli -m:o,x --resume
.EXAMPLE
    ccli -m:',h'
.EXAMPLE
    ccli -Help
.EXAMPLE
    ccli -Version
#>

# Bump on every change to this script (semver: fix -> patch, new behaviour -> minor, breaking -> major).
$CcliVersion = '1.0.0'

$first = if ($args.Count -gt 0) { [string]$args[0] } else { '' }
if ($first -ieq '-Help') { Get-Help $PSCommandPath -Detailed; return }
if ($first -ieq '-Version') { "ccli $CcliVersion"; return }

$models = [ordered]@{ h = 'haiku'; s = 'sonnet'; o = 'opus'; f = 'fable' }
$efforts = [ordered]@{ l = 'low'; m = 'medium'; h = 'high'; x = 'xhigh'; mx = 'max'; u = 'ultracode'; a = 'auto'
    low = 'low'; medium = 'medium'; high = 'high'; xhigh = 'xhigh'; max = 'max' }
$legend = 'Model: h=haiku s=sonnet o=opus f=fable. Effort: l=low m=medium h=high x=xhigh mx=max a=auto u=ultracode'

function Stop-Ccli([string]$Message) {
    Write-Error $Message -ErrorAction Continue
    exit 1
}

$list = [System.Collections.Generic.List[string]]::new()
$rest = $args

if ($first -match '^-m:?$') {
    if ($args.Count -lt 2) { Stop-Ccli "ccli: -m needs a value like f,h. $legend"; return }
    $raw = (@($args[1]) | ForEach-Object { [string]$_ }) -join ','
    $parts = @($raw -split ',')
    if ($parts.Count -gt 2) { Stop-Ccli "ccli: bad selector '$raw': at most <model>,<effort>. $legend"; return }
    $m = $parts[0].Trim().ToLowerInvariant()
    $e = if ($parts.Count -eq 2) { $parts[1].Trim().ToLowerInvariant() } else { '' }
    if ($m -and -not $models.Contains($m)) { Stop-Ccli "ccli: unknown model '$m'. $legend"; return }
    if ($e -and -not $efforts.Contains($e)) { Stop-Ccli "ccli: unknown effort '$e'. $legend"; return }
    if ($m) { $list.Add('--model'); $list.Add($models[$m]) }
    if ($e -and $e -ne 'a') { $list.Add('--effort'); $list.Add($efforts[$e]) }
    $rest = @()
    if ($args.Count -gt 2) { $rest = @($args[2..($args.Count - 1)]) }
}

foreach ($a in $rest) { $list.Add((@($a) | ForEach-Object { [string]$_ }) -join ',') }

if (-not (Get-Command claude -CommandType Application -ErrorAction SilentlyContinue)) {
    Stop-Ccli "ccli: the 'claude' command was not found on PATH."
    return
}

$global:LASTEXITCODE = 0
& claude @list
exit $LASTEXITCODE
