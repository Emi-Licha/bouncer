#!/usr/bin/env bash
# Message catalogue for everything Bouncer prints.
#
# Language resolution, highest priority first:
#   1. BOUNCER_LANG in the environment
#   2. lang= in .bouncer.conf at the repository root
#   3. English
#
# Any value other than "es" resolves to English, so a typo degrades to the
# default rather than printing raw keys at people.
#
# Written for bash 3.2: no associative arrays, so the catalogue is two case
# statements. A key absent from the Spanish one falls through to English,
# which keeps a half-translated catalogue readable instead of broken.

bouncer_resolve_lang() {
  local want="${BOUNCER_LANG:-}"
  if [ -z "$want" ] && [ -r .bouncer.conf ]; then
    want=$(sed -n 's/^[[:space:]]*lang[[:space:]]*=[[:space:]]*\([A-Za-z_-]*\).*/\1/p' \
             .bouncer.conf 2>/dev/null | head -1)
  fi
  case "$want" in
    es | es[-_]*) printf 'es' ;;
    *)            printf 'en' ;;
  esac
}

BOUNCER_LANG_ACTIVE=$(bouncer_resolve_lang)

msg_en() {
  case "$1" in
    lang_active)        printf 'language' ;;

    skipped_header)     printf 'skipped (no such content in this repo):' ;;
    missing_tools)      printf 'MISSING TOOLS' ;;
    missing_tools_hint) printf '(the repo has content that requires them). Run: make bootstrap' ;;
    failed_checks)      printf 'FAILED CHECKS:' ;;
    verify_ok)          printf 'verify OK' ;;
    required_by)        printf '(required by: %%s)' ;;
    untracked_warn)     printf 'untracked files are invisible to pre-commit:' ;;
    no_cluster)         printf 'skipped: no reachable cluster' ;;
    kubeconform_skipped) printf '%%s resource(s) had no schema and were not validated' ;;
    unknown_stage)      printf 'unknown stage: %%s (expected: lint, core, full, doctor)' ;;
    doctor_tool)        printf 'TOOL' ;;
    doctor_status)      printf 'STATUS' ;;
    doctor_ok)          printf 'ok' ;;
    doctor_missing)     printf 'missing' ;;

    skip_precommit)     printf 'pre-commit (no .pre-commit-config.yaml)' ;;
    skip_k8s)           printf 'kubeconform (no kubernetes manifests)' ;;
    skip_helm)          printf 'helm (no charts)' ;;
    skip_policy)        printf 'kyverno (no policy tests)' ;;
    skip_terraform)     printf 'terraform (no .tf files)' ;;
    skip_tfdocs)        printf 'terraform-docs (no .terraform-docs.yml)' ;;
    skip_tfdocs_nooutput) printf 'terraform-docs (.terraform-docs.yml sets no output file, so --output-check verifies nothing)' ;;
    skip_python)        printf 'python (no .py files)' ;;
    skip_mypy)          printf 'mypy (no src/)' ;;
    skip_pytest)        printf 'pytest (needs tests/ and pyproject.toml)' ;;
    skip_cov)           printf 'coverage floor (needs a src/ layout to scope it to)' ;;
    skip_e2e)           printf 'e2e (no kustomizations)' ;;

    demo_intro)         printf 'Each fixture below is broken on purpose. Every check is expected to fail.' ;;
    demo_skipped)       printf '%%s is not installed. Run: make bootstrap' ;;
    demo_caught)        printf 'the gate caught it (exit %%s)' ;;
    demo_missed)        printf 'THE GATE MISSED IT: a non-zero exit was expected' ;;
    demo_failed)        printf 'demo FAILED: at least one fixture was not rejected.' ;;
    demo_ok)            printf 'demo OK: every fixture was rejected, as it should be.' ;;
    demo_no_fixtures)   printf 'demo cannot run: %%s is missing. Copy examples/ from Bouncer, or skip make demo.' ;;
    selftest_no_fixtures) printf 'selftest cannot run: %%s is missing. Copy examples/ from Bouncer, or skip make selftest.' ;;
    demo_case_shell)    printf 'shellcheck: an unquoted, undefined variable' ;;
    demo_case_yaml)     printf 'yamllint: invalid indentation' ;;
    demo_case_docker)   printf 'hadolint: untagged base image, no apt cleanup' ;;

    boot_brew)          printf '== installing toolchain with homebrew ==' ;;
    boot_apt)           printf '== installing what apt carries (UNTESTED PATH) ==' ;;
    boot_dnf)           printf '== installing what dnf carries (UNTESTED PATH) ==' ;;
    boot_already)       printf 'already installed' ;;
    boot_installing)    printf 'installing...' ;;
    boot_tap)           printf 'installing from terraform-linters/tap...' ;;
    boot_hooks)         printf '== installing git hooks ==' ;;
    boot_warming)       printf '== warming pre-commit environments ==' ;;
    boot_still_missing) printf 'Still missing, install these yourself:' ;;
    boot_missing_note)  printf 'The gate only fails on a missing tool when the repository actually has content that needs it, so an incomplete toolchain is not necessarily a problem. Run '"'"'make doctor'"'"' to see where you stand.' ;;
    boot_done)          printf 'bootstrap done. Run: make doctor' ;;
    boot_no_pm)         printf 'No supported package manager found (brew, apt-get, dnf).' ;;
    boot_no_pm_hint)    printf 'Install the tools listed by '"'"'make doctor'"'"' by hand.' ;;
    boot_from_project)  printf 'from its own project' ;;

    lint_failed)        printf 'LINT FAILED: %%s' ;;
    stop_blocked)       printf '=== make verify FAILED (attempt %%s/3): the turn cannot end ===' ;;
    stop_released)      printf 'verify keeps failing after 3 attempts, releasing the gate' ;;
    *)                  printf '' ;;
  esac
}

