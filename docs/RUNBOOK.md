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

Ergebnis (am 21.09.2026 mit drei Videos geprueft):

```
immich/library/admin/
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

- **Die Ebene `admin/`** fuegt Immich selbst ein: das Storage-Label des Benutzers. Sie ist
  nicht Teil des Templates und laesst sich nicht abschalten.
- **Videos belegen etwa doppelten Platz.** Immich behaelt das Original in `library/` und legt
  eine transkodierte Fassung in `encoded-video/` ab. Gemessen: drei Clips mit 56 MB Originalen
  ergaben 53 MB Transkodate.

Gehoert ein Foto zu mehreren Alben, gewinnt das zuletzt erstellte. Fotos ohne Album landen unter
`Ohne Album` und wandern beim naechsten Migrationslauf in den richtigen Ordner, sobald sie einem
Album zugewiesen sind.

Fuer den Ordner `import/` (External Library) gilt das Template **nicht**: Dort laesst Immich die
Dateien liegen, wo sie sind, und liest sie nur. Die Ordnernamen bestimmst du dort selbst per SMB -
dieselbe Benennung funktioniert also auch dort, nur von Hand. Achtung: Wird eine Datei innerhalb
der External Library verschoben, gilt sie beim naechsten Scan als neues Asset; Album-Zuordnung und
Beschreibungen in Immich gehen dabei verloren.

## Systemkonfiguration der Weboberflaeche

`immich/system-config.json` ist die versionierte Fassung der Einstellungen aus
Verwaltung -> Einstellungen. Sichern und Wiederherstellen geht dort ueber
"Als JSON exportieren" bzw. "Aus JSON importieren". Die Datei enthaelt keine
Geheimnisse (SMTP und OAuth sind leer) und gehoert deshalb ins Repo.

Bewusst gesetzt, abweichend von den Immich-Standardwerten:

| Einstellung | Standard | hier | Grund |
|---|---|---|---|
| `job.metadataExtraction` | 5 | 2 | 8 schwache ARM-Kerne, wenig RAM |
| `job.thumbnailGeneration` | 3 | 2 | siehe oben |
| `job.backgroundTask`, `library`, `migration`, `sidecar`, `search`, `workflow` | 5 | 2 | siehe oben |
| `library.scan` | `0 0 * * *` | `0 4 * * *` | lag auf derselben Zeit wie `nightlyTasks` (00:00) |
| `machineLearning.enabled` | true | false | ML-Container laeuft nicht (Profil `ml`) |
| `storageTemplate.template` | Jahr/Monat/Datei | Ereignis-Ordner | Vorgabe des Nutzers, siehe oben |
| `backup.database` | aus | `0 02 * * *`, 7 Staende | naechtlicher Dump nach `immich/backups/` |

Unveraendert gelassen und warum:

- `ffmpeg.accel: disabled` - die NAS hat keine Hardware-Beschleunigung.
- `ffmpeg.acceptedVideoCodecs: [h264]` - HEVC-Videos werden beim Upload einmalig nach
  h264 umgewandelt. Das kostet auf dieser CPU Minuten pro Video, dafuer laufen sie
  danach in jedem Browser. `job.videoConversion` steht auf 1, es blockiert also immer
  nur ein Video. Wer lieber Rechenzeit spart, nimmt `hevc` in die Liste auf - dann
  spielt Firefox solche Videos allerdings nicht ab.
- `ffmpeg.transcode: required` - transkodiert wird nur bei HDR, abweichendem
  Pixelformat oder unbekanntem Codec. Ein unbekannter *Container* fuehrt lediglich zum
  Remuxing nach MP4, das ist billig.
- `integrityChecks` taeglich 03:00 mit 1 % Stichprobe - liest Dateien von der HDD,
  liegt aber zeitlich frei.

Nach dem Import einer geaenderten Datei: Die Einstellungen greifen sofort, ein Neustart
der Container ist nicht noetig.
## Handy-Sicherung und naechtliche Speicher-Migration

Der vorgesehene Alltag: Die Immich-App sichert neue Handyfotos automatisch (App -> Sicherung:
Album "Kamera", Hintergrundsicherung an, nur ueber WLAN; unter Android die App von der
Akku-Optimierung ausnehmen). Der Server ist nur im LAN erreichbar, hochgeladen wird also zu Hause.

Automatisch gesicherte Fotos haben noch kein Album und landen unter `<Jahr>/Ohne Album/`. Werden
sie spaeter einem Album zugeordnet, verschiebt erst der Job "Speicher-Migration" die Dateien in den
Albumordner. Damit das ohne Handgriff passiert, stoesst der Dienst `storage-migration`
(Container `immich_storage_migration`, `immich/migrate.sh`) den Job jede Nacht in der Stunde 01 an -
vor dem Backup um 02:00. Wer tagsueber Alben zuordnet, findet die Dateien am naechsten Morgen im
richtigen Ordner. Sofort geht es weiterhin ueber Verwaltung -> Aufgaben.

- Log: `docker logs immich_storage_migration` - je Nacht eine Zeile "Speicher-Migration angestossen"
  oder "FEHLER: HTTP <Code>".
- Von Hand: `docker compose run --rm --no-deps storage-migration once`
- Der API-Schluessel steht als `MIGRATION_API_KEY` in der `.env` auf der NAS (600, nicht im Git).
  Wird der Schluessel in Immich zurueckgezogen, meldet das Log HTTP 401; dann neuen Schluessel
  eintragen und `docker compose up -d`.
- Der Container laeuft als 1001:10, weil die ACLs der NAS dem Image-Benutzer (UID 100) den Zugriff
  auf `migrate.sh` verweigern.
## Abfragen ueber die API

`scripts/immich-api.ps1` fragt Bibliotheken, Bestand und Auftrags-Warteschlangen ab und
kann den Bibliotheks-Scan anstossen:

```
.\scripts\immich-api.ps1                 # Zustand
.\scripts\immich-api.ps1 -Aktion scan    # Scan der externen Bibliothek anstossen
.\scripts\immich-api.ps1 -Aktion jobs    # nur die Warteschlangen
```

Der API-Schluessel liegt in `%USERPROFILE%\.immich\api-key` - ausserhalb des Repos, nur fuer
das eigene Konto lesbar. Erstellt wird er in Immich unter Kontoeinstellungen -> API-Schluessel;
Immich zeigt ihn nur ein einziges Mal an. Zurueckziehen geht an derselben Stelle, dann ist er
sofort ungueltig. Eingerichtet am 21.09.2026.

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

1. **Datenbank.** Immich legt selbst Dumps unter `<Fotos>/backups/` ab (taeglich 02:00,
   7 Staende). Von Hand anstossen: Verwaltung -> Aufgaben -> Button **Aufgabe erstellen**
   oben rechts -> **Datenbanksicherung erstellen**. Der Auslöser steht nicht in der
   Aufgabenliste selbst. Geprueft am 21.09.2026: erzeugt
   `immich-db-backup-<Zeit>-v3.2.2-pg14.19.sql.gz`, rund 19 MB - fast alles Geodaten
   fuer die Ortsauflösung, dieser Grundstock bleibt konstant.
   Alternativ auf der Kommandozeile:
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

**Bevorzugt ueber die Oberflaeche:** Verwaltung -> Wartung -> Abschnitt
"Datenbanksicherung wiederherstellen". Dort stehen alle Sicherungen mit Version und
Datum; ein Klick auf Wiederherstellen genuegt. Immich legt vorher automatisch einen
Ruecksprungpunkt an, falls die Wiederherstellung scheitert.

**Ueber die Kommandozeile**, wenn die Oberflaeche nicht erreichbar ist:

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

Eingerichtet am 21.09.2026. Der Ordner ist **nur lesend** als `/import` in den Server
eingebunden (`IMPORT_LOCATION` in der `.env`, Langform-Bind mit `read_only: true`).
Geprueft: `touch /import/...` im Container scheitert mit "Read-only file system".

**Wichtig: Der Importpfad in der Oberflaeche ist der Pfad IM CONTAINER**, also `/import` -
nicht der Host-Pfad. Einrichten unter Verwaltung -> Externe Bibliotheken:
Bibliothek erstellen, Besitzer waehlen, Importpfad `/import` hinzufuegen, dann scannen.

Dateien dorthin legst du per SMB:
`\\STEVENAS\personal_folder\Steves Bilder Archiv\import\`

Dort bestimmst du die Ordnernamen vollstaendig selbst - das Storage Template gilt hier
nicht, Immich laesst die Dateien liegen, wo sie sind. Dieselbe Benennung wie in der
verwalteten Bibliothek (`YYYY-MM-DD Titel`) ist sinnvoll, aber Handarbeit.

Drei Dinge, die man dabei wissen muss:

- **Verschieben kostet Metadaten.** Wird eine Datei innerhalb der Bibliothek an eine andere
  Stelle bewegt, gilt sie beim naechsten Scan als neues Asset; Album-Zuordnung, Beschreibung
  und Bewertung in Immich gehen verloren. Also erst einsortieren, dann scannen lassen.
- **Geloeschte Dateien landen im Papierkorb.** Verschwindet eine Datei von der Platte, legt
  Immich sie beim Rescan in den Papierkorb und entfernt sie nach 30 Tagen endgueltig.
  Zurueckholen geht nur, indem man die Originaldatei wieder herstellt.
- **Keine Symlinks** in den Importpfaden - Immich kommt damit nicht zurecht.

Der Scan laeuft taeglich um 04:00 (`library.scan`, siehe Systemkonfiguration) und laesst
sich jederzeit von Hand anstossen. Automatisches Ueberwachen des Dateisystems
(`library.watch`) ist bewusst aus: Es gilt als experimentell und braucht inotify-Watches
fuer jede Datei.