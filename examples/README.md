# Examples

## English

Every file in `broken/` is invalid deliberately. They exist so the gate can
be watched rejecting something instead of only being described.

Run them with:

```bash
make demo
```

The demo passes when **every** fixture is rejected. A fixture that passes means
the gate stopped catching something it used to catch, which is the failure
these fixtures exist to detect.

| File | What it breaks |
| --- | --- |
| `unquoted-var.sh` | An unquoted variable that is never assigned: shellcheck SC2154 and SC2086. |
| `bad-indent.yaml` | A mapping value indented under a scalar: a YAML syntax error. |
| `Dockerfile` | An untagged base image and an `apt-get install` that never cleans up. |

These files are excluded from the repository's own checks, in
`.pre-commit-config.yaml` and in the `scan()` prune list in `scripts/verify.sh`.
That exclusion is what lets them stay broken while `make verify` stays green. If
you add a fixture here, it needs a matching assertion in `scripts/demo.sh`.
Otherwise it is just an invalid file nobody looks at.

## Español

Todos los archivos de `broken/` son inválidos a propósito. Existen para
poder **ver** al gate rechazando algo, en vez de solo leer que lo hace.

Se corren con:

```bash
make demo
```

El demo pasa cuando **todos** los fixtures son rechazados. Si alguno pasa,
significa que el gate dejó de atrapar algo que antes atrapaba, que es
precisamente la falla que estos fixtures sirven para detectar.

| Archivo | Qué rompe |
| --- | --- |
| `unquoted-var.sh` | Una variable sin comillas que nunca se asigna: shellcheck SC2154 y SC2086. |
| `bad-indent.yaml` | Un valor de mapping indentado bajo un escalar: error de sintaxis YAML. |
| `Dockerfile` | Imagen base sin tag y un `apt-get install` que no limpia. |

Estos archivos están excluidos de los checks del propio repositorio, en
`.pre-commit-config.yaml` y en la lista de prune de `scan()` en
`scripts/verify.sh`. Esa exclusión es lo que les permite seguir rotos mientras
`make verify` sigue en verde. Si agregás un fixture acá, necesita su assertion
correspondiente en `scripts/demo.sh`. Si no, es solo un archivo inválido que
nadie mira.
