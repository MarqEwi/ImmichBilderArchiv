<#
.SYNOPSIS
    Gruppiert die Dateien aus den Sammelalben (WhatsApp, Screenshots, Downloads, ...) nach
    zeitlicher Naehe, damit man darin verborgene echte Ereignisse erkennen und benennen kann.
    Liest nur, aendert nichts.

.DESCRIPTION
    Alben wie "WhatsApp Images" oder "Download" sind Sammelbecken ohne einzelnes Ereignis - sie
    laufen ueber Monate bis Jahre. Manche der darin liegenden Fotos gehoeren aber inhaltlich zu
    echten Ereignissen (z. B. per WhatsApp empfangene Urlaubsfotos). Dieses Skript clustert alle
    Dateien dieser Alben nach Datum: liegen zwei Aufnahmetage nicht mehr als -LueckeTage auseinander,
    zaehlen sie zum selben Cluster.

    Ergebnis sind zwei Dateien unter listen\:
      <Datum> Kram-Cluster.csv   - eine Zeile je Cluster, zum Durchsehen und Ausfuellen
      <Datum> Kram-Cluster.json  - Cluster-Id -> Asset-Ids, wird von kram-cluster-anwenden.ps1 gebraucht

    In der CSV die Spalte "Neuer Titel" fuer Cluster ausfuellen, die ein eigenes Ereignis-Album
    verdienen (z. B. "2024-12 Weihnachten bei Oma", ruhig mit oder ohne Datum - das Skript stellt
    das Cluster-Datum voran, wenn noch keines am Anfang steht). Leer lassen = bleibt im Sammelalbum.

.EXAMPLE
    .\scripts\kram-cluster-vorschlag.ps1
    .\scripts\kram-cluster-vorschlag.ps1 -LueckeTage 5 -MinDateien 3
#>
param(
    [string]$Server = 'http://192.168.2.101:2283',
    [int]$LueckeTage = 3,
    [int]$MinDateien = 2
)
$h = @{ 'x-api-key' = (Get-Content (Join-Path $env:USERPROFILE '.immich\api-key') -Raw).Trim() }
$kram = 'Screenshots','WhatsApp','WhatsApp Video','WhatsApp Images','WhatsApp Animated Gifs','Instagram',
        'eBay','Meme','Wallpaper','Download','PokemonGO','Signal','Quick Share','Edits','Video Editor','Profilbilder'

$alben = Invoke-RestMethod -Uri "$Server/api/albums" -Headers $h -TimeoutSec 30
$kramAlben = $alben | Where-Object { $kram -contains $_.albumName -and $_.assetCount -gt 0 }
Write-Host "Sammelalben: $($kramAlben.Count) ($(($kramAlben | Measure-Object assetCount -Sum).Sum) Dateien, mit Ueberschneidungen)"

# id -> [pscustomobject]{ Datum; Datei; Alben (Set) }
$alle = @{}
foreach ($al in $kramAlben) {
    $page = 1
    do {
        $body = @{ albumIds = @($al.id); size = 1000; page = $page; withExif = $false } | ConvertTo-Json
        $r = Invoke-RestMethod -Uri "$Server/api/search/metadata" -Method Post -Headers $h -ContentType 'application/json' -Body $body -TimeoutSec 60
        foreach ($a in $r.assets.items) {
            if (-not $alle.ContainsKey($a.id)) {
                $alle[$a.id] = [pscustomobject]@{ Id = $a.id; Datum = ([datetime]$a.localDateTime).Date; Datei = $a.originalFileName; Alben = [System.Collections.Generic.HashSet[string]]::new() }
            }
            [void]$alle[$a.id].Alben.Add($al.albumName)
        }
        $page = if ($r.assets.nextPage) { [int]$r.assets.nextPage } else { $null }
    } while ($page)
}
Write-Host "Eindeutige Dateien: $($alle.Count)"

$sortiert = $alle.Values | Sort-Object Datum
$cluster = @()
$aktuell = $null
foreach ($a in $sortiert) {
    if ($null -eq $aktuell) {
        $aktuell = [pscustomobject]@{ Von = $a.Datum; Bis = $a.Datum; Items = [System.Collections.Generic.List[object]]::new() }
    } elseif (($a.Datum - $aktuell.Bis).TotalDays -gt $LueckeTage) {
        $cluster += $aktuell
        $aktuell = [pscustomobject]@{ Von = $a.Datum; Bis = $a.Datum; Items = [System.Collections.Generic.List[object]]::new() }
    }
    $aktuell.Bis = $a.Datum
    $aktuell.Items.Add($a)
}
if ($aktuell) { $cluster += $aktuell }
Write-Host "Cluster gesamt: $($cluster.Count), davon mit mindestens $MinDateien Dateien: $(@($cluster | Where-Object { $_.Items.Count -ge $MinDateien }).Count)"

$ordner = Join-Path (Split-Path -Parent $PSScriptRoot) 'listen'
New-Item -ItemType Directory -Force -Path $ordner | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-dd'
$csvPfad = Join-Path $ordner "$stamp Kram-Cluster.csv"
$jsonPfad = Join-Path $ordner "$stamp Kram-Cluster.json"

$i = 0
$zeilen = foreach ($c in ($cluster | Where-Object { $_.Items.Count -ge $MinDateien } | Sort-Object Von)) {
    $i++
    $tage = [int]($c.Bis - $c.Von).TotalDays
    $albenListe = ($c.Items.Alben | Select-Object -Unique | Sort-Object) -join ', '
    $beispiele = ($c.Items | Select-Object -First 3 -ExpandProperty Datei) -join ', '
    [pscustomobject]@{
        ClusterId = $i; Von = $c.Von.ToString('yyyy-MM-dd'); Bis = $c.Bis.ToString('yyyy-MM-dd')
        Tage = $tage; Dateien = $c.Items.Count; Alben = $albenListe; Beispiele = $beispiele; 'Neuer Titel' = ''
    }
}
$zeilen | Export-Csv -Path $csvPfad -Delimiter ';' -NoTypeInformation -Encoding UTF8

$map = @{}
$i = 0
foreach ($c in ($cluster | Where-Object { $_.Items.Count -ge $MinDateien } | Sort-Object Von)) {
    $i++
    $map["$i"] = @($c.Items | ForEach-Object { $_.Id })
}
($map | ConvertTo-Json -Depth 5) -replace "`r`n", "`n" | Set-Content -Path $jsonPfad -Encoding UTF8 -NoNewline

Write-Host ""
$zeilen | Format-Table ClusterId, Von, Bis, Tage, Dateien, Alben, Beispiele -AutoSize | Out-String -Width 220 | Write-Host
Write-Host "Liste:  $csvPfad"
Write-Host "Zuordnung (fuer kram-cluster-anwenden.ps1): $jsonPfad"
Write-Host ""
Write-Host "In der CSV 'Neuer Titel' fuer Cluster ausfuellen, die ein eigenes Album verdienen. Dann:"
Write-Host "  .\scripts\kram-cluster-anwenden.ps1 -Liste `"$csvPfad`" -Zuordnung `"$jsonPfad`""
