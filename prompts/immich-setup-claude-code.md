# Immich auf dem UGREEN NASync DH2300 einrichten – Prompt für Claude Code (PowerShell)

> Diesen gesamten Text in Claude Code einfügen. Claude Code läuft dabei in
> **PowerShell auf dem Windows-Master-PC** und arbeitet über SSH auf dem NAS.
> Das Repo `ImmichBilderArchiv` ist lokal ausgecheckt und ist das aktuelle
> Arbeitsverzeichnis. Alle Konfigurationsdateien entstehen zuerst im Repo und
> werden von dort auf das NAS kopiert (Infrastructure as Code).

---

## Auftrag

Ich möchte Immich (selbstgehostete Fotoverwaltung) auf meinem UGREEN NASync DH2300
einrichten. Arbeite Schritt für Schritt. Vor jedem Schritt, der etwas verändert
(Container starten, Dateien anlegen oder kopieren, Rechte setzen, Verzeichnisse
erstellen), zeigst du mir, was du vorhast, und wartest auf mein OK.
Rein lesende Befehle (ls, cat, df, docker ps, docker stats, ss, …) darfst du ohne
Rückfrage ausführen.

Der vorgesehene Ordner für die Fotos auf dem NAS heißt in Windows-Schreibweise:

    \\STEVENAS\personal_folder\Steves Bilder Archiv

Der Ordner existiert bereits und ist leer.

## Arbeitsumgebung

- Du arbeitest in **PowerShell** auf dem Windows-Master-PC.
- Das NAS erreichst du per SSH: `ssh -4 MarcEwers@STEVENAS` (Public-Key ist eingerichtet).
  **IPv6-Falle:** immer IPv4 erzwingen (`ssh -4`, `scp -4`) oder direkt die
  IPv4-Adresse verwenden. Ermittle die IPv4-Adresse zu Beginn
  (`Resolve-DnsName STEVENAS -Type A` oder `ping -4 STEVENAS`) und nutze sie
  konsequent. Schlag mir vor, einen Eintrag in `~/.ssh/config` anzulegen
  (`Host stevenas`, `HostName <IPv4>`, `User MarcEwers`, `AddressFamily inet`),
  aber lege ihn erst nach meinem OK an.
- Auf dem NAS gibt es **kein sudo** und du brauchst auch keines: der Benutzer ist
  in der Gruppe `docker`.
- Mehrzeilige Befehle nicht in PowerShell-Strings verschachteln. Stattdessen:
  Skript als Datei unter `scripts/` im Repo anlegen und per
  `Get-Content -Raw .\scripts\<name>.sh | ssh -4 MarcEwers@<IPv4> bash -s`
  ausführen, oder Dateien per `scp -4` kopieren.
