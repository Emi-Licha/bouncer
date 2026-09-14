# Bouncer

**Un harness de verificación para trabajo agéntico.**

[Read it in English](README.md)

Bouncer se para en la puerta del trabajo de tu agente. Nada de lo que produce
tu agente pasa sin haber sido chequeado, y lo que falla no termina el turno:
vuelve al agente con el motivo de la falla.

```text
        ┌───────────┐
        │    Vos    │  le pedís algo
        └─────┬─────┘
              │
              ▼
        ┌───────────┐
        │  Agente   │◀──────────────────────────────────────────┐
        └─────┬─────┘  hace el trabajo, y dice que terminó      │
              │                                                 │
              ▼                                                 │
        ┌───────────┐                                           │
        │  Bouncer  │  corre los checks que tu repo necesita    │
        └─────┬─────┘                                           │
              │                                                 │
      ┌───────┼──────────────┐                                  │
      │       │              │                                  │
    PASS  ESCALATE        BOUNCE ───────────────────────────────┘
      │       │           con la falla
      ▼       ▼
  ┌───────────────────┐
  │        Vos        │
  └───────────────────┘

  PASS      la respuesta te llega, ya pasó por el gate
  ESCALATE  tercera falla seguida: el gate sigue en rojo, y decidís vos
```

Un patova no discute si estás o no en la lista. Y estar muy convencido de que
estás en la lista no te va a hacer entrar. Esa es toda la idea.

## Por qué

Tu agente dice que finalizó con la tarea que le diste. Casi nunca es así.
Entonces leés el diff, encontrás la variable sin comillas, prompteás de nuevo,
te vuelve a decir que está listo, y ahí se te fue toda la tarde en ese ida y
vuelta constante.

Un prompt mejor no va a arreglar eso, y no es que tu agente sea descuidado. Para
cuando cree que el trabajo está terminado, y esa creencia sale de lo que quiso
hacer, no de algo que haya mirado lo que efectivamente hizo. Nadie corrió los
linters, validó los manifiestos ni corrió los tests. El primer chequeo sos vos.

Bouncer pone un chequeo antes que vos. Envuelve el trabajo de tu agente como un
test harness envuelve código bajo prueba: corre los checks, lee el resultado, y
decide si el trabajo pasa.

## Qué chequea

Bouncer mira lo que quedó hecho en tu repo, no lo que el agente dice que hizo.
Lo pasa por las mismas herramientas que usarías vos (linters, validadores y
tests), que para el mismo archivo dan siempre la misma respuesta. Así atrapa
cosas como:

- un script de shell que se rompe la primera vez que una variable tiene un
  espacio
- YAML que no parsea, o un manifiesto de Kubernetes que no respeta su schema
- un chart de Helm que no renderiza, una policy de Kyverno cuyo propio test falla
- Terraform que no valida, o cuya documentación generada ya no coincide
- una suite de tests que falla, o cobertura por debajo del piso
- un secreto a punto de ser commiteado

Corre solo lo que aplica: si no hay Terraform en tu repo, no hay checks de
Terraform. Qué cuenta como check lo cambiás vos: son herramientas comunes,
declaradas en `.pre-commit-config.yaml` y en `scripts/verify.sh`, no un lenguaje
que Bouncer se inventó.

## El veredicto

Cada vez que tu agente dice que terminó, Bouncer corre `make verify`. Si pasa,
el veredicto es `PASS`. Si falla, es `BOUNCE`. Y si falla tres veces seguidas,
`ESCALATE`:

| Veredicto | Qué pasa |
| --- | --- |
| `PASS` | El turno termina. La respuesta que leés ya pasó por el gate. |
| `BOUNCE` | El turno no termina. La falla le cae en el contexto al agente, y la arregla sin que vos escribas nada. |
| `ESCALATE` | La tercera falla seguida, falle en lo que falle. Bouncer deja de insistir, termina el turno con el gate todavía en rojo, y la decisión pasa a ser tuya. |

El tercero importa tanto como los otros dos. Hay fallas que el agente no puede
arreglar, y sin un límite el agente seguiría intentando arreglarlas para
siempre, gastando tokens en vueltas que no llevan a nada. Y un gate que nunca te
deja avanzar es un gate que la gente termina desactivando. Por eso, a la tercera
falla, Bouncer frena y te escala el problema: te avisa en ese momento, y la
decisión de cómo resolverlo pasa a ser tuya.

