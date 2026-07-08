@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: ==========================================
::  ALMA Agent v2.0 — Instalador TODO EN UNO
::  Doble click → Admin → Instalado y corriendo
:: ==========================================

title ALMA Agent - Instalador

:: Verificar permisos de administrador
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo   ERROR: Se requieren permisos de Administrador.
    echo   Click derecho → Ejecutar como administrador.
    echo.
    pause
    exit /b 1
)

set NAME=%COMPUTERNAME%
if not "%1"=="" set NAME=%1

set INSTALL_DIR=%ProgramFiles%\ALMA Agent
set STARTUP_DIR=%ProgramData%\Microsoft\Windows\Start Menu\Programs\Startup

echo.
echo   =============================================
echo     ALMA Agent v2.0 — Instalador
echo     Gestlife Bridge System
echo   =============================================
echo.
echo   Instalando en:  %INSTALL_DIR%
echo   Nombre agente:  %NAME%
echo.

:: 0. Matar agentes anteriores
echo   [0/5] Deteniendo version anterior...
taskkill /F /IM pythonw.exe /FI "MEMUSAGE gt 1" 2>nul
taskkill /F /IM python.exe /FI "IMAGENAME eq python.exe" 2>nul
schtasks /End /TN "ALMA Agent" 2>nul
schtasks /Delete /TN "ALMA Agent" /F 2>nul
schtasks /Delete /TN "ALMA Agent Watchdog" /F 2>nul
timeout /t 2 /nobreak >nul

:: 1. Crear directorio
echo   [1/5] Creando directorio...
mkdir "%INSTALL_DIR%" 2>nul

:: 2. Extraer Python embebido
echo   [2/5] Instalando Python embebido...
if exist "python-embed.zip" (
    powershell -Command "Expand-Archive -Force '%~dp0python-embed.zip' '%INSTALL_DIR%\python'" -ErrorAction SilentlyContinue
    if exist "%INSTALL_DIR%\python\python.exe" (
        echo     Python embebido: OK
    ) else (
        :: Fallback: intentar con tar
        tar -xf "%~dp0python-embed.zip" -C "%INSTALL_DIR%\python" 2>nul
        if not exist "%INSTALL_DIR%\python\python.exe" (
            echo     ERROR: No se pudo extraer python-embed.zip
            echo     El archivo debe estar en la misma carpeta que setup.bat
            pause
            exit /b 1
        )
    )
) else (
    echo     ERROR: python-embed.zip no encontrado.
    echo     Debe estar en la misma carpeta que setup.bat
    pause
    exit /b 1
)

:: Configurar Python embebido - mantener el _pth original, solo añadir import site
:: El python311.zip ya contiene toda la stdlib, no se necesitan Lib/Lib\site-packages
if exist "%INSTALL_DIR%\python\python311._pth" (
    :: Asegurar que import site esté activo (necesario para asyncio y otras cosas)
    powershell -Command "(Get-Content '%INSTALL_DIR%\python\python311._pth') -replace '#import site', 'import site' | Set-Content '%INSTALL_DIR%\python\python311._pth'" -ErrorAction SilentlyContinue
)

:: 3. Copiar archivos del agente
echo   [3/5] Copiando agente...
copy /Y "%~dp0alma-agent.py" "%INSTALL_DIR%\alma-agent.py" >nul
copy /Y "%~dp0alma-cli.bat" "%INSTALL_DIR%\alma-cli.bat" >nul

:: Crear config inicial
(
echo {
echo     "server_host": "ai.gestlife.com",
echo     "server_port": 9555,
echo     "agent_name": "%NAME%",
echo     "retry_seconds": 10,
echo     "ping_interval": 30,
echo     "auto_update": true,
echo     "update_check_interval": 3600
echo }
) > "%INSTALL_DIR%\alma-agent-config.json"

:: 4. Crear Scheduled Task (inicio automático + persistencia)
echo   [4/5] Configurando inicio automático...

:: Crear wrapper batch para el Scheduled Task (necesita cd al directorio)
set WRAPPER=%INSTALL_DIR%\start-alma.bat
(
echo @echo off
echo cd /d "%INSTALL_DIR%"
echo start "" /B "%INSTALL_DIR%\python\pythonw.exe" "%INSTALL_DIR%\alma-agent.py"
) > "%WRAPPER%"

:: Dar permisos de escritura a SYSTEM en el directorio (para logs)
icacls "%INSTALL_DIR%" /grant "SYSTEM:(OI)(CI)F" /T /Q >nul 2>&1

:: Eliminar tareas anteriores
schtasks /Delete /TN "ALMA Agent" /F >nul 2>&1
schtasks /Delete /TN "ALMA Agent Watchdog" /F >nul 2>&1

:: Scheduled Task: SYSTEM, al inicio, reinicio si falla
schtasks /Create /TN "ALMA Agent" /SC ONSTART /RU SYSTEM /RL HIGHEST /TR "\"%WRAPPER%\"" /F >nul 2>&1

:: Tarea watchdog: cada 5 min verifica que esté corriendo
schtasks /Create /TN "ALMA Agent Watchdog" /SC MINUTE /MO 5 /RU SYSTEM /TR "schtasks /Run /TN \"ALMA Agent\"" /F >nul 2>&1

:: 5. Iniciar ahora
echo   [5/5] Iniciando agente...
schtasks /Run /TN "ALMA Agent" >nul 2>&1

:: Verificar
timeout /t 3 /nobreak >nul
tasklist /FI "IMAGENAME eq pythonw.exe" 2>nul | find /i "pythonw" >nul
if %errorlevel% equ 0 (
    echo     Agente: EN EJECUCION
) else (
    echo     Agente: iniciando...
)

:: Acceso directo al CLI en Escritorio
set DESKTOP=%USERPROFILE%\Desktop
if exist "%PUBLIC%\Desktop" set DESKTOP=%PUBLIC%\Desktop
echo @echo off > "%DESKTOP%\ALMA CLI.lnk" 2>nul
powershell -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%DESKTOP%\ALMA CLI.lnk'); $s.TargetPath = 'cmd.exe'; $s.Arguments = '/k cd /d \"%INSTALL_DIR%\" ^&^& alma-cli.bat'; $s.WorkingDirectory = '%INSTALL_DIR%'; $s.Description = 'ALMA Agent CLI'; $s.Save()" 2>nul

echo.
echo   =============================================
echo     ALMA Agent v2.0 — INSTALADO
echo   =============================================
echo.
echo     Servidor:  ai.gestlife.com:9555
echo     Agente:    %NAME%
echo     Carpeta:   %INSTALL_DIR%
echo     Dashboard: https://ai.gestlife.com:9557
echo.
echo   Comandos locales (en %INSTALL_DIR%):
echo     alma-cli status      — Ver estado
echo     alma-cli stop        — Detener agente
echo     alma-cli config ...  — Cambiar configuracion
echo.
pause