- **PowerShell-Fallen beim Schreiben von Dateien, die aufs NAS gehen:**
  - Zeilenenden müssen **LF** sein, nicht CRLF (sonst kaputte `.env`, kaputte
    Shell-Skripte, „$'\r': command not found").
  - Kodierung **UTF-8 ohne BOM** (PowerShell 5.1 `Out-File` schreibt sonst UTF-16
    bzw. BOM). Schreibe Dateien z. B. mit
    `[System.IO.File]::WriteAllText($pfad, $text, (New-Object System.Text.UTF8Encoding $false))`
    oder in PowerShell 7 mit `Set-Content -Encoding utf8NoBOM -NoNewline`.
  - Lege im Repo eine `.gitattributes` mit `* text eol=lf` an, damit Git die
    Zeilenenden nicht wieder auf CRLF umstellt.
  - Nach jedem Kopieren auf dem NAS prüfen: `file <datei>` (muss „ASCII/UTF-8 text",
    nicht „with CRLF line terminators" sagen) und `head -c 3 <datei> | xxd`
    (darf nicht mit `ef bb bf` beginnen).
- Der Ordnername enthält **Leerzeichen** → überall in Anführungszeichen setzen:
  in Shell-Befehlen, in `.env` (`UPLOAD_LOCATION="/volume1/…/Steves Bilder Archiv"`),
  in der Compose-Datei die **Langform** für Volumes verwenden
  (`type: bind`, `source: ${UPLOAD_LOCATION}`, `target: /data`) statt der
  Kurzform `pfad:/data`. Vor jedem `up` mit `docker compose config` prüfen, dass
  der Pfad korrekt aufgelöst wird.
- Die Compose-Dateien selbst legst du auf dem NAS in einem Pfad **ohne**
  Leerzeichen ab (z. B. `/volume1/docker/immich/`); nur `UPLOAD_LOCATION` zeigt
  auf den Ordner mit Leerzeichen.

## Bekannte Fakten (bereits gemessen)

- NAS: UGOS Pro, Hostname STEVENAS, Architektur arm64
- Docker 29.4.3, Compose v2
- Benutzer: uid=1001(MarcEwers) gid=10(admin), Mitglied der Gruppe docker → kein sudo nötig
- SSH per Public-Key vom Master-PC eingerichtet. Achtung IPv6-Falle: Verbindung
  über IPv4 erzwingen (ssh -4 oder IP-Adresse)
- RAM: 3,8 GB gesamt, nur ca. 1,3 GB verfügbar. Swap 5,9 GB vorhanden.
- /volume1: 3,6 TB, 2,6 TB frei
- Produktiv laufende Container, die NICHT gestört werden dürfen:
  heizung (homeassistant :8123, mosquitto :1883, brunner-bridge, port80-guard),
  sync (training-sync), mfp (mfp-server :8484, mfp-keepalive)
- Belegte Ports u. a.: 80, 443, 1883, 8123, 8484, 9443, 9999 (UGOS-Weboberfläche)
- System-Zeitzone steht auf Europe/Amsterdam; für Immich TZ=Europe/Berlin verwenden

## Harte Regeln

- Niemals `docker compose down`, `docker stop`, `docker rm`, `docker restart` auf
  Container anderer Projekte (heizung, sync, mfp). Alle Compose-Befehle nur mit
  `-p immich` bzw. aus dem Immich-Projektverzeichnis und nie mit `-v`.
- Kein `docker system prune`, kein `docker image prune -a`, kein `docker network prune`.
- Keine Änderungen an UGOS-Systemdateien, keine Änderungen an bestehenden Shares
  oder deren Rechten, keine Änderungen an der Firewall.
- Keine Ports verwenden, die bereits belegt sind. Nur 2283 (nach Prüfung) nach
  außen veröffentlichen; Postgres und Valkey bleiben ohne Host-Port.
- Kein Image-Tag und keine Umgebungsvariable erfinden. Grundlage sind
  ausschließlich die **offizielle `docker-compose.yml` und `example.env` des
  aktuellen Immich-Releases**
  (https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml
  und …/example.env). Lade sie herunter, lies sie, und leite alle Anpassungen davon ab.
- Geheimnisse (`DB_PASSWORD`) nur in `.env`, niemals in `docker-compose.yml`,
  niemals ins Git. Das Postgres-Passwort darf laut Immich-Doku nur aus `A-Za-z0-9`
  bestehen (keine Sonderzeichen).
- Wenn etwas unklar ist oder ein Befehl anders ausgeht als erwartet: anhalten,
  Ausgabe zeigen, fragen. Nicht raten, nicht „reparieren".

## Phase 0 – Verbindung (lesend)

1. IPv4-Adresse des NAS ermitteln, `ssh -4 MarcEwers@<IPv4> 'hostname; id; uname -m; docker version --format "{{.Server.Version}}"; docker compose version'`.
2. Bestätige, dass die Fakten oben stimmen. Weiche eine ab, sag es mir zuerst.

## Phase 1 – Noch zu ermitteln (zuerst, nur lesend)

Führe aus und fasse die Ergebnisse in einer Tabelle zusammen:

- CPU-Kerne: `nproc`, `lscpu | head -20`, `cat /proc/cpuinfo | grep -m1 -i model`
- Speicher: `free -m`, `cat /proc/swaps`, `cat /proc/sys/vm/swappiness`
- Plattenlayout: `lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT`, `cat /proc/mdstat`,
  `df -h /volume1`, `mount | grep -E "volume1|btrfs|ext4"` → ist /volume1 HDD oder SSD?
  (`cat /sys/block/*/queue/rotational`)
- RAM je laufendem Container: `docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.CPUPerc}}"`
- Bestehende Compose-Projekte und deren Konventionen (wo liegen Compose-Dateien,
  Daten, `.env`?): `docker compose ls -a`,
  `docker inspect --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' $(docker ps -q) | sort -u`,
  `ls -la /volume1/docker 2>/dev/null`, `ls -la /volume1`
  → Immich soll demselben Muster folgen wie die bestehenden Projekte.
- Ist Port 2283 frei: `ss -tlnp | grep -E ":2283\b" || echo "2283 frei"`,
  zusätzlich `docker ps --format "{{.Names}}\t{{.Ports}}"` und
  `netstat -tlnp 2>/dev/null | grep 2283`
- Der echte Linux-Pfad hinter der Windows-Freigabe
  `\\STEVENAS\personal_folder\Steves Bilder Archiv`:
  `testparm -s 2>/dev/null | grep -A5 -i personal`, `cat /etc/samba/smb.conf 2>/dev/null | grep -B2 -A6 -i personal`,
  `find /volume1 -maxdepth 4 -type d -iname "*Bilder Archiv*" 2>/dev/null`,
  `getent passwd MarcEwers` (Home-Verzeichnis, oft liegt `personal_folder` dort).
  Ergebnis mit `ls -la "<pfad>"` und `stat "<pfad>"` verifizieren (Eigentümer,
  Gruppe, Rechte, wirklich leer?). Prüfe auch, ob es ein Symlink ist
  (`readlink -f`), und nutze im Zweifel den aufgelösten Zielpfad.
- Schreibtest als aktueller Benutzer:
  `touch "<pfad>/.immich-schreibtest" && rm "<pfad>/.immich-schreibtest"`
  (Das ist eine harmlose Änderung; trotzdem vorher ankündigen.)
- Docker-Bridge-Netz und Adressbereiche, um Kollisionen zu vermeiden:
  `docker network ls`, `ip -4 addr | grep inet`
- Erreichbarkeit von GitHub/ghcr.io vom NAS aus (für `docker pull`):
  `curl -4 -sI https://ghcr.io | head -1`
- Aktuelles Immich-Release: `curl -4 -s https://api.github.com/repos/immich-app/immich/releases/latest | grep tag_name`

## Phase 2 – Plan vorlegen und Entscheidungen einholen

Lege mir **vor** dem Anlegen irgendeiner Datei einen Plan mit folgenden Punkten
vor und warte auf meine Antworten:

1. **RAM-Strategie.** 1,3 GB frei ist für Immich knapp (Empfehlung der Doku:
   4 GB+). Schlag konkret vor, wie viel RAM Immich-Server, Postgres, Valkey und
   Machine-Learning jeweils bekommen und wie du das begrenzt
   (`deploy.resources.limits.memory` in Compose v2). Meine Präferenz, sofern die
   Messung nichts anderes ergibt:
   - Machine-Learning-Container zunächst **nicht** starten (Service in der
     Compose-Datei auskommentiert lassen bzw. Profil) und Smart Search /
     Gesichtserkennung in den Admin-Einstellungen ausgeschaltet lassen. Später
     bei Bedarf gezielt aktivieren.
   - Postgres mit reduziertem `shared_buffers`, falls die offizielle Compose-Datei
     das über `command:` setzt (nur ändern, was dort schon steht).
   - `DB_STORAGE_TYPE=HDD` setzen, falls /volume1 auf rotierenden Platten liegt
     und die Variable in `example.env` existiert.
   - Harte Limits so wählen, dass die produktiven Container ihren aktuellen
     Verbrauch plus Reserve behalten.
2. **Pfade.** Vorschlag, nach Vorbild der bestehenden Projekte:
   - Compose-Projekt: `/volume1/docker/immich/` (oder der ermittelte Konventionspfad)
   - `UPLOAD_LOCATION` = der ermittelte Linux-Pfad von „Steves Bilder Archiv"
   - `DB_DATA_LOCATION` = `/volume1/docker/immich/postgres` (Postgres **nicht**
     in den Foto-Ordner, nicht auf eine SMB-Freigabe)
3. **Ordnerlayout im Foto-Ordner.** Erkläre mir kurz, dass Immich in
   `UPLOAD_LOCATION` seine eigenen Unterordner anlegt (`library/`, `upload/`,
   `thumbs/`, `encoded-video/`, `profile/`, `backups/`) und dort niemand manuell
   Dateien ablegen soll. Frage mich, ob ich
   - a) den ganzen Ordner Immich überlassen will (einfachste Variante), oder
   - b) einen Unterordner `immich/` als `UPLOAD_LOCATION` und daneben einen
     Unterordner `import/` will, den ich später als **External Library**
     (read-only) einbinde, um bestehende Fotos per SMB dorthin zu kopieren.
   Gib eine Empfehlung ab.
