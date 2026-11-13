# Angular (SPA / SSR) → OpenShift Cloud Readiness

Ruleset custom de **Red Hat MTA / Konveyor** (v1.1.0) que analiza aplicaciones **Angular** (SPA tradicionales y proyectos con **`@angular/ssr`**) y genera un **reporte de incidencias** a corregir **antes de contenerizar** y desplegar en **OpenShift / Kubernetes**.

Para instalación y comandos `mta-cli`, ver [`INSTALL.md`](INSTALL.md).

---

## Objetivo final

Dejar la aplicación en un estado **Twelve-Factor / cloud-ready** compatible con:

1. **Build Once, Deploy Anywhere**: una sola imagen CI promovida a staging/prod sin recompilar por entorno.
2. **OpenShift**: no-root, puerto **8080**, configuración por ConfigMap/Secret (runtime), logs a `stdout`/`stderr`.
3. **Arquitectura correcta**:
   - **SPA** → multi-stage `node:<lts>-alpine` → `nginxinc/nginx-unprivileged:alpine` (estáticos).
   - **SSR** → runtime `node:<lts>-alpine` (o Distroless) ejecutando `node dist/<app>/server/server.mjs`.

El ruleset **no genera el Dockerfile**. Su salida es un informe de violaciones (`angular-ocp-*`) para triage y remediación previa al empaquetado.

Estado objetivo típico tras remediación:

| Área | Target |
|------|--------|
| Runtime SPA | nginx-unprivileged :8080, `try_files` HTML5, cache `index.html` no-store |
| Runtime SSR | `USER node`, `PORT=8080`, solo `dist/` + deps de producción |
| Config | `assets/config.json` / `envsubst` — no `environment.prod.ts` por entorno |
| Secretos | OpenShift Secret; nunca en `environment*.ts` ni en el bundle |
| Red | URLs relativas o config runtime; nunca `localhost` bakeado |
| Observabilidad | SSR → logs JSON a stdout; SPA → access log del ingress/nginx |

---

## Versiones de Angular compatibles (análisis)

El análisis es por **contenido de fuentes** (`builtin.filecontent`: `.ts`, `.js`, `angular.json`, `package.json`, `environment*.ts`, `server.ts`, etc.). No requiere `ng build`.

| Plataforma | Versiones típicas | ¿Se analiza? | Notas |
|------------|-------------------|--------------|--------|
| **Angular ≤16** | 9–16 | Sí | `angular-ocp-ver-00001` (fuera de soporte) |
| **Angular 17–18** | 17, 18 | Sí | `angular-ocp-ver-00002` → planificar upgrade |
| **Angular 19+** | 19, 20, 21… | Sí | Baseline recomendada para contenedores nuevos |
| SPA (`browser` / `application` builder) | cualquiera | Sí | Verificar ruta `dist/<app>/browser` en Angular 17+ |
| SSR (`@angular/ssr`) | 17+ típico | Sí | FS local, puerto 80, shell, platform browser |
| Service Worker (`ngsw`) | opcional | Sí | Cache de `index.html` en rollouts |

**Target de contenedorización recomendado:** Angular **19+** (o la major LTS/activa vigente) sobre Node LTS alpine (build) y nginx-unprivileged (SPA) o Node no-root (SSR).

---

## Qué evalúan las reglas

**22 reglas** en 6 grupos. Prefijo de IDs: `angular-ocp-`.

### 01 — Configuración y secretos (`01-config-secrets.yaml`)

| ruleID | Evalúa | Por qué importa al contenerizar |
|--------|--------|----------------------------------|
| `angular-ocp-sec-00001` | API keys / secrets en `environment*.ts` | Se bakean en el bundle/imagen |
| `angular-ocp-sec-00002` | Secretos literales en `.ts`/`.js` | Credenciales en el artefacto |
| `angular-ocp-cfg-00001` | `environment.development.ts` con secretos/localhost | No debe viajar al publish |

### 02 — Red y endpoints (`02-networking-endpoints.yaml`)

| ruleID | Evalúa | Por qué importa al contenerizar |
|--------|--------|----------------------------------|
| `angular-ocp-net-00001` | `localhost` / `127.0.0.1` en env o código | No es el Service/Ingress del cluster |
| `angular-ocp-net-00002` | `proxy.conf` → localhost | Solo vale para `ng serve`, no en la imagen |
| `angular-ocp-net-00003` | `apiUrl` absoluto `https://…` en environments | Rompe Build Once Deploy Anywhere |
| `angular-ocp-net-00004` | `const baseUrl = 'http://…'` en `src/app/**` | API bakeada en services (p. ej. Bezkoder CRUD) |

