<#
.SYNOPSIS
    Benennt Immich-Alben nach einer geprueften Vorschlagsliste um.

.DESCRIPTION
    Liest die CSV aus album-vorschlag.ps1 und benennt nur Zeilen mit Aktion "umbenennen" um, deren
    "Neuer Name" sich vom aktuellen unterscheidet. Ohne -Anwenden wird nur gezeigt, was passieren
    wuerde. Geloescht wird nichts. Die Ordner auf der Platte zieht die naechtliche
    Speicher-Migration nach (oder sofort: Verwaltung -> Aufgaben -> Speicher-Migration).

.EXAMPLE
    .\scripts\album-umbenennen.ps1 -Liste "listen\2026-09-21 Album-Vorschlag.csv"
    .\scripts\album-umbenennen.ps1 -Liste "listen\2026-09-21 Album-Vorschlag.csv" -Anwenden
#>
param(
    [Parameter(Mandatory)][string]$Liste,
    [switch]$Anwenden,
    [string]$Server = 'http://192.168.2.101:2283'
)
$h = @{ 'x-api-key' = (Get-Content (Join-Path $env:USERPROFILE '.immich\api-key') -Raw).Trim() }
$aktuell = @{}
foreach ($a in (Invoke-RestMethod -Uri "$Server/api/albums" -Headers $h -TimeoutSec 60)) { $aktuell[$a.id] = $a.albumName }

foreach ($z in (Import-Csv -Path $Liste -Delimiter ';' -Encoding UTF8 | Where-Object Aktion -eq 'umbenennen')) {
    $neu = $z.'Neuer Name'.Trim()
    if (-not $aktuell.ContainsKey($z.Id)) { Write-Warning "Album nicht mehr vorhanden: $($z.Album)"; continue }
    if ($aktuell[$z.Id] -eq $neu -or -not $neu) { continue }
    if ($neu -notmatch '^\d{4}-\d{2}-\d{2} \S') { Write-Warning "Uebersprungen, passt nicht zum Schema: '$neu'"; continue }
    if ($Anwenden) {
        $body = [System.Text.Encoding]::UTF8.GetBytes((@{ albumName = $neu } | ConvertTo-Json))
        Invoke-RestMethod -Uri "$Server/api/albums/$($z.Id)" -Method Patch -Headers $h -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 30 | Out-Null
        "umbenannt:  $($aktuell[$z.Id])  ->  $neu"
    } else {
        "wuerde umbenennen:  $($aktuell[$z.Id])  ->  $neu"
    }
}
if (-not $Anwenden) { "`nNichts geaendert. Zum Umsetzen mit -Anwenden aufrufen." }