# Runbook: Immich auf STEVENAS

Stand 21.09.2026. Immich v3.2.2, Compose-Projekt `immich`.

## Wo liegt was

| | Pfad |
|---|---|
| Compose-Projekt | `/volume1/Grundlagen/docker/immich/` (`docker-compose.yml`, `.env`) |
| Datenbank | `/volume1/Grundlagen/docker/immich/postgres/` |
| Fotos | `/volume1/@home/MarcEwers/Steves Bilder Archiv/immich/` |
| Import-Ordner | `/volume1/@home/MarcEwers/Steves Bilder Archiv/import/` (noch nicht eingebunden) |
| Windows-Sicht | Freigabe `personal_folder`, Ordner `Steves Bilder Archiv` |
| Weboberflaeche | `http://192.168.2.101:2283` (nur LAN) |

Container: `immich_server`, `immich_postgres`, `immich_redis`. Der ML-Container
`immich_machine_learning` ist im Profil `ml` und laeuft **nicht**.

## Ordnerstruktur der Bilder

Gewuenscht (Vorgabe vom 21.09.2026): ein Ordner je Ereignis, benannt `YYYY-MM-DD Titel`,
z. B. `2026-09-21 Kindergeburtstag Olli`. Umgesetzt ueber das Storage Template in
Verwaltung -> Einstellungen -> Speicher-Template:

```
{{y}}/{{#if album}}{{{album}}}{{else}}Ohne Album{{/if}}/{{filename}}
```

Ergebnis:

```
immich/library/
├── 2026/
│   ├── 2026-09-21 Kindergeburtstag Olli/
│   ├── 2026-08-03 Sommerfest/
│   └── Ohne Album/
└── 2025/
    └── 2025-12-24 Weihnachten/
```

Drei Dinge dazu:

- **Der Ordnername ist der Albumname.** Deshalb das Album selbst `2026-09-21 Kindergeburtstag Olli`
  nennen. Das Datum kommt so vom Ereignis und nicht vom einzelnen Foto - bei einem Urlaub ueber
  mehrere Tage entstuende sonst je Aufnahmetag ein eigener Ordner.
- **Dreifache Klammern bei `{{{album}}}`.** Mit zwei Klammern wandelt Immich Sonderzeichen in
  HTML-Entities um (aus `&` wird `&amp;`).
- **Ablauf:** hochladen -> Album anlegen und zuweisen -> Job "Storage Template Migration" starten.
  Der Job sortiert auch rueckwirkend um, wenn das Template spaeter geaendert wird.

Gehoert ein Foto zu mehreren Alben, gewinnt das zuletzt erstellte. Fotos ohne Album landen unter
`Ohne Album` und wandern beim naechsten Migrationslauf in den richtigen Ordner, sobald sie einem
Album zugewiesen sind.

Fuer den Ordner `import/` (External Library) gilt das Template **nicht**: Dort laesst Immich die
Dateien liegen, wo sie sind, und liest sie nur. Die Ordnernamen bestimmst du dort selbst per SMB -
dieselbe Benennung funktioniert also auch dort, nur von Hand. Achtung: Wird eine Datei innerhalb
der External Library verschoben, gilt sie beim naechsten Scan als neues Asset; Album-Zuordnung und
Beschreibungen in Immich gehen dabei verloren.

## Starten und Stoppen

Immer aus dem Projektverzeichnis, immer mit Projektnamen. **Nie `-v`** (das wuerde Volumes loeschen).

```sh
cd /volume1/Grundlagen/docker/immich
docker compose up -d                 # starten
docker compose ps                    # Zustand
docker compose stop                  # anhalten, Container bleiben bestehen
docker compose down                  # Container entfernen (Daten bleiben, liegen in Bind-Mounts)
```

Auf dieser NAS laufen weitere Projekte (`heizung`, `sync`, `mfp`). Deren Container nie
stoppen, entfernen oder neu starten. `docker system prune`, `docker image prune -a` und
`docker network prune` sind tabu - sie wuerden fremde Projekte treffen.

## Logs

```sh
docker compose logs -f                       # alles
docker compose logs --tail 100 immich-server
docker compose logs --tail 50 database
docker logs -t immich_server                 # mit Docker-Zeitstempeln
```

## Update

1. Release Notes lesen: https://github.com/immich-app/immich/releases - besonders auf
   Breaking Changes und noetige Migrationen achten.