4. **Version.** `IMMICH_VERSION` auf den konkreten, aktuellen Release-Tag pinnen
   (z. B. `v2.x.y`) statt `release`, damit Updates bewusst passieren. Nenne den Tag.
5. **Port.** 2283 (falls frei) auf `127.0.0.1`? Nein: Immich soll im LAN unter
   `http://STEVENAS:2283` erreichbar sein, also auf allen Interfaces, aber nur im
   LAN (keine Portweiterleitung im Router, kein Reverse-Proxy in diesem Schritt).
6. **Zeitzone.** `TZ=Europe/Berlin` in `.env`.
7. **Neustartverhalten.** `restart: always` wie im offiziellen Compose-File
   beibehalten, damit Immich nach NAS-Neustart wieder hochkommt.

## Phase 3 – Dateien im Repo anlegen (nach OK)

Lege im Repo `ImmichBilderArchiv` folgende Struktur an, jede Datei einzeln
ankündigen und zeigen:

```
.gitattributes            # * text eol=lf
.gitignore                # .env, *.bak, Backups
immich/docker-compose.yml # aus der offiziellen Datei abgeleitet, Änderungen als Kommentar markiert
immich/.env               # echte Werte, NICHT committen
immich/.env.example       # gleiche Schlüssel, Platzhalter statt Passwort
scripts/probe.sh          # die Lese-Befehle aus Phase 1, wiederverwendbar
scripts/deploy.ps1        # scp der Dateien aufs NAS + Encoding-/LF-Prüfung
docs/RUNBOOK.md           # Betrieb: starten, stoppen, Logs, Update, Backup, Wiederherstellung
```

