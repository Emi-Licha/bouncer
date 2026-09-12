# Bouncer

**Your agent says it's done. Bouncer checks the facts.**

[Léelo en castellano](README.es.md)

Because it almost never is. You read the diff, you find the unquoted variable,
you prompt again, it tells you it is done again, and there goes your afternoon.

A better prompt will not fix that, and the model is not being careless. To see
what is actually going on, it helps to know who decides that a task is finished.

## Why your agent thinks it is done

A model does one thing: text goes in, text comes out. It does not open files, it
does not run commands, and it does not remember what it did a minute ago.

So when your agent searches your repository, edits a file and runs the tests,
something else is doing all of that. The model asks for an action, and that
something carries it out. That something is called the harness. With Claude
Code, Claude is the model and Claude Code is the harness.

The harness also decides when to stop. By default it stops when the model says
the work is done, and the model answers from what it meant to do, rather than
from what happened. Nothing has checked the result yet. You are the first thing
that checks, which is why the afternoon goes the way it goes.

Bouncer moves that decision to a command.

## How it works, one piece at a time

Say you asked for a retry helper, and the agent wrote `retry.sh`.

**It starts with one command.** `make verify` runs the linters over your files,
validates your manifests, renders your charts, runs your tests, and exits zero
or it does not. A linter is a program that reads code without running it and
complains about what is broken or risky: `shellcheck` is the one that notices
`echo $name` falls apart the first time `$name` holds a space.

Bouncer wires up eleven of them, and runs only what applies. No Terraform in
your repository means no Terraform checks.

**Someone has to run it.** You will, twice, and then you will forget. So a hook
runs it instead. A hook is a command the agent's runtime fires by itself when
something happens; you never call it. Claude Code offers several events, and
Bouncer uses two of them.

**A hook that only complains is furniture.** What gives a hook teeth is the
number it exits with. Exit 1 is written to a debug log the agent never reads.
Exit 2 is handed to the agent, and on the `Stop` event it blocks the turn
outright. Bouncer uses exit 2.

**So the gate is the `Stop` hook.** It fires when the turn is about to end, runs
`make verify`, and if that fails, the turn does not end. The output lands in the
agent's context, so it reads the failure and fixes it without you typing
anything.

**Waiting for the end is late**, though. The agent can write twenty files before
anything looks at the first one. So the `PostToolUse` hook fires right after
each file is edited or written, lints only that file, and takes under two
seconds. Your `retry.sh` comes back with its unquoted variable while the agent
is still on it.

**And a gate with no way out is a gate you turn off.** A check the agent cannot
satisfy would loop forever, so after three failed attempts in a row Bouncer
releases the turn, says so, and writes the release down.

That is the whole mechanism:

```text
    you: "add the retry logic"
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  the agent works, and every file it touches gets linted     │
│  on the spot. Complaints go straight back to it.            │
└─────────────────────────────────────────────────────────────┘
    │
    ▼
    the agent says it is done
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  make verify: the whole gate                                │
│                                                             │
│  failed ──▶ the turn does not end, the agent fixes and      │
│             tries again (three times, then it lets go)      │
│  passed ──▶ the turn ends                                   │
└─────────────────────────────────────────────────────────────┘
    │
    ▼
    an answer that already passed the gate
```

A bouncer does not argue about whether you are on the list. Being very confident
that you are on the list does not get you in. That is the whole idea.

## What it looks like when it fires

```text
=== make verify FAILED (attempt 1/3): the turn cannot end ===
== static (pre-commit) ==
  pre-commit                   FAIL
      yamllint.................................................................Failed
      - hook id: yamllint
      - exit code: 1

      config.yaml
        2:4       error    syntax error: mapping values are not allowed here (syntax)
```

The agent reads that and fixes the YAML. You never see the round trip.

## Try it

```bash
git clone https://github.com/Emi-Licha/bouncer.git
cd bouncer
make bootstrap
```

`make bootstrap` installs the tools, which takes a few minutes the first time.
The next two commands do not need Claude Code at all.

```bash
make demo      # every fixture in examples/broken must be rejected
make selftest  # everything in examples/valid must pass
```

One shows the gate catching real defects. The other shows it accepting good
work, which is the half nobody tests. In a few seconds you have watched it do
both on your own machine, instead of taking a README's word for it.

Watching it stop an agent comes next, and that needs a restarted session.
[How it works](docs/how-it-works.md) explains why, and how to prove it.

## Install it in your own project

Bouncer is a handful of files, so installing is copying. Run these from the root
of your project.

**1. Check what you would overwrite.**