2. Neue offizielle Dateien mit den eigenen vergleichen, damit keine neue Variable fehlt:
   ```sh
   curl -4 -sL -o /tmp/neu.yml https://github.com/immich-app/immich/releases/download/<TAG>/docker-compose.yml
   diff /tmp/neu.yml docker-compose.yml
   ```
   Die eigenen Abweichungen sind mit `# ANPASSUNG:` markiert; alles andere sollte gleich sein.
3. **Vorher Backup** (siehe unten).
4. `IMMICH_VERSION` in `.env` auf den neuen Tag setzen.
5. `docker compose pull && docker compose up -d`
6. `docker compose logs -f immich-server` bis "Immich Server is listening".

## Backup

Drei Dinge gehoeren gesichert:

1. **Datenbank.** Immich legt selbst Dumps unter `<Fotos>/backups/` ab (Admin-Einstellungen,
   nachts). Manuell:
   ```sh
   docker exec -t immich_postgres pg_dumpall --clean --if-exists -U postgres \
     > "/volume1/@home/MarcEwers/Steves Bilder Archiv/immich/backups/dump-$(date +%F).sql"
   ```
2. **Fotos.** Der gesamte Ordner `Steves Bilder Archiv/immich/` (library, upload, thumbs, ...).
3. **`.env`.** Enthaelt das Datenbank-Passwort und ist nicht im Git. Ohne sie laesst sich ein
   Dump nicht einspielen.

Der Ordner `postgres/` selbst ist **kein** Backup - eine Dateikopie eines laufenden Postgres
ist im Zweifel unbrauchbar. Immer den Dump nehmen.

## Wiederherstellung

```sh
cd /volume1/Grundlagen/docker/immich
docker compose down                       # ohne -v
rm -rf postgres/*                         # nur nach Ruecksprache, das loescht die DB
docker compose up -d database
# warten bis "ready to accept connections"
cat dump-<datum>.sql | docker exec -i immich_postgres psql -U postgres -d immich
docker compose up -d
```

Fotos zurueckspielen, bevor der Server startet. Die `.env` muss dasselbe `DB_PASSWORD`
enthalten wie zum Zeitpunkt des Dumps.

## Wenn der RAM knapp wird

Die NAS hat 3,8 GB, davon ~1,3 GB frei, und `swappiness=1` - der Kernel swappt also kaum,
sondern beendet bei Speichernot Prozesse (OOM-Killer). Deshalb sind Grenzen gesetzt:
Server 640 MB, Postgres 320 MB, Valkey 64 MB.

Symptome: Container startet staendig neu, `docker inspect immich_server --format '{{.State.OOMKilled}}'`
meldet `true`, oder `dmesg | tail` zeigt "Out of memory".

Massnahmen, in dieser Reihenfolge:

1. `docker stats --no-stream` - wer verbraucht wirklich wie viel?
2. In den Admin-Einstellungen laufende Jobs drosseln (Job-Nebenlaeufigkeit auf 1).
3. Grenze fuer `immich-server` in `docker-compose.yml` erhoehen, aber nur so weit, dass
   Home Assistant (~520 MB) und die anderen Dienste ihren Bedarf behalten.
4. Erst danach ueber mehr RAM oder weniger Dienste nachdenken.

## Maschinelles Lernen spaeter aktivieren

Kostet zusaetzlich rund 1 GB RAM - auf dieser NAS derzeit nicht drin. Wenn doch:

```sh
docker compose --profile ml up -d
```

Danach in der Weboberflaeche unter Verwaltung -> Einstellungen -> Maschinelles Lernen
einschalten und die Jobs "Smart Search" und "Gesichtserkennung" anstossen. Beobachten:
`docker stats --no-stream`. Zurueck:

```sh
docker compose --profile ml stop immich-machine-learning
docker compose --profile ml rm -f immich-machine-learning
```

## External Library fuer import/

Noch nicht eingerichtet. Dafuer muesste der Ordner `import/` zusaetzlich read-only in den
Server gemountet werden (`type: bind`, `read_only: true`), danach in der Weboberflaeche
unter Verwaltung -> Externe Bibliotheken der Pfad eingetragen werden. Immich verschiebt
oder veraendert dort nichts. Erfordert eine Compose-Aenderung und einen Neustart des Servers.
