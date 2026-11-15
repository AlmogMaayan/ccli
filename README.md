# ccli

Two small PowerShell launchers for [Claude Code](https://claude.com/claude-code):

- **`ccli`** starts `claude` with a short model and effort selector.
- **`vsrun`** opens the current folder in VS Code and starts `claude` (through `ccli`) in a VS Code terminal.

## Setup

Add the folder that holds `ccli.ps1` and `vsrun.ps1` to your `PATH`, then open a new terminal so `ccli` and `vsrun` resolve from anywhere.

Requirements: PowerShell, `claude` on `PATH`, and (for `vsrun`) VS Code's `code` command on `PATH`.

## ccli

```
ccli [-m:<model>,<effort>] [claude arguments...]
```

The selector must be the first argument. It can be written `-m:f,h` or `-m f,h`. Both parts are optional and case-insensitive. It becomes `--model <name> --effort <name>`, placed before your other arguments. Everything else passes through to `claude` unchanged, and `ccli` exits with claude's exit code.

| Model | Letter | | Effort | Letter |
|---|---|---|---|---|
| haiku | `h` | | low | `l` |
| sonnet | `s` | | medium | `m` |
| opus | `o` | | high | `h` |
| fable | `f` | | xhigh | `x` |
| | | | max | `mx` |
| | | | auto (sends no `--effort`) | `a` |
| | | | ultracode | `u` |

The words `low`, `medium`, `high`, `xhigh` and `max` also work for effort.

```powershell
ccli -m:f,h          # fable, high effort
ccli -m:o,x --resume # opus, xhigh effort, resume the last session
ccli -m:',h'         # keep the default model, high effort
ccli -Help           # full help
ccli -Version        # prints "ccli <version>"
```

`-Help` and `-Version` are recognised only as the first argument.

## vsrun

```
vsrun [-m:<model>,<effort>] [-d:<inner folder>] [claude arguments...]
```

Run it from your project folder. `vsrun` writes a small VS Code workspace file outside the project (under `%LOCALAPPDATA%\vsrun`, or `VSRUN_HOME` if set). The workspace points at the current folder and has one task, `vsrun: claude`, that runs when the folder opens. The task runs `ccli.ps1` with your selector and arguments. Nothing is written into the project.

- `-m` takes the same selector as `ccli` (`-m:f,h`, `-m:f:h` or `-m f,h`).
- `-d` opens VS Code in the current folder but starts claude in an inner folder. It can be relative (`dir1\dir2`, `.\dir1`) or absolute. It must exist and be inside the current folder.
- `-m` and `-d` can come in either order and must come before any claude arguments.

```powershell
vsrun -m:s,h
vsrun -m:f,m -d:dir1\dir2
vsrun -m:o:x --resume
vsrun -Version       # or -v
```

Notes:

- The first time, VS Code asks whether to trust the workspace and allow automatic tasks.
- If that workspace window is already open, VS Code only focuses it and the task does not run again. Run it by hand with Terminal > Run Task > `vsrun: claude`, or close the window and run `vsrun` again.

## Tests

The tests run against fake `claude` and `code` commands, so neither real program starts.

```powershell
pwsh -NoProfile -File tests\ccli.tests.ps1
pwsh -NoProfile -File tests\vsrun.tests.ps1
```
