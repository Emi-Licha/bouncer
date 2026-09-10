# Examples

Two directories, for the two halves of the same question.

`broken/` holds files that are invalid on purpose. `make demo` runs the gate's
linters over them and fails if any is *not* rejected.

`valid/` holds a real module, chart, policy and manifest. `make selftest` runs
the gate itself over them and fails if it does not pass.

One shows the gate catches things. The other shows it does not cry wolf, and,
more usefully, exercises the wiring: detection, the exclusion of chart sources
from `kubeconform`, the per-module scoping of `trivy` and `terraform-docs`. Every
bug found in Bouncer so far lived in that wiring, not in the tools.

## English

```bash
make demo      # every fixture in broken/ must be rejected
make selftest  # everything in valid/ must pass
```

`valid/` is pruned from an ordinary `make verify`, so the repository's own gate
stays fast and a fork does not inherit fixtures it never asked for.
`make selftest` sets `BOUNCER_SELFTEST=1`, which unprunes it.

| File | What it is for |
| --- | --- |
| `broken/unquoted-var.sh` | An unquoted variable that is never assigned: shellcheck SC2154 and SC2086. |
| `broken/bad-indent.yaml` | A mapping value indented under a scalar: a YAML syntax error. |
| `broken/Dockerfile` | An untagged base image and an `apt-get install` that never cleans up. |
| `valid/k8s/` | A plain manifest, so `kubeconform` has something to validate. |
| `valid/chart/` | A minimal chart. Its templates are Go template text, so they are excluded from `kubeconform` and linted only through `helm template`. |
| `valid/policy/` | A kyverno policy with a test that passes. |
| `valid/terraform/` | A module with a generated README, which is what opts it into the `terraform-docs` check. |

Adding a fixture to `broken/` means adding a matching assertion in
`scripts/demo.sh`; without one it is just an invalid file nobody looks at.
Adding one to `valid/` needs nothing: `make selftest` runs the whole gate, so it
is picked up by whichever stage claims it.

Python is not covered by `selftest`. The python stage looks for `src/`, `tests/`
and `pyproject.toml` at the repository root, so a fixture in a subdirectory is
invisible to it.

## Español

```bash
make demo      # todos los fixtures de broken/ tienen que ser rechazados
make selftest  # todo lo de valid/ tiene que pasar
```

`valid/` queda excluido de un `make verify` normal, así el gate del propio repo
sigue siendo rápido y quien forkee no arrastra fixtures que nunca pidió.
`make selftest` setea `BOUNCER_SELFTEST=1`, que lo vuelve a incluir.

| Archivo | Para qué está |
| --- | --- |
| `broken/unquoted-var.sh` | Una variable sin comillas que nunca se asigna: shellcheck SC2154 y SC2086. |
| `broken/bad-indent.yaml` | Un valor de mapping indentado bajo un escalar: error de sintaxis YAML. |
| `broken/Dockerfile` | Imagen base sin tag y un `apt-get install` que no limpia. |
| `valid/k8s/` | Un manifiesto plano, para que `kubeconform` tenga algo que validar. |
| `valid/chart/` | Un chart mínimo. Sus templates son texto Go template, así que quedan fuera de `kubeconform` y se revisan solo vía `helm template`. |
| `valid/policy/` | Una policy de kyverno con un test que pasa. |
| `valid/terraform/` | Un módulo con README generado, que es lo que lo hace entrar al check de `terraform-docs`. |

Agregar un fixture a `broken/` implica agregar su assertion en `scripts/demo.sh`;
sin ella es solo un archivo inválido que nadie mira. Agregar uno a `valid/` no
necesita nada: `make selftest` corre el gate entero, así que lo levanta la etapa
que le corresponda.

Python no está cubierto por `selftest`. La etapa de python busca `src/`, `tests/`
y `pyproject.toml` en la raíz del repo, así que un fixture en un subdirectorio le
resulta invisible.
