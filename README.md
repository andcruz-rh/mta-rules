# MTA / Konveyor — Custom rulesets (cloud readiness)

Repositorio de **rulesets custom** para [Red Hat Migration Toolkit for Applications (MTA)](https://developers.redhat.com/products/mta/overview) / [Konveyor](https://www.konveyor.io/) orientados a **cloud-readiness** y **OpenShift**: detectan anti-patrones que deben corregirse **antes de contenerizar** una aplicación.

| Campo | Valor |
|-------|-------|
| Herramienta | `mta-cli` 8.x (containerless / `--run-local=true`) |
| Target | `cloud-readiness`, `openshift`, `containers` |
| Condiciones | principalmente `builtin.filecontent` |

## Rulesets incluidos

| Paquete | Stack | Versión | Qué evalúa |
|---------|-------|---------|------------|
| [`dotnet-openshift-cloud-readiness/`](dotnet-openshift-cloud-readiness/) | .NET Framework / .NET Core / **.NET 5–10** | 1.1.0 | Secretos, FS local, session/cache in-memory, logs a archivo, IIS/Windows APIs, `localhost`, TFMs EOL vs **net10.0** LTS |
| [`php-laravel-openshift-cloud-readiness/`](php-laravel-openshift-cloud-readiness/) | PHP / Laravel | 1.0.0 | Sessions/cache/queue en file/sync, disco local, `.env`/secretos, DB localhost, logging a archivo, scheduler, `exec()` |

Cada paquete contiene:

```text
<ruleset>/
├── README.md      # objetivo y catálogo de reglas (si aplica)
├── INSTALL.md     # instalación y uso con mta-cli
├── bin/           # wrapper analyze-*.sh
└── rules/         # YAML Konveyor/MTA (--rules)
```

Los directorios `fixture/` y los tarballs `*.tar.gz` **no** se versionan (solo calibración/distribución local).

## Uso rápido

```bash
# .NET
./dotnet-openshift-cloud-readiness/bin/analyze-dotnet.sh \
  --input /ruta/a/tu-app-dotnet \
  --output /tmp/mta-dotnet-out

# Laravel
./php-laravel-openshift-cloud-readiness/bin/analyze-laravel.sh \
  --input /ruta/a/tu-app-laravel \
  --output /tmp/mta-laravel-out

# Inspeccionar violaciones
rg 'dotnet-ocp-|laravel-ocp-' /tmp/mta-*-out/output.yaml
```

Detalle de flags (`--provider java`, label-selector, etc.): ver el `INSTALL.md` de cada paquete.

## Objetivo

Generar un **reporte de incidencias** accionable para triage (P0/P1/P2) hacia un despliegue Twelve-Factor en OpenShift: configuración por entorno, sin estado local al pod, logs a `stdout`/`stderr`, runtime Linux contenedorizado y sin acoplamientos Windows/IIS o disco efímero como store de negocio.

## Requisitos

- `mta-cli` 8.x en el `PATH` (`mta-cli version`)
- Análisis source-only; no sustituye Dockerfile, probes ni diseño de dominio

## Añadir un ruleset nuevo

1. Crear `<nombre>-cloud-readiness/{rules,bin}` + `INSTALL.md` (+ `README.md`).
2. Actualizar este README (tabla de paquetes).
3. Extender [`.gitignore`](.gitignore) con el mismo patrón allowlist (`rules/`, `bin/`, `README.md`, `INSTALL.md`).
