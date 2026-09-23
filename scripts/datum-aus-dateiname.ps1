<#
.SYNOPSIS
    Korrigiert das Aufnahmedatum von Dateien, deren echtes Datum nur noch im Dateinamen steht.

.DESCRIPTION
    WhatsApp entfernt das EXIF-Aufnahmedatum. Immich nimmt dann das Dateidatum - nach einem
    Handy-Umzug ist das der Umzugstag (hier 19.04.2026), und alte Bilder landen im falschen Jahr.
    Das echte Datum steckt im Namen: IMG-20220127-WA0007.jpg -> 27.01.2022.

    Das Skript setzt dateTimeOriginal ueber die API, wenn das Datum im Namen um mehr als
    -ToleranzTage vom Immich-Datum abweicht. Uhrzeit 12:00 plus laufende WA-Nummer in Sekunden,
    damit die Reihenfolge eines Tages erhalten bleibt. Das Original wird nicht veraendert; Immich
    haelt die Korrektur in der Datenbank und einer XMP-Begleitdatei.

    Ohne -Anwenden nur Trockenlauf. Mehrfach ausfuehrbar: bereits korrigierte Dateien weichen
    nicht mehr ab und werden uebersprungen. Nach weiteren Uploads einfach erneut laufen lassen.
#>
param(
    [switch]$Anwenden,
    [int]$ToleranzTage = 2,
    [string]$Server = 'http://192.168.2.101:2283'
)
$h = @{ 'x-api-key' = (Get-Content (Join-Path $env:USERPROFILE '.immich\api-key') -Raw).Trim() }
$alle = @(); $page = 1
do {
    $r = Invoke-RestMethod -Uri "$Server/api/search/metadata" -Method Post -Headers $h -ContentType 'application/json' -Body (@{ size = 1000; page = $page } | ConvertTo-Json) -TimeoutSec 120
    $alle += $r.assets.items
    # nextPage kommt als Zeichenkette zurueck ("2"), nicht als Zahl. Ohne [int]-Umwandlung wuerde
    # ConvertTo-Json daraus "page": "2" statt "page": 2 machen; die API lehnt das mit einem
    # Validierungsfehler ab, $page bliebe dieselbe kaputte Zeichenkette, und while ($page) liefe
    # endlos weiter, weil ein nicht-leerer String immer wahr ist.
    $page = if ($r.assets.nextPage) { [int]$r.assets.nextPage } else { $null }
} while ($page)

$muster = '(?<![0-9])(20[0-2][0-9])[-_]?(0[1-9]|1[0-2])[-_]?([0-2][0-9]|3[01])(?![0-9])'
$plan = foreach ($a in $alle) {
    if ($a.originalFileName -notmatch $muster) { continue }
    try { $tag = [datetime]::ParseExact("$($Matches[1])$($Matches[2])$($Matches[3])", 'yyyyMMdd', $null) } catch { continue }
    if ($tag -gt (Get-Date)) { continue }
    if ([math]::Abs((([datetime]$a.localDateTime).Date - $tag).TotalDays) -le $ToleranzTage) { continue }
    $sek = if ($a.originalFileName -match 'WA(\d+)') { [int]$Matches[1] % 3600 } else { 0 }
    [pscustomobject]@{ Id = $a.id; Datei = $a.originalFileName; Bisher = ([datetime]$a.localDateTime).ToString('yyyy-MM-dd'); Neu = $tag.AddHours(12).AddSeconds($sek) }
}
$plan = @($plan)
"Geprueft: $($alle.Count) Dateien, zu korrigieren: $($plan.Count)"
$plan | Group-Object { $_.Neu.Year } | Sort-Object Name | ForEach-Object { "  {0}: {1,4} Dateien" -f $_.Name, $_.Count }

if (-not $Anwenden) {
    ""; "Beispiele:"; $plan | Select-Object -First 6 | ForEach-Object { "  {0,-34} {1} -> {2:yyyy-MM-dd HH:mm:ss}" -f $_.Datei, $_.Bisher, $_.Neu }
    ""; "Trockenlauf - nichts geaendert. Zum Umsetzen mit -Anwenden aufrufen."
    return
}
$ok = 0
foreach ($p in $plan) {
    $body = @{ dateTimeOriginal = $p.Neu.ToString("yyyy-MM-ddTHH:mm:ss.000zzz") } | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri "$Server/api/assets/$($p.Id)" -Method Put -Headers $h -ContentType 'application/json' -Body $body -TimeoutSec 30 | Out-Null
        $ok++
    } catch { Write-Warning "$($p.Datei): $($_.Exception.Message)" }
}
"Korrigiert: $ok von $($plan.Count). Die Ordner zieht die naechtliche Speicher-Migration nach."