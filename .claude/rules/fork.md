# Fork ManDeBitcoin/mostro-app — cómo trabajar aquí

Claude Code carga este archivo en cada sesión (`.claude/rules/`), junto al `CLAUDE.md` de
upstream. `CLAUDE.md`, `AGENTS.md` y `CONTRIBUTING.md` son de upstream y siguen valiendo enteros;
esto solo añade lo propio del fork. Vive en un archivo nuevo para no editar ninguno de upstream.

## Qué es este repositorio

Fork de [MostroP2P/app](https://github.com/MostroP2P/app) ("upstream"). Tiene dos trabajos:

1. **Proponer mejoras a la comunidad.** Lo que sirve a cualquier usuario de Mostro va a upstream.
2. **Mantener nuestra instancia.** La app web servida por Coolify (`docker/README.md`) y, como
   objetivo, el nodo de BitMaxis como nodo persistente (ver [Nodo BitMaxis](#nodo-bitmaxis)).

`main` del fork es `upstream/main` más los archivos del [inventario](#inventario-del-fork). Nada más.

## Antes de escribir código: ¿a qué carril va?

| Carril | Qué | Rama desde | PR hacia | Idioma |
| --- | --- | --- | --- | --- |
| **upstream** | Útil para cualquier usuario de Mostro | `upstream/main` | `MostroP2P/app` `main` | Inglés |
| **fork** | Solo tiene sentido en nuestro despliegue | `origin/main` | `ManDeBitcoin/mostro-app` `main` | Libre |
| **sync** | Traer una versión nueva de upstream | `origin/main` | `ManDeBitcoin/mostro-app` `main` | — |

- Ante la duda, upstream.
- Si algo propio exige cambiar código de upstream, primero se propone a upstream la forma de
  hacerlo **configurable**, y el fork la usa desde sus propios archivos. Precedente: upstream ya lee
  `PUSH_SERVER_URL` al compilar "para forks" (`rust/src/config.rs`).
- Una mejora para la comunidad **nunca se desarrolla primero en el `main` del fork**. El Modo
  Simple se hizo así: quedó a 755 archivos de distancia de upstream y hubo que sacarlo de `main`
  para poder seguir a upstream (PR #6 del fork).

## Carril upstream

```bash
git remote add upstream https://github.com/MostroP2P/app.git   # si no existe
git fetch upstream main
git switch -c feat/descripcion-corta upstream/main
```

- Rama `type/kebab-desc`, commits convencionales, y **todo en inglés**: código, comentarios,
  commits, issue, PR (CONTRIBUTING.md § Language).
- La rama no lleva nada del fork: `git diff --stat upstream/main...HEAD` lista solo el cambio.
- **Quality bar** (CONTRIBUTING.md § Contribution quality bar). Sin esto, el PR se cierra sin
  revisión técnica:
  - Un issue con `status: accepted` de un maintainer **antes** del PR, enlazado con `Closes #N`.
    Solo están exentos los PRs que únicamente tocan Markdown.
  - Todas las secciones de `.github/pull_request_template.md`.
  - **Manual testing ejecutado por una persona**, contra un nodo Mostro. Claude puede escribir los
    pasos; los resultados los anota quien los corrió. Claude nunca afirma resultados que no vio.
  - Capturas antes (`main`) y después (rama) de todo cambio visible; la UI respeta
    `.specify/DESIGN_SYSTEM.md`.
  - En un fix, el primer commit (tras los `refactor:`) es `test:` y falla en `main`.
  - Commits firmados.
  - Si somos contribuyentes nuevos allí: como máximo 400 líneas cambiadas (sin código generado) y
    un solo PR abierto más a la vez.
- **Quién abre el PR.** Las sesiones de Claude solo tienen acceso de GitHub a
  `ManDeBitcoin/mostro-app`. La rama se empuja al fork y el PR hacia `MostroP2P/app` lo abre
  @ManDeBitcoin desde GitHub ("Compare & pull request"), con el título y el cuerpo que Claude
  entrega en el chat.
- Cuando upstream lo fusiona, llega al fork con el siguiente sync.

## Carril fork

- Preferir **archivos nuevos**. Editar un archivo de upstream solo cuando no hay alternativa, y
  anotarlo en [Desviaciones](#desviaciones) con el motivo y cómo se retira. Cada desviación es un
  conflicto posible en cada sync.
- Comprobar: `git diff --stat upstream/main...HEAD` lista solo el inventario y las desviaciones.
- Mantener al día este archivo y la tabla de `docker/README.md`.

## Carril sync

El procedimiento está en `docker/README.md` § Following upstream: merge de `upstream/main` en una
rama `sync/upstream-AAAAMMDD`, revisar el toolchain de `Dockerfile.web` contra
`.github/workflows/web-build.yml`, PR a `main`, staging antes de producción.

## Inventario del fork

| Archivo | Para qué |
| --- | --- |
| `.claude/rules/fork.md` | Esta guía |
| `Dockerfile.web` | Compila el core Rust a wasm y el bundle web; lo sirve nginx (Coolify) |
| `.dockerignore` | Deja fuera del contexto de build las salidas locales |
| `docker/nginx.conf` | Cabeceras de aislamiento cross-origin, fallback SPA, política de caché |
| `docker/README.md` | Despliegue en Coolify y cómo seguir a upstream |
| `test/web/nginx_cache_test.dart` | Fija la política de caché de `docker/nginx.conf` |

### Desviaciones

Archivos de upstream editados en el fork: **ninguno**.

## Nodo BitMaxis

- Pubkey `001bd4747d7d265edfe3bd3b7299886146ad850d51095fe77b763c32015685b9`
  (<https://mostro.bitmaxis.com/>). Relays según el commit `f690237` (5 oct 2026):
  `wss://relay.mostro.network`, `wss://mostro-p2p.tech`, `wss://relay.shadowbip.com`; verificarlos
  contra la lista kind 10002 del nodo antes de usarlos.
- **Decidido: BitMaxis como nodo predeterminado, no fijo.** Un usuario nuevo empieza en BitMaxis y
  puede cambiar de nodo como en upstream. Se fija con una opción de compilación (la clave del
  nodo), no editando código.
- **Estado: no aplicado.** `main` usa el nodo por defecto de upstream, compilado en dos copias:
  `DEFAULT_MOSTRO_PUBKEY` en `rust/src/config.rs` y `defaultMostroPubkey` en
  `lib/core/mostro_defaults.dart`. Upstream no tiene hoy esa opción para builds de producción;
  `MOSTRO_PUB_KEY` existe, pero solo en el entorno de pruebas Mortsom (`lib/core/test_environment.dart`,
  con su banner rojo), así que no sirve aquí.
- **Ruta: carril fork.** Es solo para nuestro despliegue; por ahora no se propone a upstream.
  Cómo aplicarlo (argumento de build en `Dockerfile.web`, o desviación en los dos archivos de
  arriba): pendiente de aprobación.

## El código personalizado anterior

El Modo Simple y la fijación al nodo BitMaxis salieron de `main` en el PR #6 del fork, pero siguen
en el historial:

- `3adb13f`, el último `main` personalizado (7 oct 2026), es ancestro del `main` actual:
  `git show 3adb13f:<ruta>` y `git ls-tree -r --name-only 3adb13f lib/features/simple_mode`.
  Si un clon superficial no lo tiene: `git fetch --unshallow origin`.
- Ramas en `origin`: `feat/bitmaxis-only`, `feat/simple-payment-method-picker`,
  `claude/amazing-allen-9fa49e`, `feat/simple-buy-order-and-price-stepper`,
  `fix/simple-icon-cache-and-bond-qr`.

Es **referencia** para portar ideas, por el carril que toque, nunca algo que se fusione tal cual:
diverge de upstream en 755 archivos.

## Sesiones de Claude en la nube

- El clon solo trae `origin`; `upstream` se añade como arriba (lectura pública).
- La sesión arranca en una rama `claude/<nombre-al-azar>` que asigna el entorno. Las ramas se
  publican con nombre descriptivo (`type/kebab-desc`; `sync/upstream-AAAAMMDD` para un sync); como la sesión solo puede empujar su
  rama asignada, Claude pide autorización a @ManDeBitcoin para publicar con el nombre correcto.
- No se abren PRs, ni se fusiona a `main`, sin que @ManDeBitcoin lo pida.
- **Los PRs de los carriles fork y sync los abre Claude**, con base `ManDeBitcoin/mostro-app`.
  Si se abren desde GitHub, ojo: en un fork, el botón "Compare & pull request" propone como base
  el repositorio de la comunidad (`MostroP2P/app`). Hay que cambiar *base repository* a
  `ManDeBitcoin/mostro-app` antes de crearlo. Así se abrió por error MostroP2P/app#789 (cerrado
  sin fusionar), que llevaba esta guía y 63 commits del fork.

## Workflows de upstream en el fork

`deploy-pages.yml` publica en GitHub Pages en cada push a `main`, y `release.yml` firma APKs con
cada tag. Ninguno se quiere aquí: se desactivan en Settings → Actions del fork, nunca editándolos
(sería una desviación).
