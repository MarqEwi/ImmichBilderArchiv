<#
.SYNOPSIS
    Erstellt eine Vorschlagsliste, wie die Immich-Alben ins Schema "YYYY-MM-DD Titel" kommen. Liest nur.

.DESCRIPTION
    Je Album: Anzahl, aelteste und juengste Aufnahme, Vorschlag und Aktion. Das Ergebnis ist eine CSV
    unter listen\ (nicht im Git, enthaelt Namen). Dort die Spalten "Neuer Name" und "Aktion" anpassen,
    dann mit album-umbenennen.ps1 umsetzen.

    Aktion:  umbenennen   - Ereignis, bekommt das Datum der aeltesten Aufnahme vorangestellt
             behalten     - folgt dem Schema schon, oder Sammlung ueber laengere Zeit (Person, Thema)
             aussortieren - kein Archivmaterial (Screenshots, Messenger ...); nur ein Hinweis,
                            geloescht wird von keinem Skript
             leer         - noch keine Dateien angekommen
#>
param(
    [string]$Server = 'http://192.168.2.101:2283',
    [int]$EreignisMaxTage = 14
)
$h = @{ 'x-api-key' = (Get-Content (Join-Path $env:USERPROFILE '.immich\api-key') -Raw).Trim() }
$kram = 'Screenshots','WhatsApp','WhatsApp Video','WhatsApp Images','WhatsApp Animated Gifs','Instagram',
        'eBay','Meme','Wallpaper','Download','PokemonGO','Signal','Quick Share','Edits','Video Editor','Profilbilder'

$zeilen = foreach ($a in (Invoke-RestMethod -Uri "$Server/api/albums" -Headers $h -TimeoutSec 60)) {
    $von = if ($a.startDate) { ([datetime]$a.startDate).ToLocalTime() } else { $null }
    $bis = if ($a.endDate)   { ([datetime]$a.endDate).ToLocalTime() }   else { $null }
    $tage = if ($von -and $bis) { [int]($bis.Date - $von.Date).TotalDays } else { 0 }
    $neu = $a.albumName
    if     ($a.assetCount -eq 0)                        { $aktion = 'leer' }
    elseif ($kram -contains $a.albumName)               { $aktion = 'aussortieren' }
    elseif ($a.albumName -match '^\d{4}-\d{2}-\d{2} ')  { $aktion = 'behalten' }
    elseif ($tage -gt $EreignisMaxTage)                 { $aktion = 'behalten' }
    else { $aktion = 'umbenennen'; $neu = '{0:yyyy-MM-dd} {1}' -f $von, $a.albumName }
    [pscustomobject]@{
        Album = $a.albumName; Dateien = $a.assetCount
        Von = if ($von) { $von.ToString('yyyy-MM-dd') } else { '' }
        Bis = if ($bis) { $bis.ToString('yyyy-MM-dd') } else { '' }
        Tage = $tage; 'Neuer Name' = $neu; Aktion = $aktion; Id = $a.id
    }
}
$zeilen = $zeilen | Sort-Object @{e={@('umbenennen','behalten','aussortieren','leer').IndexOf($_.Aktion)}}, Von

$ordner = Join-Path (Split-Path -Parent $PSScriptRoot) 'listen'
New-Item -ItemType Directory -Force -Path $ordner | Out-Null
$datei = Join-Path $ordner ("{0:yyyy-MM-dd} Album-Vorschlag.csv" -f (Get-Date))
$zeilen | Export-Csv -Path $datei -Delimiter ';' -NoTypeInformation -Encoding UTF8
$zeilen | Where-Object Aktion -ne 'leer' | Format-Table Album, Dateien, Von, Bis, Tage, 'Neuer Name', Aktion -AutoSize
"Leere Alben (Upload noch nicht dort angekommen): $(($zeilen | Where-Object Aktion -eq 'leer').Count)"
"Liste: $datei"