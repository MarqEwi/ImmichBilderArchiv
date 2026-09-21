<#
.SYNOPSIS
    Zeigt den Zustand von Immich auf der NAS. Aendert nichts.

.DESCRIPTION
    Fuehrt scripts/status.sh auf der NAS aus. Funktioniert aus jedem
    Arbeitsverzeichnis, weil der Skriptpfad selbst ermittelt wird.

    Bewusst ueber cmd mit Eingabe-Umleitung statt einer PowerShell-Pipe:
    Beim Pipen haengt PowerShell 5.1 ein BOM an, woran bash in der ersten
    Zeile scheitert ("#!/bin/sh: No such file or directory").

.EXAMPLE
    .\scripts\status.ps1
    .\scripts\status.ps1 -Nas 192.168.2.101
#>
param(
    [string]$Nas  = '192.168.2.101',
    [string]$User = 'MarcEwers'
)

$sh = Join-Path $PSScriptRoot 'status.sh'
if (-not (Test-Path $sh)) { throw "Fehlt: $sh" }

Push-Location $PSScriptRoot
try {
    cmd /c "ssh -4 $User@$Nas bash -s < status.sh"
} finally {
    Pop-Location
}