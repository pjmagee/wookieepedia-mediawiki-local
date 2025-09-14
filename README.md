# Wookieepedia Local Viewer (Simplified)

Minimal MediaWiki 1.41 + mandatory extensions to load and view a Wookieepedia dump locally.

## Goal

1. Put `starwars_pages_current.xml` (or `.xml.gz` / `.xml.7z`) into `./dumps`
2. By default, pages with content model `interactivemap` are filtered out to avoid import errors. To import all map pages, set `MW_ENABLE_MAPS=1` in the environment.
3. Run `docker compose up -d --build`
4. Open <http://localhost:8080/wiki/Main_Page>

## Mandatory Extensions

| Extension | Why |
|-----------|-----|
| ParserFunctions | Template logic (#if, #switch, etc.) |
| Scribunto | Lua modules widely used |
| Cite | `<ref>` tags |
| TemplateStyles | Template CSS |
| ImageMap | Interactive images |
| Interwiki | Interwiki links |
| PortableInfobox | Infobox layouts |

All former optional/flag-gated extensions removed for simplicity.

## Prerequisites

- Docker & Docker Compose
- Wookieepedia pages-current dump renamed (or copied) as `starwars_pages_current.xml[.gz|.7z]`

## Volumes

- `./dumps` (bind mount) – place dump here
- Named volume `images` – uploads

## Quick Start

```powershell
mkdir -p dumps
copy path\to\starwars_pages_current.xml.7z .\dumps\
docker compose up -d --build
docker compose logs -f mediawiki
```

### Startup Flow

1. Wait for DB
2. Schema update
3. Import dump (namespaces: Main|File|Template|Category|Module)
4. Run maintenance & jobs
5. Write marker `dumps/.imported`

### Clean Re-import

```powershell
docker compose down -v
del .\dumps\.imported
docker compose up -d --build
```

## Environment Variables (Remaining)

| Variable | Purpose |
|----------|---------|
| MW_SITE_NAME | Site name |
| MW_SITE_LANG | Language code |
| MW_ADMIN_USER / MW_ADMIN_PASS | Initial admin account |

Vector skin is hard-coded in `LocalSettings.php` for consistency; change there if you really need another skin.

## Removed Features
## Map Pages and Interactive Maps

By default, pages with content model `interactivemap` are filtered out before import to avoid errors (these require the Kartographer extension). If you want to import all map pages and enable interactive maps:

1. Set `MW_ENABLE_MAPS=1` in the environment for the mediawiki service in `docker-compose.yml`.
2. Kartographer will be installed automatically.
3. All pages will be imported, but you may need to configure map services for full functionality.

If you leave the default, map pages are skipped and the import will not fail. The filtering is done by `filter_maps.py` (bind-mounted), so switching the `MW_ENABLE_MAPS` value only requires a container restart (re-import if you removed `.imported`). No image rebuild is needed unless you add new extensions.

Fast import, dump splitting, parallel import, read-only mode, file cache, search, gadgets, timed media, syntax highlight, minimal mode – all deleted to keep the stack lean.

## PortableInfobox

Included automatically. If you see raw `<pi` markup, confirm the extension exists in `extensions/PortableInfobox`.

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
del .\dumps\.imported
docker compose up -d --build
```

## License

MediaWiki & extensions: their licenses. This repo scaffold: as-is.

---
Enjoy your local Wookieepedia.

## Repository Layout (Minimal)

Only the essentials are kept:

- `docker-compose.yml` – two-service stack (MariaDB + MediaWiki)
- `Dockerfile` – builds image with mandatory extensions
- `fetch-extensions.sh` – clones required extensions
- `import-dump.sh` – single-pass namespace-scoped import
- `start-mediawiki.sh` – deterministic startup + conditional import
- `LocalSettings.php` – locked-down minimal configuration
- `dumps/` – place your `starwars_pages_current.xml[.gz|.7z]` here

All former helper, split, tuning, analytics, or job scripts were removed.

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

Quick re-import cycle for new supplemental files (old behavior – still works):

```powershell
Remove-Item .\dumps\.imported -ErrorAction SilentlyContinue
docker compose restart mediawiki
```

You can repeat this as you discover additional missing modules or templates.

### Automatic supplemental detection

On every container start the startup script now scans `dumps/extra/*.xml` and imports only those files that are new or modified (tracked via a sidecar marker `filename.xml.imported`). No need to remove the main `.imported` marker for the large dump just to add a small module.

Workflow now:

1. Drop / update XML in `dumps/extra/`
2. `docker compose restart mediawiki`
3. Watch logs for lines like:
   - `Importing supplemental /data/dumps/extra/Module_LinkCheck.xml`
   - `Supplemental import(s) complete` or `No new supplemental XML files to import`

To force re-import a particular supplemental file, delete its sidecar marker:

```powershell
Remove-Item .\dumps\extra\Module_LinkCheck.xml.imported
docker compose restart mediawiki
```

Main dump re-import is only needed if you want to rebuild everything: remove `dumps/.imported` as before.

## Development (Live Script Editing)

The compose file bind-mounts `start-mediawiki.sh` and `import-dump.sh` into the container (read-only). Any local edit to those scripts is picked up on the next restart:

```powershell
docker compose restart mediawiki
```

No image rebuild needed unless you change the Dockerfile or add new system packages. Ensure files use LF line endings (not CRLF) to avoid bash parsing issues.
