<#
.SYNOPSIS
    Sichert die Immich-Systemeinstellungen nach immich/system-config.json.

.DESCRIPTION
    Holt die Einstellungen ueber die API und schreibt sie mit alphabetisch sortierten Schluesseln,
    LF und ohne BOM. Die Sortierung ist der Punkt: API und Oberflaeche liefern die Schluessel in
    unterschiedlicher Reihenfolge, ohne Sortierung zeigt git diff hunderte Scheinaenderungen.
    Nach jeder Aenderung in Verwaltung -> Einstellungen ausfuehren und committen.
#>
param([string]$Server = 'http://192.168.2.101:2283')
$h = @{ 'x-api-key' = (Get-Content (Join-Path $env:USERPROFILE '.immich\api-key') -Raw).Trim() }

function Sortiert($o) {
    if ($o -is [pscustomobject]) {
        $n = [ordered]@{}
        foreach ($k in ($o.PSObject.Properties.Name | Sort-Object)) { $n[$k] = Sortiert $o.$k }
        return [pscustomobject]$n
    }
    if ($o -is [array]) { return ,@($o | ForEach-Object { Sortiert $_ }) }
    return $o
}
$cfg = Sortiert (Invoke-RestMethod -Uri "$Server/api/system-config" -Headers $h -TimeoutSec 30)
$ziel = Join-Path (Split-Path -Parent $PSScriptRoot) 'immich\system-config.json'
$json = ($cfg | ConvertTo-Json -Depth 20) -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($ziel, $json + "`n", (New-Object System.Text.UTF8Encoding $false))
"Gesichert: $ziel"