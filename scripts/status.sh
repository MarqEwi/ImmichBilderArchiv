#!/bin/sh
# Zeigt den Zustand des Immich-Fotoarchivs. Aendert nichts.
# Aufruf vom PC (cmd-Redirect, weil PowerShell beim Pipen ein BOM anhaengt und bash daran scheitert):
#   cmd /c "ssh -4 MarcEwers@192.168.2.101 bash -s < scripts\status.sh"
P="/volume1/@home/MarcEwers/Steves Bilder Archiv/immich"

echo "=== Container ==="
docker ps --filter name=immich --format "{{.Names}} | {{.Status}}"

echo
echo "=== Speicher (Limit / echt ohne Page-Cache) ==="
for c in immich_server immich_postgres immich_redis; do
  ID=$(docker inspect --format "{{.Id}}" "$c" 2>/dev/null) || continue
  ANON=""
  for f in "/sys/fs/cgroup/system.slice/docker-$ID.scope/memory.stat" "/sys/fs/cgroup/docker/$ID/memory.stat"; do
    [ -f "$f" ] && { ANON=$(awk '/^anon /{printf "%d", $2/1048576}' "$f"); break; }
  done
  printf "%-18s %s   echt: %s MB\n" "$c" "$(docker stats --no-stream --format '{{.MemUsage}}' "$c")" "${ANON:-?}"
done

echo
echo "=== Dateien je Ordner ==="
cd "$P" || exit 1
for d in library upload encoded-video thumbs backups; do
  printf "%-14s %5s Dateien  %8s\n" "$d" "$(find "$d" -type f ! -name .immich | wc -l)" "$(du -sh "$d" | cut -f1)"
done

echo
echo "=== Ereignis-Ordner in library/ ==="
cd "$P/library" || exit 1
find . -mindepth 3 -maxdepth 3 -type d 2>/dev/null | sed "s|^\./||" | sort
[ -z "$(find . -mindepth 3 -maxdepth 3 -type d 2>/dev/null)" ] && echo "(noch keine)"

echo
echo "=== Zuletzt abgelegte Dateien ==="
find . -type f ! -name .immich -printf "%TY-%Tm-%Td %TH:%TM  %8s  %p\n" 2>/dev/null | sort | tail -n 8