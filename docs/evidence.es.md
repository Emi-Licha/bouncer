# Qué se corrió de verdad, y qué no puede hacer Bouncer

[Read it in English](evidence.md) · [Volver al README](../README.es.md)

Un repositorio que habla de verificación debería decir qué probó en vez de pedir
que le crean. Todo esto se corrió en macOS.

## Contra una sesión real de Claude Code

- Los dos hooks registrados, y de qué archivo de settings salieron.
- `PostToolUse` devolviendo un error de lint al contexto del agente.
- `Stop` bloqueando un turno, la liberación al tercer intento, y el contador
  reseteándose.
- `.claude/.skip-verify` dejando terminar un turno con el gate todavía en rojo.
- El reviewer siguiendo el idioma configurado en los dos sentidos: preguntado en
  castellano y con el default en inglés contestó en inglés, y configurado en
  castellano contestó en castellano.

## En la línea de comandos

- Contenido real: `kubeconform` aceptando un manifiesto bueno y rechazando uno
  malo, `helm template` sobre un chart, `kyverno test` en los dos sentidos,
  `terraform validate`, `tflint`, `trivy`, `terraform-docs` sobre un módulo al
  día y sobre uno desactualizado, y el piso de cobertura rechazando 75% y
  aceptando 100%.
- `make verify-full` contra kind sobre colima. Un ConfigMap llamado
  `Nombre_Invalido` es `Valid: 1` para kubeconform, cuyo schema no restringe el
  formato del nombre, y el API server lo rechaza por no ser un subdominio
  RFC 1123. Esa brecha es por lo que la etapa e2e existe aparte.
- Nombres con espacio, comilla o salto de línea, tanto en archivos como en
  directorios.
- `bootstrap` en sus tres ramas y el código de salida de cada una, dos de ellas
  con un gestor de paquetes simulado para no instalar nada.
- Los dos idiomas en `verify`, `demo`, `doctor`, `bootstrap` y los dos hooks.
- El registro de liberaciones en sus dos caminos y en los dos idiomas, dándole
  al hook de Stop la misma entrada que le manda Claude Code, sobre una copia de
  prueba del repo. Incluidas sus dos formas de degradarse: sin catálogo, y con
  el resumen reformateado, que anotan que no se pudo leer el check en vez de un
  `?` pelado.
- Instalarlo en un proyecto vacío siguiendo al pie de la letra los pasos de
  instalación: `make verify` en verde con contenido limpio y en rojo con un
  script roto, los dos hooks saliendo con 2 al recibir la misma entrada que les
  manda Claude Code, y `make demo` y `make selftest` negándose a correr hasta
  que se copiaron los fixtures.

Los chequeos sobre contenido real se pueden reproducir con `make demo` y
`make selftest`, salvo el piso de cobertura: la etapa de Python busca `src/`,
`tests/` y `pyproject.toml` en la raíz del repo y no puede ver un fixture en un
subdirectorio. Todo lo demás se corrió a mano y queda registrado acá, sin
automatizar.

**Sin correr:** el camino apt/dnf de `bootstrap.sh`, que está escrito pero nunca
se ejecutó, y el presupuesto de tres minutos contra un repo con contenido real.
Acá `verify` tarda unos dos segundos y `selftest` unos cuatro.

## Qué no puede hacer

**Partes del gate necesitan red**, aunque nunca credenciales de nube:
`pre-commit` baja sus entornos de hooks la primera vez, `kubeconform` baja los
schemas que no tiene en caché, `trivy` baja su paquete de checks, y
`terraform init` baja los providers que declare un módulo.

**Los hooks necesitan `jq`** para leer lo que les manda Claude Code. Sin él se
hacen a un lado en silencio antes que trabar la sesión. `make bootstrap` lo
instala, `make doctor` lo lista y `make verify` falla sin él, pero el hook de
Stop no te puede avisar: es justamente la parte que necesita `jq`.

**El reviewer es un modelo de lenguaje, no un linter.** Sus dos primeras
revisiones trajeron siete hallazgos, dos reales, y las dos veces el arreglo que
propuso habría sido peor que el problema. Endurecerle las reglas, para que
compruebe lo que puede comprobar y nunca recete un remedio que no probó, cambió
eso: sus dos revisiones más recientes trajeron siete hallazgos, seis reales. El
precio es tiempo, unos cinco minutos y medio sobre un diff de noventa líneas, la
mayor parte verificando sus propias afirmaciones, y nada lo limita. Reproducí un
hallazgo antes de actuar sobre él, en cualquier caso.

**`.bouncer-releases.log` es una nota para vos, no una auditoría.** Vive en tu
working tree, así que cualquier cosa que pueda escribir ahí lo puede editar, el
agente incluido. Dos sesiones a la vez intercalan líneas que se parecen entre
sí, y nada rota el archivo: dejá `.claude/.skip-verify` puesto y crece una línea
por turno.

**Nada hace cumplir lo que pide `CLAUDE.md`**: el plan, el commit, la review y
la regla de no pushear. Son instrucciones, no hooks, así que se sostienen
mientras el agente, y quien pushea, las respeten.
