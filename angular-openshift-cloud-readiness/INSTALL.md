# Angular (SPA / SSR) → OpenShift cloud-readiness (MTA 8.x)

Ruleset custom para **Migration Toolkit for Applications 8.x** (`mta-cli`) / **Konveyor** que detecta anti-patrones **Angular** (SPA y SSR) que deben corregirse **antes de contenerizar** y desplegar en **OpenShift**.

**Baselines de contenedor recomendadas:**

- **SPA:** multi-stage `node:<lts>-alpine` → `nginxinc/nginx-unprivileged:alpine` (:8080)
- **SSR:** `node:<lts>-alpine` no-root, `node dist/<app>/server/server.mjs`, `PORT=8080`

Para objetivo, matriz de versiones y detalle de cada regla, ver [`README.md`](README.md).

| Campo | Valor |
|-------|-------|
| Versión | 1.1.0 |
| Validado con | `mta-cli` **8.0.0** (mismo patrón operativo que .NET / Laravel) |
| Source | `angular`, `typescript`, `javascript` |
| Target | `cloud-readiness`, `openshift`, `containers` |
| Condiciones | `builtin.filecontent` / `builtin.file` |

## Contenido del paquete

```text
angular-openshift-cloud-readiness/
├── README.md                  # objetivo, versiones Angular y catálogo de reglas
├── INSTALL.md
├── VERSION
├── bin/analyze-angular.sh     # wrapper recomendado para mta-cli
├── rules/                     # ← directorio para --rules
│   ├── ruleset.yaml
│   ├── 01-config-secrets.yaml
│   ├── 02-networking-endpoints.yaml
│   ├── 03-runtime-config.yaml
│   ├── 04-ssr-nodejs.yaml
│   ├── 05-browser-platform.yaml
│   └── 06-version-toolchain.yaml
└── fixture/                   # app sintética para calibrar (sin repo piloto)
    ├── src/
    └── version-samples/       # angular18 / angular20
```

## Qué detecta (mapa de incidencias)

| Archivo | Enfoque pre-contenedor |
|---------|------------------------|
| `01-config-secrets` | Secretos en `environment*.ts` y literales en `.ts`/`.js` |
| `02-networking-endpoints` | `localhost`, `proxy.conf`, `apiUrl` absolutos, `baseUrl` en services |
| `03-runtime-config` | `fileReplacements`, config solo compile-time, `process.env` cliente |
| `04-ssr-nodejs` | FS local, puerto 80, shell, `process.exit`, logs a archivo |
| `05-browser-platform` | `window`/`document`, tokens en `localStorage`, Service Worker |
| `06-version-toolchain` | Angular ≤16 / 17–18, `engines.node`, builder legacy |

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
tar -xzf angular-openshift-cloud-readiness-1.1.0.tar.gz -C "$HOME/mta-custom-rules"
chmod +x "$HOME/mta-custom-rules/angular-openshift-cloud-readiness/bin/analyze-angular.sh"
```

### 2. (Opcional) Ubicación compartida

```bash
sudo mkdir -p /opt/mta/custom-rules
sudo tar -xzf angular-openshift-cloud-readiness-1.1.0.tar.gz -C /opt/mta/custom-rules
sudo chmod +x /opt/mta/custom-rules/angular-openshift-cloud-readiness/bin/analyze-angular.sh
```

No hay registro en un catálogo: el ruleset se carga con `--rules` en cada análisis.

## Uso (importante para Angular/TS en MTA 8.0)

**Hallazgo de producto:** `mta-cli` 8.0 **no expone un provider Angular/TypeScript** equivalente al de Java para estas reglas. Sin flags extra puede fallar por provider no soportado.

**Workaround validado (mismo patrón que PHP/Laravel y .NET):** forzar `--provider java` en modo containerless. El provider `builtin` sigue activo y evalúa las reglas `filecontent` sobre `.ts`, `.js`, `angular.json`, `package.json`, `environment*.ts`, `server.ts`, etc.

### Opción A — script incluido (recomendado)

```bash
PKG="$HOME/mta-custom-rules/angular-openshift-cloud-readiness"

# Calibración con fixture (sin repo piloto)
"$PKG/bin/analyze-angular.sh" \
  --input "$PKG/fixture" \
  --output /tmp/mta-angular-fixture

# App Angular real
"$PKG/bin/analyze-angular.sh" \
  --input /ruta/a/tu-app-angular \
  --output /tmp/mta-angular-app
```

### Opción B — comando manual

```bash
RULES="$HOME/mta-custom-rules/angular-openshift-cloud-readiness/rules"
APP="/ruta/a/tu-app-angular"
OUT="/tmp/mta-angular-out"

mta-cli analyze \
  --input "$APP" \
  --output "$OUT" \
  --mode source-only \
  --provider java \
  --run-local=true \
  --rules "$RULES" \
  --enable-default-rulesets=false \
  --label-selector "(konveyor.io/source=angular)" \
  --overwrite
