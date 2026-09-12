# Bouncer

**Tu agente dice que está listo. Bouncer chequea los factos.**

[Read it in English](README.md)

Porque casi nunca lo está. Leés el diff, encontrás la variable sin comillas,
prompteás de nuevo, te vuelve a decir que está listo, y ahí se te fue la tarde.

Un prompt mejor no va a arreglar eso, y no es que el modelo sea descuidado. Para
ver qué está pasando en realidad, conviene saber quién decide que una tarea
terminó.

## Por qué tu agente cree que terminó

Un modelo hace una sola cosa: entra texto, sale texto. No abre archivos, no
corre comandos y no se acuerda de lo que hizo hace un minuto.

Así que cuando tu agente busca en tu repo, edita un archivo y corre los tests,
todo eso lo hace otra cosa. El modelo pide una acción, y esa otra cosa la
ejecuta. A esa otra cosa se le dice harness. Con Claude Code, Claude es el
modelo y Claude Code es el harness.

El harness también decide cuándo parar. Por defecto para cuando el modelo dice
que el trabajo está terminado, y el modelo contesta desde lo que quiso hacer, no
desde lo que pasó. Todavía nadie chequeó el resultado. El primero que chequea
sos vos, y por eso la tarde termina como termina.

Bouncer mueve esa decisión a un comando.

## Cómo funciona, una pieza por vez

Pongamos que pediste un helper de reintentos y el agente escribió `retry.sh`.

**Empieza con un comando.** `make verify` corre los linters sobre tus archivos,
valida tus manifiestos, renderiza tus charts, corre tus tests, y sale con cero o
no. Un linter es un programa que lee código sin ejecutarlo y se queja de lo que
está roto o es riesgoso: `shellcheck` es el que te avisa que `echo $name` se
rompe la primera vez que `$name` tiene un espacio.

Bouncer engancha once, y corre solo lo que aplica. Si no hay Terraform en tu
repo, no hay checks de Terraform.

**Alguien lo tiene que correr.** Vos lo vas a correr dos veces, y después te vas
a olvidar. Así que lo corre un hook. Un hook es un comando que el runtime del
agente dispara solo cuando pasa algo; vos nunca lo llamás. Claude Code ofrece
varios eventos, y Bouncer usa dos.

**Un hook que solo se queja es decoración.** Lo que le da dientes es el número
con el que sale. Exit 1 va a un log de debug que el agente no lee nunca. Exit 2
se le entrega al agente, y en el evento `Stop` bloquea el turno directamente.
Bouncer usa exit 2.

**Entonces el gate es el hook de `Stop`.** Se dispara cuando el turno está por
terminar, corre `make verify`, y si eso falla, el turno no termina. La salida le
cae en el contexto al agente, así que lee la falla y la corrige sin que vos
escribas nada.

**Igual, esperar al final es tarde.** El agente puede escribir veinte archivos
antes de que algo mire el primero. Por eso el hook de `PostToolUse` se dispara
justo después de que cada archivo se edita o se escribe, lintea solo ese
archivo, y tarda menos de dos segundos. Tu `retry.sh` vuelve con la variable sin
comillas mientras el agente todavía está en eso.

**Y un gate sin salida es un gate que apagás.** Un check que el agente no puede
satisfacer generaría un loop infinito, así que después de tres intentos
fallidos seguidos Bouncer libera el turno, lo dice, y deja la liberación
escrita.

Ese es todo el mecanismo:

```text
    vos: "agregá la lógica de reintento"
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  el agente trabaja, y cada archivo que toca se lintea en    │
│  el momento. Las quejas le vuelven derecho a él.            │
└─────────────────────────────────────────────────────────────┘
    │
    ▼
    el agente dice que terminó
    │
    ▼
┌─────────────────────────────────────────────────────────────┐
│  make verify: el gate entero                                │
│                                                             │
│  falló ──▶ el turno no termina, el agente arregla y prueba  │
│            de nuevo (tres veces, después lo suelta)         │
│  pasó  ──▶ el turno termina                                 │
└─────────────────────────────────────────────────────────────┘
    │
    ▼
    una respuesta que ya pasó el gate
```

Un patova no discute si estás en la lista. Estar muy convencido de que estás en
la lista no te hace entrar. Esa es toda la idea.

## Cómo se ve cuando salta

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

El agente lee eso y arregla el YAML. Vos nunca ves la ida y vuelta.

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
ls Makefile .pre-commit-config.yaml .claude/settings.json CLAUDE.md 2>/dev/null
```

Lo que aparezca ya existe. Esos combinalos a mano en vez de copiar encima;
[cómo funciona](docs/how-it-works.es.md#combinarlo-con-un-proyecto-que-ya-existe)
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
printf '.claude/settings.local.json\n.claude/.skip-verify\n.verify-tmp/\n.bouncer-releases.log\n' >> .gitignore
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
| `make releases` | Cada vez que el gate se hizo a un lado, y por qué. |
| `make doctor` | Qué herramientas tenés y cuáles te faltan. |
| `make bootstrap` | Las instala. |
| `make lang` | En qué idioma está hablando Bouncer. |
| `make clean` | Borra directorios temporales y de cache. |

## En tu idioma

Bouncer habla inglés por defecto, y los informes del reviewer también. Para
castellano, o lo configurás para vos:

```bash
BOUNCER_LANG=es make verify
```

O para todos los que clonen el repo, con un `.bouncer.conf` en la raíz:

```ini
lang = es
```

La variable le gana al archivo, así que un default de equipo y una preferencia
personal nunca tienen que pelearse.

## Seguí leyendo

- **[Cómo funciona](docs/how-it-works.es.md)**: las piezas de un harness y
  cuáles es Bouncer, qué hace cada archivo, las dos trampas que hacen que un
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
- **Estás armando tu propio harness**, y querés la semántica de los exit codes y
  las trampas escritas por alguien que se las comió.

Probablemente no te sirva si tu agente no es Claude Code, porque el loop depende
de los hooks de Claude Code; si tu stack es JavaScript, Go, Java o Rust, que
todavía no tienen linters conectados; o si lo necesitás en Windows, o querés que
reemplace a tu CI. Corre en tu máquina, y está probado en macOS.

## Licencia

MIT. Ver [LICENSE](LICENSE).
