# .NET / .NET Core → OpenShift cloud-readiness (MTA 8.x)

Ruleset custom para **Migration Toolkit for Applications 8.x** (`mta-cli`) / **Konveyor** que detecta anti-patrones **.NET Framework / .NET Core / ASP.NET Core / .NET 5–10** que deben corregirse **antes de contenerizar** y desplegar en **OpenShift**.

**Baseline de contenedor recomendada:** `.NET 10 LTS` (`net10.0`) + imágenes `mcr.microsoft.com/dotnet/*:10.0`.

Para objetivo, matriz TFM (incl. .NET 10) y detalle de cada regla, ver [`README.md`](README.md).

| Campo | Valor |
|-------|-------|
| Versión | 1.1.0 |
| Validado con | `mta-cli` **8.0.0** (mismo patrón operativo que el ruleset Laravel) |
| Source | `dotnet`, `dotnetcore`, `dotnet10` |
| Target | `cloud-readiness`, `openshift`, `containers` |
| TFMs analizados | `net4x`, `netcoreapp2/3`, `net5.0`–`net10.0` |
| Condiciones | `builtin.filecontent` / `builtin.file` |

## Contenido del paquete

```text
dotnet-openshift-cloud-readiness/
├── README.md                  # objetivo, TFMs (.NET 10) y catálogo de reglas
├── INSTALL.md
├── VERSION
├── bin/analyze-dotnet.sh      # wrapper recomendado para mta-cli
├── rules/                     # ← directorio para --rules
│   ├── ruleset.yaml
│   ├── 01-config-secrets.yaml
│   ├── 02-filesystem-paths.yaml
│   ├── 03-state-sessions-cache.yaml
│   ├── 04-logging-telemetry.yaml
│   ├── 05-networking-hosting.yaml
│   ├── 06-windows-framework.yaml
│   ├── 07-process-runtime.yaml
│   └── 08-tfm-runtime.yaml    # TFMs EOL/STS vs net10.0 LTS
└── fixture/                   # app sintética para calibrar (sin repo piloto)
    ├── src/
    └── tfm-samples/           # net6 / net9 / net10
```

## Qué detecta (mapa de incidencias)

| Archivo | Enfoque pre-contenedor |
|---------|------------------------|
| `01-config-secrets` | Secretos en `appsettings`, connection strings en código, `ConfigurationManager` |
| `02-filesystem-paths` | `C:\…`, `File.Write*`, `Server.MapPath`, SpecialFolder/Temp como store |
| `03-state-sessions-cache` | Session/cache in-memory, SQLite/LocalDB como store “prod” |
| `04-logging-telemetry` | Sinks a archivo, Windows Event Log, Trace listeners a disco |
| `05-networking-hosting` | `localhost`, puerto 80, IIS/`System.Web`, PFX de desarrollo |
| `06-windows-framework` | `net4x`, Registry/WMI, `System.Drawing`, P/Invoke/COM, Negotiate |
| `07-process-runtime` | `Process.Start`, `HttpContext.Current`, `Environment.Exit`, CWD, HostedService |
| `08-tfm-runtime` | TFMs EOL (`net6`…), STS (`net9`), aviso `net8` → preferir **net10.0** |

## Requisitos

- MTA 8.x CLI (`mta-cli` en el `PATH`)
- Análisis **containerless** (`--run-local=true`, default en 8.0)

```bash
mta-cli version
```

## Instalación

### 1. Extraer el tarball

```bash
mkdir -p "$HOME/mta-custom-rules"
tar -xzf dotnet-openshift-cloud-readiness-1.1.0.tar.gz -C "$HOME/mta-custom-rules"
chmod +x "$HOME/mta-custom-rules/dotnet-openshift-cloud-readiness/bin/analyze-dotnet.sh"
```

### 2. (Opcional) Ubicación compartida