Anforderungen an `docker-compose.yml`:
- Ausgangspunkt ist die offizielle Datei des gepinnten Releases; jede Abweichung
  bekommt einen Kommentar `# ANPASSUNG: …` mit Begründung.
- `name: immich` als Projektname.
- Volumes in Langform (siehe oben), `UPLOAD_LOCATION` und `DB_DATA_LOCATION` aus `.env`.
- Speicherlimits gemäß Phase 2.
- Kein Host-Port außer 2283 am Server.
- `docker compose -f immich/docker-compose.yml --env-file immich/.env config`
  lokal (falls Docker Desktop vorhanden) oder auf dem NAS ausführen und mir die
  aufgelöste Ausgabe zeigen, bevor irgendetwas gestartet wird.

`.env`: `UPLOAD_LOCATION` in Anführungszeichen, `DB_PASSWORD` zufällig, 32 Zeichen,
nur `A-Za-z0-9` (z. B. per `-join ((48..57)+(65..90)+(97..122) | Get-Random -Count 32 | % {[char]$_})`).

## Phase 4 – Übertragen und starten (jeder Schritt einzeln mit OK)

1. Verzeichnisse auf dem NAS anlegen: `mkdir -p /volume1/docker/immich/postgres`
   (bzw. Konventionspfad). Rechte prüfen, nichts per `chmod 777`.
