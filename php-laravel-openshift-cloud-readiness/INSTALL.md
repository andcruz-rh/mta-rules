# PHP Laravel → OpenShift cloud-readiness (MTA 8.x)

Ruleset custom para **Migration Toolkit for Applications 8.x** (`mta-cli`) que detecta anti-patrones Laravel incompatibles con **OpenShift + contenedores**.

| Campo | Valor |
|-------|-------|
| Versión | 1.0.0 |
| Validado con | `mta-cli` **8.0.0** |
| Source | PHP / Laravel |
| Target | `cloud-readiness`, `openshift` |
| Condiciones | `builtin.filecontent` / `builtin.file` |

## Contenido del paquete

```text
php-laravel-openshift-cloud-readiness/
├── INSTALL.md
├── VERSION
├── bin/analyze-laravel.sh     # wrapper recomendado para mta-cli
├── rules/                     # ← directorio para --rules
│   ├── ruleset.yaml
│   ├── 01-sessions-cache-queue.yaml
│   ├── 02-filesystem-storage.yaml
│   ├── 03-env-secrets-db.yaml
│   ├── 04-logging-scheduler.yaml
│   └── 05-runtime-shell.yaml
└── fixture/                   # app sintética para calibrar (sin repo piloto)
```

## Requisitos

- MTA 8.x CLI (`mta-cli` en el `PATH`)
- Para el modo validado aquí: análisis **containerless** (`--run-local=true`, default en 8.0)

```bash
mta-cli version
```

## Instalación

### 1. Extraer el tarball

```bash
mkdir -p "$HOME/mta-custom-rules"
tar -xzf php-laravel-openshift-cloud-readiness-1.0.0.tar.gz -C "$HOME/mta-custom-rules"
chmod +x "$HOME/mta-custom-rules/php-laravel-openshift-cloud-readiness/bin/analyze-laravel.sh"
```

### 2. (Opcional) Ubicación compartida

```bash
sudo mkdir -p /opt/mta/custom-rules
sudo tar -xzf php-laravel-openshift-cloud-readiness-1.0.0.tar.gz -C /opt/mta/custom-rules
sudo chmod +x /opt/mta/custom-rules/php-laravel-openshift-cloud-readiness/bin/analyze-laravel.sh
```

No hay registro en un catálogo: el ruleset se carga con `--rules` en cada análisis.

## Uso (importante para PHP en MTA 8.0)

**Hallazgo de producto:** `mta-cli` detecta PHP pero **no tiene provider PHP**. Sin flags extra falla con:

```text
Error: provider php not supported. Use --providerOverride or --provider option
```

**Workaround validado (8.0.0):** forzar `--provider java` en modo containerless. El provider `builtin` sigue activo y evalúa las reglas `filecontent` sobre `.php` / `.env`.

### Opción A — script incluido (recomendado)

```bash
PKG="$HOME/mta-custom-rules/php-laravel-openshift-cloud-readiness"

# Calibración con fixture (sin repo piloto)
"$PKG/bin/analyze-laravel.sh" \
  --input "$PKG/fixture" \
  --output /tmp/mta-laravel-fixture

# App Laravel real
"$PKG/bin/analyze-laravel.sh" \
  --input /ruta/a/tu-app-laravel \
  --output /tmp/mta-laravel-app
```

### Opción B — comando manual

```bash
RULES="$HOME/mta-custom-rules/php-laravel-openshift-cloud-readiness/rules"
APP="/ruta/a/tu-app-laravel"
OUT="/tmp/mta-laravel-out"

mta-cli analyze \
  --input "$APP" \
  --output "$OUT" \
  --mode source-only \
  --provider java \
  --run-local=true \
  --rules "$RULES" \
  --enable-default-rulesets=false \
  --label-selector "(konveyor.io/source=laravel)" \
  --overwrite
```

### Ver el reporte

```bash
xdg-open /tmp/mta-laravel-fixture/static-report/index.html
# o inspeccionar YAML:
rg 'laravel-ocp-' /tmp/mta-laravel-fixture/output.yaml
```

### Resultado esperado en el fixture

Deben aparecer (al menos) estas violaciones:

| ruleID | Tema |
|--------|------|
| `laravel-ocp-sess-00001` | `SESSION_DRIVER=file` |
| `laravel-ocp-cache-00001` | `CACHE_DRIVER=file` |
| `laravel-ocp-queue-00001` | `QUEUE_CONNECTION=sync` |
| `laravel-ocp-fs-00001` | `FILESYSTEM_DISK=local` |
| `laravel-ocp-fs-00002` | write a `storage_path` |
| `laravel-ocp-sec-00001` | secretos en `.env` |
| `laravel-ocp-net-00001` | `DB_HOST`/`REDIS_HOST` localhost |
| `laravel-ocp-cfg-00001` | defaults en `.env.example` |
| `laravel-ocp-log-00001` | `LOG_CHANNEL=daily` |
| `laravel-ocp-sched-00001` | scheduler |
| `laravel-ocp-rt-00001` | `exec()` |

## Triage → remediación OpenShift

| Prioridad | Acción típica |
|-----------|----------------|
| P0 | `SESSION_DRIVER=redis`, `DB_HOST=<Service DNS>`, secrets vía OpenShift Secret |
| P0 | Uploads → disco S3-compatible; no depender del FS del pod |
| P1 | `CACHE_DRIVER=redis`, `LOG_CHANNEL=stderr`, Deployment `queue:work` |
| P1 | CronJob para `php artisan schedule:run` |
| P2 | Revisar `exec`, defaults de `.env.example` |

## Limitaciones

- No hay AST/LSP PHP: reglas basadas en **regex** → falsos positivos/negativos.
- `--provider java` es un **workaround operativo** para habilitar `builtin` en apps PHP; no implica análisis semántico Java de tu código Laravel.
- `--enable-default-rulesets=false` evita ruido de rulesets Java por defecto.
- No sustituye diseño de dominio, Dockerfile, probes ni sizing de Redis/DB.

## Desinstalación

```bash
rm -rf "$HOME/mta-custom-rules/php-laravel-openshift-cloud-readiness"
```

## Referencias

- [MTA 8.x — Configuring and using rules](https://docs.redhat.com/en/documentation/migration_toolkit_for_applications/8.1/html/configuring_and_using_rules_for_an_mta_analysis/rules-introduction_rules-development-guide)
- [Analyzing non-Java applications (CLI)](https://docs.redhat.com/en/documentation/migration_toolkit_for_applications/8.1/html/using_the_migration_toolkit_for_applications_command_line_interface/analyzing-nonjava-applications_cli-guide)
- [Konveyor analyzer rules](https://github.com/konveyor/analyzer-lsp/blob/main/docs/rules.md)
