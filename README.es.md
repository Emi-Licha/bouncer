# Bouncer

![Un patovica en pixel art, de brazos cruzados, detrás de tres paneles: PASS, BOUNCE y ESCALATE](docs/assets/bouncer.jpg)

**Un harness de verificación para trabajo agéntico.**

[Read it in English](README.md)

Tu agente dice que terminó.

Mirás el diff.

Algo está mal.

Así que le escribís de nuevo:

> "Los tests están fallando. Arreglalos."

Los arregla.

Y otra vez dice que terminó.

Chequeás.

Hay otra cosa rota.

Así que le escribís de nuevo.

Esta es la parte del trabajo con agentes que se siente extrañamente manual: el
agente puede hacer el trabajo, pero el que decide si está realmente terminado
seguís siendo vos.

Ese no debería ser tu trabajo.

El repo ya sabe cómo chequear casi todo esto:

- Los linters saben si la sintaxis es válida.
- Los tests saben si el código funciona.
- Terraform sabe si su configuración es válida.
- Helm sabe si un chart renderiza.
- kubeconform sabe si un manifiesto respeta su schema de Kubernetes.

Las herramientas ya existen.

Lo que falta es algo que haga que el agente las escuche.

Eso es Bouncer.

## La idea

Bouncer pone un gate de verificación entre tu agente y el final de su turno.

```text
Vos
 │
 ▼
Agente
 │
 │  "Terminé."
 ▼
Bouncer
 │
 ├── PASS ────────► Vos
 │
 ├── BOUNCE ──────► Agente
 │                   │
 │                   └── arregla la falla
 │
 └── ESCALATE ────► Vos
```

El agente sigue haciendo el trabajo. Bouncer no reemplaza al agente, no mejora
su razonamiento ni le reescribe los prompts.

Hace una sola cosa: chequea lo que el agente realmente dejó hecho.

Si el repo pasa sus checks, el turno termina. Si algo falla, Bouncer le devuelve
la falla al agente en vez de terminar el turno, y el agente tiene otra
oportunidad de arreglarlo.

No tenés que escribir el segundo prompt.

## Por qué importa

Un agente decide que terminó según lo que cree que logró.

Bouncer decide si terminó según lo que realmente pasó.

Son cosas distintas. Un agente puede decir:

> "Agregué el deployment de Kubernetes."

Y el repo puede decir:

> "El YAML no parsea."

Bouncer le cree al repo.

## Qué chequea Bouncer

Bouncer no inventa un lenguaje de verificación nuevo. Usa herramientas estándar
que seguramente ya conocés:

- linters
- validadores
- tests
- chequeos de schema
- chequeos de seguridad
- chequeos de archivos generados
- pisos de cobertura

Son un set fijo, elegido para trabajo de infraestructura, y Bouncer corre solo
lo que aplica: si no hay Terraform en tu repo, no hay checks de Terraform.

Los tests son lo que conviene mirar antes de confiar en él. Bouncer corre pytest
cuando encuentra `tests/` y `pyproject.toml` en la raíz del repo, y ningún otro
runner de tests. Si tu proyecto se testea con `go test`, `npm test` o
`cargo test`, agregá ese comando vos: como un hook local en
`.pre-commit-config.yaml`, que el gate corre y cuya falla lo bloquea, o como una
etapa en `scripts/verify.sh` si la suite es lenta, porque los hooks de
pre-commit también corren en cada `git commit`.

Un hook local que corre un comando sobre todo el proyecto necesita dos ajustes:
`pass_filenames: false`, porque si no pre-commit le agrega al comando el nombre
de cada archivo que coincide, y `always_run: true`, para que corra aunque un
commit no toque ningún archivo que coincida. Dentro de los hooks de
`repo: local`:

```yaml
      - id: project-tests
        name: project tests
        entry: go test ./...
        language: system
        pass_filenames: false
        always_run: true
```

Un recorte de lo que le vuelve al agente cuando un check falla. El hook le pasa
las últimas sesenta líneas de la salida, que también listan los checks que
pasaron o se saltearon:

```text
=== make verify FALLÓ (intento 1/3): no se puede terminar el turno ===
== units ==
  tfdocs helpers               ok
== static (pre-commit) ==
  pre-commit                   FAIL
      [...]
      yamllint.................................................................Failed
      - hook id: yamllint
      - exit code: 1

      config.yaml
        2:5       error    syntax error: mapping values are not allowed here (syntax)
      [...]

CHECKS FALLIDOS:
  - pre-commit
```

Esa falla no te llega a vos como un prompt nuevo. Le vuelve al agente:

```text
Agente
  │
  ▼
Bouncer
  │
  │ FAIL
  ▼
"yamllint falló en config.yaml:2:5"
  │
  ▼
Agente
  │
  └── arregla config.yaml
```

Después el agente intenta terminar de nuevo, Bouncer chequea de nuevo, y eso es
el bounce.

## Los tres resultados posibles

Cada verificación termina con uno de tres veredictos.

### PASS

El repo cumple con el gate. El turno termina.

```text
Agente → Bouncer → PASS → Vos
```