2. Dateien per `scp -4` kopieren, danach LF/BOM-Prüfung auf dem NAS (siehe oben)
   und `sha256sum` lokal vs. NAS vergleichen.
3. `docker compose config` auf dem NAS → aufgelöste Datei zeigen.
4. `docker compose pull` (nur Images laden, nichts starten). Freien Platz vorher
   und nachher zeigen.
5. `docker compose up -d` **nur** für `database` und `redis`/`valkey`, dann
   `docker compose logs --tail 50 database` prüfen (Migrationen, „ready to accept
   connections").
6. `docker compose up -d immich-server`, dann Logs verfolgen, bis
   „Immich Server is listening" erscheint. Bei Fehlern: anhalten, Logs zeigen.
7. `docker stats --no-stream` für **alle** Container: bestätigen, dass die
   produktiven Container unverändert laufen und wie viel RAM Immich wirklich nimmt.

## Phase 5 – Verifizierung (lesend)

- `docker compose ps` → alle Immich-Container `healthy`/`running`.
- Auf dem NAS: `curl -4 -s http://localhost:2283/api/server/ping` → erwartet `{"res":"pong"}`.
- Vom PC: `Invoke-WebRequest -UseBasicParsing http://<IPv4>:2283/api/server/ping`.
- `docker compose logs --tail 100` ohne ERROR-Zeilen.
- `free -m` und `docker stats --no-stream` erneut; Vergleich mit Phase 1.
- Prüfen, dass HomeAssistant (:8123), MQTT (:1883) und mfp (:8484) weiterhin
  antworten (nur `ss -tlnp` bzw. ein `curl -sI`, keine Neustarts).
- Prüfen, dass Immich in `UPLOAD_LOCATION` seine Unterordner angelegt hat und
  diese über die Windows-Freigabe `\\STEVENAS\personal_folder\Steves Bilder Archiv`
  sichtbar sind (ich prüfe das im Explorer, du sagst mir, was ich sehen müsste).

## Phase 6 – Ersteinrichtung in der Web-Oberfläche (Anleitung für mich)

Schreibe mir eine kurze Checkliste für `http://<IPv4>:2283`:
1. Admin-Konto anlegen (erster Benutzer).
2. Verwaltung → Einstellungen → Maschinelles Lernen: ausschalten, solange der
   ML-Container nicht läuft (sonst Fehlermeldungen in den Jobs).
3. Storage Template aktivieren und ein Muster vorschlagen
   (z. B. `{{y}}/{{y}}-{{MM}}/{{filename}}`), damit die Ordnerstruktur im
   Archiv lesbar bleibt.
4. Datenbank-Backup-Job (automatischer Dump nach `backups/`) prüfen, Zeitpunkt
   nachts.
5. Optional: External Library für `import/` anlegen (falls in Phase 2 gewählt) –
   dazu muss der Ordner zusätzlich read-only in den Server gemountet werden; das
   wäre eine spätere Compose-Änderung, erst nach meinem OK.
6. Mobile App: Server-URL `http://<IPv4>:2283` (nur im LAN, kein externer Zugriff).

## Phase 7 – Abschluss

- `docs/RUNBOOK.md` fertigstellen: Start/Stop (`docker compose -p immich …`),
  Logs, Update-Ablauf (Release Notes lesen → `IMMICH_VERSION` ändern →
  `pull` → `up -d`), Backup (DB-Dump in `backups/` + `UPLOAD_LOCATION` +
  `.env`), Wiederherstellung, was bei RAM-Not zu tun ist, wie man den
  ML-Container später gezielt aktiviert.
- Alle Repo-Dateien außer `.env` committen (Commit-Nachricht auf Deutsch,
  beschreibend). Push erst nach meinem OK.
- Zum Schluss eine Zusammenfassung: was läuft, wo liegen Daten, welche Ports,
  wie viel RAM, was ist bewusst noch nicht aktiviert (ML, External Library,
  Reverse-Proxy/HTTPS, externer Zugriff).
