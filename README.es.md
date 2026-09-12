# Bouncer

**Un harness de verificación para trabajo agéntico.**

[Read it in English](README.md)

Bouncer se para en la puerta del trabajo de tu agente. Nada de lo que produce
pasa sin haber sido chequeado, y lo que falla no termina el turno: vuelve al
agente con el motivo.

```text
        ┌───────────┐
        │  Agente   │  escribe un archivo, y dice que terminó
        └─────┬─────┘
              │
              ▼
        ┌───────────┐
        │  Bouncer  │  corre todos los checks que tu repo necesita
        └─────┬─────┘
              │
      ┌───────┴───────┐
      │               │
    PASS           BOUNCE
      │               │
      ▼               ▼
  el turno pasa    la falla le vuelve al agente,
                   que la arregla y prueba de nuevo
                      │
                      ▼
                   tres bounces seguidos, y Bouncer
                   libera el turno y lo dice
```

Un patova no discute si estás en la lista. Estar muy convencido de que estás en
la lista no te hace entrar. Esa es toda la idea.

## Por qué

Tu agente dice que terminó. Casi nunca es así. Entonces leés el diff, encontrás
la variable sin comillas, prompteás de nuevo, te vuelve a decir que está listo,
y ahí se te fue la tarde.

Un prompt mejor no va a arreglar eso, y no es que el modelo sea descuidado. La
cuestión es quién decide que una tarea terminó.

Un modelo hace una sola cosa: entra texto, sale texto. No abre archivos, no
corre comandos y no se acuerda de lo que hizo hace un minuto. Cuando tu agente
busca en tu repo, edita un archivo y corre los tests, esas acciones las ejecuta
otra cosa. A esa otra cosa se le dice harness, y con Claude Code, Claude es el
modelo y Claude Code es el harness.

El harness también decide cuándo parar. Por defecto para cuando el modelo dice
que el trabajo está terminado, y el modelo contesta desde lo que quiso hacer, no
desde lo que pasó. Todavía nadie chequeó el resultado. El primero que chequea
sos vos.

Bouncer mueve esa decisión a un comando, y lo pone en la puerta.

## Qué chequea

Bouncer chequea lo que el agente dejó en tu repo, no cómo se comportó en el
camino. Es un alcance elegido a propósito: un artefacto lo puede chequear un
programa que da la misma respuesta siempre, y un programa así es lo único que
vale la pena poner en una puerta.

- un script de shell que se rompe la primera vez que una variable tiene un
  espacio
- YAML que no parsea, o un manifiesto de Kubernetes que el cluster rechazaría
- un chart de Helm que no renderiza, una policy de Kyverno cuyo propio test falla
- Terraform que no valida, o cuya documentación generada ya no coincide
- una suite de tests que falla, o cobertura por debajo del piso
- un secreto a punto de ser commiteado

Once linters y validadores, y corre solo lo que aplica. Si no hay Terraform en
tu repo, no hay checks de Terraform. Qué cuenta como check lo cambiás vos: son
herramientas comunes, declaradas en `.pre-commit-config.yaml` y en
`scripts/verify.sh`, no un lenguaje que Bouncer se inventó.

## El veredicto

Lo produce un comando, `make verify`. Todo lo demás existe para correrlo en el
momento justo y para actuar según la respuesta.

| Veredicto | Qué pasa |
| --- | --- |
| `PASS` | El turno termina. La respuesta que leés ya pasó por el gate. |
| `BOUNCE` | El turno no termina. La falla le cae en el contexto al agente, y la arregla sin que vos escribas nada. |
| `RELEASE` | Tres bounces seguidos sobre el mismo problema, así que Bouncer suelta, lo dice, y lo deja escrito. |

El tercero importa tanto como los otros dos. Un check que el agente no puede
satisfacer generaría un loop infinito, y un gate que te deja encerrado es uno
que apagás antes del mediodía. Bouncer prefiere hacerse a un lado en voz alta
antes que tenerte de rehén en silencio, y `make releases` te muestra cada vez
que lo hizo.

## Qué no es Bouncer

No es un agente, y no intenta hacer el trabajo. No hace más inteligente al
modelo ni te reescribe los prompts. El modelo sigue haciendo cada arreglo.

Contesta una sola pregunta: ¿esta ejecución dejó el repo en un estado que
aceptamos?

## Cómo llega hasta ahí

Dos hooks, que son comandos que Claude Code dispara solo. Vos nunca los llamás.

**Mientras el agente trabaja**, `PostToolUse` se dispara después de que cada
archivo se edita o se escribe, lintea ese archivo solo, y tarda menos de dos
segundos. La queja le llega al agente mientras todavía está en ese archivo.

**Cuando el turno está por terminar**, `Stop` corre `make verify`, el gate
entero, y de ahí sale el veredicto.

Lo que le da dientes a un hook es el número con el que sale. Exit 1 va a un log
de debug que el agente no lee nunca. Exit 2 se le entrega al agente, y en `Stop`
además bloquea el turno. Bouncer usa exit 2, y
[cómo funciona](docs/how-it-works.es.md#el-exit-code-es-todo-el-truco) explica
por qué ese detalle es donde la mayoría de los harnesses falla en silencio.

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

## Roadmap

Bouncer chequea artefactos. Una capa de verificación para sistemas agénticos
podría chequear más que eso, y estas son las piezas que acá todavía no existen,
nombradas para que nadie tenga que adivinar:

- **Verificación de tools.** Si se llamó a la tool correcta, con argumentos
  válidos, y si se salteó un paso que se esperaba.
- **Métricas de costo y tokens.** Cuánto gastó un turno, y un techo para eso.
- **Grafos de ejecución.** La forma de una corrida, para distinguir un flujo que
  se desvió del camino esperado de uno que tomó otra ruta igual de válida.
- **Evals.** Un conjunto estable de tareas para correr antes y después de tocar
  el harness, y poder distinguir una mejora de una regresión.

Ninguna está empezada. Las piezas que sí están construidas se describen en
[cómo funciona](docs/how-it-works.es.md), y qué se corrió para probarlas está en
[la evidencia](docs/evidence.es.md).

## Licencia

MIT. Ver [LICENSE](LICENSE).
