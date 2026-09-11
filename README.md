# Bouncer

**[English](#english)** | **[Español](#español)**

## English

**Your agent says it's done. Bouncer checks the facts.**

Because it usually is not.

So you read the diff, you find the unquoted variable, you prompt again, it tells
you it is done again, and there goes your afternoon.

This is not a prompting problem, and a better prompt will not fix it. Nor is it
the model being careless. What is missing is structure: nothing checks the work
between the agent saying "done" and you reading it. Bouncer is that structure, a
harness around your agent. The model still makes every fix. The harness decides
when the work counts as finished.

**Bouncer closes the loop.** The agent acts, a check runs on its own, the failure
goes straight back into the agent's context, and it corrects without being asked.
It cannot end the turn until the check passes.

What you get out of that is accuracy that does not depend on you noticing.

```text
  you: "add the retry logic"
        │
        ▼
┌───────────────── everything below happens without you ─────────────────┐
│   agent edits a file                                                   │
│         │                                                              │
│         ▼                                                              │
│   PostToolUse hook  ──▶  lints that one file, under 2s                 │
│         │                exit 2 drops the complaint straight           │
│         │                into the agent's context                      │
│         ▼                                                              │
│   agent fixes it, unprompted, then tries to end the turn               │
│         │                                                              │
│         ▼                                                              │
│   Stop hook         ──▶  runs `make verify`, the whole gate            │
│         │                exit 2 blocks the turn and hands              │
│         │                back the failure as the reason                │
│         │                                     │                        │
│         │   ◀─────────────────────────────────┘  round again           │
│         │        (three rounds, then it gives up and says so)          │
└────────────────────────────────────────────────────────────────────────┘
        │
        │  make verify passed
        ▼
  an answer you did not have to check
```

A bouncer does not argue about whether you are on the list. Being extremely
confident that you are on the list does not get you in. That is the whole idea.

| Without Bouncer | With Bouncer |
| --- | --- |
| The agent says it is done, and you find out it is not. | It cannot end the turn until `make verify` passes. |
| You are the linter, reading every diff. | The linter's complaint lands in the agent's context on its own. |
| "Please fix the lint errors", prompt after prompt. | It fixes them before you ever see the answer. |
| Checks run when someone remembers to run them. | Checks run on every edit and every turn, whether anyone remembers or not. |
| A green result you have to take on trust. | `make demo` and `make selftest` show it working on your own machine. |

Here is the Stop hook refusing to let a turn end:

```text
=== make verify FAILED (attempt 1/3): the turn cannot end ===
== static (pre-commit) ==
  pre-commit                   FAIL
      yamllint.......................................................Failed
      config.yaml
        2:4  error  syntax error: mapping values are not allowed here
```

And the PostToolUse hook handing back a complaint nobody asked for:

```text
PostToolUse:Edit hook returned blocking error
LINT FAILED: demo.sh
  echo $undefined_target
       ^-------------^ SC2154: undefined_target is referenced but not assigned.
```

### What Bouncer is

**It is a harness, and its shape is a loop.** A harness is the structure you put
around an agent, not the agent itself. It does not make the model smarter and it
does not rewrite your prompts. It changes what the model is allowed to call
finished. The shape is a closed loop: act, check, feed the failure back, correct,
repeat until it passes. The distinctive part is not what gets checked. It is who
decides, and that moves from the agent to a command that does not negotiate.

It is not a library you import, a service you run, a pipeline or a graph, and it
is not prompt engineering. There is no orchestration anywhere in it: two events
and one command, sitting in your repository, changing what your agent is allowed
to do.

### Who it is for

- **You use Claude Code every day** and you are tired of the second prompt, the
  one that says "the lint is failing, fix it". Bouncer makes that prompt
  unnecessary.
- **You write infrastructure with an agent.** Terraform, Kubernetes manifests,
  Helm charts, Kyverno policies: places where a plausible-looking mistake costs
  more than a failed build. That is the stack Bouncer checks out of the box.
- **Your team wants one Definition of Done for AI-assisted changes.** The same
  gate runs for every person and every agent, and the same checks run again at
  `git commit`.
- **You review what an agent produced.** The diff reaches you already linted and
  validated, so review time goes on design instead of unquoted variables.
- **You are building your own harness.** The exit code semantics, the traps and
  the record of what was actually tested are the parts that are hard to find
  written down anywhere else.

It is probably not for you if:

- **Your agent is not Claude Code.** The loop depends on Claude Code hooks.
  `make verify` and `pre-commit` still work anywhere, but nothing stops the turn.
- **Your stack is JavaScript, Go, Java or Rust.** No linters for those are wired
  in yet. Adding one is an entry in `.pre-commit-config.yaml`, but out of the box
  Bouncer would skip your code.
- **You need it on Windows**, or you want it to replace CI. It is tested on
  macOS, and it runs on your machine, not on a server.

### The cast

Five things, in plain language. If you already know what a linter and a hook are,
skip to [Try it](#try-it-in-three-commands).

**The gate** is `make verify`. One command. It exits zero or it does not.
Everything else in Bouncer exists either to run it at the right moment, or to
make its answer worth trusting.

**A linter** is a program that reads code without running it and complains about
what is wrong or risky. `shellcheck` reads a shell script and points out that
`echo $name` breaks the first time a filename contains a space. There is one for
nearly every kind of file, and Bouncer wires up eleven: shell, YAML, Markdown,
Dockerfiles, GitHub Actions workflows, Python, Terraform, Kubernetes manifests,
Helm charts, Kyverno policies, and a scanner that hunts for leaked secrets.

**A hook** is a command the agent's runtime runs by itself when something
happens. You never call it. It fires. Claude Code offers several events; Bouncer
uses two. `PostToolUse` fires right after a file is written, and lints just that
file. `Stop` fires when the turn is about to end, and runs the gate. The runtime
hands the hook some JSON on standard input, and then reads the hook's **exit
code** to decide what happens next. That exit code is where all the leverage
lives, and where nearly everyone gets it wrong:

| The hook exits | What the runtime does |
| --- | --- |
| `0` | Fine, carry on. The agent is told nothing. |
| `1` | Treats it as a non-blocking error and writes it to the debug log. **The agent never sees it.** |
| `2` | Reads your stderr and puts it in front of the agent. On `Stop`, the turn is blocked outright. |

Build a hook on exit 1 and it will look correct forever while achieving
absolutely nothing. Bouncer uses exit 2 on both.

**`pre-commit`** is an off-the-shelf tool that runs a list of checks over your
files. Bouncer uses it as the single place the fast checks are defined, so
`make verify` and your git commit can never disagree about what "clean" means.
Those linters are declared `repo: local`, meaning they call the same binaries
`make bootstrap` installed, so they cannot quietly drift to a different version.

**The reviewer** is a second agent that reads the finished diff with no memory of
the conversation that produced it. It cannot see how anyone talked themselves
into a decision, which is exactly the point. It reports. It does not fix.

And **`CLAUDE.md`** holds the rules your agent reads at the start of every
session. Mostly one rule: fix the cause, never disable the check.

### Try it in three commands

```bash
make bootstrap
```

Then restart your Claude Code session. That step is not optional, and
[the trap](#the-trap) explains why.

```bash
make demo
```

Runs the linters over `examples/broken/`, which is invalid on purpose, and fails
if anything is *not* rejected.

```bash
make selftest
```

Runs the whole gate over `examples/valid/`, which holds a real Terraform module,
Helm chart, Kyverno policy and Kubernetes manifest, and has to pass.

Between the two you have watched it reject what it should and accept what it
should, on your own machine, in about ten seconds. Nothing here asks to be taken
on faith.

### Install it in your own project

"Try it" runs inside this repository. To put Bouncer in front of your own agent,
copy it into your project. It is a handful of files, so installing is copying.

**1. Check for files you would overwrite.**

```bash
ls Makefile .pre-commit-config.yaml .claude/settings.json CLAUDE.md
```

If any of those already exist, do not copy over them. Merge them by hand, as
described at the end of step 5.

**2. Copy the files.** From a clone of this repository, shown here as
`/path/to/bouncer`, standing in the root of your project:

```bash
mkdir -p .claude scripts
cp -R /path/to/bouncer/.claude/hooks /path/to/bouncer/.claude/agents .claude/
cp /path/to/bouncer/.claude/settings.json .claude/
cp /path/to/bouncer/scripts/*.sh scripts/
cp /path/to/bouncer/Makefile /path/to/bouncer/.pre-commit-config.yaml .
cp /path/to/bouncer/.yamllint.yml /path/to/bouncer/.markdownlint.yaml .
```

If you also want `make demo` and `make selftest`, copy the fixtures they run
against. Without them both commands refuse to run rather than pass on nothing.

```bash
cp -R /path/to/bouncer/examples .
```

**3. Keep Bouncer's scratch files out of git.**

```bash
printf '.claude/settings.local.json\n.claude/.skip-verify\n.verify-tmp/\n' >> .gitignore
```

**4. Install the tools and the git hook, then track the new files.** `pre-commit`
only checks files git is tracking.

```bash
make bootstrap
git add .claude scripts Makefile .pre-commit-config.yaml .yamllint.yml .markdownlint.yaml .gitignore
```

**5. Tell your agent the rules.** Add this to your `CLAUDE.md`, creating it if it
does not exist:

```markdown
## Definition of Done

Nothing is done until `make verify` passes. If the Stop hook blocks the turn,
fix the cause. Never disable a check, lower a threshold, skip a test, or edit
the Makefile or the hooks to get past it.

Never use `git commit --no-verify`, and never create `.claude/.skip-verify`:
that file is the user's escape hatch.

When something fails twice, stop and ask instead of trying a third variation.
```

If step 1 found existing files, merge instead of copying:

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
| `make verify` | The gate. Everything else is built around this one command. |
| `make lint` | The fast half on its own. |
| `make verify-full` | Adds a server-side dry run against a live cluster. |
| `make demo` | Proves the gate still catches things. |
| `make selftest` | Proves the gate still accepts good things. |
| `make doctor` | Which tools you have and which you are missing. |
| `make bootstrap` | Installs them. |

Bouncer works out what your repository actually contains and runs only what
applies. Add Terraform next month and nothing here needs editing.

Seven files, and none of them is clever:

| Path | What it is |
| --- | --- |
| `Makefile` | The commands above. |
| `scripts/verify.sh` | The engine. It lives here because macOS ships GNU Make 3.81, which has no `.ONESHELL`. |
| `scripts/messages.sh` | Every string it prints, in English and Spanish. |
| `.claude/hooks/` | The two hooks. |
| `.claude/agents/reviewer.md` | The reviewer's instructions and its tool permissions. |
| `.pre-commit-config.yaml` | The single definition of every fast static check. |
| `CLAUDE.md` | The rules. |

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
block in `scripts/messages.sh`, and missing keys fall back to English, so a half
finished translation still works.

### Design notes

**Missing content is skipped. A missing tool is not.** No `.tf` files means the
Terraform checks are skipped, which is honest. But `.tf` files with no `tflint`
installed is a hard failure, because otherwise the gate goes green for the worst
possible reason: nothing is installed to catch anything.

**`kubeconform ok` does not mean every manifest was checked.**
`-ignore-missing-schemas` is what lets a custom resource through, and it is also
how a run reports success having validated a fraction of what it read. The stage
prints the skipped count, so a green line is not mistaken for more coverage than
it is.

**The coverage floor is 85%, and only for `src/` layouts.** A bare `--cov` counts
the test files, which are close to fully covered by definition and drag the total
over the line: 75% source plus 100% tests reports 89%. Without a `src/` to scope
to, the floor is dropped out loud, because a threshold that goes green for the
wrong reason is worse than no threshold.

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
wall, and you should know that before pointing it at a repository you care about.

### What has actually been run

A repository about verification should say what was tested rather than ask to be
believed. All of this was run on macOS, end to end, against the real runtime:

- Both hooks registered, and which settings file they came from.
- `PostToolUse` returning a lint error into the agent's context.
- `Stop` blocking a turn, the three-strike release, and the counter resetting.
- `.claude/.skip-verify` closing a turn with the gate still red.
- Real content: `kubeconform` accepting a good manifest and rejecting a bad one,
  `helm template` on a chart, `kyverno test` both ways, `terraform validate`,
  `tflint`, `trivy`, `terraform-docs` on a current and on a stale module, and the
  coverage floor rejecting 75% while accepting 100%.
- `make verify-full` against kind on colima. A ConfigMap named `Nombre_Invalido`
  is `Valid: 1` to kubeconform, whose schema does not constrain name format, and
  the API server rejects it for not being an RFC 1123 subdomain. That gap is why
  the e2e stage exists separately.
- Names holding a space, a quote or a newline, in files and directories alike.
- `bootstrap` on all three of its branches, and the exit code each returns.
- Both languages everywhere, the reviewer included: asked in Spanish with the
  English default in place, it answered in English.
- Installing into an empty project by following the install steps above to
  the letter: `make verify` green on clean content and red on a broken script,
  both hooks exiting 2, and `make demo` and `make selftest` refusing to run when
  the fixtures were not copied.

Everything except the coverage floor is reproducible with `make demo` and
`make selftest`. The floor is the exception, because the Python stage looks for
`src/`, `tests/` and `pyproject.toml` at the repository root and cannot see a
fixture in a subdirectory.

Not run: the apt/dnf path in `bootstrap.sh`, which is written but never executed,
and the three minute budget against a repository with real content. Here `verify`
takes about two seconds and `selftest` about six.

### Limits

`terraform init` and the first `kubeconform` run need the network, though never
cloud credentials.

The reviewer is a language model, not a linter. Early on it was close to useless:
ten findings across three runs, three of them real, and twice a suggested fix
that would have been worse than the bug. Tightening its rules, so that it checks
what it can check and never prescribes a remedy it has not run, changed that. It
now costs about five and a half minutes on a ninety-line diff, most of that spent
verifying its own claims. `maxTurns` bounds it if that is too slow. Reproduce a
finding before acting on it, either way.

### License

MIT. See [LICENSE](LICENSE).

## Español

**Your agent says it's done. Bouncer checks the facts.**

*Tu agente dice que está listo. Bouncer chequea los factos.*

Porque casi nunca lo está.

Entonces leés el diff, encontrás la variable sin comillas, prompteás de nuevo, te
vuelve a decir que está listo, y ahí se te fue la tarde.

Esto no es un problema de prompts, y promptear mejor no lo arregla. Tampoco es
que el modelo sea descuidado. Lo que falta es estructura: nada chequea el trabajo
entre que el agente dice "listo" y vos lo leés. Bouncer es esa estructura, un
harness alrededor de tu agente. Los arreglos los sigue haciendo el modelo. El
harness decide cuándo el trabajo cuenta como terminado.

**Bouncer cierra el loop.** El agente actúa, un chequeo corre solo, la falla
vuelve derecho a su contexto, y corrige sin que se lo pidas. Y no puede terminar
el turno, o sea devolverte el control, hasta que el chequeo pase.

Lo que ganás con eso es precisión que no depende de que vos te des cuenta.

```text
  vos: "agregá la lógica de reintento"
        │
        ▼
┌──────────────────── todo lo de abajo pasa sin vos ─────────────────────┐
│   el agente edita un archivo                                           │
│         │                                                              │
│         ▼                                                              │
│   hook PostToolUse  ──▶  lintea ese archivo, en menos de 2s            │
│         │                 exit 2 le mete la queja derecho              │
│         │                 en el contexto al agente                     │
│         ▼                                                              │
│   lo arregla solo, y recién ahí intenta terminar el turno              │
│         │                                                              │
│         ▼                                                              │
│   hook Stop         ──▶  corre `make verify`, el gate entero           │
│         │                 exit 2 le frena el turno y le                │
│         │                 devuelve la falla como motivo                │
│         │                                      │                       │
│         │   ◀──────────────────────────────────┘  otra vuelta          │
│         │       (tres vueltas, después se rinde y lo dice)             │
└────────────────────────────────────────────────────────────────────────┘
        │
        │  make verify pasó
        ▼
  una respuesta que no tuviste que revisar
```

Un patovica no discute si estás en la lista. Estar muy convencido de que estás en
la lista no te hace entrar. Esa es toda la idea.

| Sin Bouncer | Con Bouncer |
| --- | --- |
| El agente dice que está listo y descubrís que no. | No puede terminar el turno hasta que `make verify` pase. |
| Vos sos el linter, leyendo cada diff. | La queja del linter le cae sola en el contexto al agente. |
| "Arreglá los errores de lint", prompt tras prompt. | Los arregla antes de que veas la respuesta. |
| Los checks corren cuando alguien se acuerda de correrlos. | Corren en cada edición y en cada turno, se acuerde alguien o no. |
| Un verde que te tenés que creer. | `make demo` y `make selftest` te lo muestran andando en tu máquina. |

Así se ve el hook de Stop negándose a dejar terminar un turno:

```text
=== make verify FALLÓ (intento 1/3): no se puede terminar el turno ===
== static (pre-commit) ==
  pre-commit                   FAIL
      yamllint.......................................................Failed
      config.yaml
        2:4  error  syntax error: mapping values are not allowed here
```

Y el hook de PostToolUse devolviendo una queja que nadie pidió:

```text
PostToolUse:Edit hook returned blocking error
LINT FALLÓ: demo.sh
  echo $undefined_target
       ^-------------^ SC2154: undefined_target is referenced but not assigned.
```

### Qué es Bouncer

**Es un harness, y tiene forma de loop.** Un harness es la estructura que ponés
alrededor de un agente, no el agente en sí. No hace más inteligente al modelo ni
te reescribe los prompts. Cambia lo que el modelo tiene permitido dar por
terminado. La forma es un loop cerrado: actuar, chequear, devolver la falla,
corregir, repetir hasta que pase. Lo distintivo no es qué se chequea. Es quién
decide, y eso pasa del agente a un comando que no negocia.

No es una librería que importás, ni un servicio que corrés, ni un pipeline, ni un
graph, y tampoco es ingeniería de prompts. No hay orquestación en ningún lado: dos
eventos y un comando, viviendo en tu repo, cambiando lo que tu agente tiene
permitido hacer.

### A quién le sirve

- **Usás Claude Code todos los días** y te cansaste del segundo prompt, el de
  "está fallando el lint, arreglalo". Bouncer hace que ese prompt sobre.
- **Escribís infraestructura con un agente.** Terraform, manifiestos de
  Kubernetes, charts de Helm, policies de Kyverno: lugares donde un error que
  parece razonable sale más caro que un build roto. Es el stack que Bouncer
  chequea de fábrica.
- **Tu equipo quiere una sola definición de terminado para cambios hechos con
  IA.** El mismo gate corre para cada persona y cada agente, y los mismos checks
  vuelven a correr en el `git commit`.
- **Revisás lo que produce un agente.** El diff te llega ya linteado y validado,
  así que el tiempo de review se va en diseño y no en variables sin comillas.
- **Estás armando tu propio harness.** La semántica de los exit codes, las
  trampas y el registro de qué se probó de verdad son justo lo que cuesta
  encontrar escrito en otro lado.

Probablemente no es para vos si:

- **Tu agente no es Claude Code.** El loop depende de los hooks de Claude Code.
  `make verify` y `pre-commit` andan en cualquier lado, pero nada frena el turno.
- **Tu stack es JavaScript, Go, Java o Rust.** Todavía no hay linters conectados
  para esos. Agregar uno es una entrada en `.pre-commit-config.yaml`, pero tal
  como viene Bouncer se saltearía tu código.
- **Lo necesitás en Windows**, o querés que reemplace a tu CI. Está probado en
  macOS y corre en tu máquina, no en un servidor.

### El elenco

Cinco cosas, en criollo. Si ya sabés qué es un linter y qué es un hook, saltá a
[Probalo](#probalo-en-tres-comandos).

**El gate** es `make verify`. Un comando. Sale con cero o no sale con cero. Todo
lo demás en Bouncer existe para correrlo en el momento justo, o para que su
respuesta valga algo.

**Un linter** es un programa que lee código sin ejecutarlo y se queja de lo que
está mal o es riesgoso. `shellcheck` lee un script de shell y te marca que
`echo $nombre` se rompe la primera vez que un archivo tenga un espacio en el
nombre. Hay uno para casi cada tipo de archivo, y Bouncer conecta once: shell,
YAML, Markdown, Dockerfiles, workflows de GitHub Actions, Python, Terraform,
manifiestos de Kubernetes, charts de Helm, policies de Kyverno, y un escáner que
busca secretos filtrados.

**Un hook** es un comando que el runtime del agente corre por su cuenta cuando
pasa algo. Vos nunca lo llamás. Se dispara. Claude Code ofrece varios eventos;
Bouncer usa dos. `PostToolUse` se dispara justo después de que se escribe un
archivo, y lintea solo ese archivo. `Stop` se dispara cuando el turno está por
terminar, y corre el gate. El runtime le pasa al hook un JSON por entrada estándar,
y después lee el **código de salida** del hook para decidir qué hacer. Ese código
de salida es donde está toda la palanca, y donde casi todo el mundo se equivoca:

| El hook sale con | Qué hace el runtime |
| --- | --- |
| `0` | Todo bien, seguí. Al agente no se le dice nada. |
| `1` | Lo toma como error no bloqueante y lo escribe en el log de debug. **El agente nunca lo ve.** |
| `2` | Lee tu stderr y se lo pone adelante al agente. En `Stop`, además le frena el turno. |

Armá un hook sobre exit 1 y va a parecer correcto para siempre sin lograr
absolutamente nada. Bouncer usa exit 2 en los dos.

**`pre-commit`** es una herramienta ya hecha que corre una lista de chequeos
sobre tus archivos. Bouncer la usa como el único lugar donde se definen los
checks rápidos, así `make verify` y tu commit de git nunca pueden estar en
desacuerdo sobre qué significa "limpio". Esos linters están declarados como
`repo: local`, o sea que llaman a los mismos binarios que instaló
`make bootstrap`, así que no pueden derivar en silencio a otra versión.

**El reviewer** es un segundo agente que lee el diff terminado sin memoria de la
conversación que lo produjo. No puede ver cómo alguien se convenció a sí mismo de
una decisión, que es exactamente el punto. Reporta. No arregla.

Y **`CLAUDE.md`** tiene las reglas que tu agente lee al empezar cada sesión.
Básicamente una: arreglá la causa, nunca deshabilites el check.

### Probalo en tres comandos

```bash
make bootstrap
```

Después reiniciá tu sesión de Claude Code. Ese paso no es opcional, y
[la trampa](#la-trampa) explica por qué.

```bash
make demo
```

Corre los linters sobre `examples/broken/`, que es inválido a propósito, y falla
si algo *no* es rechazado.

```bash
make selftest
```

Corre el gate entero sobre `examples/valid/`, que tiene un módulo de Terraform,
un chart de Helm, una policy de Kyverno y un manifiesto de Kubernetes de verdad,
y tiene que pasar.

Entre los dos ya lo viste rechazar lo que debe y aceptar lo que debe, en tu
propia máquina, en unos diez segundos. Acá no hay nada que tengas que creer.

### Instalalo en tu proyecto

"Probalo" corre adentro de este repositorio. Para ponerle Bouncer adelante a tu
propio agente, copialo a tu proyecto. Son un puñado de archivos, así que
instalarlo es copiarlos.

**1. Fijate si vas a pisar algún archivo.**

```bash
ls Makefile .pre-commit-config.yaml .claude/settings.json CLAUDE.md
```

Si alguno ya existe, no lo sobreescribas. Mergealo a mano, como se explica al
final del paso 5.

**2. Copiá los archivos.** Desde un clon de este repositorio, que abajo aparece
como `/ruta/a/bouncer`, parado en la raíz de tu proyecto:

```bash
mkdir -p .claude scripts
cp -R /ruta/a/bouncer/.claude/hooks /ruta/a/bouncer/.claude/agents .claude/
cp /ruta/a/bouncer/.claude/settings.json .claude/
cp /ruta/a/bouncer/scripts/*.sh scripts/
cp /ruta/a/bouncer/Makefile /ruta/a/bouncer/.pre-commit-config.yaml .
cp /ruta/a/bouncer/.yamllint.yml /ruta/a/bouncer/.markdownlint.yaml .
```

Si además querés `make demo` y `make selftest`, copiá los fixtures contra los que
corren. Sin ellos, los dos comandos se niegan a correr en vez de pasar sin haber
probado nada.

```bash
cp -R /ruta/a/bouncer/examples .
```

**3. Dejá los archivos temporales de Bouncer fuera de git.**

```bash
printf '.claude/settings.local.json\n.claude/.skip-verify\n.verify-tmp/\n' >> .gitignore
```

**4. Instalá las herramientas y el hook de git, y trackeá los archivos nuevos.**
`pre-commit` solo revisa lo que git está trackeando.

```bash
make bootstrap
git add .claude scripts Makefile .pre-commit-config.yaml .yamllint.yml .markdownlint.yaml .gitignore
```

**5. Contale las reglas a tu agente.** Agregá esto a tu `CLAUDE.md`, y crealo si
no existe:

```markdown
## Definition of Done

Nothing is done until `make verify` passes. If the Stop hook blocks the turn,
fix the cause. Never disable a check, lower a threshold, skip a test, or edit
the Makefile or the hooks to get past it.

Never use `git commit --no-verify`, and never create `.claude/.skip-verify`:
that file is the user's escape hatch.

When something fails twice, stop and ask instead of trying a third variation.
```

Si en el paso 1 encontraste archivos existentes, mergealos en vez de copiar:

- `.claude/settings.json`: copiá el bloque `hooks` del de Bouncer al tuyo.
- `Makefile`: copiá los targets que quieras. `verify` es obligatorio, porque es
  el que llama el hook de Stop.
- `.pre-commit-config.yaml`: sumá las entradas de `repos` de Bouncer a las tuyas.
- `CLAUDE.md`: agregá el bloque de arriba al final.

**6. Reiniciá Claude Code y comprobá que el gate está vivo.** Los hooks se leen
al arrancar la sesión, así que nada queda armado hasta que reinicies. Después
corré los tres chequeos de [la trampa](#la-trampa). No te los saltees: un gate
que nunca viste bloquear nada es un gate que no tenés.

### Qué te llevás

| Comando | Qué hace |
| --- | --- |
| `make verify` | El gate. Todo lo demás está construido alrededor de este comando. |
| `make lint` | Solo la mitad rápida. |
| `make verify-full` | Agrega un dry run server-side contra un cluster real. |
| `make demo` | Prueba que el gate sigue atrapando cosas. |
| `make selftest` | Prueba que el gate sigue aceptando lo bueno. |
| `make doctor` | Qué herramientas tenés y cuáles te faltan. |
| `make bootstrap` | Las instala. |

Bouncer se fija qué contiene realmente tu repo y corre solo lo que aplica. Si el
mes que viene agregás Terraform, no hay que tocar nada acá.

Siete archivos, y ninguno es ingenioso:

| Ruta | Qué es |
| --- | --- |
| `Makefile` | Los comandos de arriba. |
| `scripts/verify.sh` | El motor. Vive acá porque macOS trae GNU Make 3.81, que no tiene `.ONESHELL`. |
| `scripts/messages.sh` | Todas las cadenas que imprime, en inglés y castellano. |
| `.claude/hooks/` | Los dos hooks. |
| `.claude/agents/reviewer.md` | Las instrucciones del reviewer y sus permisos de herramientas. |
| `.pre-commit-config.yaml` | La única definición de los checks estáticos rápidos. |
| `CLAUDE.md` | Las reglas. |

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

### Decisiones de diseño

**El contenido que falta se saltea. Una herramienta que falta, no.** Que no haya
archivos `.tf` significa saltear los checks de Terraform, y eso es honesto. Pero
que haya `.tf` sin `tflint` instalado es fallo duro, porque si no el gate se pone
verde por el peor motivo posible: no hay nada instalado que pueda atrapar nada.

**Que diga `kubeconform ok` no significa que se hayan chequeado todos los
manifiestos.** `-ignore-missing-schemas` es lo que deja pasar un recurso
personalizado, y también es la forma en que una corrida reporta éxito habiendo
validado una fracción de lo que leyó. La etapa imprime cuántos salteó, para que
una línea verde no se confunda con más cobertura de la que es.

**El piso de cobertura es 85%, y solo para layouts con `src/`.** Un `--cov`
pelado cuenta los archivos de test, que están casi completamente cubiertos por
definición y empujan el total por encima de la línea: 75% del fuente más 100% de
tests reporta 89%. Sin un `src/` al que acotarlo, el piso se abandona en voz
alta, porque un umbral que da verde por el motivo equivocado es peor que no tener
umbral.

**Los archivos sin trackear advierten, no fallan.** `pre-commit` solo ve archivos
que git está trackeando, así que uno recién creado se saltea el paso estático
entero. Fallar por eso te bloquearía todo el día, y un gate que la gente apaga no
sirve para nada. La advertencia mantiene la grieta a la vista en vez de
silenciosa.

**El hook de Stop se rinde a los tres intentos.** Un check que el agente no puede
arreglar generaría un loop infinito. El contador se resetea al liberar, porque
sin eso el gate queda abierto el resto de la sesión.

**El reviewer no debería escribir, y en general no puede.** Tiene `Write` y
`Edit` negados. Conserva `Bash`, porque un revisor que no puede comprobar si un
binario existe infla severidades sobre suposiciones, y con `Bash` se pueden
escribir archivos. El último tramo de esa prohibición es una regla de su prompt y
no un muro, y conviene saberlo antes de apuntarlo a un repo que te importa.

### Qué se corrió de verdad

Un repositorio que habla de verificación debería decir qué probó en vez de pedir
que le crean. Todo esto se corrió en macOS, punta a punta, contra el runtime
real:

- Los dos hooks registrados, y de qué archivo de settings salieron.
- `PostToolUse` devolviendo un error de lint al contexto del agente.
- `Stop` bloqueando un turno, la liberación al tercer intento, y el contador
  reseteándose.
- `.claude/.skip-verify` dejando terminar un turno con el gate todavía en rojo.
- Contenido real: `kubeconform` aceptando un manifiesto bueno y rechazando uno
  malo, `helm template` sobre un chart, `kyverno test` en los dos sentidos,
  `terraform validate`, `tflint`, `trivy`, `terraform-docs` sobre un módulo al
  día y sobre uno desactualizado, y el piso de cobertura rechazando 75% y
  aceptando 100%.
- `make verify-full` contra kind sobre colima. Un ConfigMap llamado
  `Nombre_Invalido` es `Valid: 1` para kubeconform, cuyo schema no restringe el
  formato del nombre, y el API server lo rechaza por no ser un subdominio RFC
  1123. Esa brecha es por lo que la etapa e2e existe aparte.
- Nombres con espacio, comilla o salto de línea, tanto en archivos como en
  directorios.
- `bootstrap` en sus tres ramas, con el código de salida de cada una.
- Los dos idiomas en todos lados, incluido el reviewer: preguntado en castellano
  y con el default en inglés puesto, contestó en inglés.
- Instalarlo en un proyecto vacío siguiendo al pie de la letra los pasos de
  instalación de arriba: `make verify` en verde con contenido limpio y en rojo
  con un script roto, los dos hooks saliendo con 2, y `make demo` y
  `make selftest` negándose a correr cuando no se copiaron los fixtures.

Todo salvo el piso de cobertura es reproducible con `make demo` y
`make selftest`. El piso es la excepción, porque la etapa de Python busca `src/`,
`tests/` y `pyproject.toml` en la raíz del repo y no puede ver un fixture en un
subdirectorio.

Sin correr: el camino apt/dnf de `bootstrap.sh`, que está escrito pero nunca se
ejecutó, y el presupuesto de tres minutos contra un repo con contenido real. Acá
`verify` tarda unos dos segundos y `selftest` unos seis.

### Límites

`terraform init` y la primera corrida de `kubeconform` necesitan red, aunque
nunca credenciales de nube.

El reviewer es un modelo de lenguaje, no un linter. Al principio era casi inútil:
diez hallazgos en tres corridas, tres reales, y dos veces un arreglo propuesto
que habría sido peor que el problema. Endurecerle las reglas, para que compruebe
lo que puede comprobar y nunca recete un remedio que no probó, cambió eso. Ahora
cuesta unos cinco minutos y medio sobre un diff de noventa líneas, la mayor parte
verificando sus propias afirmaciones. `maxTurns` lo acota si te resulta lento.
Reproducí un hallazgo antes de actuar sobre él, en cualquier caso.

### Licencia

MIT. Ver [LICENSE](LICENSE).