Un turno también puede terminar sin que el gate haya corrido, y se ve igual que
un `PASS`: cuando existe `.claude/.skip-verify`, cuando falta `jq` o el
`Makefile`, o cuando el hook no puede leer su entrada o llegar al proyecto. El
primero queda anotado en `make escalations`; los demás no.
[Qué se corrió de verdad](docs/evidence.es.md) cubre cada uno.

## Qué no es Bouncer

No es un agente, y no intenta hacer el trabajo. No hace más inteligente a tu
agente ni te reescribe los prompts. Tu agente sigue haciendo cada arreglo.

Contesta una sola pregunta: ¿esta ejecución dejó el repo en un estado que
aceptamos?

## Cómo llega hasta ahí

Dos hooks, que son comandos que Claude Code dispara solo. Vos nunca los llamás.

**Mientras el agente trabaja**, `PostToolUse` se dispara después de que cada
archivo se edita o se escribe, lintea ese archivo solo, y tarda menos de dos
segundos. La queja le llega al agente mientras todavía está en ese archivo.

**Cuando el turno está por terminar**, `Stop` corre `make verify`, el gate
entero, y de ahí sale el veredicto.

Lo que hace que un hook pueda frenar al agente es el número con el que sale.
Exit 1 va a un log de debug que el agente no lee nunca. Exit 2 se le entrega al
agente, y en `Stop` además bloquea el turno. Bouncer usa exit 2, y
[cómo funciona](docs/how-it-works.es.md#el-exit-code-es-todo-el-truco) explica
por qué ese detalle es donde la mayoría de los hooks falla en silencio.

## Cómo se ve un bounce de verdad

```text
=== make verify FALLÓ (intento 1/3): no se puede terminar el turno ===
== static (pre-commit) ==
  pre-commit                   FAIL
      yamllint.................................................................Failed
      - hook id: yamllint
      - exit code: 1

      config.yaml
        2:4       error    syntax error: mapping values are not allowed here (syntax)
```

El agente lee eso, arregla el YAML, e intenta terminar el turno de nuevo. Vos
nunca ves la ida y vuelta: lo que te llega es la respuesta que pasó.

## Probalo

```bash
git clone https://github.com/Emi-Licha/bouncer.git
cd bouncer
make bootstrap
```

`make bootstrap` instala las herramientas, y la primera vez tarda unos minutos.
Los dos comandos que siguen no necesitan Claude Code para nada.

```bash
make demo      # todos los fixtures de examples/broken tienen que ser rechazados
make selftest  # todo lo de examples/valid tiene que pasar
```

Uno muestra al gate atrapando defectos de verdad. El otro lo muestra aceptando
trabajo bueno, que es la mitad que nadie prueba. En pocos segundos lo viste
hacer las dos cosas en tu máquina, en vez de creerle a un README.

Verlo frenar a un agente viene después, y eso necesita una sesión reiniciada.
[Cómo funciona](docs/how-it-works.es.md) explica por qué, y cómo comprobarlo.

## Instalalo en tu proyecto

Bouncer son un puñado de archivos, así que instalarlo es copiarlo. Todo esto se
corre desde la raíz de tu proyecto.

**1. Fijate qué pisarías.**

```bash
ls -d Makefile .pre-commit-config.yaml .yamllint.yml .markdownlint.yaml CLAUDE.md \
      .claude/settings.json .claude/hooks .claude/agents examples scripts 2>/dev/null
```

Lo que aparezca ya existe. Esos combinalos a mano en vez de copiar encima. Si
aparece `scripts`, fijate si tiene archivos con el mismo nombre que los de
Bouncer antes del paso 2, porque se pisan.
[Cómo funciona](docs/how-it-works.es.md#combinarlo-con-un-proyecto-que-ya-existe)
dice qué va dónde.

**2. Copiá los archivos.**

```bash
git clone https://github.com/Emi-Licha/bouncer.git /ruta/a/bouncer
mkdir -p .claude scripts
cp -R /ruta/a/bouncer/.claude/hooks /ruta/a/bouncer/.claude/agents .claude/
cp /ruta/a/bouncer/.claude/settings.json .claude/
cp /ruta/a/bouncer/scripts/*.sh scripts/
cp /ruta/a/bouncer/Makefile /ruta/a/bouncer/.pre-commit-config.yaml .
cp /ruta/a/bouncer/.yamllint.yml /ruta/a/bouncer/.markdownlint.yaml .
cp -R /ruta/a/bouncer/examples .
```

La última línea es opcional: trae los fixtures contra los que corren
`make demo` y `make selftest`. Sin ellos, los dos se niegan a correr antes que
pasar sin haber probado nada.

**3. Dejá los archivos temporales de Bouncer fuera de git.**

```bash
printf '.claude/settings.local.json\n.claude/.skip-verify\n.verify-tmp/\n.bouncer-escalations.log\n' >> .gitignore
```

**4. Instalá las herramientas y trackeá los archivos nuevos.** `pre-commit` solo
chequea archivos que git conoce.

```bash
make bootstrap
git add .claude scripts examples Makefile .pre-commit-config.yaml \
        .yamllint.yml .markdownlint.yaml .gitignore
```

**5. Contale las reglas a tu agente.** Agregá esto a tu `CLAUDE.md`, y crealo si
no tenés:

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

**6. Reiniciá Claude Code y comprobá que el gate está vivo.** Los hooks se leen
al arrancar la sesión, así que hasta que no reinicies no hay nada armado.
Después rompé algo a propósito y confirmá que te frenan. Un gate que nunca viste
bloquear nada es un gate que no tenés, y
[cómo funciona](docs/how-it-works.es.md#la-trampa) te da los tres chequeos.

## Los comandos

| Comando | Qué hace |
| --- | --- |
| `make verify` | El gate. Todo lo demás existe para correr esto en el momento justo. |
| `make lint` | Solo la mitad estática, la rápida. |
| `make verify-full` | Suma un dry run del lado del servidor contra un cluster. |
| `make demo` | Prueba que el gate sigue atrapando cosas. |
| `make selftest` | Prueba que el gate sigue aceptando lo bueno. |
| `make escalations` | Cada vez que el gate te pasó la decisión, y por qué. |
| `make doctor` | Qué herramientas tenés y cuáles te faltan. |
| `make bootstrap` | Las instala. |
| `make lang` | En qué idioma está hablando Bouncer. |
| `make clean` | Borra directorios temporales y de cache. |

## En tu idioma

Bouncer habla inglés por defecto, y los informes del reviewer también. Lo podés
tener en español para vos, configurándolo de la siguiente manera en la terminal
desde la que abrís Claude Code, así también lo ven los hooks:

```bash
export BOUNCER_LANG=es
claude
```

O para todos los que clonen el repo, con un `.bouncer.conf` en la raíz:

```ini
lang = es
```

La variable le gana al archivo, de esa manera un default de equipo y una
preferencia personal nunca tienen que pelearse.

## Seguí leyendo

- **[Cómo funciona](docs/how-it-works.es.md)**: dónde entra Bouncer en un
  agente, qué hace cada archivo, las dos trampas que hacen que un
  gate parezca real sin serlo, y por qué cada decisión salió como salió.
- **[Qué se corrió de verdad](docs/evidence.es.md)**: cada afirmación de acá que
  fue probada, cómo, y qué no se probó. Incluido lo que Bouncer no puede hacer.

## A quién le sirve

- **Usás Claude Code todos los días** y te cansaste del segundo prompt, el de
  "está fallando el lint, arreglalo".
- **Escribís infraestructura con un agente.** Terraform, manifiestos de
  Kubernetes, charts de Helm, policies de Kyverno: lugares donde un error que
  parece razonable sale más caro que un build roto. Es el stack que Bouncer
  chequea de fábrica.
- **Tu equipo quiere una sola definición de terminado** para el trabajo hecho
  con un agente, y que el mismo gate corra para todos.
- **Estás armando tu propio harness de verificación**, y querés la semántica de
  los exit codes y las trampas escritas por alguien que ya cayó en ellas.

Probablemente no te sirva si:

- **Tu agente no es Claude Code.** El loop depende de los hooks de Claude Code.
- **Tu stack es JavaScript, Go, Java o Rust.** Todavía no hay linters conectados
  para esos lenguajes.
- **Lo necesitás en Windows.** Por ahora está probado solo en macOS.

## Licencia

MIT. Ver [LICENSE](LICENSE).
