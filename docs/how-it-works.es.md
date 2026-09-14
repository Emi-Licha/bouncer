# Cómo funciona Bouncer

[Read it in English](how-it-works.md) · [Volver al README](../README.es.md)

El README te cuenta qué hace Bouncer. Esto es lo que hay abajo: dónde se ubica
dentro de un agente, para qué está cada archivo, las dos formas en que un gate
puede parecer real sin serlo, y por qué las decisiones salieron como salieron.

## Dónde se ubica Bouncer

La palabra harness se usa de dos maneras, y conviene no mezclarlas. En testing,
un harness es el código que envuelve algo para chequearlo: lo corre, lee lo que
devuelve, y decide si está bien. En ese sentido Bouncer es un harness de
verificación. En la ingeniería de agentes, el harness es todo lo que rodea al
modelo y le permite actuar, y en ese sentido Claude Code es uno. El resto de
esta sección usa el segundo sentido, para mostrar dónde entra Bouncer.

El harness de un agente, en ese sentido, se suele describir como nueve piezas. Seis le permiten al agente
trabajar, y tres son las que te permiten confiar en el resultado:

| # | La pieza | Para qué está | Quién te la da |
| --- | --- | --- | --- |
| 1 | Tools | Buscar, leer, editar, correr comandos. El modelo pide; el harness ejecuta. | Claude Code |
| 2 | Un loop | Volver a llamar al modelo con el resultado, para que un paso lleve al siguiente. | Claude Code |
| 3 | Memoria | Llevar lo que ya pasó a la llamada siguiente, porque el modelo no guarda nada. | Claude Code |
| 4 | Contexto | Elegir qué ve el modelo cada vez, porque el repo entero no entra y tampoco ayudaría. | Claude Code |
| 5 | Un lugar donde trabajar | Un sandbox, para que un comando malo caiga ahí y no en tu máquina. | Claude Code, hasta donde lo configures |
| 6 | Un objetivo, y verificación | Saber que está terminado porque algo lo chequeó, no porque el modelo lo dijo. | **Bouncer** |
| 7 | Permisos y límites | Qué puede hacer solo, qué te tiene que preguntar, y cuándo dejar de intentar. | Claude Code, y Bouncer para el cuándo parar |
| 8 | Observabilidad | Ver qué pasó de verdad en una corrida. | Nadie acá |
| 9 | Evals | Medir si un cambio en el harness mejoró o empeoró las cosas. | Nadie acá |

Bouncer es la pieza seis y la mitad de la siete. Cinco de esas primeras seis ya
vienen con tu agente. La sexta no, porque solo vos sabés qué significa
"terminado" en tu repo.

La ocho no la hace. Las trazas valen cuando una corrida no se puede repetir, y
un `make verify` que falla sí se puede: corrélo de nuevo en la misma máquina y
te da lo mismo, con más detalle del que un log iba a guardar. Lo que no se
recupera después es un momento en que el gate no corrió, así que esos quedan en
`.bouncer-releases.log` y los imprime `make releases`. La nueve, medir un cambio
del harness mismo, no está cubierta.

