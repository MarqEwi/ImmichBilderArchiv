#!/bin/sh
# Liest den Zustand der NAS aus - aendert nichts. Aufruf vom PC aus:
#   Get-Content -Raw .\scripts\probe.sh | ssh -4 MarcEwers@192.168.2.101 bash -s
# Grundlage fuer die RAM- und Pfadentscheidungen der Immich-Einrichtung.
echo "=== System ==="
hostname; id; uname -m
echo "Docker: $(docker version --format '{{.Server.Version}}')"
docker compose version

echo
echo "=== CPU ==="
echo "Kerne: $(nproc)"
lscpu | grep -E "Model name|Architecture"

echo
echo "=== Speicher (MB) ==="
free -m
echo "swappiness: $(cat /proc/sys/vm/swappiness)  (1 = Swap wird kaum genutzt, bei RAM-Not greift der OOM-Killer)"

echo
echo "=== Platten ==="
df -h /volume1
for d in /sys/block/sd* /sys/block/nvme*; do
  [ -e "$d/queue/rotational" ] && echo "$(basename "$d") rotational=$(cat "$d/queue/rotational")  (1 = HDD, 0 = SSD)"
done

echo
echo "=== Container und RAM ==="
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.CPUPerc}}"

echo
echo "=== Compose-Projekte ==="
docker compose ls -a

echo
echo "=== Port 2283 ==="
ss -tlnp 2>/dev/null | grep -E ":2283\b" || echo "2283 frei"

echo
echo "=== Veroeffentlichte Ports ==="
docker ps --format "{{.Names}}\t{{.Ports}}"

echo
echo "=== Fotoordner ==="
P="/volume1/@home/MarcEwers/Steves Bilder Archiv"
ls -la "$P" 2>&1 | head -5
echo "Eintraege: $(ls -A "$P" 2>/dev/null | wc -l)"
