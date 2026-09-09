# A verification harness for Claude Code

A closed loop in which an agent cannot declare work finished that does not pass
verification, and in which lint errors come back on their own instead of waiting
to be pointed out.

Tested on macOS. See [What is verified](#what-is-verified) before trusting any
of it.

## English

### The problem

An agent that is allowed to judge its own work will pass itself. You end up as
the linter: reading diffs, spotting the unquoted variable, saying so, waiting.

The fix is not a better prompt. It is a gate the agent cannot open — a command
that decides, and hooks that run whether or not the agent feels like running
them.

### How the loop closes

```text
  edit a file ──► PostToolUse hook ──► lints that one file
                                       exit 2 → the error lands in context
                                                and the next step fixes it

  end of turn ──► Stop hook ─────────► runs `make verify`
                                       exit 2 → the turn cannot end,
                                                the output becomes the reason
```

Two exit codes carry the whole design, and getting them wrong is the most common
way this fails:

| Exit | What actually happens |
| --- | --- |
| `0` | Success. Nothing reaches the model. |
| `1` | Non-blocking error. It reaches the **debug log only** — the model never sees it. A hook built on exit 1 looks like it works and does nothing. |
| `2` | `PostToolUse`: stderr is shown to the model as a warning; the edit still stands. `Stop`: the turn is blocked and stderr becomes the reason. |

### Quick start

```bash
make bootstrap
```

Then restart your Claude Code session — see [the silent failure](#the-failure-that-looks-like-success)
for why that matters — and confirm the gate works:

```bash
make demo
```

`make demo` runs the gate's linters against files in `examples/broken/` that are
invalid on purpose, and fails if any of them is *not* rejected.

### The pieces

| Path | What it does |
| --- | --- |
| `Makefile` | `verify` is the canonical gate. Also `lint`, `verify-full`, `demo`, `doctor`, `bootstrap`. |
| `scripts/verify.sh` | The engine. The logic lives here because macOS ships GNU Make 3.81, which has no `.ONESHELL`. |
| `.claude/hooks/lint-changed.sh` | `PostToolUse` on `Edit\|Write`. Lints only the file just written, in under two seconds. |
| `.claude/hooks/verify-on-stop.sh` | `Stop`. Runs `make verify` and blocks the turn while it fails. |
| `.claude/agents/reviewer.md` | Reviews a milestone with no memory of how it was built. |
| `.pre-commit-config.yaml` | The single definition of every fast static check. |
| `CLAUDE.md` | The rules. Chiefly: fix the cause, never disable the check. |

### The failure that looks like success

**Hooks are read when a session starts.** Writing `.claude/settings.json` in the
middle of a session arms nothing. Everything looks correct and no hook runs.

A wrong path in that file fails the same way — quietly, as a non-blocking error.
So the only honest test is to break something on purpose and confirm you were
stopped:

1. Run `/hooks` and confirm both appear, and which file they came from.
2. Write a file with a real lint error. The error must come back to you.
3. Break `make verify`, then try to end the turn. You must be blocked.

If step 3 does not block you, you have no gate, whatever the config says.

### Design decisions

**Detection instead of a fixed stack.** `verify` looks at what the repository
actually contains and runs only what applies. Adding Terraform later needs no
edit here.

**Absent content is skipped; a missing tool is not.** No `.tf` files means the
Terraform checks are skipped, and that is honest. But `.tf` files with no
`tflint` installed is a hard failure — otherwise the gate passes green precisely
because nothing is installed.

**`pre-commit` is the only place static checks are defined**, and `make verify`
runs it first. Its linters are `repo: local`, so they call the same binaries
`make bootstrap` installs and cannot drift to a different version.

**Untracked files warn, they do not fail.** `pre-commit` only sees tracked
files, so an untracked file bypasses the static pass entirely. Failing on that
would block you constantly during normal work, and a gate people switch off is
worth nothing. The warning is what keeps the gap visible instead of silent.

**The reviewer cannot write.** It is denied `Write` and `Edit` by its tool
allowlist, not by being asked nicely in its prompt. It also never sees the
conversation — that is the point, since it is not anchored to decisions already
made.

**The Stop hook releases after three failures.** A check the agent cannot fix
would otherwise loop forever. The counter resets when it releases; without that
the gate stays open for the rest of the session.

### What is verified

Published claims about a verification harness ought to say what was actually
run. On macOS, end to end, against the real runtime:

- Both hooks registered, and from which settings file.
- `PostToolUse` returning a lint error into the model's context.
- `Stop` blocking a turn while `make verify` failed.
- The three-strike release, and the counter resetting afterwards.
- `.claude/.skip-verify` closing a turn with the gate still red.
- `make demo` rejecting every fixture.

Not verified:

- **The apt/dnf path in `bootstrap.sh`.** Written, never run. Homebrew is the
  tested route, on macOS and Linuxbrew alike.
- **The kubeconform schema cache.** The flag is accepted and the directory is
  created, but the authoring environment could not reach the schema host, so a
  warm cache was never observed.
- **`make verify-full`.** No cluster was available; it reports that and skips.

### Limits

`terraform init` and the first `kubeconform` run need the network, though never
cloud credentials. The three-minute budget assumes warm caches. And a subagent
reviewing a diff is a language model: across three runs it produced ten
findings, of which three were real, and twice its suggested remedy would have
been worse than the defect. Read its output; do not apply it.

### License

MIT. See [LICENSE](LICENSE).

## Español

### El problema

Un agente al que se le permite juzgar su propio trabajo se va a aprobar. El
linter terminás siendo vos: leyendo diffs, viendo la variable sin comillas,
avisando, esperando.

La solución no es un prompt mejor. Es un gate que el agente no pueda abrir: un
comando que decide, y hooks que corren tenga ganas o no.

### Cómo cierra el loop

```text
  editar archivo ──► hook PostToolUse ──► lintea ese archivo
                                          exit 2 → el error entra al contexto
                                                   y el paso siguiente lo arregla

  fin de turno ────► hook Stop ─────────► corre `make verify`
                                          exit 2 → el turno no puede cerrar,
                                                   la salida es el motivo
```

Dos exit codes sostienen todo el diseño, y equivocarlos es la forma más común de
que esto falle:

| Exit | Qué pasa en realidad |
| --- | --- |
| `0` | Éxito. Nada llega al modelo. |
| `1` | Error no bloqueante. Llega **solo al debug log** — el modelo nunca lo ve. Un hook basado en exit 1 parece andar y no hace nada. |
| `2` | `PostToolUse`: el stderr se le muestra al modelo como warning; la edición queda igual. `Stop`: el turno se bloquea y el stderr es el motivo. |

### Arranque rápido

```bash
make bootstrap
```

Después reiniciá la sesión de Claude Code — el porqué está en
[la falla silenciosa](#la-falla-que-parece-éxito) — y confirmá que el gate anda:

```bash
make demo
```

`make demo` corre los linters del gate contra archivos de `examples/broken/` que
son inválidos a propósito, y falla si alguno *no* es rechazado.

### Las piezas

| Ruta | Qué hace |
| --- | --- |
| `Makefile` | `verify` es el gate canónico. También `lint`, `verify-full`, `demo`, `doctor`, `bootstrap`. |
| `scripts/verify.sh` | El motor. La lógica vive acá porque macOS trae GNU Make 3.81, sin `.ONESHELL`. |
| `.claude/hooks/lint-changed.sh` | `PostToolUse` con matcher `Edit\|Write`. Lintea solo el archivo recién escrito, en menos de dos segundos. |
| `.claude/hooks/verify-on-stop.sh` | `Stop`. Corre `make verify` y bloquea el turno mientras falle. |
| `.claude/agents/reviewer.md` | Revisa un milestone sin memoria de cómo se construyó. |
| `.pre-commit-config.yaml` | La única definición de los checks estáticos rápidos. |
| `CLAUDE.md` | Las reglas. Sobre todo: arreglá la causa, nunca deshabilites el check. |

### La falla que parece éxito

**Los hooks se leen al arrancar la sesión.** Escribir `.claude/settings.json` en
el medio de una sesión no arma nada. Todo se ve correcto y ningún hook corre.

Una ruta mal escrita en ese archivo falla igual: en silencio, como error no
bloqueante. Así que la única prueba honesta es romper algo a propósito y
confirmar que te frenaron:

1. Corré `/hooks` y confirmá que aparecen los dos, y de qué archivo salieron.
2. Escribí un archivo con un error de lint real. El error tiene que volverte.
3. Rompé `make verify` e intentá cerrar el turno. Te tiene que bloquear.

Si el paso 3 no te bloquea, no tenés gate, diga lo que diga la configuración.

### Decisiones de diseño

**Detección en vez de un stack fijo.** `verify` mira qué contiene realmente el
repositorio y corre solo lo que aplica. Agregar Terraform más adelante no
requiere tocar nada acá.

**El contenido ausente se saltea; una herramienta faltante no.** Que no haya
`.tf` significa saltear los checks de Terraform, y eso es honesto. Pero que haya
`.tf` sin `tflint` instalado es fallo duro — si no, el gate pasa en verde
justamente porque no hay nada instalado.

**`pre-commit` es el único lugar donde se definen los checks estáticos**, y
`make verify` lo corre primero. Sus linters son `repo: local`, así que llaman a
los mismos binarios que instala `make bootstrap` y no pueden derivar a otra
versión.

**Los archivos sin trackear advierten, no fallan.** `pre-commit` solo ve
archivos trackeados, así que uno sin trackear evita el paso estático por
completo. Fallar por eso te bloquearía constantemente durante el trabajo normal,
y un gate que la gente apaga no vale nada. El warning es lo que mantiene la
grieta visible en vez de silenciosa.

**El reviewer no puede escribir.** Tiene `Write` y `Edit` denegados por su
allowlist de herramientas, no por pedírselo amablemente en el prompt. Tampoco ve
la conversación — eso es a propósito, porque así no queda anclado a decisiones
ya tomadas.

**El hook de Stop libera al tercer fallo.** Un check que el agente no puede
arreglar generaría un loop infinito. El contador se resetea al liberar; sin eso
el gate queda abierto el resto de la sesión.

### Qué está verificado

Un repositorio que publica un arnés de verificación debería decir qué corrió de
verdad. En macOS, punta a punta, contra el runtime real:

- Los dos hooks registrados, y de qué archivo de settings salieron.
- `PostToolUse` devolviendo un error de lint al contexto del modelo.
- `Stop` bloqueando un turno mientras `make verify` fallaba.
- La liberación al tercer intento, y el contador reseteándose después.
- `.claude/.skip-verify` cerrando un turno con el gate todavía en rojo.
- `make demo` rechazando todos los fixtures.

Sin verificar:

- **El camino apt/dnf de `bootstrap.sh`.** Escrito, nunca ejecutado. Homebrew es
  la ruta probada, tanto en macOS como en Linuxbrew.
- **El cache de schemas de kubeconform.** El flag se acepta y el directorio se
  crea, pero el entorno donde se escribió esto no pudo alcanzar el host de
  schemas, así que nunca se observó un cache caliente.
- **`make verify-full`.** No había cluster disponible; lo reporta y lo saltea.

### Límites

`terraform init` y la primera corrida de `kubeconform` necesitan red, aunque
nunca credenciales de nube. El presupuesto de tres minutos asume caches
calientes. Y un subagente revisando un diff es un modelo de lenguaje: en tres
corridas produjo diez hallazgos, de los cuales tres eran reales, y dos veces el
remedio que propuso habría sido peor que el defecto. Leé su salida; no la
apliques.

### Licencia

MIT. Ver [LICENSE](LICENSE).
