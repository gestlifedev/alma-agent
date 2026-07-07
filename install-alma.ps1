# ALMA Agent Installer for Windows
# Guardar como: install-alma.ps1
# Ejecutar en PowerShell como Administrador: 
#   powershell -ExecutionPolicy Bypass -File install-alma.ps1

param(
    [string]$ServerHost = "46.27.219.187",
    [int]$ServerPort = 9555,
    [string]$AgentName = $env:COMPUTERNAME
)

$ErrorActionPreference = "Stop"
$INSTALL_DIR = "$env:ProgramFiles\ALMA Agent"
$AGENT_URL = "https://raw.githubusercontent.com/gestlifedev/alma-agent/master/alma-agent.py"
$PYTHON_URL = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
$NSSM_URL = "https://nssm.cc/release/nssm-2.24.zip"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ALMA Agent - Instalador v1.0" -ForegroundColor Cyan
Write-Host "  Gestlife Bridge System" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Crear directorio
Write-Host "[1/5] Creando directorio de instalación..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $INSTALL_DIR | Out-Null

# 2. Verificar/Instalar Python
Write-Host "[2/5] Verificando Python..." -ForegroundColor Yellow
$pythonCmd = $null
try {
    $py = Get-Command python3 -ErrorAction Stop
    $pythonCmd = "python3"
} catch {
    try {
        $py = Get-Command python -ErrorAction Stop
        $pythonCmd = "python"
    } catch {
        Write-Host "  Python no encontrado. Descargando Python 3.11..." -ForegroundColor Yellow
        $pyInstaller = "$env:TEMP\python-installer.exe"
        Invoke-WebRequest -Uri $PYTHON_URL -OutFile $pyInstaller
        Start-Process -FilePath $pyInstaller -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
        Remove-Item $pyInstaller
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        $pythonCmd = "python"
    }
}
Write-Host "  Python: OK" -ForegroundColor Green

# 3. Instalar websockets
Write-Host "[3/5] Instalando dependencias..." -ForegroundColor Yellow
& $pythonCmd -m pip install --quiet --upgrade pip 2>$null
# El agente no necesita dependencias externas (WebSocket puro)
Write-Host "  Dependencias: OK (agente sin dependencias)" -ForegroundColor Green

# 4. Descargar agente
Write-Host "[4/5] Descargando ALMA Agent..." -ForegroundColor Yellow
$agentPath = "$INSTALL_DIR\alma-agent.py"
Invoke-WebRequest -Uri $AGENT_URL -OutFile $agentPath -UseBasicParsing

# Crear config
$config = @{
    server_host = $ServerHost
    server_port = $ServerPort
    agent_name = $AgentName
    retry_seconds = 10
    ping_interval = 30
    auto_update = $true
    update_check_interval = 3600
} | ConvertTo-Json
$config | Out-File -FilePath "$INSTALL_DIR\alma-agent-config.json" -Encoding UTF8
Write-Host "  Agente descargado y configurado" -ForegroundColor Green

# 5. Crear servicio Windows con NSSM o Scheduled Task
Write-Host "[5/5] Configurando inicio automático..." -ForegroundColor Yellow

# Método 1: Scheduled Task (más fiable, no requiere NSSM)
$taskName = "ALMA Agent"
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Crear script wrapper
$wrapper = @"
@echo off
cd /d "$INSTALL_DIR"
$pythonCmd alma-agent.py >> "$INSTALL_DIR\alma-agent.log" 2>&1
"@
$wrapper | Out-File -FilePath "$INSTALL_DIR\start-alma.bat" -Encoding ASCII

# Scheduled task: run at startup, every 5 min if not running
$action = New-ScheduledTaskAction -Execute "$INSTALL_DIR\start-alma.bat"
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

# Iniciar ahora
Start-ScheduledTask -TaskName $taskName
Write-Host "  Servicio Windows: OK (Scheduled Task)" -ForegroundColor Green

# 6. Crear acceso directo en Escritorio
$shortcut = "$env:USERPROFILE\Desktop\ALMA Agent.lnk"
$WshShell = New-Object -ComObject WScript.Shell
$ShortcutObj = $WshShell.CreateShortcut($shortcut)
$ShortcutObj.TargetPath = "$INSTALL_DIR\start-alma.bat"
$ShortcutObj.WorkingDirectory = $INSTALL_DIR
$ShortcutObj.Description = "ALMA Agent - Gestlife Bridge"
$ShortcutObj.Save()

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  ALMA Agent instalado correctamente!" -ForegroundColor Green
Write-Host "  Nombre: $AgentName" -ForegroundColor White
Write-Host "  Servidor: ${ServerHost}:${ServerPort}" -ForegroundColor White
Write-Host "  Directorio: $INSTALL_DIR" -ForegroundColor White
Write-Host "  Dashboard: https://ai.gestlife.com/bridge/" -ForegroundColor Cyan
Write-Host "  El agente se iniciará con Windows" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green

# Abrir dashboard
Start-Process "https://ai.gestlife.com/bridge/"