msg_es() {
  case "$1" in
    lang_active)        printf 'idioma' ;;

    skipped_header)     printf 'salteado (no hay contenido de ese tipo en este repo):' ;;
    missing_tools)      printf 'FALTAN HERRAMIENTAS' ;;
    missing_tools_hint) printf '(el repo tiene contenido que las necesita). Corré: make bootstrap' ;;
    failed_checks)      printf 'CHECKS FALLIDOS:' ;;
    verify_ok)          printf 'verify OK' ;;
    required_by)        printf '(lo pide: %%s)' ;;
    untracked_warn)     printf 'los archivos sin trackear son invisibles para pre-commit:' ;;
    no_cluster)         printf 'salteado: no hay cluster accesible' ;;
    kubeconform_skipped) printf '%%s recurso(s) sin schema, no se validaron' ;;
    unknown_stage)      printf 'etapa desconocida: %%s (se esperaba: lint, core, full, doctor)' ;;
    doctor_tool)        printf 'HERRAMIENTA' ;;
    doctor_status)      printf 'ESTADO' ;;
    doctor_ok)          printf 'ok' ;;
    doctor_missing)     printf 'falta' ;;

    skip_precommit)     printf 'pre-commit (no hay .pre-commit-config.yaml)' ;;
    skip_k8s)           printf 'kubeconform (no hay manifiestos de kubernetes)' ;;
    skip_helm)          printf 'helm (no hay charts)' ;;
    skip_policy)        printf 'kyverno (no hay tests de policy)' ;;
    skip_terraform)     printf 'terraform (no hay archivos .tf)' ;;
    skip_tfdocs)        printf 'terraform-docs (no hay .terraform-docs.yml)' ;;
    skip_tfdocs_nooutput) printf 'terraform-docs (.terraform-docs.yml no define archivo de salida, asi que --output-check no verifica nada)' ;;
    skip_python)        printf 'python (no hay archivos .py)' ;;
    skip_mypy)          printf 'mypy (no hay src/)' ;;
    skip_pytest)        printf 'pytest (necesita tests/ y pyproject.toml)' ;;
    skip_cov)           printf 'piso de cobertura (necesita un layout src/ al que acotarlo)' ;;
    skip_e2e)           printf 'e2e (no hay kustomizations)' ;;

    demo_intro)         printf 'Cada fixture de abajo está roto a propósito. Se espera que todos los checks fallen.' ;;
    demo_skipped)       printf '%%s no está instalado. Corré: make bootstrap' ;;
    demo_caught)        printf 'el gate lo atrapó (exit %%s)' ;;
    demo_missed)        printf 'EL GATE NO LO ATRAPÓ: se esperaba un exit distinto de cero' ;;
    demo_failed)        printf 'demo FALLÓ: al menos un fixture no fue rechazado.' ;;
    demo_ok)            printf 'demo OK: todos los fixtures fueron rechazados, como corresponde.' ;;
    demo_no_fixtures)   printf 'demo no puede correr: falta %%s. Copiá examples/ de Bouncer, o no uses make demo.' ;;
    selftest_no_fixtures) printf 'selftest no puede correr: falta %%s. Copiá examples/ de Bouncer, o no uses make selftest.' ;;
    demo_case_shell)    printf 'shellcheck: una variable sin comillas y sin definir' ;;
    demo_case_yaml)     printf 'yamllint: indentación inválida' ;;
    demo_case_docker)   printf 'hadolint: imagen base sin tag, sin limpieza de apt' ;;

    boot_brew)          printf '== instalando el toolchain con homebrew ==' ;;
    boot_apt)           printf '== instalando lo que trae apt (CAMINO NO PROBADO) ==' ;;
    boot_dnf)           printf '== instalando lo que trae dnf (CAMINO NO PROBADO) ==' ;;
    boot_already)       printf 'ya instalado' ;;
    boot_installing)    printf 'instalando...' ;;
    boot_tap)           printf 'instalando desde terraform-linters/tap...' ;;
    boot_hooks)         printf '== instalando los hooks de git ==' ;;
    boot_warming)       printf '== precalentando los entornos de pre-commit ==' ;;
    boot_still_missing) printf 'Todavía faltan estas, instalalas a mano:' ;;
    boot_missing_note)  printf 'El gate solo falla por una herramienta faltante cuando el repo tiene contenido que la necesita, así que un toolchain incompleto no es necesariamente un problema. Corré '"'"'make doctor'"'"' para ver cómo estás.' ;;
    boot_done)          printf 'bootstrap listo. Corré: make doctor' ;;
    boot_no_pm)         printf 'No se encontró un gestor de paquetes soportado (brew, apt-get, dnf).' ;;
    boot_no_pm_hint)    printf 'Instalá a mano las herramientas que lista '"'"'make doctor'"'"'.' ;;
    boot_from_project)  printf 'desde su propio proyecto' ;;

    lint_failed)        printf 'LINT FALLÓ: %%s' ;;
    stop_blocked)       printf '=== make verify FALLÓ (intento %%s/3): no se puede terminar el turno ===' ;;
    stop_released)      printf 'verify sigue fallando después de 3 intentos, se libera el gate' ;;
    *)                  printf '' ;;
  esac
}

# msg <key> [printf args...]
msg() {
  local key="$1"
  shift
  local fmt=""
  if [ "$BOUNCER_LANG_ACTIVE" = "es" ]; then
    fmt=$(msg_es "$key")
  fi
  if [ -z "$fmt" ]; then
    fmt=$(msg_en "$key")
  fi
  if [ -z "$fmt" ]; then
    # A missing key is a bug in the caller, not something to hide.
    printf '[missing message: %s]' "$key"
    return
  fi
  # The format string comes from the catalogue above, never from user input.
  # shellcheck disable=SC2059
  printf "$fmt" "$@"
}
