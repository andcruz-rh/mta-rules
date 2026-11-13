# .NET / .NET Core → OpenShift Cloud Readiness

Ruleset custom de **Red Hat MTA / Konveyor** (v1.1.0) que analiza aplicaciones **.NET Framework**, **.NET Core** y **.NET 5–10** y genera un **reporte de incidencias** a corregir **antes de contenerizar** y desplegar en **OpenShift / Kubernetes**.

Para instalación y comandos `mta-cli`, ver [`INSTALL.md`](INSTALL.md).

---

## Objetivo final

Dejar la aplicación en un estado **Twelve-Factor / cloud-ready** compatible con:

1. **Contenedores Linux** (baseline preferida: **.NET 10 LTS** / `net10.0`).
2. **OpenShift**: multi-réplica, no-root, configuración por variables de entorno, logs a `stdout`/`stderr`, apagado elegante ante `SIGTERM`.
3. **CI/CD reproducible**: secretos fuera del repo/imagen, sin dependencias Windows-only ni disco efímero del pod como store de negocio.

El ruleset **no genera el Dockerfile**. Su salida es un informe de violaciones (`dotnet-ocp-*`) para triage y remediación previa al empaquetado.

Estado objetivo típico tras remediación:

| Área | Target |
|------|--------|
| Runtime | .NET **10 LTS** (`net10.0`) en Linux; Kestrel (alternativa: `net8.0` LTS si el calendario de soporte aún aplica) |
| Imagen | Multi-stage `sdk:10.0` → `aspnet:10.0` / `runtime:10.0` (Chiseled / Alpine / slim) |
| Seguridad | `USER $APP_UID`, puerto **8080**, Secret/ConfigMap |
| Estado | Redis/DB compartidos; sin session/cache solo en memoria del proceso |
| Datos | Object storage o PVC explícito; nunca `C:\` ni FS local del contenedor |
| Observabilidad | Logs estructurados a consola + recolector del cluster |

---

## Versiones de .NET compatibles (análisis)

El análisis es por **contenido de fuentes** (`builtin.filecontent`: `.cs`, `.csproj`, `appsettings*.json`, `web.config`, etc.). No requiere compilar el proyecto.

| Plataforma | TFMs típicos | ¿Se analiza? | Notas |
|------------|--------------|--------------|--------|
| **.NET Framework** | `net40`–`net48` | Sí | `mandatory` → Windows containers o port a **net10.0** |
| **.NET Core** | `netcoreapp2.x`–`3.1` | Sí | `dotnet-ocp-tfm-00001` (fuera de soporte) |
| **.NET 5 / 6 / 7** | `net5.0`–`net7.0` | Sí | `dotnet-ocp-tfm-00001` (EOL para nueva baseline) |
| **.NET 8 LTS** | `net8.0` | Sí | Válido; aviso potencial de planificar **.NET 10** |
| **.NET 9 STS** | `net9.0` | Sí | `dotnet-ocp-tfm-00002` → preferir LTS |
| **.NET 10 LTS** | `net10.0` | Sí | **Baseline recomendada** para contenedores OpenShift |
| ASP.NET Classic (`System.Web`) | WebForms / MVC 5 | Sí | Acoplamiento IIS → migrar a ASP.NET Core |
| ASP.NET Core | Web / Minimal APIs / gRPC | Sí | Sessions, Kestrel, `IConfiguration`, workers |
| Worker Services / consolas | `Microsoft.NET.Sdk.Worker` | Sí | Process, logging, graceful shutdown |
| F# / VB.NET | `.fs`, `.vb` + proyectos | Parcial | Mismos patrones de texto; cobertura menor que C# |

**Target de contenedorización recomendado:** .NET **10 LTS** (`net10.0`) sobre imágenes Linux oficiales Microsoft (`mcr.microsoft.com/dotnet/*:10.0`).  
**.NET Framework 4.x** en producción contenedorizada implica **Windows containers**; el ruleset lo marca como bloqueante para el path Linux/OpenShift estándar.

---

## Qué evalúan las reglas

**32 reglas** en 8 grupos. Prefijo de IDs: `dotnet-ocp-`.

### 01 — Configuración y secretos (`01-config-secrets.yaml`)

| ruleID | Evalúa | Por qué importa al contenerizar |
|--------|--------|----------------------------------|
| `dotnet-ocp-sec-00001` | Passwords / API keys / connection strings en `appsettings*.json` | Secretos en imagen o git; usar Secret + env |
| `dotnet-ocp-sec-00002` | Literales `Password=` / `*Connection("...")` en código | Credenciales en el binario |
| `dotnet-ocp-cfg-00001` | `ConfigurationManager` / App.config Framework | Preferir `IConfiguration` + variables de entorno |
| `dotnet-ocp-cfg-00002` | Secretos o `localhost` en `appsettings.Development.json` | No debe viajar al publish/imagen (`.dockerignore`) |

### 02 — Sistema de archivos (`02-filesystem-paths.yaml`)

| ruleID | Evalúa | Por qué importa al contenerizar |
|--------|--------|----------------------------------|
| `dotnet-ocp-fs-00001` | Rutas Windows `C:\`, `D:\` | No existen en contenedores Linux |
| `dotnet-ocp-fs-00002` | `File.Write*`, `FileStream`, `Directory.CreateDirectory` | Disco del pod es efímero |
| `dotnet-ocp-fs-00003` | `Server.MapPath` / `HostingEnvironment.MapPath` | Acoplamiento IIS / `System.Web` |
| `dotnet-ocp-fs-00004` | `SpecialFolder` / `GetTempPath` como store | No es almacenamiento durable entre pods |

### 03 — Estado, sesiones y datos (`03-state-sessions-cache.yaml`)

| ruleID | Evalúa | Por qué importa al contenerizar |
|--------|--------|----------------------------------|
| `dotnet-ocp-sess-00001` | `AddSession` / `UseSession` | Sin store distribuido falla multi-réplica |
| `dotnet-ocp-cache-00001` | `AddDistributedMemoryCache` | Cache “distribuida” solo local al proceso |
| `dotnet-ocp-cache-00002` | `AddMemoryCache` / `IMemoryCache` | OK como L1; no como estado compartido |
| `dotnet-ocp-data-00001` | `UseSqlite` / LocalDB / `.db` embebido | Store local al nodo/pod, no cloud-ready |

### 04 — Logging (`04-logging-telemetry.yaml`)

| ruleID | Evalúa | Por qué importa al contenerizar |
|--------|--------|----------------------------------|
| `dotnet-ocp-log-00001` | Sinks a archivo (Serilog/NLog/log4net/MEL) | Logs se pierden con el pod |
| `dotnet-ocp-log-00002` | Windows Event Log | No aplica en Linux containers |
| `dotnet-ocp-log-00003` | `TextWriterTraceListener` y similares | Trace a disco no es Twelve-Factor |

### 05 — Red y hosting (`05-networking-hosting.yaml`)

| ruleID | Evalúa | Por qué importa al contenerizar |
|--------|--------|----------------------------------|
| `dotnet-ocp-net-00001` | `localhost` / `127.0.0.1` hacia DB/APIs | Dentro del pod no es el Service del cluster |
| `dotnet-ocp-net-00002` | Binding puerto 80 / `UseUrls` fijo | No-root → puerto **8080**; Route/Service delante |
| `dotnet-ocp-host-00001` | IIS, `System.Web`, `web.config` | Modelo de hosting distinto a Kestrel en Linux |
| `dotnet-ocp-host-00002` | PFX / certs de desarrollo Kestrel | TLS en Route/Ingress; no embeber certs de dev |

### 06 — Windows y .NET Framework (`06-windows-framework.yaml`)

| ruleID | Evalúa | Por qué importa al contenerizar |
|--------|--------|----------------------------------|
| `dotnet-ocp-win-00001` | `TargetFramework` net4x / net48 | Bloquea path Linux; exige Windows containers o port |
| `dotnet-ocp-win-00002` | Registry, WMI, Named Pipes | APIs ausentes en Linux |
| `dotnet-ocp-win-00003` | `System.Drawing` / GDI+ | Frágil/roto fuera de Windows / imágenes mínimas |
| `dotnet-ocp-win-00004` | `DllImport` / COM Interop Windows | Binarios `.dll`/COM no portan a Linux |
| `dotnet-ocp-win-00005` | Negotiate / NTLM / Windows Auth | Sustituir o diseñar OIDC / Kerberos explícito |

### 07 — Proceso y runtime (`07-process-runtime.yaml`)

| ruleID | Evalúa | Por qué importa al contenerizar |
|--------|--------|----------------------------------|
| `dotnet-ocp-rt-00001` | `Process.Start`, `cmd.exe`, shell | Choca con SCC, Chiseled (sin shell) y 1 proceso/contenedor |
| `dotnet-ocp-rt-00002` | `HttpContext.Current` | Modelo legacy; problemático con async |
| `dotnet-ocp-rt-00003` | `Environment.Exit` / `FailFast` | Evita graceful shutdown ante `SIGTERM` |
| `dotnet-ocp-rt-00004` | `Directory.GetCurrentDirectory` | CWD poco fiable como content root en containers |
| `dotnet-ocp-rt-00005` | `BackgroundService` / `IHostedService` | Revisar cancelación limpia al parar el pod |

### 08 — Target Framework / runtime (`08-tfm-runtime.yaml`)

| ruleID | Evalúa | Por qué importa al contenerizar |
|--------|--------|----------------------------------|
| `dotnet-ocp-tfm-00001` | `netcoreapp2/3`, `net5.0`–`net7.0` | TFM sin soporte adecuado para nueva imagen Linux |
| `dotnet-ocp-tfm-00002` | `net9.0` (STS) | Preferir **net10.0 LTS** en producción |
| `dotnet-ocp-tfm-00003` | `net8.0` | Aviso: evaluar upgrade a **net10.0** al crear el Dockerfile |

`net10.0` **no** dispara reglas de upgrade TFM: es el target deseado.

---

## Categorías y esfuerzo

- **`mandatory`**: bloquea o degrada seriamente el despliegue multi-réplica / Linux / OpenShift.
- **`potential`**: requiere triage; a menudo correcto en dev o aceptable con mitigación documentada.
- **`effort`**: estimación relativa Konveyor (1 = bajo, 7+ = migración estructural, p. ej. salir de net48).

---

## Flujo recomendado

```text
Código .NET ──► mta-cli + este ruleset ──► reporte dotnet-ocp-*
                                              │
                                              ▼
                                    Triage P0 / P1 / P2
                                              │
                                              ▼
                         Remediación (config, estado, Windows APIs, logs…)
                                              │
                                              ▼
                    Dockerfile multi-stage + OpenShift (Deployment/Route/Secret)
```

Calibración sin app real:

```bash
./bin/analyze-dotnet.sh --input ./fixture --output /tmp/mta-dotnet-fixture
rg 'dotnet-ocp-' /tmp/mta-dotnet-fixture/output.yaml
```

---

## Limitaciones

- Detección por **regex**, no AST/.NET LSP → posibles falsos positivos/negativos.
- No sustituye diseño de dominio, sizing, probes, NetworkPolicies ni revisión de SCC.
- En MTA 8.0 el provider `.NET` nativo no cubre este modo; el wrapper usa `--provider java` solo para habilitar `builtin` (detalle en `INSTALL.md`).

---

## Referencias

- [INSTALL.md](INSTALL.md) — instalación, `mta-cli`, fixture esperado
- [Konveyor analyzer rules](https://github.com/konveyor/analyzer-lsp/blob/main/docs/rules.md)
- [MTA — Configuring and using rules](https://docs.redhat.com/en/documentation/migration_toolkit_for_applications/8.1/html/configuring_and_using_rules_for_an_mta_analysis/rules-introduction_rules-development-guide)
- [Containerize a .NET app](https://learn.microsoft.com/en-us/dotnet/core/docker/introduction)
