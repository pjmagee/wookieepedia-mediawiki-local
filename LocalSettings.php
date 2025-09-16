<?php
# LocalSettings for StarWars local rendering
if ( getenv('MW_SITE_NAME') ) {
    $wgSitename = getenv('MW_SITE_NAME');
} else {
    $wgSitename = 'StarWars Local';
}
$wgMetaNamespace = str_replace(' ', '_', $wgSitename);

$wgScriptPath = '';
$wgArticlePath = '/wiki/$1';
$wgUsePathInfo = true;

$wgServer = getenv('MW_SERVER') ?: 'http://localhost:8080';
$wgResourceBasePath = $wgScriptPath;

$wgDBtype = 'mysql';
$wgDBserver = getenv('MW_DB_HOST') ?: 'db';
$wgDBname = getenv('MW_DB_NAME') ?: 'mediawiki';
$wgDBuser = getenv('MW_DB_USER') ?: 'wikiuser';
$wgDBpassword = getenv('MW_DB_PASS') ?: 'secret';
$wgDBprefix = '';
$wgDBTableOptions = 'ENGINE=InnoDB, DEFAULT CHARSET=binary';

$wgDBmysql5 = false;

$wgShellLocale = 'C.UTF-8';
$wgLanguageCode = getenv('MW_SITE_LANG') ?: 'en';
$wgSecretKey = getenv('MW_SECRET_KEY') ?: 'change-me-please-123';
$wgAuthenticationTokenVersion = '1';

$wgUpgradeKey = getenv('MW_UPGRADE_KEY') ?: 'upgrade-key';

$wgEmergencyContact = 'admin@localhost';
$wgPasswordSender = 'admin@localhost';

$wgEnableEmail = false;
$wgEnableUserEmail = false;

$wgRightsText = '';
$wgRightsUrl  = '';

$wgDiff3 = '/usr/bin/diff3';

$wgLogo = "$wgResourceBasePath/resources/assets/change-your-logo.svg";

$wgEnableUploads = true;
$wgUseImageMagick = true;
$wgImageMagickConvertCommand = '/usr/bin/convert';

# Performance / memory
ini_set('memory_limit', '512M');
$wgJobRunRate = 0; // We'll run jobs manually after import

// Local development wiki – no read-only or file cache toggles.

# Enable object cache (could add Redis if needed later)
$wgMainCacheType = CACHE_ACCEL;
$wgParserCacheType = CACHE_ACCEL;
$wgSessionCacheType = CACHE_DB;

# Avoid sending external pingbacks etc.
$wgEnableCreativeCommonsRdf = false;

# Time zone
$wgLocaltimezone = 'UTC';
$wgLocalTZoffset = 0;

// All required extensions loaded unconditionally.

// Core essential extensions (always load)
wfLoadExtension('ParserFunctions');
$wgPFEnableStringFunctions = true;
wfLoadExtension('Scribunto');
// Use standalone Lua interpreter (luastandalone) – simpler, no php-luasandbox package in base image.
$wgScribuntoDefaultEngine = 'luastandalone';
$wgScribuntoEngineConf['luastandalone']['timeout'] = 30; // seconds
$wgScribuntoEngineConf['luastandalone']['memoryLimit'] = 52428800; // 50MB
$wgScribuntoEngineConf['luastandalone']['cpuLimit'] = 30; // soft CPU cap
$wgScribuntoEngineConf['luastandalone']['engine'] = [
    'luaPath' => '/usr/bin/lua5.4',
];
wfLoadExtension('Cite');
wfLoadExtension('TemplateStyles');
wfLoadExtension('ImageMap');
wfLoadExtension('Interwiki');

// Mandatory layout/infobox dependencies
if ( is_dir( __DIR__ . '/extensions/PortableInfobox' ) ) { wfLoadExtension('PortableInfobox'); } else { error_log('PortableInfobox extension directory missing; infoboxes will not render.'); }

// Mapping extensions intentionally omitted to keep stack minimal.

# Extra-safe defaults for import
$wgGroupPermissions['*']['edit'] = false;
$wgGroupPermissions['*']['createaccount'] = false;
$wgGroupPermissions['sysop']['edit'] = true;

# Interwiki caching (basic)
$wgInterwikiCache = [];

# Debug (turn on manually if needed)
$wgShowExceptionDetails = false;
$wgDebugToolbar = false;

# Load skins if needed (Vector)
wfLoadSkin('Vector');
// Force Vector skin only (simple)
$wgDefaultSkin = 'vector';

# End of LocalSettings.php
