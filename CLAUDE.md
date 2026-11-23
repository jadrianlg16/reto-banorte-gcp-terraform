# Reglas del proyecto para Claude Code

Proyecto integrador TC3003B (Equipo 2, socio formador Banorte): landing zone de Google Cloud en
Terraform. Todo el proyecto está en `gcp-datacenter/`; el pipeline en `.github/workflows/`. Las
carpetas `labs/` y `entregas/` son de fases anteriores.

## Antes de trabajar

- Lee `gcp-datacenter/README.md` y, si vas a desplegar o probar en GCP,
  `gcp-datacenter/docs/guia-colaborador-gcp.md` (guía paso a paso y prompt de arranque).
- `gcp-datacenter/docs/pendientes-apply.md` lista lo que solo un despliegue real confirma;
  `gcp-datacenter/docs/backlog.md`, lo que falta para terminar el proyecto.
- Las reglas de construcción (estilo, pruebas, marcadores `VERIFICAR-EN-APPLY`, documentación)
  están en `gcp-datacenter/docs/CONTRATO.md`.

## Reglas

- El repositorio es **privado** y se queda así. Nunca subas `terraform.tfvars`, estados,
  llaves, el JSON de `GCP_TFVARS_JSON` ni credenciales; revisa `git status` antes de cada commit.
  La carpeta `docs/` de la raíz y `labs/README.md` son locales y confidenciales: no las abras ni
  las copies.
- Cualquier cambio en GCP o en GitHub (apply, destroy, IAM, variables, lanzar flujos) se muestra
  primero con su costo y su efecto, y espera el sí de la persona. Contraseñas, códigos de
  verificación y pasos de consola los hace la persona.
- Nada directo a `main`: rama `fix/<tema>` o `verif/<fecha>` y PR. Integrar a `main` dispara
  `apply.yml`.
- Las etapas 1 a 5 solo las aplica el pipeline (cuentas de servicio por WIF). Las personas tienen
  solo lectura; la etapa 0 es la única manual (runbook 01).
- Afirmaciones sobre GCP o GitHub solo con fuente oficial o comprobadas; lo demás se marca
  HYPOTHESIS. Cada punto comprobado de `pendientes-apply.md` lleva "Verificado el AAAA-MM-DD con
  `<comando>`: <resultado>" o "Falló el ...".
- Documentación en español, como la existente. Sin valores de una máquina en particular (rutas,
  IPs, puertos) en el código.
- Antes de proponer un cambio de código, corre desde `gcp-datacenter/`: `bash scripts/check.sh`,
  `bash scripts/policy-check.sh`, `bash scripts/selftest.sh` y `bash scripts/docs.sh --check`
  (Terraform 1.16.5; un timeout del registro se reintenta).
