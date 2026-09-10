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
invalid on purpose. It fails if any of them is *not* rejected, so it tells you
the gate is awake rather than asking you to assume it.

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
| `Makefile` | `verify` is the canonical gate. Also `lint`, `verify-full`, `demo`, `doctor`, `lang`, `bootstrap`. |
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

**`pre-commit` is the only place static checks are defined**, and `make verify`
runs it first. Its linters are `repo: local`, so they call the same binaries
`make bootstrap` installs and cannot drift to a different version.

**Untracked files warn, they do not fail.** `pre-commit` only sees tracked
files, so an untracked file skips the static pass entirely. Failing on that
would block you constantly while you work, and a gate people switch off is worth
nothing. The warning keeps the gap visible instead of silent.

**The reviewer cannot write.** Its tool allowlist denies `Write` and `Edit`. It
is not asked nicely in a prompt, it simply has no way to change your code. It
also never sees the conversation, which is the point: it is not attached to
decisions that were already made.

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

Not verified:

- **The apt/dnf path in `bootstrap.sh`.** Written, never run. Homebrew is the
  tested route, on macOS and Linuxbrew alike.
- **The kubeconform schema cache.** The flag is accepted and the directory gets
  created, but the machine this was written on could not reach the schema host,
  so a warm cache was never actually observed.
- **`make verify-full`.** No cluster was available. It reports that and skips.

### Limits

`terraform init` and the first `kubeconform` run need network access, though
never cloud credentials. The three minute budget assumes warm caches.

And the reviewer is a language model, not a linter. Across three runs it
produced ten findings, of which three were real. Twice, the fix it suggested
would have been worse than the bug it found: one would have disabled the Stop
hook's anti-loop guard, the other would have reintroduced the exact
vulnerability it was meant to close. Read what it says. Do not apply it blindly.

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
inválidos a propósito. Falla si alguno *no* es rechazado, así que te avisa que
el gate está despierto en vez de pedirte que lo supongas.

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
| `Makefile` | `verify` es el gate canónico. También están `lint`, `verify-full`, `demo`, `doctor`, `lang` y `bootstrap`. |
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

**`pre-commit` es el único lugar donde se definen los checks estáticos**, y
`make verify` lo corre primero. Sus linters son `repo: local`, así que llaman a
los mismos binarios que instala `make bootstrap` y no pueden quedar en versiones
distintas.

**Los archivos sin trackear advierten, no fallan.** `pre-commit` solo ve
archivos trackeados, así que uno sin trackear se saltea todo el paso estático.
Fallar por eso te bloquearía todo el tiempo mientras trabajás, y un gate que la
gente apaga no sirve para nada. La advertencia mantiene la grieta a la vista en
vez de silenciosa.

**El reviewer no puede escribir.** Su allowlist de herramientas le niega `Write`
y `Edit`. No se lo pedimos amablemente en un prompt: directamente no tiene forma
de tocarte el código. Tampoco ve la conversación, y eso es a propósito, porque
así no queda apegado a decisiones que ya se tomaron.

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

Sin verificar:

- **El camino apt/dnf de `bootstrap.sh`.** Escrito, nunca ejecutado. Homebrew es
  la ruta probada, tanto en macOS como en Linuxbrew.
- **El cache de schemas de kubeconform.** El flag se acepta y el directorio se
  crea, pero la máquina donde se escribió esto no podía alcanzar el host de
  schemas, así que nunca se llegó a ver un cache caliente.
- **`make verify-full`.** No había cluster disponible. Lo reporta y lo saltea.

### Límites

`terraform init` y la primera corrida de `kubeconform` necesitan red, aunque
nunca credenciales de nube. El presupuesto de tres minutos asume caches
calientes.

Y el reviewer es un modelo de lenguaje, no un linter. En tres corridas produjo
diez hallazgos, de los cuales tres eran reales. Dos veces, el arreglo que
propuso habría sido peor que el problema que encontró: uno desactivaba el
guardarraíl anti-loop del hook de Stop, y el otro reintroducía exactamente la
vulnerabilidad que venía a cerrar. Leé lo que dice. No lo apliques a ciegas.

### Licencia

MIT. Ver [LICENSE](LICENSE).
