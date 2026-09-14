# Bouncer

**A verification harness for agentic coding.**

[Léelo en castellano](README.es.md)

Bouncer sits at the door of your agent's work. Nothing the agent produces gets
through until it has been checked, and what fails does not end the turn: it
goes back to the agent with the reason.

```text
        ┌───────────┐
        │   Agent   │  writes a file, then says it is done
        └─────┬─────┘
              │
              ▼
        ┌───────────┐
        │  Bouncer  │  runs every check your repository needs
        └─────┬─────┘
              │
      ┌───────┴───────┐
      │               │
    PASS           BOUNCE
      │               │
      ▼               ▼
  the turn ends    the failure goes back to the agent,
                   which fixes it and tries again
                      │
                      ▼
                   three bounces in a row, and Bouncer
                   releases the turn and says so
```

A bouncer does not argue about whether you are on the list. Being very confident
that you are on the list does not get you in. That is the whole idea.

## Why

Your agent says it is done. It almost never is. So you read the diff, you find
the unquoted variable, you prompt again, it tells you it is done again, and
there goes your afternoon.

A better prompt will not fix that, and your agent is not being careless. It
stops when it believes the work is finished, and that belief comes from what it
meant to do, not from anything that looked at what it did. Nothing has run the
linters, validated the manifests or run the tests. You are the first check.

Bouncer puts a check before you. It wraps your agent's work the way a test
harness wraps code under test: it runs the checks, reads the result, and decides
whether the work gets through.

## What it checks

Bouncer checks what the agent left in your repository, not how it behaved along
the way. That is a deliberate scope: an artifact can be checked by a program
that gives the same answer every time, and a program that does is the only thing
worth putting at a door.

- a shell script that breaks the first time a variable holds a space
- YAML that does not parse, or a Kubernetes manifest the cluster would reject
- a Helm chart that does not render, a Kyverno policy whose own test fails
- Terraform that does not validate, or whose generated docs no longer match
- a test suite that fails, or coverage under the floor
- a secret about to be committed

Eleven linters and validators, and it runs only what applies. No Terraform in
your repository means no Terraform checks. What counts as a check is yours to
change: they are ordinary tools, declared in `.pre-commit-config.yaml` and in
`scripts/verify.sh`, not a language Bouncer invented.

## The verdict

One command, `make verify`, produces it. Everything else exists to run that
command at the right moment and to act on the answer.

| Verdict | What happens |
| --- | --- |
| `PASS` | The turn ends. The answer you read has already been through the gate. |
| `BOUNCE` | The turn does not end. The failure goes into the agent's context, and it fixes it without you typing anything. |
| `RELEASE` | Three bounces in a row on the same problem, so Bouncer lets go, says so, and writes it down. |

That third one matters as much as the first two. A check the agent cannot
satisfy would loop forever, and a gate that traps you is a gate you switch off
by lunchtime. Bouncer would rather step aside loudly than hold you hostage
quietly, and `make releases` shows you every time it did.

## What Bouncer is not

It is not an agent, and it does not try to do the work. It does not make your
agent smarter and it does not rewrite your prompts. Your agent still makes every
fix.

It answers one question: did this execution leave the repository in a state we
accept?

## How it gets there

Two hooks, which are commands Claude Code fires by itself. You never call them.

**While the agent works**, `PostToolUse` fires after each file is edited or
written, lints that one file, and takes under two seconds. The complaint reaches
the agent while it is still on that file.

**When the turn is about to end**, `Stop` runs `make verify`, the whole gate, and
that is where the verdict comes from.

What gives a hook teeth is the number it exits with. Exit 1 goes to a debug log
the agent never reads. Exit 2 is handed to the agent, and on `Stop` it blocks
the turn. Bouncer uses exit 2, and
[how it works](docs/how-it-works.md#the-exit-code-is-the-whole-trick) explains
why that one detail is where most hooks quietly fail.

## A bounce, as it actually looks

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

The agent reads that, fixes the YAML, and tries to end the turn again. You never
see the round trip: what reaches you is the answer that got through.

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

- **[How it works](docs/how-it-works.md)**: where Bouncer fits in an agent,
  what each file does, the two traps that make a gate look
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
- **You are building your own verification harness**, and want the exit-code
  semantics and the traps written down by someone who hit them.

It is probably not for you if your agent is not Claude Code, since the loop
depends on Claude Code hooks; if your stack is JavaScript, Go, Java or Rust,
which have no linters wired in yet; or if you need it on Windows, or want it to
replace CI. It runs on your machine, and it is tested on macOS.

## Roadmap

Bouncer checks artifacts. A verification layer for agentic systems could check
more than that, and these are the pieces that do not exist here yet, named so
nobody has to guess:

- **Tool verification.** Whether the right tool was called, with valid
  arguments, and whether an expected step was skipped.
- **Cost and token metrics.** What a turn spent, and a ceiling on it.
- **Execution graphs.** The shape of a run, so a workflow that diverged from the
  expected path can be told apart from one that took a different valid route.
- **Evals.** A stable set of tasks to run before and after changing Bouncer,
  so an improvement can be told from a regression.

None of these are started. The pieces that are built are described in
[how it works](docs/how-it-works.md), and what was actually run to test them is
in [the evidence](docs/evidence.md).

## License

MIT. See [LICENSE](LICENSE).
