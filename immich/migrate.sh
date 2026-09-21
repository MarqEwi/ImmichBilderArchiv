#!/bin/sh
# Stoesst einmal pro Nacht die Speicher-Migration von Immich an.
# Hintergrund: Fotos aus der Handy-Sicherung landen zunaechst unter "Ohne Album". Werden sie
# spaeter einem Album zugeordnet, verschiebt erst dieser Job die Dateien in den Albumordner.
# Laeuft im Container immich_storage_migration (curlimages/curl), spricht den Server ueber das
# Compose-Netz an - die LAN-IP waere wegen des kaputten Hairpin-NAT der NAS nicht erreichbar.
#
# Aufruf mit Argument "once": einmal ausfuehren und beenden (zum Testen).
set -u
URL="${IMMICH_URL:-http://immich-server:2283}"
KEY="${MIGRATION_API_KEY:?MIGRATION_API_KEY fehlt in der .env}"
RUN_HOUR="${RUN_HOUR:-01}"

migriere() {
  CODE=$(curl -s -o /tmp/antwort -w '%{http_code}' --max-time 60 -X PUT \
    -H "x-api-key: $KEY" -H 'Content-Type: application/json' \
    -d '{"command":"start","force":false}' \
    "$URL/api/jobs/storageTemplateMigration")
  if [ "$CODE" = "200" ]; then
    echo "$(date '+%F %T') Speicher-Migration angestossen"
  else
    echo "$(date '+%F %T') FEHLER: HTTP $CODE - $(head -c 300 /tmp/antwort 2>/dev/null)"
  fi
}

if [ "${1:-}" = "once" ]; then
  migriere
  exit 0
fi

echo "$(date '+%F %T') gestartet, Migration taeglich in der Stunde $RUN_HOUR"
LAST=""
while true; do
  if [ "$(date +%H)" = "$RUN_HOUR" ] && [ "$(date +%F)" != "$LAST" ]; then
    migriere
    LAST=$(date +%F)
  fi
  sleep 600
done