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

`valid/` is left out of the validation stages of an ordinary `make verify`
(kubeconform, helm, kyverno and terraform), so the repository's own gate stays
fast and a fork does not inherit fixtures it never asked for. The static linters
still check it, like any other tracked file. `make selftest` sets
`BOUNCER_SELFTEST=1`, which brings it back in.

| File | What it is for |
| --- | --- |
| `broken/unquoted-var.sh` | An unquoted variable that is never assigned: shellcheck SC2154 and SC2086. |
| `broken/bad-indent.yaml` | A mapping value indented under a scalar: a YAML syntax error. |
| `broken/Dockerfile` | An untagged base image and an `apt-get install` that never cleans up. |
| `valid/k8s/` | A plain manifest and a kustomization, so `kubeconform` has something to validate and the e2e stage something to apply. |
| `valid/chart/` | A minimal chart. Its templates are Go template text, so they are left out of `kubeconform` and `yamllint` and checked only through `helm template`. |
| `valid/policy/` | A kyverno policy with a test that passes. |
| `valid/terraform/` | A module with its own `.terraform-docs.yml` and a generated README, which is what opts it into the `terraform-docs` check. |

Adding a fixture to `broken/` means adding a matching assertion in
`scripts/demo.sh`; without one it is just an invalid file nobody looks at.
Adding one to `valid/` needs nothing: `make selftest` runs the whole gate, so it
is picked up by whichever stage claims it.

Some things a fixture cannot express. The shapes of a `.terraform-docs.yml` that
the config parser has to read are one: a fixture is one config in one shape, and
the bugs were in the other shapes. Those cases live in `scripts/tfdocs-test.sh`,
which `make selftest` runs next to the fixtures.

Python is not covered by `selftest`. The python stage looks for `src/`, `tests/`
and `pyproject.toml` at the repository root, so a fixture in a subdirectory is
invisible to it.

## Español

```bash
make demo      # todos los fixtures de broken/ tienen que ser rechazados
make selftest  # todo lo de valid/ tiene que pasar
```

`valid/` queda fuera de las etapas de validación de un `make verify` normal
(kubeconform, helm, kyverno y terraform), así el gate del propio repo sigue
siendo rápido y quien forkee no arrastra fixtures que nunca pidió. Los linters
estáticos lo revisan igual, como a cualquier archivo trackeado. `make selftest`
setea `BOUNCER_SELFTEST=1`, que lo vuelve a incluir.

| Archivo | Para qué está |
| --- | --- |
| `broken/unquoted-var.sh` | Una variable sin comillas que nunca se asigna: shellcheck SC2154 y SC2086. |
| `broken/bad-indent.yaml` | Un valor de mapping indentado bajo un escalar: error de sintaxis YAML. |
| `broken/Dockerfile` | Imagen base sin tag y un `apt-get install` que no limpia. |
| `valid/k8s/` | Un manifiesto plano y una kustomization, para que `kubeconform` tenga algo que validar y la etapa e2e algo que aplicar. |
| `valid/chart/` | Un chart mínimo. Sus templates son texto Go template, así que quedan fuera de `kubeconform` y `yamllint` y se revisan solo vía `helm template`. |
| `valid/policy/` | Una policy de kyverno con un test que pasa. |
| `valid/terraform/` | Un módulo con su propio `.terraform-docs.yml` y README generado, que es lo que lo hace entrar al check de `terraform-docs`. |

Agregar un fixture a `broken/` implica agregar su assertion en `scripts/demo.sh`;
sin ella es solo un archivo inválido que nadie mira. Agregar uno a `valid/` no
necesita nada: `make selftest` corre el gate entero, así que lo levanta la etapa
que le corresponda.

Hay cosas que un fixture no puede expresar. Las formas de un `.terraform-docs.yml`
que el parser tiene que leer son una: un fixture es una config en una forma, y los
bugs estaban en las otras formas. Esos casos viven en `scripts/tfdocs-test.sh`,
que `make selftest` corre al lado de los fixtures.

Python no está cubierto por `selftest`. La etapa de python busca `src/`, `tests/`
y `pyproject.toml` en la raíz del repo, así que un fixture en un subdirectorio le
resulta invisible.
