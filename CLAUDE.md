# CLAUDE.md

Operating rules for this repository.

## English

### Definition of Done

Nothing is done until `make verify` passes.

If the Stop hook blocks the turn, fix the cause. Never disable a check, never
lower a threshold, never skip a test to get past it, and never edit the
Makefile or the hooks to make something pass. If a check is itself wrong, say
so and we change it together.

### Milestone flow

1. A three-line plan, then go ahead. It is not a request for approval: it lets
   the user see what you are about to do and stop you if they disagree.
2. Implement.
3. `make verify`.
4. Commit.
5. Review with the `reviewer` subagent.
6. Stop.

### Reviews

Relay a review from the `reviewer` subagent by quoting it in full, in the
language it was written in. Your own reading of it goes afterwards, clearly
separated from the report. A paraphrase drops the severities and the `path:line`
locations, and the report is an artefact someone may want to paste into a pull
request.

Reproduce a finding before acting on it. The reviewer has twice proposed a
remedy worse than the defect it had found.

Nothing is pushed while a review has a critical or high finding open. Fix it
first, or show that it is not a defect.

### Tests

TDD where it applies: write the test first, confirm it fails for the right
reason, then implement.

### Commits

Conventional Commits, in English, one commit per logical unit.

### Language

Code comments and annotations: English. Documentation: English and Spanish,
both versions.

### Forbidden

- `git commit --no-verify`, or any other bypass of the hooks.
- Editing the hooks or the Makefile so a failing check passes.
- Creating `.claude/.skip-verify` unprompted. It is the user's escape hatch.
- Committing files nobody has looked at, such as stray or generated files left
  in the working tree. This is about what goes into a commit, not about the
  `reviewer` subagent, which runs after it.
- Pushing while a review has a critical or high finding open.

### When something fails twice

Stop and ask. Do not try a third variation.

## Español

### Definición de terminado

Nada está terminado hasta que `make verify` pase.

Si el hook de Stop bloquea el turno, se arregla la causa. Nunca deshabilitar un
check, nunca relajar un umbral, nunca marcar un test como skip para pasar, y
nunca editar el Makefile ni los hooks para que algo pase. Si un check está mal,
decilo y lo cambiamos juntos.

### Flujo por milestone

1. Plan de tres líneas, y seguir. No es un pedido de aprobación: es para que el
   usuario vea qué vas a encarar y te frene si no está de acuerdo.
2. Implementar.
3. `make verify`.
4. Commit.
5. Review con el subagente `reviewer`.
6. Parar.

### Revisiones

Los informes del subagente `reviewer` se relevan citándolos completos y en el
idioma en que fueron escritos. Tu lectura del informe va después, separada de
él. Un resumen pierde las severidades y las ubicaciones `path:line`, y el
informe es un artefacto que alguien puede querer pegar en un pull request.

Reproducí un hallazgo antes de actuar sobre él. El reviewer ya propuso dos veces
un remedio peor que el defecto que había encontrado.

No se pushea nada mientras una review tenga un hallazgo crítico o alto abierto.
Primero se arregla, o se muestra que no es un defecto.

### Tests

TDD donde aplique: primero el test, confirmar que falla por la razón correcta,
después implementar.

### Commits

Conventional Commits, en inglés, uno por unidad lógica.

### Idioma

Comentarios y anotaciones en el código: inglés. Documentación: inglés y
español, las dos versiones.

### Prohibido

- `git commit --no-verify`, o cualquier otro bypass de los hooks.
- Editar los hooks o el Makefile para que pase un check que falla.
- Crear `.claude/.skip-verify` por cuenta propia. Es el escape del usuario.
- Commitear archivos que nadie miró, como archivos sueltos o generados que
  quedaron en el working tree. Esto habla de lo que entra en un commit, no del
  subagente `reviewer`, que corre después.
- Pushear con un hallazgo crítico o alto abierto en una review.

### Cuando algo falla dos veces

Parar y preguntar. No probar una tercera variante.
