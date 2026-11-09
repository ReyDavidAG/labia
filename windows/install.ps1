<#
.SYNOPSIS
    Pone Labia en el menú Inicio (y, si quieres, la abre al iniciar sesión).

.DESCRIPTION
    Crea el acceso directo «Labia» en el menú Inicio, con su ícono, para que aparezca al buscar «Labia» en
    Windows. Abrirla desde ahí muestra los ajustes; si ya estaba abierta, los abre en esa misma.
    Se puede correr varias veces: reemplaza los accesos directos, no los duplica.
    Requiere el entorno de linux\.venv ya instalado (ver windows\README.md).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File windows\install.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File windows\install.ps1 -Inicio
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File windows\install.ps1 -Quitar
#>
param(
    [switch]$Inicio,  # también abrir Labia al iniciar sesión
    [switch]$Quitar   # borrar los accesos directos
)
$ErrorActionPreference = 'Stop'

$linux = Join-Path (Split-Path $PSScriptRoot -Parent) 'linux'
$python = Join-Path $linux '.venv\Scripts\python.exe'
if (-not (Test-Path $python)) {
    throw "No encontré $python. Primero instala Labia (windows\README.md, sección «Instalar»)."
}

$arguments = @('-m', 'labia.shortcuts_windows')
$arguments += if ($Quitar) { 'quitar' } else { 'instalar' }
if ($Inicio -and -not $Quitar) { $arguments += '--inicio' }

Push-Location $linux
try {
    & $python @arguments
    if ($LASTEXITCODE -ne 0) { throw "labia.shortcuts_windows terminó con código $LASTEXITCODE" }
} finally {
    Pop-Location
}
if (-not $Quitar) {
    Write-Host 'Listo: busca «Labia» en el menú Inicio.' -ForegroundColor Green
}