```

### Ver el reporte

```bash
xdg-open /tmp/mta-angular-fixture/static-report/index.html
# o inspeccionar YAML:
rg 'angular-ocp-' /tmp/mta-angular-fixture/output.yaml
```

### Resultado esperado en el fixture

Deben aparecer (al menos) estas violaciones:

| ruleID | Tema |
|--------|------|
| `angular-ocp-sec-00001` | secretos / apiKey en `environment*.ts` |
| `angular-ocp-sec-00002` | secreto hardcodeado en `api.service.ts` |
| `angular-ocp-cfg-00001` | secretos/localhost en `environment.development.ts` |
| `angular-ocp-net-00001` | `localhost` / `127.0.0.1` |
| `angular-ocp-net-00002` | `proxy.conf.json` → localhost |
| `angular-ocp-net-00003` | `apiUrl` absoluto en environments |
| `angular-ocp-net-00004` | `const baseUrl = 'http://…'` en services |
| `angular-ocp-cfg-00002` | `fileReplacements` en `angular.json` |
| `angular-ocp-cfg-00003` | `production: true` en `environment.prod.ts` |
| `angular-ocp-cfg-00004` | `process.env` en código cliente |
| `angular-ocp-ssr-00001` | `writeFileSync` / `mkdirSync` en `server.ts` |
| `angular-ocp-ssr-00002` | `listen` puerto `80` |
| `angular-ocp-ssr-00003` | `child_process` / `execSync` |
| `angular-ocp-ssr-00004` | `process.exit` |
| `angular-ocp-ssr-00005` | Winston File transport |
| `angular-ocp-dom-00001` | `window.localStorage` / `document.cookie` |
| `angular-ocp-state-00001` | token en `localStorage` |
| `angular-ocp-sw-00001` | `@angular/service-worker` / `ngsw` |
| `angular-ocp-ver-00001` | `@angular/core` 16 (EOL) |
| `angular-ocp-ver-00002` | `@angular/core` 18 en `version-samples` |
| `angular-ocp-ver-00003` | `engines.node` ^16 |
| `angular-ocp-build-00001` | builder `browser` / `outputPath` |
| *(sin hit ver upgrade)* | `version-samples/angular20` (`^20.1.0`) |

## Triage → remediación pre-Docker / OpenShift

| Prioridad | Acción típica |
|-----------|----------------|
| P0 | Upgrade Angular ≤16 → **19+**; alinear Node LTS en `engines` y Dockerfile |
| P0 | Secretos fuera del repo: OpenShift **Secret** + config runtime (`config.json` / `envsubst`) |
| P0 | Eliminar `localhost` bakeado; API relativa o host vía ConfigMap |
| P0 | SSR: puerto **8080**, sin escritura a FS local, logs a stdout |
| P1 | Sustituir `fileReplacements` por config runtime (Build Once Deploy Anywhere) |
| P1 | SPA: nginx-unprivileged, `try_files` → `/index.html`, cache diferenciada |
| P1 | Guardas `isPlatformBrowser` si hay SSR; revisar Service Worker vs rollouts |
| P2 | Tokens: flujo OIDC/BFF + cookies HttpOnly; planificar 17/18 → 19+ |

### Checklist Docker (post-remediación)

**SPA**

```bash
# build
docker build -t my-angular:1.0.0 .
# run (nginx-unprivileged escucha en 8080)
docker run --rm -p 8080:8080 -e API_URL=https://api.example.com my-angular:1.0.0
```

- Multi-stage: `node:<lts>-alpine` (`npm ci` / `pnpm install --frozen-lockfile`) → `nginxinc/nginx-unprivileged:alpine`
- Copiar `dist/<project>/browser` (Angular 17+ `application` builder) o `dist/<project>` (builder legacy)
- `.dockerignore`: `node_modules/`, `dist/`, `.angular/`, `.git/`, `coverage/`, `*.log`, `.env*`
- `nginx.conf`: `try_files $uri $uri/ /index.html;`; `Cache-Control: no-cache` en `index.html`; `immutable` en `*.js`/`*.css` hasheados
- `USER nginx`, `HEALTHCHECK` con `wget` a `http://localhost:8080/`
- Runtime config: montar/sustituir `assets/config.json` (no rebuild)

**SSR**

```bash
docker run --rm -p 8080:8080 -e PORT=8080 -e API_URL=http://backend:8080 my-angular-ssr:1.0.0
```

- Runtime: copiar `dist/` + production deps; `CMD ["node","dist/<app>/server/server.mjs"]`
- `USER node`, `PORT=8080`, graceful shutdown ante `SIGTERM`

## Limitaciones

- No hay AST/LSP TypeScript en este modo: reglas basadas en **regex** → falsos positivos/negativos.
- `--provider java` es un **workaround operativo** para habilitar `builtin`; no implica análisis semántico Java de tu código Angular.
- `--enable-default-rulesets=false` evita ruido de rulesets Java por defecto.
- No sustituye diseño de dominio, Dockerfile final, probes, sizing de Redis/IdP ni revisión de SCC.

## Desinstalación

```bash
rm -rf "$HOME/mta-custom-rules/angular-openshift-cloud-readiness"
```

## Referencias

- [MTA 8.x — Configuring and using rules](https://docs.redhat.com/en/documentation/migration_toolkit_for_applications/8.1/html/configuring_and_using_rules_for_an_mta_analysis/rules-introduction_rules-development-guide)
- [Analyzing non-Java applications (CLI)](https://docs.redhat.com/en/documentation/migration_toolkit_for_applications/8.1/html/using_the_migration_toolkit_for_applications_command_line_interface/analyzing-nonjava-applications_cli-guide)
- [Konveyor analyzer rules](https://github.com/konveyor/analyzer-lsp/blob/main/docs/rules.md)
- [Angular SSR](https://angular.dev/guide/ssr)