Ese mapa de nueve piezas no es nuestro. Sale de [la explicación de harness
engineering de santi](https://x.com/santtiagom_/status/2098782814837543075), que
arma un harness desde cero pieza por pieza.

## El exit code es todo el truco

El runtime le pasa al hook un JSON por entrada estándar, y después lee el exit
code del hook para decidir qué pasa:

| El hook sale con | Qué hace el runtime |
| --- | --- |
| `0` | Todo bien, seguí. Al agente no se le dice nada. |
| `1` | Lo toma como un error no bloqueante y lo escribe en el log de debug. **El agente nunca lo ve.** |
| `2` | Lee tu stderr y se lo pone adelante al agente. En `Stop`, además, el turno queda bloqueado. |

Armá un hook sobre exit 1 y va a parecer correcto para siempre, sin lograr
absolutamente nada. Los dos hooks de Bouncer usan exit 2.

**`PostToolUse`**, con matcher `Edit|Write`, lintea el único archivo que se
acaba de tocar, en menos de dos segundos. No puede deshacer la edición, porque
la tool ya corrió, pero la queja le cae en el contexto y el paso siguiente la
arregla.

**`Stop`** corre `make verify`, el gate entero. Si falla, escribe a stderr un
encabezado y las últimas sesenta líneas de la salida, y sale con 2, así que el
turno no puede terminar. Cuenta las fallas seguidas en un archivo bajo `TMPDIR`.
A la tercera libera el turno, lo dice en un mensaje que vos ves, y resetea el
contador, porque sin ese reset el gate quedaría abierto el resto de la sesión.

Los dos hooks son defensivos: ante cualquier condición inesperada salen con 0 y
en silencio. Un hook roto que bloquea todos los turnos es peor que no tener
hook.

## La trampa

Dos formas de que esto parezca que anda sin hacer nada. El exit code de arriba
es la primera. Esta es la segunda.

**Los hooks se leen al arrancar la sesión.** Escribí `.claude/settings.json` en
el medio de una sesión y no queda nada armado. Todos los archivos están bien, la
configuración es válida, y ningún hook corre. Una ruta mal escrita en ese
archivo se comporta igual, calladita, como un error no bloqueante.

Así que no le creas a la configuración. Rompé algo y confirmá que te frenaron:

1. `/hooks` tiene que listar los dos, y decir de qué archivo salieron.
2. Escribí un archivo con un error de lint real. Te tiene que volver.
3. Rompé `make verify` e intentá terminar el turno. Te tiene que frenar.

Si el paso 3 no te bloquea, no tenés gate, diga lo que diga la configuración.

## Los archivos

| Ruta | Qué es |
| --- | --- |
| `Makefile` | Todos los comandos que lista el README. |
| `scripts/verify.sh` | El motor detrás de `make verify`. Vive acá porque macOS trae GNU Make 3.81, que no tiene `.ONESHELL`. |
| `scripts/messages.sh` | Todas las cadenas que imprime Bouncer, en inglés y castellano. |
| `scripts/yamllint.sh` | Corre `yamllint` para pre-commit y para el hook de lint, dejando afuera los templates de charts de Helm, estén donde estén. |
| `scripts/tfdocs.sh` | Encuentra la config de terraform-docs que va a usar un módulo, y lee su archivo de salida. |
| `scripts/tfdocs-test.sh` | Los casos que esas dos ya erraron alguna vez, que corre `make verify`. |
| `scripts/bootstrap.sh` | Instala el toolchain. |
| `scripts/demo.sh` | Corre los linters sobre `examples/broken/`. |
| `.claude/settings.json` | Registra los dos hooks. |
| `.claude/hooks/` | `lint-changed.sh` y `verify-on-stop.sh`. |
| `.claude/agents/reviewer.md` | Las instrucciones del reviewer y sus permisos de herramientas. |
| `.pre-commit-config.yaml` | La única definición de cada check estático rápido. |
| `examples/` | Los fixtures de `make demo` y `make selftest`. |
| `CLAUDE.md` | Las reglas que tu agente lee al empezar cada sesión. |

Los checks rápidos viven en `.pre-commit-config.yaml` y los corre `pre-commit`,
una herramienta ya hecha. La llama el gate y la llama tu `git commit`, así que
los dos nunca pueden estar en desacuerdo sobre qué significa "limpio". Los
linters de ahí están declarados como locales, o sea que llaman a los binarios
que instaló `make bootstrap` en vez de bajarse los suyos. Cinco hooks de
mantenimiento, entre ellos el que busca conflictos de merge, sí vienen del repo
de `pre-commit`, fijados a una versión.

## Qué pide CLAUDE.md y qué hacen cumplir los hooks

Los hooks hacen cumplir una sola cosa: el turno no termina mientras `make
verify` falle. Todo lo demás es una regla que tu agente lee en `CLAUDE.md` y
sigue porque está escrita, no porque algo lo frene. Eso incluye el plan de tres
líneas antes de arrancar, el commit, la review después, y no pushear mientras
una review tenga un hallazgo crítico o alto abierto.

**El reviewer** es un segundo agente que lee el diff terminado sin memoria de la
conversación que lo produjo. No puede ver cómo alguien se convenció a sí mismo
de una decisión, que es exactamente el punto. Reporta hallazgos con severidad y
`archivo:línea`, y no arregla nada. No es parte del loop: un chequeo que puede
responder distinto para el mismo código no puede ser un gate, así que queda como
segunda opinión.

## Combinarlo con un proyecto que ya existe

Si los pasos de instalación encontraron archivos que ya tenías, llevate las
partes en vez de los archivos:

- `.claude/settings.json`: copiá el bloque `hooks` del de Bouncer al tuyo.
- `Makefile`: copiá los targets que quieras. `verify` es obligatorio, porque es
  el que llama el hook de Stop.
- `.pre-commit-config.yaml`: sumá las entradas de `repos` de Bouncer a las tuyas.
- `CLAUDE.md`: pegá al final el bloque de Definition of Done del README.

## Por qué hace las cosas así

**El contenido que falta se saltea. Una herramienta que falta, no.** Si no hay
archivos `.tf`, los checks de Terraform se saltean, y eso es honesto. Pero tener
archivos `.tf` sin `tflint` instalado es un fallo duro, porque si no el gate se
pone verde por el peor motivo posible: no hay nada instalado que pueda atrapar
nada.

**Que diga `kubeconform ok` no significa que se hayan chequeado todos los
manifiestos.** `-ignore-missing-schemas` es lo que deja pasar un recurso
personalizado, y también es la forma en que una corrida reporta éxito habiendo
validado una fracción de lo que leyó. La etapa imprime cuántos salteó.

**El piso de cobertura es 85%, y solo para layouts con `src/`.** Un `--cov`
pelado cuenta los archivos de test, que están casi completamente cubiertos por
definición y empujan el total por encima de la línea: 75% del fuente más 100% de
tests reporta 89%. Sin un `src/` al que acotarlo, el piso se abandona en voz
alta, porque un umbral que da verde por el motivo equivocado es peor que no
tener umbral.

**Los archivos sin trackear advierten, no fallan.** `pre-commit` solo ve
archivos que git está trackeando, así que uno recién creado se saltea el paso
estático entero. Fallar por eso te bloquearía todo el día, y un gate que la
gente apaga no sirve para nada. La advertencia mantiene la grieta a la vista en
vez de silenciosa.

**Los templates de un chart no son YAML.** Son texto Go template que recién es
YAML cuando helm lo renderiza, así que `yamllint` y `kubeconform` solo podrían
fallar sobre ellos. Quedan afuera de los dos, esté donde esté el chart, y se
revisan con `helm template`.

**El chequeo de documentación de Terraform es doblemente opcional.** Corre solo
donde un `.terraform-docs.yml` define un archivo de salida, buscado igual que lo
busca terraform-docs: el módulo, el `.config/` del módulo, la raíz, el
`.config/` de la raíz, y por último `~/.tfdocs.d`, que está fuera del repo. Una
config ahí maneja el chequeo en tu máquina y en la de nadie más, CI incluido. Y
aun así solo sobre los módulos donde ese archivo de salida tenga el marcador
`BEGIN_TF_DOCS`, así que un ejemplo de uso queda afuera. El archivo lo lee un
parser chico que entiende el estilo en bloque de siempre; una config escrita
como un mapa en una línea, `output: {file: ...}`, se reporta como ilegible y se
saltea, en vez de adivinarla.

**El reviewer no debería escribir, y en general no puede.** Tiene `Write` y
`Edit` negados. Conserva `Bash`, porque un revisor que no puede comprobar si un
binario existe infla severidades sobre suposiciones, y con `Bash` se pueden
escribir archivos. El último tramo de esa prohibición es una regla de su prompt
y no un muro, y conviene saberlo antes de apuntarlo a un repo que te importa.
