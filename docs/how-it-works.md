# How Bouncer works

[Léelo en castellano](how-it-works.es.md) · [Back to the README](../README.md)

The README tells you what Bouncer does. This is the part underneath: where it
sits in an agent, what each file is for, the two ways a gate can look real while
doing nothing, and why the decisions went the way they did.

## Where Bouncer sits

The word harness is used two ways, and it helps to keep them apart. In testing,
a harness is the code that wraps something to check it: it runs it, reads what
comes back, and decides whether it is right. That is the sense in which Bouncer
is a verification harness. In agent engineering, the harness is everything
around the model that lets it act at all, and in that sense Claude Code is one.
The rest of this section uses the second sense, to show where Bouncer fits.

An agent's harness, in that sense, is usually described as nine pieces. Six let the agent work at all,
and three are what let you trust the result:

| # | The piece | What it is for | Who gives it to you |
| --- | --- | --- | --- |
| 1 | Tools | Searching, reading, editing, running commands. The model asks; the harness executes. | Claude Code |
| 2 | A loop | Calling the model again with the result, so one step leads to the next. | Claude Code |
| 3 | Memory | Carrying what already happened into the next call, since the model keeps nothing. | Claude Code |
| 4 | Context | Choosing what the model sees each time, because the whole repository does not fit and would not help. | Claude Code |
| 5 | A place to work | A sandbox, so a bad command lands there and not on your machine. | Claude Code, as far as you configure it |
| 6 | A goal, and verification | Knowing the work is done because something checked, not because the model said so. | **Bouncer** |
| 7 | Permissions and limits | What it may do on its own, what it must ask about, and when to stop trying. | Claude Code, and Bouncer for the stopping |
| 8 | Observability | Seeing what actually happened on a run. | Outside Bouncer's scope |
| 9 | Evals | Measuring whether a change to the harness helped or hurt. | Outside Bouncer's scope |

Bouncer is piece six and half of piece seven. Five of those first six come with
your agent already. The sixth does not, because only you know what "done" means
in your repository.

Pieces eight and nine sit outside what Bouncer sets out to do: it is a gate, not
a recorder or a benchmark. It keeps one record, because it is the one thing that
cannot be recovered afterwards. Every moment the gate handed the decision to you
goes into `.bouncer-escalations.log`, and `make escalations` prints it. Anything
else about a failing run, you get by running `make verify` again.

