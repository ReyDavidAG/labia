<#
.SYNOPSIS
    Instala (o actualiza) Labia en Windows con un solo comando.

.DESCRIPTION
    1. Instala Git y Python 3.12 con winget si faltan.
    2. Baja Labia de GitHub a la carpeta de destino (o la actualiza si ya estaba).
    3. Crea su entorno de Python e instala las dependencias.
    4. Baja el modelo de Whisper (1.6 GB, sólo la primera vez).
    5. Pone Labia en el menú Inicio y, si es una instalación nueva (salvo -SinInicio), la abre al iniciar sesión.
    6. La abre.

    Correrlo otra vez actualiza Labia sin tocar tus ajustes ni tu historial (%APPDATA%\Labia), y respeta si
    elegiste abrirla o no al iniciar sesión.

.EXAMPLE
    irm https://raw.githubusercontent.com/ReyDavidAG/labia/main/windows/setup.ps1 -OutFile $env:TEMP\labia-setup.ps1; powershell -ExecutionPolicy Bypass -File $env:TEMP\labia-setup.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File $env:TEMP\labia-setup.ps1 -Desinstalar
#>
param(
    [string]$Destino = (Join-Path $env:LOCALAPPDATA 'Programs\Labia'),
    [string]$Rama = 'main',
    [switch]$SinInicio,     # no abrir Labia al iniciar sesión
    [switch]$Desinstalar,   # quitar accesos directos y la carpeta de Labia (conserva ajustes e historial)
    [string]$Repo = 'https://github.com/ReyDavidAG/labia.git'  # otro origen (un fork)
)
$ErrorActionPreference = 'Stop'
$Linux = Join-Path $Destino 'linux'
$Python = Join-Path $Linux '.venv\Scripts\python.exe'
$PythonW = Join-Path $Linux '.venv\Scripts\pythonw.exe'

function Step($text) { Write-Host "`n▸ $text" -ForegroundColor Cyan }
function Ok($text) { Write-Host "  ✓ $text" -ForegroundColor Green }

function Invoke-Checked {
    # Native commands don't throw on failure: check the exit code ourselves.
    param([string]$What, [scriptblock]$Command)
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "$What falló (código $LASTEXITCODE)." }
}

function Update-Path {
    # winget installs update PATH in the registry, not in this window.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Install-WithWinget($id, $name) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "Falta $name y no está winget para instalarlo. Instala «App Installer» desde la Microsoft Store, o $name a mano, y vuelve a correr esto."
    }
    Invoke-Checked "Instalar $name" { winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements }
    Update-Path
}

function Stop-Labia {
    # Ask it to quit (it finishes a dictation in progress first); if it doesn't, close it.
    $running = @(Get-CimInstance Win32_Process -Filter "Name like 'python%'" |
        Where-Object { $_.CommandLine -match '-m labia(\s|$)' -or $_.CommandLine -match 'pill_windows|settings_windows' })
    if (-not $running) { return }
    Step 'Cerrando la Labia que está abierta'
    if (Test-Path $Python) {
        Push-Location $Linux
        try { & $Python -c "from labia import tray_windows as t; t.post_to_running('quit')" 2>$null } catch { }
        finally { Pop-Location }
    }
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline) {
        $alive = @($running | Where-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue })
        if (-not $alive) { break }
        Start-Sleep -Milliseconds 500
    }
    $running | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Ok 'Cerrada'
}

function Test-Python312 {
    if (-not (Get-Command py -ErrorAction SilentlyContinue)) { return $false }
    & py -3.12 -c "import tkinter" 2>$null
    return $LASTEXITCODE -eq 0
}

# --- desinstalar ---------------------------------------------------------------