### 03 — Config runtime / Twelve-Factor (`03-runtime-config.yaml`)

| ruleID | Evalúa | Por qué importa al contenerizar |
|--------|--------|----------------------------------|
| `angular-ocp-cfg-00002` | `fileReplacements` → `environment.prod.ts` | Implica rebuild por entorno |
| `angular-ocp-cfg-00003` | `production: true` + config estática | Separar flags de build vs deploy |
| `angular-ocp-cfg-00004` | `process.env.*` en bundle cliente | No lee env del Deployment en runtime |

### 04 — SSR / Node (`04-ssr-nodejs.yaml`)

| ruleID | Evalúa | Por qué importa al contenerizar |
|--------|--------|----------------------------------|
| `angular-ocp-ssr-00001` | `writeFile` / `mkdirSync` en `server.ts` | Disco del pod efímero |
| `angular-ocp-ssr-00002` | `listen(80/443)` | No-root → puerto **8080** |
| `angular-ocp-ssr-00003` | `child_process` / `execSync` | Choca con SCC e imágenes mínimas |
| `angular-ocp-ssr-00004` | `process.exit` | Evita graceful shutdown ante `SIGTERM` |
| `angular-ocp-ssr-00005` | Winston/pino a archivo | Logs se pierden con el pod |

### 05 — Browser / plataforma (`05-browser-platform.yaml`)

| ruleID | Evalúa | Por qué importa al contenerizar |
|--------|--------|----------------------------------|
| `angular-ocp-dom-00001` | `window` / `document` directo | Rompe SSR en contenedor Node |
| `angular-ocp-state-00001` | Tokens en `localStorage` | Preferir IdP + cookies HttpOnly |
| `angular-ocp-sw-00001` | Service Worker / `ngsw` | Puede atrapar `index.html` viejo |

### 06 — Versión y toolchain (`06-version-toolchain.yaml`)

| ruleID | Evalúa | Por qué importa al contenerizar |
|--------|--------|----------------------------------|
| `angular-ocp-ver-00001` | `@angular/core` ≤16 | Fuera de soporte para baseline nueva |
| `angular-ocp-ver-00002` | `@angular/core` 17–18 | Planificar upgrade a 19+ |
| `angular-ocp-ver-00003` | `engines.node` antiguo (<18 / 14 / 16) | Alinear con `node:<lts>-alpine` |
| `angular-ocp-build-00001` | Builder `browser` / `outputPath` legacy | Confirmar `dist/<app>/browser` en Dockerfile |

Angular **20+** en `package.json` **no** dispara reglas de upgrade de major.

---

## Categorías y esfuerzo

- **`mandatory`**: bloquea o degrada seriamente el despliegue multi-entorno / no-root / OpenShift.
- **`potential`**: requiere triage; a menudo correcto en SPA pura o aceptable con mitigación.
- **`effort`**: estimación relativa Konveyor (1 = bajo, 5+ = upgrade estructural de framework).

---

## Flujo recomendado

```text
Código Angular ──► mta-cli + este ruleset ──► reporte angular-ocp-*
                                              │
                                              ▼
                                    Triage P0 / P1 / P2
                                              │
                                              ▼
              Remediación (runtime config, secretos, SSR, versiones…)
                                              │
                                              ▼
     Dockerfile multi-stage SPA|SSR + OpenShift (Deployment/Route/Secret)
```

Calibración sin app real:

```bash
./bin/analyze-angular.sh --input ./fixture --output /tmp/mta-angular-fixture
rg 'angular-ocp-' /tmp/mta-angular-fixture/output.yaml
```

---

## Limitaciones

- Detección por **regex**, no AST/TypeScript LSP → posibles falsos positivos/negativos.
- Reglas DOM/SW son heurísticas: en SPA sin SSR el impacto es menor — triagelo.
- No sustituye diseño de Ingress, probes, NetworkPolicies ni el `nginx.conf` final.
- En MTA 8.0 no hay provider Angular nativo; el wrapper usa `--provider java` solo para habilitar `builtin` (detalle en `INSTALL.md`).

---

## Referencias

- [INSTALL.md](INSTALL.md) — instalación, `mta-cli`, fixture esperado
- [Konveyor analyzer rules](https://github.com/konveyor/analyzer-lsp/blob/main/docs/rules.md)
- [MTA — Configuring and using rules](https://docs.redhat.com/en/documentation/migration_toolkit_for_applications/8.1/html/configuring_and_using_rules_for_an_mta_analysis/rules-introduction_rules-development-guide)
- [Angular SSR](https://angular.dev/guide/ssr)
- [nginx-unprivileged](https://github.com/nginxinc/docker-nginx-unprivileged)
