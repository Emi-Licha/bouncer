# What was actually run, and what Bouncer cannot do

[Léelo en castellano](evidence.es.md) · [Back to the README](../README.md)

A repository about verification should say what it tested rather than ask to be
believed. All of this was run on macOS.

## Against a live Claude Code session

- Both hooks registered, and which settings file they came from.
- `PostToolUse` returning a lint error into the agent's context.
- `Stop` blocking a turn, the three-strike escalation, and the counter resetting.
- `.claude/.skip-verify` letting a turn end with the gate still red.
- The reviewer following the configured language both ways: asked in Spanish
  with the English default it answered in English, and set to Spanish it
  answered in Spanish.

## At the command line

- Real content: `kubeconform` accepting a good manifest and rejecting a bad one,
  `helm template` on a chart, `kyverno test` both ways, `terraform validate`,
  `tflint`, `trivy`, `terraform-docs` on a current and on a stale module, and
  the coverage floor rejecting 75% while accepting 100%.
- `make verify-full` against kind on colima. A ConfigMap named `Nombre_Invalido`
  is `Valid: 1` to kubeconform, whose schema does not constrain name format, and
  the API server rejects it for not being an RFC 1123 subdomain. That gap is why
  the e2e stage exists separately.
- Names holding a space, a quote or a newline, in files and directories alike.
- `bootstrap` on all three of its branches and the exit code each returns, two
  of them with a stand-in package manager so nothing was installed.
- Both languages across `verify`, `demo`, `doctor`, `bootstrap` and both hooks.
- The escalation log on both of its paths and in both languages, by feeding the
  Stop hook the input Claude Code sends it, in a scratch copy of the repository.
  Including the two ways it degrades: no catalogue, and a reformatted summary,
  which log that the failing check could not be read rather than a bare `?`.
- Installing into an empty project by following the install steps to the letter:
  `make verify` green on clean content and red on a broken script, both hooks
  exiting 2 when fed the same input Claude Code sends them, and `make demo` and
  `make selftest` refusing to run until the fixtures were copied.

The checks against real content can be reproduced with `make demo` and
`make selftest`, except the coverage floor: the Python stage looks for `src/`,
`tests/` and `pyproject.toml` at the repository root and cannot see a fixture in
a subdirectory. Everything else was run by hand and is recorded here, not
automated.

**Not run:** the apt/dnf path in `bootstrap.sh`, which is written but never
executed, and the three-minute budget against a repository with real content.
Here `verify` takes about two seconds and `selftest` about four.

## What it cannot do

**Parts of the gate need the network**, though never cloud credentials:
`pre-commit` downloads its hook environments on first run, `kubeconform` fetches
schemas it has not cached, `trivy` fetches its checks bundle, and
`terraform init` fetches any providers a module declares.

**The hooks need `jq`** to read what Claude Code sends them. Without it they
step aside in silence rather than wedge the session. `make bootstrap` installs
it, `make doctor` lists it, and `make verify` fails without it, but the Stop
hook itself cannot warn you: it is the part that needs `jq`.

**The reviewer is a language model, not a linter.** Its first two reviews
produced seven findings, two of them real, and both times the fix it suggested
would have been worse than the bug. Tightening its rules, so that it checks what
it can check and never prescribes a remedy it has not run, changed that: its two
most recent reviews produced seven findings, six of them real. The price is
time, about five and a half minutes on a ninety-line diff, most of it spent
verifying its own claims, and nothing caps that. Reproduce a finding before
acting on it, either way.

**`.bouncer-escalations.log` is a note to yourself, not an audit trail.** It sits
in your working tree, so anything that can write there can edit it, the agent
included. Two sessions running at once interleave lines that look alike, and
nothing rotates the file: leave `.claude/.skip-verify` in place and it grows by
a line per turn.

**Nothing enforces what `CLAUDE.md` asks for**: the plan, the commit, the review
and the no-push rule. They are instructions, not hooks, so they hold as long as
the agent, and whoever pushes, follows them.