That nine-piece map is not ours. It comes from [santi's walk-through of harness
engineering](https://x.com/santtiagom_/status/2098782814837543075), which builds
a harness from nothing one piece at a time.

## The exit code is the whole trick

The runtime hands a hook some JSON on standard input, and then reads the hook's
exit code to decide what happens next:

| The hook exits | What the runtime does |
| --- | --- |
| `0` | Fine, carry on. The agent is told nothing. |
| `1` | Treats it as a non-blocking error and writes it to the debug log. **The agent never sees it.** |
| `2` | Reads your stderr and puts it in front of the agent. On `Stop`, the turn is blocked outright. |

Build a hook on exit 1 and it will look correct forever while achieving
absolutely nothing. Both of Bouncer's hooks use exit 2.

**`PostToolUse`**, matched on `Edit|Write`, lints the one file that was just
touched, in under two seconds. It cannot undo the edit, since the tool already
ran, but the complaint lands in context and the next step fixes it.

**`Stop`** runs `make verify`, the whole gate. On failure it writes a header and
the last sixty lines of the output to stderr and exits 2, so the turn cannot
end. It counts consecutive failures in a file under `TMPDIR`. On the third one
it escalates instead: it ends the turn with the gate red, tells you so, and resets the
counter, because without the reset the gate would stay open for the rest of the
session.

Both hooks are defensive: any unexpected condition exits 0 in silence. A broken
hook that blocks every turn is worse than no hook.

## The trap

Two ways this looks like it is working while doing nothing at all. The exit code
above is the first. Here is the second.

**Hooks are read when a session starts.** Write `.claude/settings.json` in the
middle of a session and nothing is armed. Every file is right, the config is
valid, and no hook runs. A wrong path in that file behaves identically, quietly,
as a non-blocking error.

So do not trust the config. Break something and confirm you were stopped:

1. `/hooks` should list both, and say which file they came from.
2. Write a file with a real lint error. It has to come back to you.
3. Break `make verify`, then try to end the turn. You have to be blocked.

If step 3 does not block you, you do not have a gate, whatever the config says.

## The files

| Path | What it is |
| --- | --- |
| `Makefile` | Every command the README lists. |
| `scripts/verify.sh` | The engine behind `make verify`. It lives here because macOS ships GNU Make 3.81, which has no `.ONESHELL`. |
| `scripts/messages.sh` | Every string Bouncer prints, in English and Spanish. |
| `scripts/yamllint.sh` | Runs `yamllint` for pre-commit and for the lint hook, leaving out Helm chart templates wherever the chart lives. |
| `scripts/tfdocs.sh` | Finds the terraform-docs config a module will use, and reads its output file. |
| `scripts/tfdocs-test.sh` | The cases those two have already got wrong, run by `make verify`. |
| `scripts/bootstrap.sh` | Installs the toolchain. |
| `scripts/demo.sh` | Runs the linters over `examples/broken/`. |
| `.claude/settings.json` | Registers the two hooks. |
| `.claude/hooks/` | `lint-changed.sh` and `verify-on-stop.sh`. |
| `.claude/agents/reviewer.md` | The reviewer's instructions and its tool permissions. |
| `.pre-commit-config.yaml` | The single definition of every fast static check. |
| `examples/` | The fixtures for `make demo` and `make selftest`. |
| `CLAUDE.md` | The rules your agent reads at the start of every session. |

The fast checks live in `.pre-commit-config.yaml` and are run by `pre-commit`,
an off-the-shelf runner. The gate calls it and so does your `git commit`, so the
two can never disagree about what "clean" means. The linters there are declared
local, which means they call the binaries `make bootstrap` installed rather than
fetching their own. Five housekeeping hooks, the merge-conflict check among
them, do come from `pre-commit`'s own repository, pinned to a version.

## What CLAUDE.md asks for, and what the hooks enforce

The hooks enforce one thing: the turn does not end while `make verify` fails.
Everything else is a rule your agent reads in `CLAUDE.md` and follows because it
is written down, not because anything stops it. That includes the three-line
plan before it starts, the commit, the review after it, and not pushing while a
review has an open critical or high finding.

**The reviewer** is a second agent that reads the finished diff with no memory
of the conversation that produced it. It cannot see how anyone talked themselves
into a decision, which is exactly the point. It reports findings with a severity
and a `path:line`, and it does not fix anything. It is not part of the loop: a
check that can answer differently for the same code cannot be a gate, so it
stays a second opinion.

## Merging into an existing project

If the install steps found files you already have, take the parts rather than
the files:

- `.claude/settings.json`: copy the `hooks` block from Bouncer's into yours.
- `Makefile`: copy the targets you want. `verify` is required, because it is the
  one the Stop hook calls.
- `.pre-commit-config.yaml`: add Bouncer's `repos` entries to yours.
- `CLAUDE.md`: append the Definition of Done block from the README.

## Why it does things this way

**Missing content is skipped. A missing tool is not.** No `.tf` files means the
Terraform checks are skipped, which is honest. But `.tf` files with no `tflint`
installed is a hard failure, because otherwise the gate goes green for the worst
possible reason: nothing is installed to catch anything.

**`kubeconform ok` does not mean every manifest was checked.**
`-ignore-missing-schemas` is what lets a custom resource through, and it is also
how a run reports success having validated a fraction of what it read. The stage
prints how many it skipped.

**The coverage floor is 85%, and only for `src/` layouts.** A bare `--cov`
counts the test files, which are close to fully covered by definition and drag
the total over the line: 75% source plus 100% tests reports 89%. With no `src/`
to scope to, the floor is dropped out loud, because a threshold that goes green
for the wrong reason is worse than no threshold.

**Untracked files warn, they do not fail.** `pre-commit` only sees files git is
tracking, so a brand new file skips the static pass entirely. Failing on that
would block you all day, and a gate people switch off is worth nothing. The
warning keeps the hole visible instead of silent.

**Chart templates are not YAML.** They are Go template text that only becomes
YAML once helm renders it, so `yamllint` and `kubeconform` would only ever fail
on them. They are left out of both, wherever the chart lives, and checked
through `helm template` instead.

**The Terraform documentation check is opt-in twice over.** It runs only where a
`.terraform-docs.yml` sets an output file, looked up the way terraform-docs
looks it up: the module, the module's `.config/`, the root, the root's
`.config/`, and last `~/.tfdocs.d`, which is outside the repository. A config
there drives the check on your machine and nobody else's, CI included. And then
only on modules where that output file carries the `BEGIN_TF_DOCS` marker, so a
usage example is left alone. The file is read by a small parser that understands
the usual block style; a config written as a one-line `output: {file: ...}` map
is reported as unreadable and skipped, rather than guessed at.

**The reviewer is not supposed to write, and mostly cannot.** `Write` and `Edit`
are withheld from it. It keeps `Bash`, because a reviewer that cannot check
whether a binary exists inflates severities over guesses, and `Bash` can write
files. The last step of that prohibition is a rule in its prompt rather than a
wall, and you should know that before pointing it at a repository you care
about.
