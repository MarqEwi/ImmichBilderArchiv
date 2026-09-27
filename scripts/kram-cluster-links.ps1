<#
.SYNOPSIS
    Erzeugt einen Freigabe-Link je Cluster, um sich die tatsaechlichen Bilder anzusehen.

.DESCRIPTION
    Legt fuer jeden Cluster aus der CSV (kram-cluster-vorschlag.ps1) einen Immich-Freigabe-Link
    ("Shared Link") mit genau dessen Dateien an - bewusst KEIN Album, damit die Speicher-Migration
    nichts verschiebt. Der Link zeigt eine Galerie im Browser, mit Download-Knopf, laueft nach
    -GueltigTage von selbst ab (Vorgabe 14 Tage) und muss nicht manuell aufgeraeumt werden.

    Liest die bestehende CSV EIN (nicht neu erzeugt), damit bereits eingetragene "Neuer Titel"
    erhalten bleiben, und schreibt sie mit einer zusaetzlichen Spalte "Link" davor zurueck.
    Excel macht aus der URL automatisch einen klickbaren Link.

    Zum Loeschen von Dateien: der Link fuehrt in die normale Immich-Oberflaeche (nur ohne Login-
    Zwang); dort laesst sich wie gewohnt mehrfach auswaehlen und loeschen (Papierkorb, 30 Tage,
    siehe Systemeinstellungen). Das faellt nicht in den Bereich dieses Skripts - es zeigt nur an.

.EXAMPLE
    .\scripts\kram-cluster-links.ps1 -Liste "listen\2026-09-27 Kram-Cluster.csv" -Zuordnung "listen\2026-09-27 Kram-Cluster.json"
#>
param(
    [Parameter(Mandatory)][string]$Liste,
    [Parameter(Mandatory)][string]$Zuordnung,
    [int]$GueltigTage = 14,
    [string]$Server = 'http://192.168.2.101:2283'
)
$h = @{ 'x-api-key' = (Get-Content (Join-Path $env:USERPROFILE '.immich\api-key') -Raw).Trim() }
$map = Get-Content $Zuordnung -Raw | ConvertFrom-Json
$zeilen = Import-Csv -Path $Liste -Delimiter ';' -Encoding UTF8
$ablauf = (Get-Date).AddDays($GueltigTage).ToString('yyyy-MM-ddTHH:mm:ss.000Z')

$ergebnis = foreach ($z in $zeilen) {
    $ids = $map.($z.ClusterId)
    $link = ''
    if ($ids -and $ids.Count -gt 0) {
        $beschr = "Cluster $($z.ClusterId): $($z.Von) bis $($z.Bis) ($($ids.Count) Dateien)"
        $body = @{ type = 'INDIVIDUAL'; assetIds = @($ids); allowDownload = $true; showMetadata = $true; description = $beschr; expiresAt = $ablauf } | ConvertTo-Json
        try {
            $r = Invoke-RestMethod -Uri "$Server/api/shared-links" -Method Post -Headers $h -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 30
            $link = "$Server/share/$($r.key)"
        } catch {
            Write-Warning "Cluster $($z.ClusterId): $($_.Exception.Message)"
        }
    }
    # Neue Spaltenreihenfolge: ..., Beispiele, Link, Neuer Titel
    [pscustomobject]@{
        ClusterId = $z.ClusterId; Von = $z.Von; Bis = $z.Bis; Tage = $z.Tage; Dateien = $z.Dateien
        Alben = $z.Alben; Beispiele = $z.Beispiele; Link = $link; 'Neuer Titel' = $z.'Neuer Titel'
    }
}
$ergebnis | Export-Csv -Path $Liste -Delimiter ';' -NoTypeInformation -Encoding UTF8

"$(@($ergebnis | Where-Object Link).Count) Links erstellt, gueltig bis $((Get-Date).AddDays($GueltigTage).ToString('yyyy-MM-dd'))."
"Liste aktualisiert: $Liste"
"Bitte in Excel/Editor neu oeffnen (falls schon offen), sonst werden die Links nicht angezeigt."