```bash
sudo mkdir -p /opt/mta/custom-rules
sudo tar -xzf dotnet-openshift-cloud-readiness-1.1.0.tar.gz -C /opt/mta/custom-rules
sudo chmod +x /opt/mta/custom-rules/dotnet-openshift-cloud-readiness/bin/analyze-dotnet.sh
```

No hay registro en un catálogo: el ruleset se carga con `--rules` en cada análisis.

## Uso (importante para .NET en MTA 8.0)

**Hallazgo de producto:** `mta-cli` 8.0 **no expone un provider .NET** equivalente al de Java para estas reglas. Sin flags extra puede fallar por provider no soportado.

**Workaround validado (mismo patrón que PHP/Laravel):** forzar `--provider java` en modo containerless. El provider `builtin` sigue activo y evalúa las reglas `filecontent` sobre `.cs`, `.csproj`, `appsettings*.json`, `web.config`, etc.

### Opción A — script incluido (recomendado)

```bash
PKG="$HOME/mta-custom-rules/dotnet-openshift-cloud-readiness"

# Calibración con fixture (sin repo piloto)
"$PKG/bin/analyze-dotnet.sh" \
  --input "$PKG/fixture" \
  --output /tmp/mta-dotnet-fixture

# App .NET real
"$PKG/bin/analyze-dotnet.sh" \
  --input /ruta/a/tu-app-dotnet \
  --output /tmp/mta-dotnet-app
```

### Opción B — comando manual

```bash
RULES="$HOME/mta-custom-rules/dotnet-openshift-cloud-readiness/rules"
APP="/ruta/a/tu-app-dotnet"
OUT="/tmp/mta-dotnet-out"

mta-cli analyze \
  --input "$APP" \
  --output "$OUT" \
  --mode source-only \
  --provider java \
  --run-local=true \
  --rules "$RULES" \
  --enable-default-rulesets=false \
  --label-selector "(konveyor.io/source=dotnet)" \
  --overwrite
```

### Ver el reporte

```bash
xdg-open /tmp/mta-dotnet-fixture/static-report/index.html
# o inspeccionar YAML:
rg 'dotnet-ocp-' /tmp/mta-dotnet-fixture/output.yaml
```

### Resultado esperado en el fixture

Deben aparecer (al menos) estas violaciones:

| ruleID | Tema |
|--------|------|
| `dotnet-ocp-sec-00001` | secretos / passwords en `appsettings` |
| `dotnet-ocp-sec-00002` | connection string hardcodeada en C# |
| `dotnet-ocp-cfg-00001` | `ConfigurationManager` |
| `dotnet-ocp-cfg-00002` | secretos/localhost en `appsettings.Development.json` |
| `dotnet-ocp-fs-00001` | ruta `C:\…` |
| `dotnet-ocp-fs-00002` | `File.Write*` / `Directory.CreateDirectory` |
| `dotnet-ocp-fs-00003` | `Server.MapPath` / `HttpContext.Current` |
| `dotnet-ocp-sess-00001` | `AddSession` / `UseSession` |
| `dotnet-ocp-cache-00001` | `AddDistributedMemoryCache` |
| `dotnet-ocp-cache-00002` | `AddMemoryCache` / `IMemoryCache` |
| `dotnet-ocp-data-00001` | `UseSqlite` |
| `dotnet-ocp-log-00001` | logging a archivo (Serilog `WriteTo.File`) |
| `dotnet-ocp-log-00002` | Windows Event Log |
| `dotnet-ocp-log-00003` | `TextWriterTraceListener` |
| `dotnet-ocp-net-00001` | `localhost` / `127.0.0.1` |
| `dotnet-ocp-net-00002` | binding puerto `80` |
| `dotnet-ocp-host-00001` | IIS / `System.Web` / `web.config` |
| `dotnet-ocp-host-00002` | certificados HTTPS de desarrollo |
| `dotnet-ocp-win-00001` | `TargetFramework` net48 |
| `dotnet-ocp-win-00002` | Registry / WMI |
| `dotnet-ocp-win-00003` | `System.Drawing` |
| `dotnet-ocp-win-00004` | `DllImport` / `ComImport` |
| `dotnet-ocp-win-00005` | Windows Authentication / Negotiate |
| `dotnet-ocp-rt-00001` | `Process.Start` / `cmd.exe` |
| `dotnet-ocp-rt-00002` | `HttpContext.Current` |
| `dotnet-ocp-rt-00003` | `Environment.Exit` |
| `dotnet-ocp-rt-00004` | `Directory.GetCurrentDirectory` |
| `dotnet-ocp-rt-00005` | `BackgroundService` / `AddHostedService` |
| `dotnet-ocp-tfm-00001` | TFM EOL (`net6.0` en `fixture/tfm-samples`) |
| `dotnet-ocp-tfm-00002` | TFM STS (`net9.0` en `fixture/tfm-samples`) |
| *(sin hit TFM)* | `CurrentNet10.csproj` (`net10.0`) y `tfm-00003` (solo `net8.0`) |

