# Claude Code verification harness

**[English](#english)** | **[Español](#español)**

## English

Your coding agent decides when it is finished. This takes that decision away
from it.

One command says whether the work passes. Two hooks run that command whether the
agent feels like it or not. If it does not pass, the turn does not end.

```text
=== make verify FAILED (attempt 1/3): the turn cannot end ===
== static (pre-commit) ==
  pre-commit                   FAIL
      yamllint.......................................................Failed
      config.yaml
        2:4  error  syntax error: mapping values are not allowed here
```

That is an agent stopped mid-sentence. It cannot answer you until the repository
is clean again.

On the way in, the same idea at a smaller scale. Edit a file and the linter comes
back on its own, without you asking:

```text
PostToolUse:Edit hook returned blocking error
LINT FAILED: demo.sh
  echo $undefined_target
       ^-------------^ SC2154: undefined_target is referenced but not assigned.
```

You stop being the linter.

### Try it in three commands

```bash
make bootstrap
```

Then restart your Claude Code session. That step is not optional, and
[the part everyone gets wrong](#the-part-everyone-gets-wrong) explains why.

```bash
make demo
```

Runs the gate over `examples/broken/`, which is invalid on purpose, and fails if
anything is *not* rejected.

```bash
make selftest
```

Runs the gate over `examples/valid/`, which holds a real module, chart, policy
and manifest, and has to pass.

Between the two you have watched it reject what it should and accept what it
should, on your own machine, in about ten seconds. Nothing here asks to be taken
on faith.

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

It works out what your repository actually contains and runs only what applies:
Kubernetes manifests, Helm charts, Kyverno policies, Terraform, Python, shell,
Dockerfiles, GitHub Actions, Markdown, YAML, and a secret scan. Add Terraform
next month and nothing here needs editing.

### How it works

```text
  you edit a file
        |
        v
  PostToolUse hook  ->  lints that one file, in under two seconds
                        exit 2 puts the error in the agent's context

  the turn tries to end
        |
        v
  Stop hook         ->  runs `make verify`
                        exit 2 means the turn cannot end
```

Seven pieces, and none of them is clever:

| Path | What it is |
| --- | --- |
| `Makefile` | The commands above. |
| `scripts/verify.sh` | The engine. It lives here because macOS ships GNU Make 3.81, which has no `.ONESHELL`. |
| `scripts/messages.sh` | Every string it prints, in English and Spanish. |
| `.claude/hooks/` | The two hooks. |
| `.claude/agents/reviewer.md` | A reviewer that reads your diff with no memory of how it was written. |
| `.pre-commit-config.yaml` | The single definition of every fast static check. |
| `CLAUDE.md` | The rules. Mainly: fix the cause, never disable the check. |

### The part everyone gets wrong

Two ways this looks like it is working while doing nothing at all.

**Exit 1 is not exit 2.** A hook that exits 1 reports a non-blocking error that
goes to the debug log, and the agent never sees it. Only exit 2 puts your stderr
in front of the model. Build a hook on exit 1 and it will look correct forever
while achieving nothing.

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

Everything it prints, and the reviewer's reports, are in English by default. For
Spanish, either just for you:

```bash
HARNESS_LANG=es make verify
```

or for everyone who clones it, with a `.harness.conf` in the root:

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
`-ignore-missing-schemas` is what lets a CRD through, and it is also how a run
reports success having validated a fraction of what it read. The stage prints the
skipped count, so a green line is not mistaken for more coverage than it is.

**The coverage floor is 85%, and only for `src/` layouts.** A bare `--cov` counts
the test files, which are close to fully covered by definition and drag the total
over the line: 75% source plus 100% tests reports 89%. Without a `src/` to scope
to, the floor is dropped out loud, because a threshold that goes green for the
wrong reason is worse than no threshold.

**Untracked files warn, they do not fail.** `pre-commit` only sees tracked files,
so an untracked one skips the static pass. Failing on that would block you all
day, and a gate people switch off is worth nothing. The warning keeps the hole
visible instead of silent.

**The Stop hook gives up after three tries.** A check the agent cannot fix would
otherwise loop forever. The counter resets on release, because without that the
gate stays open for the rest of the session.

**The reviewer is not supposed to write, and mostly cannot.** `Write` and `Edit`
are withheld. It keeps `Bash`, because a reviewer that cannot check whether a
binary exists inflates severities over guesses, and `Bash` can write files. The
last step of that prohibition is a rule in its prompt rather than a wall, and you
should know that before pointing it at a repository you care about.

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

Tu agente decide cuándo terminó. Esto le saca esa decisión.

Un comando dice si el trabajo pasa. Dos hooks lo corren tenga ganas o no. Si no
pasa, el turno no cierra.

```text
=== make verify FALLÓ (intento 1/3): el turno no puede cerrar ===
== static (pre-commit) ==
  pre-commit                   FAIL
      yamllint.......................................................Failed
      config.yaml
        2:4  error  syntax error: mapping values are not allowed here
```

Eso es un agente frenado a mitad de la frase. No puede contestarte hasta que el
repo vuelva a estar limpio.

En la entrada, la misma idea en chico. Editás un archivo y el linter te vuelve
solo, sin que preguntes:

```text
PostToolUse:Edit hook returned blocking error
LINT FALLÓ: demo.sh
  echo $undefined_target
       ^-------------^ SC2154: undefined_target is referenced but not assigned.
```

Dejás de ser vos el linter.

### Probalo en tres comandos

```bash
make bootstrap
```

Después reiniciá tu sesión de Claude Code. Ese paso no es opcional, y
[la parte que todos hacen mal](#la-parte-que-todos-hacen-mal) explica por qué.

```bash
make demo
```

Corre el gate sobre `examples/broken/`, que es inválido a propósito, y falla si
algo *no* es rechazado.

```bash
make selftest
```

Corre el gate sobre `examples/valid/`, que tiene un módulo, un chart, una policy
y un manifiesto de verdad, y tiene que pasar.

Entre los dos ya lo viste rechazar lo que debe y aceptar lo que debe, en tu
propia máquina, en unos diez segundos. Acá no hay nada que tengas que creer.

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

Se fija qué contiene realmente tu repo y corre solo lo que aplica: manifiestos de
Kubernetes, charts de Helm, policies de Kyverno, Terraform, Python, shell,
Dockerfiles, GitHub Actions, Markdown, YAML y un escaneo de secretos. Si el mes
que viene agregás Terraform, no hay que tocar nada acá.

### Cómo funciona

```text
  editás un archivo
        |
        v
  hook PostToolUse  ->  lintea ese archivo, en menos de dos segundos
                        exit 2 mete el error en el contexto del agente

  el turno intenta cerrar
        |
        v
  hook Stop         ->  corre `make verify`
                        exit 2 significa que el turno no puede cerrar
```

Siete piezas, y ninguna es ingeniosa:

| Ruta | Qué es |
| --- | --- |
| `Makefile` | Los comandos de arriba. |
| `scripts/verify.sh` | El motor. Vive acá porque macOS trae GNU Make 3.81, que no tiene `.ONESHELL`. |
| `scripts/messages.sh` | Todas las cadenas que imprime, en inglés y castellano. |
| `.claude/hooks/` | Los dos hooks. |
| `.claude/agents/reviewer.md` | Un reviewer que lee tu diff sin memoria de cómo se escribió. |
| `.pre-commit-config.yaml` | La única definición de los checks estáticos rápidos. |
| `CLAUDE.md` | Las reglas. Sobre todo: arreglá la causa, nunca deshabilites el check. |

### La parte que todos hacen mal

Dos formas en que esto parece andar mientras no hace absolutamente nada.

**Exit 1 no es exit 2.** Un hook que sale con 1 reporta un error no bloqueante
que va al log de debug, y el agente nunca lo ve. Solo el exit 2 le pone tu stderr
adelante. Armá un hook sobre exit 1 y va a parecer correcto para siempre sin
lograr nada.

**Los hooks se leen al arrancar la sesión.** Escribí `.claude/settings.json` en
el medio de una sesión y no se arma nada. Todos los archivos están bien, la
configuración es válida, ningún hook corre. Una ruta mal escrita en ese archivo
se comporta igual, en silencio, como error no bloqueante.

Así que no le creas a la configuración. Rompé algo y confirmá que te frenaron:

1. `/hooks` tiene que listar los dos, y decir de qué archivo salieron.
2. Escribí un archivo con un error de lint real. Te tiene que volver.
3. Rompé `make verify` e intentá cerrar el turno. Te tiene que bloquear.

Si el paso 3 no te bloquea, no tenés gate, diga lo que diga la configuración.

### Hacelo tuyo

Todo lo que imprime, y los informes del reviewer, están en inglés por defecto.
Para castellano, o bien solo para vos:

```bash
HARNESS_LANG=es make verify
```

o para todos los que lo clonen, con un `.harness.conf` en la raíz:

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
manifiestos.** `-ignore-missing-schemas` es lo que deja pasar un CRD, y también
es la forma en que una corrida reporta éxito habiendo validado una fracción de lo
que leyó. La etapa imprime cuántos salteó, para que una línea verde no se
confunda con más cobertura de la que es.

**El piso de cobertura es 85%, y solo para layouts con `src/`.** Un `--cov`
pelado cuenta los archivos de test, que están casi completamente cubiertos por
definición y empujan el total por encima de la línea: 75% del fuente más 100% de
tests reporta 89%. Sin un `src/` al que acotarlo, el piso se abandona en voz
alta, porque un umbral que da verde por el motivo equivocado es peor que no tener
umbral.

**Los archivos sin trackear advierten, no fallan.** `pre-commit` solo ve archivos
trackeados, así que uno sin trackear se saltea el paso estático. Fallar por eso
te bloquearía todo el día, y un gate que la gente apaga no sirve para nada. La
advertencia mantiene la grieta a la vista en vez de silenciosa.

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
- `.claude/.skip-verify` cerrando un turno con el gate todavía en rojo.
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
