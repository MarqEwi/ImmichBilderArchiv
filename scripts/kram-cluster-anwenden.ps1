<#
.SYNOPSIS
    Erstellt aus ausgewaehlten Clustern (siehe kram-cluster-vorschlag.ps1) echte Ereignis-Alben.

.DESCRIPTION
    Liest die CSV und nimmt nur Zeilen mit ausgefuelltem "Neuer Titel". Beginnt der Titel nicht
    bereits mit einem Datum (YYYY-MM-DD), wird das Cluster-Startdatum vorangestellt. Legt je Zeile
    ein neues Immich-Album mit genau diesem Namen an und fuegt die zugehoerigen Dateien (aus der
    JSON-Zuordnung) hinzu.

    Die Dateien bleiben zusaetzlich in ihrem bisherigen Sammelalbum (WhatsApp Images o. Ae.) - das
    wird bewusst nicht angefasst. Fuer den Ordner auf der Platte reicht das: Immich waehlt bei
    Mehrfachzugehoerigkeit das zuletzt ERSTELLTE Album, und das neue Ereignis-Album ist immer
    juenger als das Jahre alte Sammelalbum, gewinnt also automatisch den Vorrang.

    Ohne -Anwenden nur Trockenlauf. Nach dem Anwenden zieht die naechtliche Speicher-Migration die
    Ordner nach, oder man stoesst sie sofort an (Verwaltung -> Aufgaben, oder ueber die API).

.EXAMPLE
    .\scripts\kram-cluster-anwenden.ps1 -Liste "listen\2026-09-27 Kram-Cluster.csv" -Zuordnung "listen\2026-09-27 Kram-Cluster.json"
    .\scripts\kram-cluster-anwenden.ps1 -Liste "..." -Zuordnung "..." -Anwenden
#>
param(
    [Parameter(Mandatory)][string]$Liste,
    [Parameter(Mandatory)][string]$Zuordnung,
    [switch]$Anwenden,
    [string]$Server = 'http://192.168.2.101:2283'
)
$h = @{ 'x-api-key' = (Get-Content (Join-Path $env:USERPROFILE '.immich\api-key') -Raw).Trim() }
$map = Get-Content $Zuordnung -Raw | ConvertFrom-Json

$zeilen = Import-Csv -Path $Liste -Delimiter ';' -Encoding UTF8 | Where-Object { $_.'Neuer Titel'.Trim() -ne '' }
if (-not $zeilen) { "Keine Zeile mit ausgefuelltem 'Neuer Titel' gefunden. Nichts zu tun."; return }

$plan = foreach ($z in $zeilen) {
    $titel = $z.'Neuer Titel'.Trim()
    if ($titel -notmatch '^\d{4}-\d{2}-\d{2} \S') { $titel = "$($z.Von) $titel" }
    $ids = $map.($z.ClusterId)
    if (-not $ids -or $ids.Count -eq 0) { Write-Warning "Cluster $($z.ClusterId): keine Asset-Ids in der Zuordnung gefunden - uebersprungen"; continue }
    [pscustomobject]@{ ClusterId = $z.ClusterId; Titel = $titel; AnzahlDateien = $ids.Count; Ids = $ids }
}

"Geplante neue Alben: $(@($plan).Count)"
$plan | ForEach-Object { "  Cluster {0,-4} {1,-45} {2} Dateien" -f $_.ClusterId, $_.Titel, $_.AnzahlDateien }

if (-not $Anwenden) {
    ""; "Trockenlauf - nichts erstellt. Zum Umsetzen mit -Anwenden aufrufen."
    return
}

foreach ($p in $plan) {
    $body = @{ albumName = $p.Titel; assetIds = @($p.Ids) } | ConvertTo-Json
    try {
        $neu = Invoke-RestMethod -Uri "$Server/api/albums" -Method Post -Headers $h -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 60
        "erstellt: $($p.Titel)  ($($neu.assetCount) Dateien, Id $($neu.id))"
    } catch {
        Write-Warning "$($p.Titel): $($_.Exception.Message) $($_.ErrorDetails.Message)"
    }
}
"`nFertig. Ordner auf der Platte: Speicher-Migration anstossen (Verwaltung -> Aufgaben, oder heute Nacht automatisch)."
