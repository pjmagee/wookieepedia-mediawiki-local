# Wookieepedia Local Viewer (Ultra Minimal)

Dead‑simple local read‐only viewer for a Wookieepedia pages-current dump.

## What You Get

- MediaWiki 1.41 + only extensions required to render typical Wookieepedia pages.
- One command startup; fast web container (no import work inside it).
- Separate lightweight loader you run manually to import (single pass if no split; parallel across split parts when preprocessed).
- Automatic filtering of problematic mapping content models (interactivemap, GeoJSON) – always dropped to avoid heavy map stack.

## Quick Start

```powershell
mkdir -p dumps
# Put your dump here (one of):
#  starwars_pages_current.xml
#  starwars_pages_current.xml.gz
#  starwars_pages_current.xml.7z  (7z must be available in loader image or decompress first)
copy path\to\starwars_pages_current.xml.gz .\dumps\

docker compose up -d --build   # starts db + web only
docker compose run --rm loader # performs a single-pass import (idempotent)
```

Open: <http://localhost:8080/wiki/Main_Page>

Re-run just the loader any time (it skips if already imported).

## Mandatory Extensions (always)

| Extension | Why |
|-----------|-----|
| ParserFunctions | Template logic (#if, #switch, etc.) |
| Scribunto | Lua modules widely used |
| Cite | `<ref>` tags |
| TemplateStyles | Template CSS |
| ImageMap | Interactive images |
| Interwiki | Interwiki links |
| PortableInfobox | Infobox layouts |

No feature flags. No optional maps. No parallel worker tuning.

## Prerequisites

- Docker & Docker Compose
- Wookieepedia pages-current dump renamed (or copied) as `starwars_pages_current.xml[.gz|.7z]`

## Services

- `db`        : MariaDB
- `mediawiki` : Web + mandatory extensions (shared via host bind `./extensions-shared`)
- `loader`    : On-demand import (uses filtered single file or pre-split parts)
- `preprocessor` : Optional one-shot filter + split (no DB needed)

## Volumes / Binds

- `./dumps`  : Put main dump plus optional `extra/*.xml` supplemental exports
- `images`   : Named volume for uploaded files (rarely needed offline)
- `./extensions-shared` : Host directory holding cloned mandatory extensions (seeded automatically on first start)

## Quick Start

```powershell
mkdir -p dumps
copy path\to\starwars_pages_current.xml.7z .\dumps\
docker compose up -d --build
docker compose logs -f mediawiki
```

### Import Flow (No Preprocess)

1. Start stack (`docker compose up -d --build`)
2. Run loader (`docker compose run --rm loader`)
3. Loader: ensures core schema, filters dump (drops mapping models), imports allowed namespaces (Main, File, Template, Category, Module)
4. Imports any supplemental XML in `dumps/extra/` (idempotent markers `*.xml.imported`)
5. Runs maintenance scripts, writes `dumps/.imported`
6. Subsequent loader runs exit immediately unless you delete the marker

### Optional Preprocessing (Filter + Split)

You can preprocess the dump first (filter + create `split/part*.xml`) without touching the database:

```powershell
docker compose run --rm preprocessor             # uses default 4 parts
docker compose run --rm preprocessor --parts 6   # custom parts
```

Outputs:
- `starwars_pages_current.filtered.xml`
- `split/part1.xml ... partN.xml`
- Marker: `.preprocessed`

Then run the loader which will detect parts and import them in parallel:

```powershell
docker compose run --rm loader
```

Force re-preprocess:

```powershell
docker compose run --rm preprocessor --force
```

### Re-import

```powershell
Remove-Item .\dumps\.imported -ErrorAction SilentlyContinue
docker compose run --rm loader
```

### Supplemental Only (Skip Main Dump)

After the main import is complete (marker `.imported` exists) you can still import ONLY new files placed in `dumps/extra/` without touching the main dump by running the loader in extra-only mode:

```powershell
# Using flag
docker compose run --rm loader --extra-only

# Or via environment variable
docker compose run --rm -e EXTRA_ONLY=1 loader
```

This ignores the presence (or absence) of `.imported` for the main dump and processes just un-imported or updated `extra/*.xml` files, then runs maintenance tasks.

## Environment Variables

Only basics left (see compose): site name/lang and admin credentials. Change in `docker-compose.yml` if you care.

## Removed Features

Legacy complexity cut: split import scripts (old), read-only toggles, file cache layer, search backend, gadgets, timed media, syntax highlight, job drain scripts, tuning configs.

## Filtered Models

The loader always drops pages whose latest revision model is in the block list (default: `interactivemap, GeoJSON`). This avoids needing heavyweight map extensions.

## PortableInfobox

Included. If you see raw `<pi` markup, extensions didn’t seed – run `docker compose restart mediawiki` after ensuring `extensions-shared` contains it.

### Lua Engine

Scribunto runs with the standalone Lua interpreter (`luastandalone`) using system `lua5.4`. The PHP LuaSandbox module is not bundled (package not available in the base image’s repo). For most infobox/module logic this is sufficient. If you really need LuaSandbox (slightly better performance), you would have to compile and enable it manually inside a derived image.

## API Examples

```powershell
curl http://localhost:8080/api.php?action=query&meta=siteinfo&format=json
curl "http://localhost:8080/api.php?action=parse&page=Luke_Skywalker&prop=wikitext&format=json"
```

## Sampling Pages

```powershell
curl "http://localhost:8080/api.php?action=query&list=random&rnlimit=5&rnnamespace=0&format=json"
```

## Jobs

Check remaining jobs:

```powershell
docker compose exec mediawiki php maintenance/showJobs.php
```
Run some jobs manually:

```powershell
docker compose exec mediawiki php maintenance/runJobs.php --maxjobs 200
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Raw `<pi` markup | Ensure PortableInfobox present; purge page |
| Lua timeouts | Increase Scribunto timeout in `LocalSettings.php` |
| Missing template content | Dump lacked that template; create/import manually |
| Slow first view | Normal; caches warm on demand |

## Reset Everything

```powershell
docker compose down -v
del .\dumps\.imported 2>$null
docker compose up -d --build
```

## License

MediaWiki & extensions: their licenses. This repo scaffold: as-is.

---
Enjoy your local Wookieepedia.

## Repository Layout

| Path | Purpose |
|------|---------|
| `docker-compose.yml` | 3 services (db, web, loader) |
| `Dockerfile` | Web image with mandatory extensions baked (for seeding) |
| `fetch-extensions.sh` | Clones mandatory extensions into image / seed dir |
| `start-mediawiki.sh` | DB wait + install/update + seed extensions |
| `load-data.sh` | Single-pass import + filtering + maintenance |
| `filter_maps.py` | Filters unwanted content models |
| `LocalSettings.php` | Site configuration + mandatory extensions |
| `dumps/` | Main dump + `extra` supplemental XML |
| `extensions-shared/` | Host-cloned extensions shared by both containers |
| `images` (volume) | Uploaded files |

## Supplemental Imports (Missing Modules/Templates)

If you see errors like:

```text
Script error: No such module "LinkCheck".
```

It means the original dump lacked that module or template. To add missing pieces:

1. Create a folder `dumps/extra/`
2. Place one or more small MediaWiki XML export files there (e.g. `Module_LinkCheck.xml`)
3. Restart or re-import (remove `dumps/.imported` then `docker compose restart mediawiki`)

During startup, any `dumps/extra/*.xml` files are imported after the main dump with no namespace filtering.

To export a single module/template from a live wiki: use Special:Export and include the exact page title (e.g. `Module:LinkCheck`). Save as XML and drop it into `dumps/extra/`.

Quick supplemental import after initial load (marker stays):

```powershell
docker compose run --rm loader
```

### Automatic supplemental detection

`loader` scans `dumps/extra/*.xml` and imports only new/changed files (tracked via `*.xml.imported` markers). No need to drop the main marker for small additions.

To force re-import a single supplemental file:

```powershell
Remove-Item .\dumps\extra\Module_LinkCheck.xml.imported
docker compose run --rm loader
```

Main dump re-import still requires removing `.imported`.

## Performance

If you preprocess (creating split parts) the loader imports all parts in parallel (one process per part) for faster completion. Without preprocessing it performs a single threaded import of the filtered dump.

## Development (Scripts)

Scripts are bind-mounted. Edit locally and re-run the relevant container:

```powershell
docker compose run --rm loader   # to test loader changes
docker compose restart mediawiki # to restart web only
```

Use LF endings to avoid bash issues.
