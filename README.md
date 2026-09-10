# Claude Code verification harness

**[English](#english)** | **[Español](#español)**

## English

An agent that checks its own work will pass itself. This is a setup where it
cannot: one command decides whether the work is done, and hooks run it whether
the agent feels like it or not.

Tested on macOS. Before trusting any of this, read
[What is verified](#what-is-verified).

### The problem

You end up being the linter. You read the diff, you spot the unquoted variable,
you say something, you wait. Then it happens again on the next file.

A better prompt does not fix this, because the agent is still the one deciding
whether it is finished. What fixes it is a gate the agent cannot open.

### How the loop closes

```text
  you edit a file
        |
        v
  PostToolUse hook  ->  lints just that file
                        exit 2 puts the error into the agent's context,
                        so the next step fixes it without you asking

  the turn tries to end
        |
        v
  Stop hook         ->  runs `make verify`
                        exit 2 means the turn cannot end,
                        and the output becomes the reason why
```

Two exit codes carry most of the design. Getting them wrong is the usual reason
a harness like this quietly does nothing:

| Exit | What actually happens |
| --- | --- |
| `0` | Success. Nothing reaches the agent. |
| `1` | Non-blocking error. It goes to the debug log only, so the agent never sees it. A hook built on exit 1 looks right and does nothing. |
| `2` | On `PostToolUse`, your stderr is shown to the agent as a warning (the edit still stands). On `Stop`, the turn is blocked and your stderr becomes the reason. |

### Quick start

```bash
make bootstrap
```

Now restart your Claude Code session. That step is not optional, and
[the failure that looks like success](#the-failure-that-looks-like-success)
explains why. Then check that the gate really works:

```bash
make demo
```

`make demo` runs the linters against files in `examples/broken/` that are
invalid on purpose. It fails if any of them is *not* rejected. Then the other
half:

```bash
make selftest
```

`make selftest` runs the gate itself over `examples/valid/`, which holds a real
module, chart, policy and manifest, and it has to pass. Between the two you have
watched the gate reject what it should and accept what it should, on your own
machine, without taking either on faith.

### Language

Everything the harness prints is in English by default, and so are the
reviewer's reports. Both can speak Spanish instead.

Just for you, leaving the repository untouched:

```bash
HARNESS_LANG=es make verify
```

For everyone who clones it, commit a `.harness.conf` in the root:

```ini
lang = es
```

The environment variable wins over the file, so a shared default and a personal
preference never have to fight. Any value that is not `es` resolves to English,
which means a typo degrades quietly instead of printing message keys at you.
`make lang` tells you which one is active right now.

Adding a third language means adding one case block to `scripts/messages.sh`.
Keys missing from it fall back to English rather than breaking, so a partial
translation is usable from the first string.

### The pieces

| Path | What it does |
| --- | --- |
| `Makefile` | `verify` is the canonical gate. Also `lint`, `verify-full`, `demo`, `selftest`, `doctor`, `lang`, `bootstrap`. |
| `examples/` | `broken/` must be rejected by `make demo`; `valid/` must be accepted by `make selftest`. |
| `scripts/verify.sh` | The engine. The logic lives here because macOS ships GNU Make 3.81, which has no `.ONESHELL`. |
| `scripts/messages.sh` | Every string the harness prints, in English and Spanish. |
| `.claude/hooks/lint-changed.sh` | `PostToolUse` on `Edit\|Write`. Lints only the file just written, in under two seconds. |
| `.claude/hooks/verify-on-stop.sh` | `Stop`. Runs `make verify` and blocks the turn while it fails. |
| `.claude/agents/reviewer.md` | Reviews finished work with no memory of how it was built. |
| `.pre-commit-config.yaml` | The single definition of every fast static check. |
| `CLAUDE.md` | The rules. Mainly: fix the cause, never disable the check. |

### The failure that looks like success

This is the part worth reading twice.

**Hooks are read when a session starts.** If you write `.claude/settings.json`
in the middle of a session, nothing is armed. Every file is correct, the config
is valid, and no hook runs. A wrong path in that file behaves identically,
because a hook that cannot be found is treated as a non-blocking error.

Both cases leave you believing you have a gate when you have nothing. So the
only honest test is to break something deliberately and confirm you were
stopped:

1. Run `/hooks` and confirm both appear, and which file they came from.
2. Write a file with a real lint error. The error has to come back to you.
3. Break `make verify`, then try to end the turn. You have to be blocked.

If step 3 does not block you, you do not have a gate, whatever the config says.

### Design decisions

**It detects, it does not assume.** `verify` looks at what the repository
actually contains and runs only what applies. Adding Terraform later needs no
edit here.

**Missing content is skipped. A missing tool is not.** No `.tf` files means the
Terraform checks are skipped, and that is honest. But `.tf` files with no
`tflint` installed is a hard failure, because otherwise the gate goes green for
the worst possible reason: nothing is installed to catch anything.

**The coverage floor is 85%, and only for `src/` layouts.** Coverage is measured
against `src/` rather than everything, because a bare `--cov` counts the test
files, which are close to fully covered by definition and lift the total over the
line: 75% source plus 100% tests reports 89%. Where a project has no `src/` to
scope to, the floor is dropped and said so out loud, on the grounds that a
threshold going green for the wrong reason is worse than admitting there is none.

**`pre-commit` is the only place static checks are defined**, and `make verify`
runs it first. Its linters are `repo: local`, so they call the same binaries
`make bootstrap` installs and cannot drift to a different version.

**Untracked files warn, they do not fail.** `pre-commit` only sees tracked
files, so an untracked file skips the static pass entirely. Failing on that
would block you constantly while you work, and a gate people switch off is worth
nothing. The warning keeps the gap visible instead of silent.

**The reviewer is not supposed to write, and mostly cannot.** Its allowlist
withholds `Write` and `Edit`, which takes away the convenient path. It does keep
`Bash`, because a reviewer that cannot check whether a binary exists ends up
inflating severities over guesses, and `Bash` can write files. So the last step
of that prohibition is a rule in its prompt rather than a wall, and you should
know that before pointing it at a repository you care about. It also never sees
the conversation, which is the point: it is not attached to decisions that were
already made.

**The Stop hook gives up after three failures.** A check the agent cannot fix
would otherwise loop forever. The counter resets when it releases, because
without that reset the gate stays open for the rest of the session.

### What is verified

A repository about verification should say what was actually run. On macOS,
end to end, against the real runtime:

- Both hooks registered, and which settings file they came from.
- `PostToolUse` returning a lint error into the agent's context.
- `Stop` blocking a turn while `make verify` was failing.
- The three-strike release, and the counter resetting afterwards.
- `.claude/.skip-verify` closing a turn with the gate still red.
- `make demo` rejecting every fixture.
- Both languages, across `verify`, `demo`, `doctor` and both hooks, including
  the message the Stop hook emits when it releases.
- Against real content: `kubeconform` accepting a valid manifest and rejecting
  an invalid one under `-strict`, its schema cache filling up, `helm template`
  on a stock chart, `terraform init -backend=false` and `validate`, `tflint`,
  `trivy config`, and `mypy --strict`.
- Pathological names: a space, a quote or a newline in a file *or directory*
  name survives detection, validation and reporting without being split. What a
  third-party tool then does with such a name is its own business; `tflint`, for
  one, does not cope.
- `bootstrap` on all three of its branches, and the exit code each returns: a
  complete toolchain, an incomplete one, and no package manager at all.
- `make verify-full` skipping e2e when no cluster answers, plus `help`, `clean`,
  and the unknown-stage error path in both languages.
- `.harness.conf` reaching the hooks and not only `make`, and both hooks falling
  back to English when the catalogue is missing rather than failing.
- `kyverno test` passing on a policy whose test matches, and failing when it
  does not.
- `terraform-docs` on a module that opted into generated docs, both current and
  stale; on a directory that did not opt in, which is left alone; and on a config
  that sets no output file, which is skipped rather than passed.
- The coverage floor rejecting 75% source coverage, accepting full coverage, and
  standing aside for a project that has no `src/` to scope it to.

Everything above except the coverage floor is reproducible: `make selftest` runs
the gate over `examples/valid/` and `make demo` runs it over `examples/broken/`,
so none of it has to be taken on the word of a commit message. The coverage floor
is the exception, because the python stage looks for `src/`, `tests/` and
`pyproject.toml` at the repository root and cannot see a fixture in a
subdirectory.

Not verified:

- **`make verify-full` against a live cluster.** Only the path where nothing
  answers has been seen.
- **The apt/dnf path in `bootstrap.sh`.** Written, never run. Homebrew is the
  tested route, on macOS and Linuxbrew alike.
- **The reviewer reporting in Spanish on request.** The English default has been
  confirmed the interesting way round, by asking in Spanish and getting the
  report in English, so it follows the configuration and not the conversation.
  Pointing `.harness.conf` at Spanish and watching it switch has not been done.
- **The three minute budget** against a repository with real content. On this
  one, which is nearly empty, `verify` takes about two seconds.

### Limits

`terraform init` and the first `kubeconform` run need network access, though
never cloud credentials. The three minute budget assumes warm caches.

And the reviewer is a language model, not a linter. Early on it was close to
useless: ten findings across three runs, three of them real, and twice a
suggested fix that would have been worse than the bug it found. Tightening its
rules, so that it checks claims it can check and never prescribes a remedy it
has not run, changed that: the next review returned four findings, three real
and each reproduced independently before being acted on, plus one observation it
correctly declined to dress up as a defect.

That accuracy has a price. It now runs around fifteen shell commands verifying
its own claims, and a review of a ninety-line diff takes about five and a half
minutes. If that is too slow, `maxTurns` in the agent's frontmatter bounds it
without touching its judgement. Read what it says either way, and reproduce a
finding before acting on it.

### License

MIT. See [LICENSE](LICENSE).

## Español

Un agente que revisa su propio trabajo se aprueba solo. Este es un armado donde
no puede: un comando decide si el trabajo está terminado, y hay hooks que lo
corren tenga ganas o no.

Probado en macOS. Antes de confiar en nada de esto, leé
[Qué está verificado](#qué-está-verificado).

### El problema

El linter terminás siendo vos. Leés el diff, ves la variable sin comillas,
avisás, esperás. Y en el archivo siguiente vuelve a pasar.

Un prompt mejor no lo soluciona, porque el agente sigue siendo el que decide si
terminó. Lo que lo soluciona es un gate que no pueda abrir.

### Cómo cierra el loop

```text
  editás un archivo
        |
        v
  hook PostToolUse  ->  lintea solo ese archivo
                        exit 2 mete el error en el contexto del agente,
                        así el paso siguiente lo arregla sin que se lo pidas

  el turno intenta cerrar
        |
        v
  hook Stop         ->  corre `make verify`
                        exit 2 significa que el turno no puede cerrar,
                        y la salida pasa a ser el motivo
```

Dos exit codes sostienen casi todo el diseño. Equivocarlos es la razón habitual
por la que un armado como este no hace nada sin que te enteres:

| Exit | Qué pasa en realidad |
| --- | --- |
| `0` | Éxito. Al agente no le llega nada. |
| `1` | Error no bloqueante. Va solo al log de debug, así que el agente nunca lo ve. Un hook basado en exit 1 parece correcto y no hace nada. |
| `2` | En `PostToolUse`, tu stderr se le muestra al agente como advertencia (la edición queda igual). En `Stop`, el turno se bloquea y tu stderr pasa a ser el motivo. |

### Arranque rápido

```bash
make bootstrap
```

Ahora reiniciá tu sesión de Claude Code. Ese paso no es opcional, y
[la falla que parece un éxito](#la-falla-que-parece-un-éxito) explica por qué.
Después comprobá que el gate funciona de verdad:

```bash
make demo
```

`make demo` corre los linters contra archivos de `examples/broken/` que son
inválidos a propósito. Falla si alguno *no* es rechazado. Después, la otra mitad:

```bash
make selftest
```

`make selftest` corre el gate mismo sobre `examples/valid/`, que tiene un módulo,
un chart, una policy y un manifiesto de verdad, y tiene que pasar. Entre los dos
ya viste al gate rechazar lo que debe y aceptar lo que debe, en tu propia
máquina, sin creerle nada a nadie.

### Idioma

Todo lo que imprime el arnés está en inglés por defecto, y los informes del
reviewer también. Los dos pueden hablar castellano.

Solo para vos, sin tocar el repositorio:

```bash
HARNESS_LANG=es make verify
```

Para todos los que lo clonen, commiteá un `.harness.conf` en la raíz:

```ini
lang = es
```

La variable de entorno le gana al archivo, así que un default compartido y una
preferencia personal nunca tienen que pelearse. Cualquier valor que no sea `es`
resuelve a inglés, o sea que un error de tipeo degrada en silencio en vez de
imprimirte claves de mensajes. `make lang` te dice cuál está activo ahora.

Agregar un tercer idioma es agregar un bloque `case` a `scripts/messages.sh`.
Las claves que falten caen a inglés en vez de romperse, así que una traducción
parcial ya sirve desde la primera cadena.

### Las piezas

| Ruta | Qué hace |
| --- | --- |
| `Makefile` | `verify` es el gate canónico. También están `lint`, `verify-full`, `demo`, `selftest`, `doctor`, `lang` y `bootstrap`. |
| `examples/` | `broken/` tiene que ser rechazado por `make demo`; `valid/` tiene que ser aceptado por `make selftest`. |
| `scripts/verify.sh` | El motor. La lógica vive acá porque macOS trae GNU Make 3.81, que no tiene `.ONESHELL`. |
| `scripts/messages.sh` | Todas las cadenas que imprime el arnés, en inglés y castellano. |
| `.claude/hooks/lint-changed.sh` | `PostToolUse` con matcher `Edit\|Write`. Lintea solo el archivo recién escrito, en menos de dos segundos. |
| `.claude/hooks/verify-on-stop.sh` | `Stop`. Corre `make verify` y bloquea el turno mientras falle. |
| `.claude/agents/reviewer.md` | Revisa trabajo terminado sin memoria de cómo se construyó. |
| `.pre-commit-config.yaml` | La única definición de los checks estáticos rápidos. |
| `CLAUDE.md` | Las reglas. Sobre todo: arreglá la causa, nunca deshabilites el check. |

### La falla que parece un éxito

Esta es la parte que conviene leer dos veces.

**Los hooks se leen cuando arranca la sesión.** Si escribís
`.claude/settings.json` en el medio de una sesión, no se arma nada. Todos los
archivos están bien, la configuración es válida, y ningún hook corre. Una ruta
mal escrita en ese archivo se comporta igual, porque un hook que no se encuentra
se trata como error no bloqueante.

En los dos casos te quedás creyendo que tenés un gate cuando no tenés nada. Por
eso la única prueba honesta es romper algo a propósito y confirmar que te
frenaron:

1. Corré `/hooks` y confirmá que aparecen los dos, y de qué archivo salieron.
2. Escribí un archivo con un error de lint real. El error te tiene que volver.
3. Rompé `make verify` e intentá cerrar el turno. Te tiene que bloquear.

Si el paso 3 no te bloquea, no tenés gate, diga lo que diga la configuración.

### Decisiones de diseño

**Detecta, no supone.** `verify` mira qué contiene realmente el repositorio y
corre solo lo que aplica. Si mañana agregás Terraform, no hay que tocar nada
acá.

**El contenido que falta se saltea. Una herramienta que falta, no.** Que no haya
archivos `.tf` significa saltear los checks de Terraform, y eso es honesto. Pero
que haya archivos `.tf` sin `tflint` instalado es un fallo duro, porque si no el
gate se pone verde por el peor motivo posible: no hay nada instalado que pueda
atrapar nada.

**El piso de cobertura es 85%, y solo para layouts con `src/`.** La cobertura se
mide contra `src/` y no contra todo, porque un `--cov` pelado cuenta también los
archivos de test, que están casi completamente cubiertos por definición y
empujan el total por encima de la línea: 75% del fuente más 100% de los tests
reporta 89%. Cuando un proyecto no tiene `src/` al que acotarlo, el piso se
abandona diciéndolo en voz alta, porque un umbral que da verde por el motivo
equivocado es peor que admitir que no hay umbral.

**`pre-commit` es el único lugar donde se definen los checks estáticos**, y
`make verify` lo corre primero. Sus linters son `repo: local`, así que llaman a
los mismos binarios que instala `make bootstrap` y no pueden quedar en versiones
distintas.

**Los archivos sin trackear advierten, no fallan.** `pre-commit` solo ve
archivos trackeados, así que uno sin trackear se saltea todo el paso estático.
Fallar por eso te bloquearía todo el tiempo mientras trabajás, y un gate que la
gente apaga no sirve para nada. La advertencia mantiene la grieta a la vista en
vez de silenciosa.

**El reviewer no debería escribir, y en general no puede.** Su allowlist le
niega `Write` y `Edit`, que le saca el camino cómodo. Sí conserva `Bash`, porque
un revisor que no puede comprobar si un binario existe termina inflando
severidades sobre suposiciones, y con `Bash` se pueden escribir archivos. Así
que el último tramo de esa prohibición es una regla de su prompt y no un muro,
y conviene saberlo antes de apuntarlo a un repo que te importa. Tampoco ve la
conversación, y eso es a propósito, porque así no queda apegado a decisiones que
ya se tomaron.

**El hook de Stop se rinde después de tres fallos.** Un check que el agente no
puede arreglar generaría un loop infinito. El contador se resetea cuando libera,
porque sin ese reset el gate queda abierto el resto de la sesión.

### Qué está verificado

Un repositorio que habla de verificación debería decir qué corrió de verdad. En
macOS, punta a punta, contra el runtime real:

- Los dos hooks registrados, y de qué archivo de settings salieron.
- `PostToolUse` devolviendo un error de lint al contexto del agente.
- `Stop` bloqueando un turno mientras `make verify` fallaba.
- La liberación al tercer intento, y el contador reseteándose después.
- `.claude/.skip-verify` cerrando un turno con el gate todavía en rojo.
- `make demo` rechazando todos los fixtures.
- Los dos idiomas, en `verify`, `demo`, `doctor` y los dos hooks, incluido el
  mensaje que emite el hook de Stop cuando libera.
- Contra contenido real: `kubeconform` aceptando un manifiesto válido y
  rechazando uno inválido con `-strict`, su cache de schemas poblándose,
  `helm template` sobre un chart recién creado, `terraform init -backend=false`
  y `validate`, `tflint`, `trivy config`, y `mypy --strict`.
- Nombres patológicos: un espacio, una comilla o un salto de línea en el nombre
  de un archivo *o de un directorio* sobrevive a la detección, la validación y el
  reporte sin partirse. Lo que después haga una herramienta de terceros con ese
  nombre es asunto suyo; `tflint`, por ejemplo, no lo maneja.
- `bootstrap` en sus tres ramas, con el código de salida de cada una: toolchain
  completo, incompleto, y sin ningún gestor de paquetes.
- `make verify-full` salteando e2e cuando no responde ningún cluster, más
  `help`, `clean`, y el camino de error de etapa desconocida en los dos idiomas.
- `.harness.conf` llegando a los hooks y no solo a `make`, y los dos hooks
  cayendo a inglés cuando falta el catálogo en vez de romperse.
- `kyverno test` pasando con una policy cuyo test coincide, y fallando cuando no.
- `terraform-docs` sobre un módulo que optó por docs generadas, al día y
  desactualizado; sobre un directorio que no optó, al que deja en paz; y sobre un
  config que no define archivo de salida, que se saltea en vez de pasar.
- El piso de cobertura rechazando un 75% de cobertura del fuente, aceptando la
  cobertura completa, y haciéndose a un lado en un proyecto sin `src/` al que
  acotarlo.

Todo lo anterior salvo el piso de cobertura es reproducible: `make selftest`
corre el gate sobre `examples/valid/` y `make demo` lo corre sobre
`examples/broken/`, así que nada de esto hay que creérselo por el mensaje de un
commit. El piso de cobertura es la excepción, porque la etapa de python busca
`src/`, `tests/` y `pyproject.toml` en la raíz del repo y no puede ver un fixture
en un subdirectorio.

Sin verificar:

- **`make verify-full` contra un cluster de verdad.** Solo se vio el camino en
  el que no responde ninguno.
- **El camino apt/dnf de `bootstrap.sh`.** Escrito, nunca ejecutado. Homebrew es
  la ruta probada, tanto en macOS como en Linuxbrew.
- **El reviewer reportando en castellano cuando se lo pide.** El default en
  inglés sí quedó confirmado por el lado interesante: se le preguntó en
  castellano y contestó en inglés, o sea que sigue la configuración y no la
  conversación. Falta apuntar `.harness.conf` al castellano y verlo cambiar.
- **El presupuesto de tres minutos** contra un repo con contenido real. En este,
  que está casi vacío, `verify` tarda unos dos segundos.

### Límites

`terraform init` y la primera corrida de `kubeconform` necesitan red, aunque
nunca credenciales de nube. El presupuesto de tres minutos asume caches
calientes.

Y el reviewer es un modelo de lenguaje, no un linter. Al principio era casi
inútil: diez hallazgos en tres corridas, tres reales, y dos veces un arreglo
propuesto que habría sido peor que el problema encontrado. Endurecerle las
reglas, para que compruebe lo que puede comprobar y nunca recete un remedio que
no probó, cambió eso: la revisión siguiente trajo cuatro hallazgos, tres reales
y cada uno reproducido de forma independiente antes de tocar nada, más una
observación que correctamente se negó a disfrazar de defecto.

Esa precisión tiene un precio. Ahora corre unos quince comandos de shell
verificando sus propias afirmaciones, y una revisión de un diff de noventa
líneas tarda unos cinco minutos y medio. Si te resulta lento, `maxTurns` en el
frontmatter del agente lo acota sin tocarle el criterio. Leé lo que dice igual, y
reproducí un hallazgo antes de actuar sobre él.

### Licencia

MIT. Ver [LICENSE](LICENSE).
