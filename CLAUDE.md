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

1. A three-line plan.
2. Wait for approval.
3. Implement.
4. `make verify`.
5. Commit.
6. Review with the `reviewer` subagent.
7. Stop.

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
- Committing while the working tree holds files nobody reviewed.

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

1. Plan de tres líneas.
2. Esperar aprobación.
3. Implementar.
4. `make verify`.
5. Commit.
6. Review con el subagente `reviewer`.
7. Parar.

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
- Commitear con archivos en el working tree que nadie revisó.

### Cuando algo falla dos veces

Parar y preguntar. No probar una tercera variante.
