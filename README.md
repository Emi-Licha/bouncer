# Bouncer

**[English](#english)** | **[Español](#español)**

## English

**Your agent says it's done. Bouncer checks the facts.**

Because it almost never is.

So you read the diff, you find the unquoted variable, you prompt again, it tells
you it is done again, and there goes your afternoon.

This is not a prompting problem, and a better prompt will not fix it. To see why,
it helps to know who actually decides that a task is finished.

### Why your agent thinks it is done

A model does one thing: text goes in, text comes out. It does not open files, it
does not run commands, and it does not remember what it did a minute ago.

So when your agent searches your repository, edits a file and runs the tests,
something else is doing all of that. The model asks; that something executes.
That something is the harness, and with Claude Code, Claude is the model and
Claude Code is the harness.

The harness also decides when to stop asking. By default it stops when the model
says the work is done, and the model answers from what it meant to do, not from
what happened. Nothing has looked at the result yet. You are the first thing
that does, which is why the afternoon goes the way it goes.

Bouncer moves that decision to a command.

### One command, and the pieces that make it fire

Say you asked for a retry helper, and the agent wrote `retry.sh`.

**The gate is one command**, and it answers yes or no:

```bash
make verify
```

It runs the linters over your files, validates your manifests, renders your
charts and runs your tests, then exits zero or it does not. A linter is a
program that reads code without running it and complains about what is broken or
risky: `shellcheck` is the one that notices `echo $name` falls apart the first
time `$name` holds a space. Bouncer wires up eleven of them, for shell, YAML,
Markdown, Dockerfiles, GitHub Actions, Python, Terraform, Kubernetes manifests,
Helm charts, Kyverno policies, and leaked secrets.

It only runs what applies. No Terraform in your repository means no Terraform
checks, and adding some next month needs no edit here.

Those fast checks are defined once, in `.pre-commit-config.yaml`, and run by
`pre-commit`, an off-the-shelf runner. The gate calls it and so does your
`git commit`, so the two can never disagree about what "clean" means. The
linters in there are declared local, which means they call the binaries
`make bootstrap` installed rather than fetching their own, so nobody ends up on
a different `shellcheck` than the gate uses. Five small housekeeping hooks, the
merge-conflict check among them, do come from `pre-commit`'s own repository,
pinned to a version.

So far this is a command sitting in a Makefile. Someone still has to run it, and
after the third time you will stop.

**A hook runs it for you.** A hook is a command the agent's runtime fires by
itself when something happens. You never call it. Claude Code offers several
events, and Bouncer uses two of them.

That alone is not enough either, because a hook that reports a problem is easy
to ignore. What makes a hook matter is the number it exits with:

| The hook exits | What the runtime does |
| --- | --- |
| `0` | Fine, carry on. The agent is told nothing. |
| `1` | Treats it as a non-blocking error and writes it to the debug log. **The agent never sees it.** |
| `2` | Reads your stderr and puts it in front of the agent. On `Stop`, the turn is blocked outright. |

Build a hook on exit 1 and it will look correct forever while achieving
absolutely nothing. Bouncer uses exit 2 on both of its hooks.

**The `Stop` hook is the gate.** It fires when the turn is about to end, runs
`make verify`, and on failure exits 2. The turn does not end. The output goes
straight back into the agent's context, so it reads the failure and fixes it
without you typing anything.

Waiting until the end is late, though. The agent can write twenty files before
anything checks the first one.

**The `PostToolUse` hook shortens that.** It fires right after a file is edited
or written, lints only that file, and takes under two seconds. Your `retry.sh` comes back
with its unquoted variable before the agent has moved on.

One thing is still missing. A check the agent cannot satisfy would loop forever,
and a gate that traps you is a gate you will switch off by lunchtime. So after
three failed attempts in a row Bouncer releases the turn and says so out loud,
and writes a line in `.bouncer-releases.log` so the release is not a thing that
quietly happens.

That is the whole mechanism. Here it is on one page:

```text
    you: "add the retry logic"
    │
┌───┼───── CLAUDE.md asks for this ──────────────────────────────────────┐
│   ▼                                                                    │
│   agent lays out its plan in three lines and gets going                │
│   │   so you know what it is about to do, and can stop it              │
│   │                                                                    │
└───┼────────────────────────────────────────────────────────────────────┘
╔═══╪═════ the hooks guarantee this, without you ════════════════════════╗
║   ▼                                                                    ║
║   agent edits a file                                                   ║
║   │                                                                    ║
║   ▼                                                                    ║
║   PostToolUse hook: lints that one file, in under 2 seconds            ║
║   │   exit 2 drops the complaint straight into the agent's context     ║
║   ▼                                                                    ║
║   agent fixes it and tries to end the turn ◀───────────────┐           ║
║   │                                                        │           ║
║   ▼                                                        │           ║
║   Stop hook: runs make verify, the whole gate              │           ║
║   ├─ exit 2: blocks the turn, hands the failure back ──────┘           ║
║   │     (three rounds, then it gives up and says so)                   ║
║   │                                                                    ║
╚═══╪════════════════════════════════════════════════════════════════════╝
    │  make verify passed
┌───┼───── CLAUDE.md asks for this ──────────────────────────────────────┐
│   ▼                                                                    │
│   commit                                                               │
│   │                                                                    │
│   ▼                                                                    │
│   reviewer: a second agent reads the diff, no memory of the chat       │
│   │   findings with severity and path:line, it fixes nothing           │
│   ▼                                                                    │
│   agent stops and hands you the report                                 │
│   │                                                                    │
└───┼────────────────────────────────────────────────────────────────────┘
    │
    ▼
    you: push, once no critical or high finding is left open
```

A double-lined box is enforced by the hooks. A single-lined box is something
`CLAUDE.md` asks for: the agent follows it, but nothing forces it to.

`CLAUDE.md` is the file your agent reads at the start of every session. Mostly
it holds one rule: fix the cause, never disable the check. It also asks for a
review after the commit, by a second agent that reads the finished diff with no
memory of the conversation that produced it. That reviewer reports and does not
fix, and nothing gets pushed while it has a critical or high finding open. It is
not part of the loop, because a check that can answer differently for the same
code cannot be a gate.

A bouncer does not argue about whether you are on the list. Being extremely
confident that you are on the list does not get you in. That is the whole idea.

| Without Bouncer | With Bouncer |
| --- | --- |
| The agent says it is done, and you find out it is not. | It cannot end the turn until `make verify` passes, or until three tries fail and it says so. |
| You are the linter, reading every diff. | The linter's complaint lands in the agent's context on its own. |
| "Please fix the lint errors", prompt after prompt. | It fixes them before you ever see the answer. |
| Checks run when someone remembers to run them. | Checks run as the agent writes files, and again before every turn ends. |
| A green result you have to take on trust. | `make demo` and `make selftest` show it working on your own machine. |

### What it looks like when it fires

The Stop hook refusing to let a turn end:

```text
=== make verify FAILED (attempt 1/3): the turn cannot end ===
== units ==
  tfdocs helpers               ok
== static (pre-commit) ==
  pre-commit                   FAIL
      yamllint.................................................................Failed
      - hook id: yamllint
      - exit code: 1

      config.yaml
        2:4       error    syntax error: mapping values are not allowed here (syntax)
```

And the PostToolUse hook handing back a complaint nobody asked for:

```text
PostToolUse:Edit hook returned blocking error
[${CLAUDE_PROJECT_DIR}/.claude/hooks/lint-changed.sh]: LINT FAILED: /path/to/demo.sh

In /path/to/demo.sh line 2:
echo $undefined_target
     ^---------------^ SC2154 (warning): undefined_target is referenced but not assigned.
     ^---------------^ SC2086 (info): Double quote to prevent globbing and word splitting.
```

### What Bouncer is, and what it is not

It is a harness, and its shape is a loop: act, check, feed the failure back,
correct, repeat until it passes. It does not make the model smarter and it does
not rewrite your prompts. The model still makes every fix. What changes is who
decides the work is finished, and that moves from the agent to a command that
does not negotiate.

It is not a library you import, a service you run, a pipeline or a graph. There
is no orchestration anywhere in it: two events and one command, sitting in your
repository.

A full harness is usually described as nine pieces. Six let the agent work at
all, and three are what let you trust the result:

| # | The piece | What it is for | Who gives it to you |
| --- | --- | --- | --- |
| 1 | Tools | Searching, reading, editing, running commands. The model asks; the harness executes. | Claude Code |
| 2 | A loop | Calling the model again with the result, so one step leads to the next. | Claude Code |
| 3 | Memory | Carrying what already happened into the next call, since the model keeps nothing. | Claude Code |
| 4 | Context | Choosing what the model sees each time, because the whole repository does not fit and would not help. | Claude Code |
| 5 | A place to work | A sandbox, so a bad command lands there and not on your machine. | Claude Code, as far as you configure it |
| 6 | A goal, and verification | Knowing the work is done because something checked, not because the model said so. | **Bouncer** |
| 7 | Permissions and limits | What it may do on its own, what it must ask about, and when to stop trying. | Claude Code, and Bouncer for the stopping |
| 8 | Observability | Seeing what actually happened on a run. | Nobody here, see below |
| 9 | Evals | Measuring whether a change to the harness helped or hurt. | Nobody here, see below |

Bouncer is piece six, and half of piece seven. That is the whole scope. Five of
those first six come with your agent already. The sixth does not, because only
you know what "done" means in your repository, and that is the gap Bouncer fills.

Pieces eight and nine, Bouncer does not do. Traces earn their keep when a run
cannot be repeated, and a failing `make verify` can be: run it again on the same
machine and you get the same output, in more detail than a log would carry. Not
across machines, though, and the gate says so out loud when it happens: schemas
it could not check, files git is not tracking. A cluster it cannot reach is the
same kind of gap, and `make verify-full` is where that one surfaces. What cannot
be recovered afterwards is the moment the gate did not run at all, so that is
what gets written down, and `make releases` prints it. Evals, measuring a change
to the harness itself, are not covered at all.

That nine-piece map is not ours. It comes from [santi's walk-through of harness
engineering](https://x.com/santtiagom_/status/2098782814837543075), which builds
a harness from nothing one piece at a time, and explains the parts around
Bouncer better than a README has room to.

### Who it is for

- **You use Claude Code every day** and you are tired of the second prompt, the
  one that says "the lint is failing, fix it". Bouncer makes that prompt
  unnecessary.
- **You write infrastructure with an agent.** Terraform, Kubernetes manifests,
  Helm charts, Kyverno policies: places where a plausible-looking mistake costs
  more than a failed build. That is the stack Bouncer checks out of the box.
- **Your team wants one Definition of Done for AI-assisted changes.** The same
  gate runs for every person and every agent, and its static checks run again at
  `git commit`.
- **You review what an agent produced.** The diff reaches you already linted and
  validated, so review time goes on design instead of unquoted variables.
- **You are building your own harness.** The exit code semantics, the traps and
  the record of what was actually tested are the parts that are hard to find
  written down anywhere else.

It is probably not for you if:

- **Your agent is not Claude Code.** The loop depends on Claude Code hooks.
  `make verify` and `pre-commit` still work without it, but nothing stops the
  turn.
- **Your stack is JavaScript, Go, Java or Rust.** No linters for those are wired
  in yet. Adding one is an entry in `.pre-commit-config.yaml`, but out of the
  box Bouncer would skip your code.
- **You need it on Windows**, or you want it to replace CI. It is tested on
  macOS, and it runs on your machine, not on a server.

### Try it

```bash
git clone https://github.com/Emi-Licha/bouncer.git
cd bouncer
make bootstrap
```

`make bootstrap` installs the tools and takes a few minutes the first time. The
next two commands do not need Claude Code at all.

```bash
make demo
```

Runs the linters over `examples/broken/`, which is invalid on purpose, and fails
if anything is *not* rejected.

```bash
make selftest
```

Runs the whole gate over `examples/valid/`, which holds real content (a
Terraform module, a Helm chart, a Kyverno policy and a Kubernetes manifest), and
has to pass.

That includes the end-to-end stage, a server-side dry run of the manifest against
whatever cluster your current kube context points at. Nothing gets created, but
check the context first if it points somewhere you care about. With no
reachable cluster, the stage is skipped with a warning.

Between the two you have watched it reject what it should and accept what it
should, on your own machine, in a few seconds. Nothing here asks to be taken on
faith. Watching the hooks stop an agent is the next step, and that needs a
restarted session: [the trap](#the-trap) explains why.

### Install it in your own project

"Try it" runs inside this repository. To put Bouncer in front of your own agent,
copy it into your project. It is a handful of files, so installing is copying.

**1. Check for files you would overwrite.**

```bash
ls Makefile .pre-commit-config.yaml .claude/settings.json CLAUDE.md 2>/dev/null
```

Anything it lists already exists: do not copy over it. Merge it by hand, as
described at the end of step 5.

**2. Copy the files.** Clone Bouncer into a directory outside your project. The
commands below call that directory `/path/to/bouncer`, and they all run from the
root of your project:

```bash
git clone https://github.com/Emi-Licha/bouncer.git /path/to/bouncer
mkdir -p .claude scripts
cp -R /path/to/bouncer/.claude/hooks /path/to/bouncer/.claude/agents .claude/
cp /path/to/bouncer/.claude/settings.json .claude/
cp /path/to/bouncer/scripts/*.sh scripts/
cp /path/to/bouncer/Makefile /path/to/bouncer/.pre-commit-config.yaml .
cp /path/to/bouncer/.yamllint.yml /path/to/bouncer/.markdownlint.yaml .
```

If you also want `make demo` and `make selftest`, copy the fixtures they run
against. Without them, both commands refuse to run instead of passing without
having tested anything.

```bash
cp -R /path/to/bouncer/examples .
```

**3. Keep Bouncer's scratch files out of git.**

```bash
printf '.claude/settings.local.json\n.claude/.skip-verify\n.verify-tmp/\n.bouncer-releases.log\n' >> .gitignore
```

**4. Install the tools and the git hook, then track the new files.**
`pre-commit` only checks files git is tracking.

```bash
make bootstrap
git add .claude scripts Makefile .pre-commit-config.yaml .yamllint.yml .markdownlint.yaml .gitignore
```

If you copied `examples/`, track it too with `git add examples`.

**5. Tell your agent the rules.** Add this to your `CLAUDE.md`, creating it if
it does not exist:

```markdown
## Definition of Done

Before you start, lay out your plan in three lines and go ahead. It is not a
request for approval: it lets the user stop you if they disagree.

Nothing is done until `make verify` passes. If the Stop hook blocks the turn,
fix the cause. Never disable a check, lower a threshold, skip a test, or edit
the Makefile or the hooks to get past it.

Never use `git commit --no-verify`, and never create `.claude/.skip-verify`:
that file is the user's escape hatch.

After committing a milestone, review it with the `reviewer` subagent. Do not
push while it has a critical or high finding open.

When something fails twice, stop and ask instead of trying a third variation.
```

If step 1 found existing files, merge them instead of copying:

- `.claude/settings.json`: copy the `hooks` block from Bouncer's into yours.
- `Makefile`: copy the targets you want. `verify` is required, because it is the
  one the Stop hook calls.
- `.pre-commit-config.yaml`: add Bouncer's `repos` entries to yours.
- `CLAUDE.md`: append the block above.

**6. Restart Claude Code and prove the gate is live.** Hooks are read when a
session starts, so nothing is armed until you restart. Then run the three checks
in [the trap](#the-trap). Do not skip them: a gate you have never seen block
anything is a gate you do not have.

### What you get

| Command | What it does |
| --- | --- |
| `make verify` | The gate. Everything else is built around this one command, including the cases no fixture can express. |
| `make lint` | The fast half on its own. |
| `make verify-full` | Adds a server-side dry run against a live cluster. |
| `make demo` | Proves the gate still catches things. |
| `make selftest` | Proves the gate still accepts good things. |
| `make releases` | Every time the gate stepped aside: released after three failures, or skipped through `.claude/.skip-verify`. |
| `make doctor` | Which tools you have and which you are missing. |
| `make bootstrap` | Installs them. |
| `make lang` | Which language Bouncer is speaking. |
| `make clean` | Removes scratch and cache directories. |

Run `make` with no target to list them all.

Bouncer works out what your repository actually contains and runs only what
applies. Add Terraform next month and nothing here needs editing.

The pieces, and none of them is clever:

| Path | What it is |
| --- | --- |
| `Makefile` | The commands above. |
| `scripts/verify.sh` | The engine. It lives here because macOS ships GNU Make 3.81, which has no `.ONESHELL`. |
| `scripts/messages.sh` | Every string Bouncer prints, in English and Spanish. |
| `scripts/yamllint.sh` | Runs `yamllint` for pre-commit and the lint hook, leaving out Helm chart templates wherever the chart lives. |
| `scripts/tfdocs.sh` | Finds the terraform-docs config a module will use, and reads its output file. |
| `scripts/tfdocs-test.sh` | The cases those two have already got wrong, run by `make verify`. |
| `scripts/bootstrap.sh` | Installs the tools. |
| `scripts/demo.sh` | Runs the linters over `examples/broken/`. |
| `.claude/settings.json` | Registers the two hooks. |
| `.claude/hooks/` | The two hooks: `lint-changed.sh` and `verify-on-stop.sh`. |
| `.claude/agents/reviewer.md` | The reviewer's instructions and its tool permissions. |
| `.pre-commit-config.yaml` | The single definition of every fast static check. |
| `.yamllint.yml`, `.markdownlint.yaml` | Settings for those two linters. |
| `examples/` | The fixtures for `make demo` and `make selftest`. |
| `CLAUDE.md` | The rules your agent reads. |

### The trap

Two ways this looks like it is working while doing nothing at all. The exit code
confusion above is the first. Here is the second.

**Hooks are read when a session starts.** Write `.claude/settings.json` in the
middle of a session and nothing is armed. Every file is right, the config is
valid, no hook runs. A wrong path in that file behaves identically, quietly, as
a non-blocking error.

So do not trust the config. Break something and confirm you were stopped:

1. `/hooks` should list both, and say which file they came from.
2. Write a file with a real lint error. It has to come back to you.
3. Break `make verify`, then try to end the turn. You have to be blocked.

If step 3 does not block you, you do not have a gate, whatever the config says.

### Make it yours

Bouncer speaks English by default, and so do the reviewer's reports. If you want
Spanish, there are two ways.

Just for you, leaving the repository untouched:

```bash
BOUNCER_LANG=es make verify
```

For everyone who clones it, with a `.bouncer.conf` in the root:

```ini
lang = es
```

The variable beats the file, so a team default and a personal preference never
have to fight. `make lang` says which is active. A third language is one `case`
block in `scripts/messages.sh`, and missing keys fall back to English, so a
half-finished translation still works.

The documentation check for Terraform is opt-in twice over. It runs only where a
`.terraform-docs.yml` sets an output file, found the way terraform-docs finds
it: the module, the module's `.config/`, the root, the root's `.config/`, and
last `~/.tfdocs.d`, which is outside the repository. A config there drives the
check on your machine and on nobody else's, CI included. And then only on
modules where that file carries the `BEGIN_TF_DOCS` marker, so a directory
without it, such as a usage example, is left alone.

Bouncer reads that output file with a small parser that understands the usual
block style. A config that writes `output:` as a one-line `{file: ...}` map is
reported as unreadable and skipped, rather than guessed at.

### Design notes

**Missing content is skipped. A missing tool is not.** If there are no `.tf`
files, the Terraform checks are skipped, which is honest. But `.tf` files
without `tflint` installed are a hard failure, because otherwise the gate goes
green for the worst possible reason: nothing is installed to catch anything.

**`kubeconform ok` does not mean every manifest was checked.**
`-ignore-missing-schemas` is what lets a custom resource through, and it is also
how a run reports success having validated a fraction of what it read. The stage
prints the skipped count, so a green line is not mistaken for more coverage than
it is.

**The coverage floor is 85%, and only for `src/` layouts.** A bare `--cov`
counts the test files, which are close to fully covered by definition and drag
the total over the line: 75% source plus 100% tests reports 89%. Without a
`src/` to scope to, the floor is dropped out loud, because a threshold that goes
green for the wrong reason is worse than no threshold.

**Untracked files warn, they do not fail.** `pre-commit` only sees files git is
tracking, so a brand new file skips the static pass entirely. Failing on that
would block you all day, and a gate people switch off is worth nothing. The
warning keeps the hole visible instead of silent.

**The Stop hook gives up after three tries.** A check the agent cannot fix would
otherwise loop forever. The counter resets on release, because without that the
gate stays open for the rest of the session.

**The reviewer is not supposed to write, and mostly cannot.** `Write` and `Edit`
are withheld from it. It keeps `Bash`, because a reviewer that cannot check
whether a binary exists inflates severities over guesses, and `Bash` can write
files. The last step of that prohibition is a rule in its prompt rather than a
wall, and you should know that before pointing it at a repository you care
about.

### What has actually been run

A repository about verification should say what was tested rather than ask to be
believed. All of this was run on macOS.

Against a live Claude Code session:

- Both hooks registered, and which settings file they came from.
- `PostToolUse` returning a lint error into the agent's context.
- `Stop` blocking a turn, the three-strike release, and the counter resetting.
- `.claude/.skip-verify` letting a turn end with the gate still red.
- The reviewer following the configured language both ways: asked in Spanish
  with the English default it answered in English, and set to Spanish it
  answered in Spanish.

At the command line:

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
- The release log on both of its paths and in both languages, by feeding the
  Stop hook the input Claude Code sends it, in a scratch copy of the repository.
  Including the two ways it degrades: no catalogue, and a reformatted summary,
  which log that the failing check could not be read rather than a bare `?`.
- Installing into an empty project by following the install steps above to the
  letter: `make verify` green on clean content and red on a broken script, both
  hooks exiting 2 when fed the same input Claude Code sends them, and
  `make demo` and `make selftest` refusing to run until the fixtures were
  copied.

The checks against real content can be reproduced with `make demo` and
`make selftest`, except the coverage floor: the Python stage looks for `src/`,
`tests/` and `pyproject.toml` at the repository root and cannot see a fixture in
a subdirectory. Everything else was run by hand and is recorded here, not
automated.

Not run: the apt/dnf path in `bootstrap.sh`, which is written but never
executed, and the three-minute budget against a repository with real content.
Here `verify` takes about two seconds and `selftest` about four.

### Limits

Parts of the gate need the network, though never cloud credentials: `pre-commit`
downloads its hook environments on first run, `kubeconform` fetches schemas it
has not cached, `trivy` fetches its checks bundle, and `terraform init` fetches
any providers a module declares.

The hooks need `jq` to read what Claude Code sends them. Without it they step
aside in silence rather than wedge the session. `make bootstrap` installs it,
`make doctor` lists it, and `make verify` fails without it, but the Stop hook
itself cannot warn you: it is the part that needs `jq`.

The reviewer is a language model, not a linter. Its first two reviews produced
seven findings, two of them real, and both times the fix it suggested would have
been worse than the bug. Tightening its rules, so that it checks what it can
check and never prescribes a remedy it has not run, changed that: its two most
recent reviews produced seven findings, six of them real. The price is time,
about five and a half minutes on a ninety-line diff, most of it spent verifying
its own claims, and nothing in its frontmatter caps it. Reproduce a finding
before acting on it, either way.

`.bouncer-releases.log` is a note to yourself, not an audit trail. It sits in
your working tree, so anything that can write there can edit it, the agent
included. Two sessions running at once interleave lines that look alike, and
nothing rotates the file: leave `.claude/.skip-verify` in place and it grows by
a line per turn.

Nothing enforces what `CLAUDE.md` asks for: the plan, the commit, the review and
the no-push rule. They are instructions, not hooks, so they hold only as long as
the agent, and whoever pushes, follows them.

### License

MIT. See [LICENSE](LICENSE).

## Español

**Tu agente dice que está listo. Bouncer chequea los factos.**

Porque casi nunca lo está.

Entonces leés el diff, encontrás la variable sin comillas, prompteás de nuevo,
te vuelve a decir que está listo, y ahí se te fue la tarde.

Esto no es un problema de prompting, y un prompt mejor no lo va a arreglar. Para
ver por qué, conviene saber quién decide de verdad que una tarea terminó.

### Por qué tu agente cree que terminó

Un modelo hace una sola cosa: entra texto, sale texto. No abre archivos, no corre
comandos y no se acuerda de lo que hizo hace un minuto.

Así que cuando tu agente busca en tu repo, edita un archivo y corre los tests,
todo eso lo hace otra cosa. El modelo pide; esa otra cosa ejecuta. Esa otra cosa
es el harness, y con Claude Code, Claude es el modelo y Claude Code es el
harness.

El harness también decide cuándo dejar de preguntar. Por defecto deja de
preguntar cuando el modelo dice que el trabajo está terminado, y el modelo
contesta desde lo que quiso hacer, no desde lo que pasó. Todavía nadie miró el
resultado. El primero que lo mira sos vos, y por eso la tarde termina como
termina.

Bouncer mueve esa decisión a un comando.

### Un comando, y las piezas que lo disparan

Pongamos que pediste un helper de reintentos y el agente escribió `retry.sh`.

**El gate es un comando**, y contesta que sí o que no:

```bash
make verify
```

Corre los linters sobre tus archivos, valida tus manifiestos, renderiza tus
charts y corre tus tests, y después sale con cero o no. Un linter es un programa
que lee código sin ejecutarlo y se queja de lo que está roto o es riesgoso:
`shellcheck` es el que te avisa que `echo $name` se rompe la primera vez que
`$name` tiene un espacio. Bouncer engancha once, para shell, YAML, Markdown,
Dockerfiles, GitHub Actions, Python, Terraform, manifiestos de Kubernetes,
charts de Helm, policies de Kyverno, y secretos filtrados.

Corre solo lo que aplica. Si no hay Terraform en tu repo, no hay checks de
Terraform, y si el mes que viene agregás, acá no hay que tocar nada.

Esos checks rápidos están definidos en un solo lugar, `.pre-commit-config.yaml`,
y los corre `pre-commit`, una herramienta ya hecha. La llama el gate y la llama
tu `git commit`, así que los dos nunca pueden estar en desacuerdo sobre qué
significa "limpio". Los linters de ahí están declarados como locales, o sea que
llaman a los binarios que instaló `make bootstrap` en vez de bajarse los suyos,
así que nadie termina usando un `shellcheck` distinto del que usa el gate. Cinco
hooks chicos de mantenimiento, entre ellos el que busca conflictos de merge, sí
vienen del repo de `pre-commit`, fijados a una versión.

Hasta acá esto es un comando viviendo en un Makefile. Alguien lo tiene que
correr, y a la tercera vez vos ya no lo corrés más.

**Un hook lo corre por vos.** Un hook es un comando que el runtime del agente
dispara solo cuando pasa algo. Vos nunca lo llamás. Claude Code ofrece varios
eventos, y Bouncer usa dos.

Con eso solo tampoco alcanza, porque un hook que informa un problema es fácil de
ignorar. Lo que hace que un hook pese es el número con el que sale:

| El hook sale con | Qué hace el runtime |
| --- | --- |
| `0` | Todo bien, seguí. Al agente no se le dice nada. |
| `1` | Lo toma como un error no bloqueante y lo escribe en el log de debug. **El agente nunca lo ve.** |
| `2` | Lee tu stderr y se lo pone adelante al agente. En `Stop`, además, el turno queda bloqueado. |

Armá un hook sobre exit 1 y va a parecer correcto para siempre, sin lograr
absolutamente nada. Bouncer usa exit 2 en los dos.

**El hook de `Stop` es el gate.** Se dispara cuando el turno está por terminar,
corre `make verify`, y si falla sale con 2. El turno no termina. La salida le
vuelve derecho al contexto del agente, así que lee la falla y la corrige sin que
vos escribas nada.

Igual, esperar hasta el final es tarde. El agente puede escribir veinte archivos
antes de que algo chequee el primero.

**El hook de `PostToolUse` acorta eso.** Se dispara justo después de que se
edita o se escribe un archivo, lintea solo ese archivo, y tarda menos de dos
segundos. Tu `retry.sh`
vuelve con la variable sin comillas antes de que el agente siga para otro lado.

Falta una cosa más. Un check que el agente no puede satisfacer generaría un loop
infinito, y un gate que te deja encerrado es un gate que vas a apagar antes del
mediodía. Así que después de tres intentos fallidos seguidos Bouncer libera el
turno y lo dice en voz alta, y escribe una línea en `.bouncer-releases.log` para
que esa liberación no sea algo que pasó calladito.

Ese es todo el mecanismo. Acá está en una sola página:

```text
    vos: "agregá la lógica de reintento"
    │
┌───┼───── lo pide CLAUDE.md ────────────────────────────────────────────┐
│   ▼                                                                    │
│   el agente te cuenta el plan en tres líneas y arranca                 │
│   │   para que sepas qué encara y lo frenes si no te cierra            │
│   │                                                                    │
└───┼────────────────────────────────────────────────────────────────────┘
╔═══╪═════ lo garantizan los hooks, sin vos ═════════════════════════════╗
║   ▼                                                                    ║
║   el agente edita un archivo                                           ║
║   │                                                                    ║
║   ▼                                                                    ║
║   hook de PostToolUse: lintea ese archivo, en menos de 2 segundos      ║
║   │   exit 2 le mete la queja derecho en el contexto al agente         ║
║   ▼                                                                    ║
║   el agente lo arregla e intenta terminar el turno ◀───────┐           ║
║   │                                                        │           ║
║   ▼                                                        │           ║
║   hook de Stop: corre make verify, el gate entero          │           ║
║   ├─ exit 2: frena el turno y le devuelve la falla ────────┘           ║
║   │     (tres vueltas, después se rinde y lo dice)                     ║
║   │                                                                    ║
╚═══╪════════════════════════════════════════════════════════════════════╝
    │  make verify pasó
┌───┼───── lo pide CLAUDE.md ────────────────────────────────────────────┐
│   ▼                                                                    │
│   commit                                                               │
│   │                                                                    │
│   ▼                                                                    │
│   reviewer: un segundo agente lee el diff, sin memoria de la charla    │
│   │   hallazgos con severidad y archivo:línea, no arregla nada         │
│   ▼                                                                    │
│   el agente para y te pasa el informe                                  │
│   │                                                                    │
└───┼────────────────────────────────────────────────────────────────────┘
    │
    ▼
    vos: push, cuando no queda ningún hallazgo crítico o alto abierto
```

Una caja de línea doble la hacen cumplir los hooks. Una de línea simple es algo
que pide `CLAUDE.md`: el agente lo sigue, pero nada lo obliga.

`CLAUDE.md` es el archivo que tu agente lee al empezar cada sesión. Básicamente
tiene una regla: arreglá la causa, nunca deshabilites el check. También pide una
revisión después del commit, hecha por un segundo agente que lee el diff
terminado sin memoria de la conversación que lo produjo. Ese reviewer reporta y
no arregla, y no se pushea nada mientras tenga un hallazgo crítico o alto
abierto. No es parte del loop, porque un chequeo que puede responder distinto
para el mismo código no puede ser un gate.

Un patova no discute si estás en la lista. Estar muy convencido de que estás en
la lista no te hace entrar. Esa es toda la idea.

| Sin Bouncer | Con Bouncer |
| --- | --- |
| El agente dice que terminó, y te enterás después de que no. | No puede terminar el turno hasta que `make verify` pase, o hasta que fallen tres intentos y lo diga. |
| El linter sos vos, leyendo cada diff. | La queja del linter le llega sola al contexto del agente. |
| "Por favor arreglá los errores de lint", prompt tras prompt. | Los arregla antes de que veas la respuesta. |
| Los checks corren cuando alguien se acuerda de correrlos. | Corren mientras el agente escribe archivos, y de nuevo antes de que termine cada turno. |
| Un verde que te tenés que creer. | `make demo` y `make selftest` te lo muestran andando en tu máquina. |

### Cómo se ve cuando salta

El hook de Stop negándose a dejar terminar un turno:

```text
=== make verify FALLÓ (intento 1/3): no se puede terminar el turno ===
== units ==
  tfdocs helpers               ok
== static (pre-commit) ==
  pre-commit                   FAIL
      yamllint.................................................................Failed
      - hook id: yamllint
      - exit code: 1

      config.yaml
        2:4       error    syntax error: mapping values are not allowed here (syntax)
```

Y el hook de PostToolUse devolviendo una queja que nadie pidió:

```text
PostToolUse:Edit hook returned blocking error
[${CLAUDE_PROJECT_DIR}/.claude/hooks/lint-changed.sh]: LINT FALLÓ: /path/to/demo.sh

In /path/to/demo.sh line 2:
echo $undefined_target
     ^---------------^ SC2154 (warning): undefined_target is referenced but not assigned.
     ^---------------^ SC2086 (info): Double quote to prevent globbing and word splitting.
```

### Qué es Bouncer, y qué no

Es un harness, y tiene forma de loop: actuar, chequear, devolver la falla,
corregir, repetir hasta que pase. No hace más inteligente al modelo ni te
reescribe los prompts. El modelo sigue haciendo cada arreglo. Lo que cambia es
quién decide que el trabajo está terminado, y eso pasa del agente a un comando
que no negocia.

No es una librería que importás, ni un servicio que corrés, ni un pipeline, ni
un graph. No hay orquestación en ningún lado: dos eventos y un comando, viviendo
en tu repo.

Un harness completo se suele describir como nueve piezas. Seis le permiten al
agente trabajar, y tres son las que te permiten confiar en el resultado:

| # | La pieza | Para qué está | Quién te la da |
| --- | --- | --- | --- |
| 1 | Tools | Buscar, leer, editar, correr comandos. El modelo pide; el harness ejecuta. | Claude Code |
| 2 | Un loop | Volver a llamar al modelo con el resultado, para que un paso lleve al siguiente. | Claude Code |
| 3 | Memoria | Llevar lo que ya pasó a la llamada siguiente, porque el modelo no guarda nada. | Claude Code |
| 4 | Contexto | Elegir qué ve el modelo cada vez, porque el repo entero no entra y tampoco ayudaría. | Claude Code |
| 5 | Un lugar donde trabajar | Un sandbox, para que un comando malo caiga ahí y no en tu máquina. | Claude Code, hasta donde lo configures |
| 6 | Un objetivo, y verificación | Saber que está terminado porque algo lo chequeó, no porque el modelo lo dijo. | **Bouncer** |
| 7 | Permisos y límites | Qué puede hacer solo, qué te tiene que preguntar, y cuándo dejar de intentar. | Claude Code, y Bouncer para el cuándo parar |
| 8 | Observabilidad | Ver qué pasó de verdad en una corrida. | Nadie acá, mirá abajo |
| 9 | Evals | Medir si un cambio en el harness mejoró o empeoró las cosas. | Nadie acá, mirá abajo |

Bouncer es la pieza seis, y la mitad de la siete. Ese es todo el alcance. Cinco
de esas primeras seis ya vienen con tu agente. La sexta no, porque solo vos
sabés qué significa "terminado" en tu repo, y ese es el hueco que llena Bouncer.

Las piezas ocho y nueve Bouncer no las hace. Las trazas valen sobre todo cuando
una corrida no se puede repetir, y un `make verify` que falla sí se puede:
corrélo de nuevo en la misma máquina y te da lo mismo, con más detalle del que
un log iba a guardar. Entre máquinas distintas no, y el gate lo dice en voz alta
cuando pasa: schemas que no pudo chequear, archivos que git no está trackeando.
Un cluster al que no llega es la misma clase de hueco, y ese aparece en
`make verify-full`. Lo que no se recupera después es el momento en que el gate
directamente no corrió, así que eso es lo que queda escrito, y `make releases`
te lo muestra. Las evals, medir un cambio del harness mismo, no están cubiertas.

Ese mapa de nueve piezas no es nuestro. Sale de [la explicación de harness
engineering de santi](https://x.com/santtiagom_/status/2098782814837543075), que
arma un harness desde cero pieza por pieza, y explica lo que rodea a Bouncer
mejor de lo que entra en un README.

### A quién le sirve

- **Usás Claude Code todos los días** y te cansaste del segundo prompt, el de
  "está fallando el lint, arreglalo". Bouncer hace que ese prompt sobre.
- **Escribís infraestructura con un agente.** Terraform, manifiestos de
  Kubernetes, charts de Helm, policies de Kyverno: lugares donde un error que
  parece razonable sale más caro que un build roto. Es el stack que Bouncer
  chequea de fábrica.
- **Tu equipo quiere una sola definición de terminado para cambios hechos con
  IA.** El mismo gate corre para cada persona y cada agente, y sus checks
  estáticos vuelven a correr en el `git commit`.
- **Revisás lo que produce un agente.** El diff te llega ya linteado y validado,
  así que el tiempo de review se va en diseño y no en variables sin comillas.
- **Estás armando tu propio harness.** La semántica de los exit codes, las
  trampas y el registro de qué se probó de verdad son justo lo que cuesta
  encontrar escrito en otro lado.

Probablemente no es para vos si:

- **Tu agente no es Claude Code.** El loop depende de los hooks de Claude Code.
  `make verify` y `pre-commit` andan igual sin él, pero nada frena el turno.
- **Tu stack es JavaScript, Go, Java o Rust.** Todavía no hay linters conectados
  para esos. Agregar uno es una entrada en `.pre-commit-config.yaml`, pero tal
  como viene Bouncer se saltearía tu código.
- **Lo necesitás en Windows**, o querés que reemplace a tu CI. Está probado en
  macOS y corre en tu máquina, no en un servidor.

### Probalo

```bash
git clone https://github.com/Emi-Licha/bouncer.git
cd bouncer
make bootstrap
```

`make bootstrap` instala las herramientas y la primera vez tarda unos minutos.
Los dos comandos que siguen no necesitan Claude Code para nada.

```bash
make demo
```

Corre los linters sobre `examples/broken/`, que es inválido a propósito, y falla
si algo *no* es rechazado.

```bash
make selftest
```

Corre el gate entero sobre `examples/valid/`, que tiene contenido de verdad (un
módulo de Terraform, un chart de Helm, una policy de Kyverno y un manifiesto de
Kubernetes), y tiene que pasar.

Eso incluye la etapa end-to-end, un dry run del lado del servidor del manifiesto
contra el cluster al que apunte tu contexto de kube actual. No se crea nada,
pero revisá el contexto antes si apunta a algún lugar que te importa. Sin un
cluster accesible, la etapa se saltea con una advertencia.

Entre los dos ya lo viste rechazar lo que debe y aceptar lo que debe, en tu
propia máquina, en pocos segundos. Acá no hay nada que tengas que creer. Ver a
los hooks frenar a un agente es el paso siguiente, y eso necesita una sesión
reiniciada: [la trampa](#la-trampa) explica por qué.

### Instalalo en tu proyecto

"Probalo" corre adentro de este repositorio. Para ponerle Bouncer adelante a tu
propio agente, copialo a tu proyecto. Son un puñado de archivos, así que
instalarlo es copiarlos.

**1. Fijate si vas a pisar algún archivo.**

```bash
ls Makefile .pre-commit-config.yaml .claude/settings.json CLAUDE.md 2>/dev/null
```

Lo que liste ya existe: no lo sobrescribas. Combinalo a mano, como se explica al
final del paso 5.

**2. Copiá los archivos.** Cloná Bouncer en un directorio fuera de tu proyecto.
Los comandos de abajo llaman a ese directorio `/ruta/a/bouncer`, y todos se
corren desde la raíz de tu proyecto:

```bash
git clone https://github.com/Emi-Licha/bouncer.git /ruta/a/bouncer
mkdir -p .claude scripts
cp -R /ruta/a/bouncer/.claude/hooks /ruta/a/bouncer/.claude/agents .claude/
cp /ruta/a/bouncer/.claude/settings.json .claude/
cp /ruta/a/bouncer/scripts/*.sh scripts/
cp /ruta/a/bouncer/Makefile /ruta/a/bouncer/.pre-commit-config.yaml .
cp /ruta/a/bouncer/.yamllint.yml /ruta/a/bouncer/.markdownlint.yaml .
```

Si además querés `make demo` y `make selftest`, copiá los fixtures contra los
que corren. Sin ellos, los dos comandos se niegan a correr en vez de pasar sin
haber probado nada.

```bash
cp -R /ruta/a/bouncer/examples .
```

**3. Dejá los archivos temporales de Bouncer fuera de git.**

```bash
printf '.claude/settings.local.json\n.claude/.skip-verify\n.verify-tmp/\n.bouncer-releases.log\n' >> .gitignore
```

**4. Instalá las herramientas y el hook de git, y trackeá los archivos nuevos.**
`pre-commit` solo revisa lo que git está trackeando.

```bash
make bootstrap
git add .claude scripts Makefile .pre-commit-config.yaml .yamllint.yml .markdownlint.yaml .gitignore
```

Si copiaste `examples/`, trackealo también con `git add examples`.

**5. Contale las reglas a tu agente.** Agregá esto a tu `CLAUDE.md`, y crealo si
no existe:

```markdown
## Definition of Done

Before you start, lay out your plan in three lines and go ahead. It is not a
request for approval: it lets the user stop you if they disagree.

Nothing is done until `make verify` passes. If the Stop hook blocks the turn,
fix the cause. Never disable a check, lower a threshold, skip a test, or edit
the Makefile or the hooks to get past it.

Never use `git commit --no-verify`, and never create `.claude/.skip-verify`:
that file is the user's escape hatch.

After committing a milestone, review it with the `reviewer` subagent. Do not
push while it has a critical or high finding open.

When something fails twice, stop and ask instead of trying a third variation.
```

Si en el paso 1 encontraste archivos existentes, combinalos en vez de copiarlos:

- `.claude/settings.json`: copiá el bloque `hooks` del de Bouncer al tuyo.
- `Makefile`: copiá los targets que quieras. `verify` es obligatorio, porque es
  el que llama el hook de Stop.
- `.pre-commit-config.yaml`: sumá las entradas de `repos` de Bouncer a las
  tuyas.
- `CLAUDE.md`: agregá el bloque de arriba al final.

**6. Reiniciá Claude Code y comprobá que el gate está vivo.** Los hooks se leen
al arrancar la sesión, así que nada queda armado hasta que reinicies. Después
corré los tres chequeos de [la trampa](#la-trampa). No te los saltees: un gate
que nunca viste bloquear nada es un gate que no tenés.

### Qué te llevás

| Comando | Qué hace |
| --- | --- |
| `make verify` | El gate. Todo lo demás está construido alrededor de este comando, incluidos los casos que ningún fixture puede expresar. |
| `make lint` | Solo la mitad rápida. |
| `make verify-full` | Agrega un dry run server-side contra un cluster real. |
| `make demo` | Prueba que el gate sigue atrapando cosas. |
| `make selftest` | Prueba que el gate sigue aceptando lo bueno. |
| `make releases` | Cada vez que el gate se hizo a un lado: liberado tras tres fallas, o salteado por `.claude/.skip-verify`. |
| `make doctor` | Qué herramientas tenés y cuáles te faltan. |
| `make bootstrap` | Las instala. |
| `make lang` | En qué idioma está hablando Bouncer. |
| `make clean` | Borra los directorios temporales y de caché. |

`make` a secas los lista todos.

Bouncer se fija qué contiene realmente tu repo y corre solo lo que aplica. Si el
mes que viene agregás Terraform, no hay que tocar nada acá.

Las piezas, y ninguna es ingeniosa:

| Ruta | Qué es |
| --- | --- |
| `Makefile` | Los comandos de arriba. |
| `scripts/verify.sh` | El motor. Vive acá porque macOS trae GNU Make 3.81, que no tiene `.ONESHELL`. |
| `scripts/messages.sh` | Todas las cadenas que imprime Bouncer, en inglés y castellano. |
| `scripts/yamllint.sh` | Corre `yamllint` para pre-commit y el hook de lint, dejando afuera los templates de charts de Helm, estén donde estén. |
| `scripts/tfdocs.sh` | Encuentra la config de terraform-docs que va a usar un módulo, y lee su archivo de salida. |
| `scripts/tfdocs-test.sh` | Los casos que esas dos ya erraron alguna vez, que corre `make verify`. |
| `scripts/bootstrap.sh` | Instala las herramientas. |
| `scripts/demo.sh` | Corre los linters sobre `examples/broken/`. |
| `.claude/settings.json` | Registra los dos hooks. |
| `.claude/hooks/` | Los dos hooks: `lint-changed.sh` y `verify-on-stop.sh`. |
| `.claude/agents/reviewer.md` | Las instrucciones del reviewer y sus permisos de herramientas. |
| `.pre-commit-config.yaml` | La única definición de los checks estáticos rápidos. |
| `.yamllint.yml`, `.markdownlint.yaml` | La configuración de esos dos linters. |
| `examples/` | Los fixtures de `make demo` y `make selftest`. |
| `CLAUDE.md` | Las reglas que lee tu agente. |

### La trampa

Dos formas en que esto parece andar mientras no hace absolutamente nada. La
confusión de códigos de salida de más arriba es la primera. Esta es la segunda.

**Los hooks se leen al arrancar la sesión.** Escribí `.claude/settings.json` en
el medio de una sesión y no se arma nada. Todos los archivos están bien, la
configuración es válida, ningún hook corre. Una ruta mal escrita en ese archivo
se comporta igual, en silencio, como error no bloqueante.

Así que no le creas a la configuración. Rompé algo y confirmá que te frenaron:

1. `/hooks` tiene que listar los dos, y decir de qué archivo salieron.
2. Escribí un archivo con un error de lint real. Te tiene que volver.
3. Rompé `make verify` e intentá terminar el turno. Te tiene que frenar.

Si el paso 3 no te bloquea, no tenés gate, diga lo que diga la configuración.

### Hacelo tuyo

Bouncer habla inglés por defecto, y los informes del reviewer también. Si lo
querés en castellano, hay dos formas.

Solo para vos, sin tocar el repo:

```bash
BOUNCER_LANG=es make verify
```

Para todos los que lo clonen, con un `.bouncer.conf` en la raíz:

```ini
lang = es
```

La variable le gana al archivo, así que un default de equipo y una preferencia
personal nunca tienen que pelearse. `make lang` te dice cuál está activo. Un
tercer idioma es un bloque `case` en `scripts/messages.sh`, y las claves que
falten caen a inglés, así que una traducción a medias ya sirve.

El chequeo de documentación de Terraform es doblemente opcional. Corre solo
donde un `.terraform-docs.yml` define un archivo de salida, buscado igual que lo
busca terraform-docs: el módulo, el `.config/` del módulo, la raíz, el `.config/`
de la raíz, y por último `~/.tfdocs.d`, que está fuera del repo. Una config ahí
maneja el chequeo en tu máquina y en la de nadie más, CI incluido. Y aun así
solo sobre los módulos donde ese archivo tenga el marcador `BEGIN_TF_DOCS`, así
que un directorio sin él, como un ejemplo de uso, queda afuera.

Bouncer lee ese archivo de salida con un parser chico que entiende el estilo en
bloque de siempre. Una config que escribe `output:` como un mapa en una línea,
`{file: ...}`, se reporta como ilegible y se saltea, en vez de adivinarla.

### Decisiones de diseño

**El contenido que falta se saltea. Una herramienta que falta, no.** Si no hay
archivos `.tf`, los checks de Terraform se saltean, y eso es honesto. Pero tener
archivos `.tf` sin `tflint` instalado es un fallo duro, porque si no el gate se
pone verde por el peor motivo posible: no hay nada instalado que pueda atrapar
nada.

**Que diga `kubeconform ok` no significa que se hayan chequeado todos los
manifiestos.** `-ignore-missing-schemas` es lo que deja pasar un recurso
personalizado, y también es la forma en que una corrida reporta éxito habiendo
validado una fracción de lo que leyó. La etapa imprime cuántos salteó, para que
una línea verde no se confunda con más cobertura de la que es.

**El piso de cobertura es 85%, y solo para layouts con `src/`.** Un `--cov`
pelado cuenta los archivos de test, que están casi completamente cubiertos por
definición y empujan el total por encima de la línea: 75% del fuente más 100% de
tests reporta 89%. Sin un `src/` al que acotarlo, el piso se abandona en voz
alta, porque un umbral que da verde por el motivo equivocado es peor que no
tener umbral.

**Los archivos sin trackear advierten, no fallan.** `pre-commit` solo ve
archivos que git está trackeando, así que uno recién creado se saltea el paso
estático entero. Fallar por eso te bloquearía todo el día, y un gate que la
gente apaga no sirve para nada. La advertencia mantiene la grieta a la vista en
vez de silenciosa.

**El hook de Stop se rinde a los tres intentos.** Un check que el agente no
puede arreglar generaría un loop infinito. El contador se resetea al liberar,
porque sin eso el gate queda abierto el resto de la sesión.

**El reviewer no debería escribir, y en general no puede.** Tiene `Write` y
`Edit` negados. Conserva `Bash`, porque un revisor que no puede comprobar si un
binario existe infla severidades sobre suposiciones, y con `Bash` se pueden
escribir archivos. El último tramo de esa prohibición es una regla de su prompt
y no un muro, y conviene saberlo antes de apuntarlo a un repo que te importa.

### Qué se corrió de verdad

Un repositorio que habla de verificación debería decir qué probó en vez de pedir
que le crean. Todo esto se corrió en macOS.

Contra una sesión real de Claude Code:

- Los dos hooks registrados, y de qué archivo de settings salieron.
- `PostToolUse` devolviendo un error de lint al contexto del agente.
- `Stop` bloqueando un turno, la liberación al tercer intento, y el contador
  reseteándose.
- `.claude/.skip-verify` dejando terminar un turno con el gate todavía en rojo.
- El reviewer siguiendo el idioma configurado en los dos sentidos: preguntado en
  castellano y con el default en inglés contestó en inglés, y configurado en
  castellano contestó en castellano.

En la línea de comandos:

- Contenido real: `kubeconform` aceptando un manifiesto bueno y rechazando uno
  malo, `helm template` sobre un chart, `kyverno test` en los dos sentidos,
  `terraform validate`, `tflint`, `trivy`, `terraform-docs` sobre un módulo al
  día y sobre uno desactualizado, y el piso de cobertura rechazando 75% y
  aceptando 100%.
- `make verify-full` contra kind sobre colima. Un ConfigMap llamado
  `Nombre_Invalido` es `Valid: 1` para kubeconform, cuyo schema no restringe el
  formato del nombre, y el API server lo rechaza por no ser un subdominio
  RFC 1123. Esa brecha es por lo que la etapa e2e existe aparte.
- Nombres con espacio, comilla o salto de línea, tanto en archivos como en
  directorios.
- `bootstrap` en sus tres ramas y el código de salida de cada una, dos de ellas
  con un gestor de paquetes simulado para no instalar nada.
- Los dos idiomas en `verify`, `demo`, `doctor`, `bootstrap` y los dos hooks.
- El registro de liberaciones en sus dos caminos y en los dos idiomas, dándole
  al hook de Stop la misma entrada que le manda Claude Code, sobre una copia de
  prueba del repo. Incluidas sus dos formas de degradarse: sin catálogo, y con
  el resumen reformateado, que anotan que no se pudo leer el check en vez de un
  `?` pelado.
- Instalarlo en un proyecto vacío siguiendo al pie de la letra los pasos de
  instalación de arriba: `make verify` en verde con contenido limpio y en rojo
  con un script roto, los dos hooks saliendo con 2 al recibir la misma entrada
  que les manda Claude Code, y `make demo` y `make selftest` negándose a correr
  hasta que se copiaron los fixtures.

Los chequeos sobre contenido real se pueden reproducir con `make demo` y
`make selftest`, salvo el piso de cobertura: la etapa de Python busca `src/`,
`tests/` y `pyproject.toml` en la raíz del repo y no puede ver un fixture en un
subdirectorio. Todo lo demás se corrió a mano y queda registrado acá, sin
automatizar.

Sin correr: el camino apt/dnf de `bootstrap.sh`, que está escrito pero nunca se
ejecutó, y el presupuesto de tres minutos contra un repo con contenido real. Acá
`verify` tarda unos dos segundos y `selftest` unos cuatro.

### Límites

Partes del gate necesitan red, aunque nunca credenciales de nube: `pre-commit`
baja sus entornos de hooks la primera vez, `kubeconform` baja los schemas que no
tiene en caché, `trivy` baja su paquete de checks, y `terraform init` baja los
providers que declare un módulo.

Los hooks necesitan `jq` para leer lo que les manda Claude Code. Sin él se hacen
a un lado en silencio, antes que trabar la sesión. `make bootstrap` lo instala,
`make doctor` lo lista y `make verify` falla sin él, pero el hook de Stop no te
puede avisar: es justamente la parte que necesita `jq`.

El reviewer es un modelo de lenguaje, no un linter. Sus dos primeras revisiones
trajeron siete hallazgos, dos reales, y las dos veces el arreglo que propuso
habría sido peor que el problema. Endurecerle las reglas, para que compruebe lo
que puede comprobar y nunca recete un remedio que no probó, cambió eso: sus dos
revisiones más recientes trajeron siete hallazgos, seis reales. El precio es
tiempo, unos cinco minutos y medio sobre un diff de noventa líneas, la mayor
parte verificando sus propias afirmaciones, y nada en su frontmatter lo limita.
Reproducí un hallazgo antes de actuar sobre él, en cualquier caso.

`.bouncer-releases.log` es una nota para vos, no una auditoría. Vive en tu
working tree, así que cualquier cosa que pueda escribir ahí lo puede editar, el
agente incluido. Dos sesiones a la vez intercalan líneas que se parecen entre
sí, y nada rota el archivo: dejá `.claude/.skip-verify` puesto y crece una línea
por turno.

Nada hace cumplir lo que pide `CLAUDE.md`: el plan, el commit, la review y la
regla de no pushear. Son instrucciones, no hooks, así que se sostienen solo
mientras el agente, y quien pushea, las respete.

### Licencia

MIT. Ver [LICENSE](LICENSE).
