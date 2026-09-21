<#
.SYNOPSIS
    Kopiert die Immich-Konfiguration auf die NAS und prueft Kodierung, Zeilenenden und Pruefsummen.

.DESCRIPTION
    Vor dem Kopieren wird jede Datei geprueft: LF-Zeilenenden, UTF-8 ohne BOM. Nach dem Kopieren
    wird auf der NAS "file" ausgefuehrt und sha256sum beider Seiten verglichen. Die .env wird
    zusaetzlich auf chmod 600 gesetzt.

    Startet nichts. Container werden bewusst von Hand gestartet (siehe docs/RUNBOOK.md).

.EXAMPLE
    .\scripts\deploy.ps1
    .\scripts\deploy.ps1 -Nas 192.168.2.101 -Ziel /volume1/Grundlagen/docker/immich
#>
param(
    [string]$Nas   = '192.168.2.101',
    [string]$User  = 'MarcEwers',
    [string]$Ziel  = '/volume1/Grundlagen/docker/immich'
)

$ErrorActionPreference = 'Stop'
$repo  = Split-Path -Parent $PSScriptRoot
$ssh   = "$User@$Nas"

# Quelle -> Zielname. Die .env kommt zuletzt, damit sie bei einem Abbruch vorher nicht allein dasteht.
$dateien = [ordered]@{
    "$repo\immich\docker-compose.yml" = 'docker-compose.yml'
    "$repo\immich\migrate.sh"         = 'migrate.sh'
    "$repo\immich\.env"               = '.env'
}

Write-Host '== Vorpruefung (lokal) ==' -ForegroundColor Cyan
foreach ($quelle in $dateien.Keys) {
    if (-not (Test-Path $quelle)) { throw "Fehlt: $quelle" }
    $bytes = [System.IO.File]::ReadAllBytes($quelle)

    # BOM: UTF-8-BOM ist EF BB BF
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "$quelle beginnt mit UTF-8-BOM. Neu schreiben mit [System.IO.File]::WriteAllText(`$pfad, `$text, (New-Object System.Text.UTF8Encoding `$false))"
    }
    # CR (0x0D) darf nicht vorkommen
    $cr = ($bytes | Where-Object { $_ -eq 0x0D }).Count
    if ($cr -gt 0) { throw "$quelle enthaelt $cr CR-Bytes (CRLF). Auf LF umstellen, sonst scheitern .env und Shell-Skripte auf der NAS." }

    $hash = (Get-FileHash -Algorithm SHA256 -Path $quelle).Hash.ToLower()
    Write-Host ("  OK  {0,-22} {1} Bytes  sha256 {2}" -f (Split-Path $quelle -Leaf), $bytes.Length, $hash.Substring(0,16))
}

Write-Host "`n== Kopieren nach ${ssh}:$Ziel ==" -ForegroundColor Cyan
foreach ($quelle in $dateien.Keys) {
    $name = $dateien[$quelle]
    # Bewusst KEIN scp: scp laeuft ueber SFTP, und der SFTP-Dienst der NAS zeigt die Freigaben
    # als Wurzel (/Grundlagen/...) statt des echten Dateisystems (/volume1/Grundlagen/...).
    # scp scheitert deshalb mit: dest open "...": No such file or directory.
    # "type | ssh cat" nutzt dieselben Pfade wie jeder andere SSH-Befehl und bleibt byteweise.
    # Voraussetzung: Der private Schluessel muss fuer Windows-OpenSSH streng genug berechtigt
    # sein, sonst faellt ssh auf eine Passwortabfrage zurueck und das Skript haengt:
    #   icacls "$env:USERPROFILE\.ssh\id_ed25519" /inheritance:r /grant:r "$env:USERNAME:R"
    cmd /c "type `"$quelle`" | ssh -4 $ssh `"cat > '$Ziel/$name'`""
    if ($LASTEXITCODE -ne 0) { throw "Kopieren von $name fehlgeschlagen (Exitcode $LASTEXITCODE)" }
    Write-Host "  kopiert: $name"
}

ssh -4 $ssh "chmod 600 '$Ziel/.env'"

Write-Host "`n== Nachpruefung (auf der NAS) ==" -ForegroundColor Cyan
foreach ($quelle in $dateien.Keys) {
    $name  = $dateien[$quelle]
    $lokal = (Get-FileHash -Algorithm SHA256 -Path $quelle).Hash.ToLower()
    $fern  = (ssh -4 $ssh "sha256sum '$Ziel/$name' | cut -d' ' -f1").Trim()
    $art   = (ssh -4 $ssh "file -b '$Ziel/$name'").Trim()

    if ($lokal -ne $fern) { throw "$name unterscheidet sich! lokal $lokal, NAS $fern" }
    if ($art -match 'CRLF')  { throw "$name hat auf der NAS CRLF-Zeilenenden: $art" }
    if ($art -match 'BOM')   { throw "$name hat auf der NAS ein BOM: $art" }
    Write-Host ("  OK  {0,-22} {1}" -f $name, $art)
}

Write-Host "`nFertig. Nichts gestartet." -ForegroundColor Green
Write-Host "Naechster Schritt:  ssh -4 $ssh `"cd $Ziel && docker compose config`""
