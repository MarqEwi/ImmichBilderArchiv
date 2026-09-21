<#
.SYNOPSIS
    Fragt Immich ueber die API ab und stoesst Jobs an.

.DESCRIPTION
    Der API-Schluessel wird aus %USERPROFILE%\.immich\api-key gelesen und steht
    bewusst nicht im Repo. Erstellt wird er in Immich unter Kontoeinstellungen ->
    API-Schluessel; Immich zeigt ihn nur ein einziges Mal an.

.PARAMETER Aktion
    status  - Bibliotheken, Statistik und laufende Auftraege (Vorgabe)
    scan    - Bibliotheks-Scan anstossen
    jobs    - nur die Auftrags-Warteschlangen

.EXAMPLE
    .\scripts\immich-api.ps1
    .\scripts\immich-api.ps1 -Aktion scan
#>
param(
    [ValidateSet('status','scan','jobs')]
    [string]$Aktion = 'status',
    [string]$Server = 'http://192.168.2.101:2283'
)

$keyFile = Join-Path $env:USERPROFILE '.immich\api-key'
if (-not (Test-Path $keyFile)) {
    throw "Kein API-Schluessel unter $keyFile. In Immich unter Kontoeinstellungen -> API-Schluessel erzeugen und dort ablegen."
}
$h = @{ 'x-api-key' = (Get-Content $keyFile -Raw).Trim() }

function Get-Api($pfad) { Invoke-RestMethod -Uri "$Server/api/$pfad" -Headers $h -TimeoutSec 30 }

if ($Aktion -in @('status','scan')) {
    Write-Host "== Externe Bibliotheken ==" -ForegroundColor Cyan
    foreach ($l in (Get-Api 'libraries')) {
        $st = Get-Api "libraries/$($l.id)/statistics"
        "{0,-24} Pfade: {1}" -f $l.name, ($l.importPaths -join ', ')
        "{0,-24} {1} Fotos, {2} Videos, {3} MB" -f '', $st.photos, $st.videos, [math]::Round($st.usage/1MB,1)
        "{0,-24} letzter Scan: {1}" -f '', $l.refreshedAt
        if ($Aktion -eq 'scan') {
            Invoke-RestMethod -Uri "$Server/api/libraries/$($l.id)/scan" -Method Post -Headers $h -TimeoutSec 30 | Out-Null
            Write-Host ("{0,-24} Scan angestossen." -f '') -ForegroundColor Green
        }
    }
    Write-Host "`n== Bestand gesamt ==" -ForegroundColor Cyan
    $s = Get-Api 'server/statistics'
    "{0} Fotos, {1} Videos, {2} MB belegt" -f $s.photos, $s.videos, [math]::Round($s.usage/1MB,1)
}

Write-Host "`n== Auftraege mit Arbeit ==" -ForegroundColor Cyan
$jobs = Get-Api 'jobs'
$aktiv = $false
foreach ($n in ($jobs | Get-Member -MemberType NoteProperty).Name) {
    $c = $jobs.$n.jobCounts
    if ($c.active -or $c.waiting -or $c.failed) {
        "{0,-26} aktiv {1}  wartend {2}  fehlgeschlagen {3}" -f $n, $c.active, $c.waiting, $c.failed
        $aktiv = $true
    }
}
if (-not $aktiv) { "(alle Warteschlangen leer)" }