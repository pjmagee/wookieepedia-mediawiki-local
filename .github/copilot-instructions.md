---
applyTo: '**'
---

## Wookiepedia

Find relevent extensions and configuration of the Wookiepedia wiki:

https://starwars.fandom.com/wiki/Special:Version


## Task

- Remove the split dump strategy COMPLETELY
- Remove comments from codebase from old or hacky previous code
- Import only relevant namespaces
- Simplify the docker-compose
- Remove all the boolean/feature options
- Remove read only mode shit
- Remove as much as possible crap from this project as you can
- Keep extensions mandatory and needed for all the pages we import


## MAIN GOAL OF PROJECT:

1. Import the Wookiepedia dump
2. Open local mediawiki instance
3. View the Wookiepedia content


## Import dump

https://www.mediawiki.org/wiki/Manual:ImportDump.php


php importDump.php 

--report	Report position and speed after every n pages processed.
--namespaces	Import only the pages from namespaces belonging to the list of pipe-separated namespace names or namespace indexes.
--dry-run	Parse dump without actually importing pages.
--debug	Output extra verbose debug information.
--uploads	Process file upload data if included (experimental).
--no-updates	Disable link table updates. Is faster but leaves the wiki in an inconsistent state. Run rebuildall.php after the import to correct the link table.
--image-base-path	Import files from a specified path.
--skip-to	Start from the given page number, by skipping first n-1 pages.
--username-prefix	Adds a prefix to usernames. Due to this bug it may be necessary to specify --username-prefix="" when importing files.