if ($Desinstalar) {
    Stop-Labia
    Step 'Quitando accesos directos'
    $programs = [Environment]::GetFolderPath('Programs')
    Remove-Item (Join-Path $programs 'Labia.lnk'), (Join-Path $programs 'Startup\Labia.lnk') -ErrorAction SilentlyContinue
    Ok 'Menú Inicio e inicio de sesión'
    if (Test-Path (Join-Path $Linux 'labia\app.py')) {  # sólo borra una carpeta que de verdad es Labia
        Step "Borrando $Destino"
        Remove-Item $Destino -Recurse -Force
        Ok 'Borrada'
    }
    Write-Host "`nLabia se desinstaló. Tus ajustes e historial siguen en $env:APPDATA\Labia (bórrala si ya no los quieres)." -ForegroundColor Green
    Write-Host 'El modelo sigue en la caché de Hugging Face (%USERPROFILE%\.cache\huggingface).'
    return
}

# --- instalar o actualizar -------------------------------------------------------

Write-Host 'Labia · dictado en español para Windows' -ForegroundColor White

Step 'Revisando Git y Python 3.12'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Install-WithWinget 'Git.Git' 'Git' }
Ok "Git: $((git --version) -replace 'git version ', '')"
if (-not (Test-Python312)) { Install-WithWinget 'Python.Python.3.12' 'Python 3.12' }
if (-not (Test-Python312)) {
    throw 'Python 3.12 con tkinter no responde a «py -3.12». Instálalo de python.org (no el de la Microsoft Store) y vuelve a correr esto.'
}
Ok "Python: $(& py -3.12 --version)"

Stop-Labia  # sus archivos están en uso: hay que cerrarla antes de actualizar

$fresh = -not (Test-Path (Join-Path $Destino '.git'))
if (-not $fresh) {
    Step "Actualizando Labia en $Destino (rama $Rama)"
    Invoke-Checked 'git fetch' { git -C $Destino fetch --quiet origin $Rama }
    Invoke-Checked 'git checkout' { git -C $Destino checkout --quiet $Rama }
    Invoke-Checked 'git pull' { git -C $Destino pull --quiet --ff-only origin $Rama }
} else {
    if ((Test-Path $Destino) -and (Get-ChildItem $Destino -Force | Select-Object -First 1)) {
        throw "$Destino ya existe y no es una copia de Labia. Elige otra carpeta con -Destino."
    }
    Step "Bajando Labia a $Destino (rama $Rama)"
    Invoke-Checked 'git clone' { git clone --quiet --branch $Rama $Repo $Destino }
}
Ok "Versión: $(git -C $Destino log -1 --format='%h %s')"

if (-not (Test-Path $Python)) {
    Step 'Creando el entorno de Python'
    Invoke-Checked 'Crear el entorno' { py -3.12 -m venv (Join-Path $Linux '.venv') }
}
Step 'Instalando dependencias (la primera vez baja ~2.5 GB: Whisper y CUDA)'
Invoke-Checked 'pip install' { & $Python -m pip install --quiet --disable-pip-version-check -r (Join-Path $Linux 'requirements.txt') }
Ok 'Dependencias listas'

Step 'Preparando el modelo de Whisper (1.6 GB la primera vez)'
Push-Location $Linux
try {
    Invoke-Checked 'Bajar el modelo' { & $Python -c "from labia import core, engine; engine.load(core.Preferences.load().model)" }
} finally { Pop-Location }
Ok 'Modelo listo'

Step 'Poniendo Labia en el menú Inicio'
# Opening at sign-in: on by default for a new install; an update keeps what the user chose in Ajustes.
$shortcutArgs = @('-m', 'labia.shortcuts_windows', 'instalar')
if ($fresh -and -not $SinInicio) { $shortcutArgs += '--inicio' }
Push-Location $Linux
try {
    Invoke-Checked 'Crear accesos directos' { & $Python @shortcutArgs }
    if ($SinInicio) {
        Invoke-Checked 'Quitar el inicio de sesión' { & $Python -c "from labia import shortcuts_windows as s; s.set_startup(False)" }
    }
} finally { Pop-Location }

Step 'Abriendo Labia'
Start-Process $PythonW -ArgumentList '-m', 'labia', '--abrir' -WorkingDirectory $Linux
Write-Host "`nListo. Mantén AltGr en cualquier app y habla." -ForegroundColor Green
Write-Host 'Búscala como «Labia» en el menú Inicio; su ícono está junto al reloj.'
if ($SinInicio) { Write-Host 'No se abre al iniciar sesión (Ajustes → General para cambiarlo).' }