```bash
ls Makefile .pre-commit-config.yaml .claude/settings.json CLAUDE.md 2>/dev/null
```

Anything listed already exists. Merge those by hand instead of copying over
them; [how it works](docs/how-it-works.md#merging-into-an-existing-project) says
what goes where.

**2. Copy the files.**

```bash
git clone https://github.com/Emi-Licha/bouncer.git /path/to/bouncer
mkdir -p .claude scripts
cp -R /path/to/bouncer/.claude/hooks /path/to/bouncer/.claude/agents .claude/
cp /path/to/bouncer/.claude/settings.json .claude/
cp /path/to/bouncer/scripts/*.sh scripts/
cp /path/to/bouncer/Makefile /path/to/bouncer/.pre-commit-config.yaml .
cp /path/to/bouncer/.yamllint.yml /path/to/bouncer/.markdownlint.yaml .
cp -R /path/to/bouncer/examples .
```

The last line is optional: it brings the fixtures `make demo` and
`make selftest` run against. Without them, both refuse to run rather than pass
having tested nothing.

**3. Keep Bouncer's scratch files out of git.**

```bash
printf '.claude/settings.local.json\n.claude/.skip-verify\n.verify-tmp/\n.bouncer-releases.log\n' >> .gitignore
```

**4. Install the tools, and track the new files.** `pre-commit` only checks
files git knows about.

```bash
make bootstrap
git add .claude scripts examples Makefile .pre-commit-config.yaml \
        .yamllint.yml .markdownlint.yaml .gitignore
```

**5. Tell your agent the rules.** Add this to your `CLAUDE.md`, creating it if
you do not have one:

```markdown
## Definition of Done

Nothing is done until `make verify` passes. If the Stop hook blocks the turn,
fix the cause. Never disable a check, lower a threshold, skip a test, or edit
the Makefile or the hooks to get past it.

Never use `git commit --no-verify`, and never create `.claude/.skip-verify`:
that file is the user's escape hatch.

After committing a milestone, review it with the `reviewer` subagent. Do not
push while it has a critical or high finding open.

When something fails twice, stop and ask instead of trying a third variation.
```

**6. Restart Claude Code, then prove the gate is live.** Hooks are read when a
session starts, so nothing is armed until you restart. Then break something on
purpose and confirm you get stopped. A gate you have never seen block anything
is a gate you do not have, and [how it works](docs/how-it-works.md#the-trap)
gives you the three checks to run.

## The commands

| Command | What it does |
| --- | --- |
| `make verify` | The gate. Everything else exists to run this at the right moment. |
| `make lint` | The fast static half on its own. |
| `make verify-full` | Adds a server-side dry run against a live cluster. |
| `make demo` | Proves the gate still catches things. |
| `make selftest` | Proves the gate still accepts good things. |
| `make releases` | Every time the gate stepped aside, and why. |
| `make doctor` | Which tools you have, and which you are missing. |
| `make bootstrap` | Installs them. |
| `make lang` | Which language Bouncer is speaking. |
| `make clean` | Removes scratch and cache directories. |

## In your language

Bouncer speaks English by default, and so do the reviewer's reports. For
Spanish, either set it for yourself:

```bash
BOUNCER_LANG=es make verify
```

Or for everyone who clones the repository, with a `.bouncer.conf` in the root:

```ini
lang = es
```

The variable wins over the file, so a team default and a personal preference
never have to fight.

## Read on

- **[How it works](docs/how-it-works.md)**: the pieces of a harness and which
  ones Bouncer is, what each file does, the two traps that make a gate look
  real while doing nothing, and why each decision went the way it did.
- **[What was actually run](docs/evidence.md)**: every claim here that was
  tested, how, and what was not tested. Including what Bouncer cannot do.

## Who it is for

- **You use Claude Code every day** and you are tired of the second prompt, the
  one that says "the lint is failing, fix it".
- **You write infrastructure with an agent.** Terraform, Kubernetes manifests,
  Helm charts, Kyverno policies: places where a plausible-looking mistake costs
  more than a failed build. That is the stack Bouncer checks out of the box.
- **Your team wants one Definition of Done** for work done with an agent, and
  the same gate to run for everyone.
- **You are building your own harness**, and want the exit-code semantics and
  the traps written down by someone who hit them.

It is probably not for you if your agent is not Claude Code, since the loop
depends on Claude Code hooks; if your stack is JavaScript, Go, Java or Rust,
which have no linters wired in yet; or if you need it on Windows, or want it to
replace CI. It runs on your machine, and it is tested on macOS.

## License

MIT. See [LICENSE](LICENSE).