### BOUNCE

Algo falló, pero el agente tiene otra oportunidad. La falla pasa a ser parte del
contexto del agente, sin un segundo prompt tuyo.

```text
Agente → Bouncer → FAIL
                    │
                    ▼
                 Agente
```

### ESCALATE

El agente falló tres veces seguidas. Bouncer corta el loop y te devuelve la
decisión a vos.

Esto importa porque un loop de verificación sin límite es solo otra forma de
quemar tokens para siempre.

```text
intento 1 → BOUNCE
intento 2 → BOUNCE
intento 3 → ESCALATE
```

Un aviso: un turno también puede terminar sin que el gate corra, y se ve igual
que un `PASS`. Pasa cuando existe `.claude/.skip-verify`, cuando falta `jq` o el
`Makefile`, o cuando el hook no puede leer su entrada o llegar al proyecto.
[Qué se corrió de verdad](docs/evidence.es.md) cubre cada caso.

## Cómo funciona

Bouncer usa dos momentos del ciclo del agente. Los dos son hooks de Claude Code:
comandos que Claude Code corre solo, sin que vos los llames.

- `PostToolUse` da feedback rápido mientras el agente trabaja: lintea cada
  archivo justo después de que se edita o se escribe.
- `Stop` es el gate final: corre `make verify` cuando el agente intenta terminar
  el turno.

```text
                ┌────────────────┐
                │     Agente     │
                └────────┬───────┘
                         │
                  edita / escribe
                         │
                         ▼
                ┌────────────────┐
                │  PostToolUse   │
                │ chequeo rápido │
                └────────┬───────┘
                         │
                         ▼
                  El agente sigue
                         │
                         │ "terminé"
                         ▼
                ┌────────────────┐
                │      Stop      │
                │  make verify   │
                └────────┬───────┘
                         │
           ┌─────────────┼─────────────┐
           ▼             ▼             ▼
         PASS         BOUNCE       ESCALATE
           │             │             │
           ▼             ▼             ▼
          Vos         Agente          Vos
```

El detalle importante es que Bouncer no se limita a ver la falla. Puede impedir
que el turno termine y devolverle la falla al agente. Eso es lo que convierte la
verificación en un loop, y depende del exit code con el que sale un hook:
[cómo funciona](docs/how-it-works.es.md#el-exit-code-es-todo-el-truco) explica
por qué.

## Probalo

```bash
git clone https://github.com/Emi-Licha/bouncer.git
cd bouncer

make bootstrap
make demo
make selftest
```

`make bootstrap` instala las herramientas, y la primera vez tarda unos minutos.
`make demo` muestra a Bouncer rechazando fixtures rotos a propósito.
`make selftest` lo muestra aceptando los válidos. Podés ver el gate andando
antes de conectarlo a un agente.

## Instalalo en tu proyecto

Bouncer es chico a propósito. No hay un framework de agentes nuevo para aprender
ni un DSL de verificación propio. Copiás los hooks y los scripts a tu repo,
reiniciás Claude Code, y el gate pasa a ser parte del flujo de trabajo de tu
agente.

Todo esto se corre desde la raíz de tu proyecto.

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

**5. Contale las reglas a tu agente.** Si recién creás el `CLAUDE.md`, poné un
título de primer nivel como `# CLAUDE.md` en la primera línea: el linter de
Markdown lo exige, y sin eso el gate se pone en rojo apenas lo agregás a git, y
git rechaza el commit. Después agregá esto:

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

**6. Corré el gate vos una vez, antes que el agente.** `make bootstrap` corre
solo los checks estáticos, en silencio, y ninguno de los demás, así que lo que
tu repo ya tenía mal sigue ahí, y va a rebotar el primer turno del agente.

```bash
make verify
```

Arreglá lo que marque. Si alguna regla no encaja con tu proyecto, este es el
momento de ajustar `.yamllint.yml`, `.markdownlint.yaml` o
`.pre-commit-config.yaml`. Esa decisión es tuya mientras adoptás Bouncer; una
vez que los hooks están vivos, `CLAUDE.md` le dice al agente que nunca afloje un
check para pasar.

**7. Reiniciá Claude Code y comprobá que el gate está vivo.** Los hooks se leen
al arrancar la sesión, así que hasta que no reinicies no hay nada armado.
Después rompé algo a propósito y confirmá que te frenan. Un gate que nunca viste
bloquear nada es un gate que no tenés, y
[cómo funciona](docs/how-it-works.es.md#la-trampa) te da los tres chequeos.

## Qué no es Bouncer

Bouncer no es un agente.

No escribe código.

No decide cómo resolver una tarea.

No hace más inteligente a tu modelo.

Hace algo más simple: hace que tu agente pase por el mismo gate de verificación
que habrías usado vos.

La diferencia es que, cuando algo falla, la falla le llega primero al agente.
Vos entrás cuando pasa, o cuando te escala el problema.

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

## La idea en una frase

**No le preguntes al agente si terminó. Preguntale al repo.**

## Licencia

MIT. Ver [LICENSE](LICENSE).
