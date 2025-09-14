FROM mediawiki:1.41

ENV MW_EXT_PATH=/var/www/html/extensions

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        git lua5.4 luajit p7zip-full imagemagick curl procps mariadb-client; \
    rm -rf /var/lib/apt/lists/*

# Copy extension fetcher and scripts
COPY fetch-extensions.sh /usr/local/bin/fetch-extensions
COPY import-dump.sh /usr/local/bin/import-dump
COPY start-mediawiki.sh /usr/local/bin/start-mediawiki
RUN chmod +x /usr/local/bin/fetch-extensions /usr/local/bin/import-dump /usr/local/bin/start-mediawiki

# Fetch required extensions (branches aligned with MW 1.41: REL1_41)
RUN fetch-extensions

# PortableInfobox (infobox layouts needed for Wookieepedia pages)
RUN set -eux; \
    dest="$MW_EXT_PATH/PortableInfobox"; \
    rm -rf "$dest"; \
    git clone --depth 1 -b REL1_41 https://github.com/Universal-Omega/PortableInfobox.git "$dest" || true; \
    rm -rf "$dest/.git" || true

# Copy LocalSettings template (mounted or overridden via volume if needed)
COPY LocalSettings.php /var/www/html/LocalSettings.php

# Create directory for import dumps
RUN mkdir -p /data/dumps && chown -R www-data:www-data /data
VOLUME ["/data/dumps", "/var/www/html/images"]

# Environment defaults (can be overridden in compose)
ENV MW_SITE_NAME="StarWars Local" \
    MW_SITE_LANG="en" \
    MW_ADMIN_USER="admin" \
    MW_ADMIN_PASS="adminpass"

# Healthcheck: basic HTTP check
HEALTHCHECK --interval=30s --timeout=5s --retries=5 CMD curl -f http://localhost:80/api.php?action=query&meta=siteinfo&format=json || exit 1

# Final permissions sanity
RUN chown -R www-data:www-data /var/www/html

# Startup script (auto-import + apache)
CMD ["/usr/local/bin/start-mediawiki"]