## Triage → remediación pre-Docker / OpenShift

| Prioridad | Acción típica |
|-----------|----------------|
| P0 | Portar `net4x` / TFMs EOL → **.NET 10 LTS** (`net10.0`) en Linux; eliminar Registry/WMI/GDI+/COM |
| P0 | Secretos fuera del repo: OpenShift **Secret** + `IConfiguration` / env (`ConnectionStrings__*`) |
| P0 | Sustituir disco local y `C:\` por object storage o PVC; listening en **8080** no-root |
| P0 | DB/Redis por **Service DNS** (nunca `localhost` dentro del pod) |
| P1 | Session/cache → **Redis**; logs → **stdout/stderr** estructurado |
| P1 | Hosting **Kestrel** (imagen `mcr.microsoft.com/dotnet/aspnet:10.0` Chiseled/Alpine/slim) |
| P1 | TLS en Route/Ingress; no PFX de desarrollo en la imagen |
| P2 | `net8.0`/`net9.0` → planificar **net10.0**; `Process.Start` → Job/Worker; graceful shutdown |
| P2 | Auth: OIDC (Keycloak/RH-SSO) en lugar de Negotiate puro |

### Checklist Docker (post-remediación)

- Multi-stage: `sdk:10.0` → `aspnet:10.0` / `runtime:10.0` (o `runtime-deps` si Native AOT)
- `.dockerignore`: `**/bin/`, `**/obj/`, `**/.vs/`, `appsettings.*.Development.json`
- `USER $APP_UID`, `ASPNETCORE_HTTP_PORTS=8080`
- Chiseled: sin `curl` en imagen; healthcheck en orquestador o endpoint de la app
- `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT` o tag `-extra` si necesitas ICU/tzdata

## Limitaciones

- No hay AST/LSP .NET en este modo: reglas basadas en **regex** → falsos positivos/negativos.
- `--provider java` es un **workaround operativo** para habilitar `builtin`; no implica análisis semántico Java de tu código .NET.
- `--enable-default-rulesets=false` evita ruido de rulesets Java por defecto.
- No sustituye diseño de dominio, Dockerfile, probes, sizing de Redis/DB ni revisión de SCC.

## Desinstalación

```bash
rm -rf "$HOME/mta-custom-rules/dotnet-openshift-cloud-readiness"
```

## Referencias

- [MTA 8.x — Configuring and using rules](https://docs.redhat.com/en/documentation/migration_toolkit_for_applications/8.1/html/configuring_and_using_rules_for_an_mta_analysis/rules-introduction_rules-development-guide)
- [Analyzing non-Java applications (CLI)](https://docs.redhat.com/en/documentation/migration_toolkit_for_applications/8.1/html/using_the_migration_toolkit_for_applications_command_line_interface/analyzing-nonjava-applications_cli-guide)
- [Konveyor analyzer rules](https://github.com/konveyor/analyzer-lsp/blob/main/docs/rules.md)
- [Containerize a .NET app](https://learn.microsoft.com/en-us/dotnet/core/docker/introduction)
