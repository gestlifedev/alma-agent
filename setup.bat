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

:: Configurar Python embebido para usar pip y imports
echo. > "%INSTALL_DIR%\python\python311._pth"
(
echo python311.zip
echo .
echo Lib
echo Lib\site-packages
) > "%INSTALL_DIR%\python\python311._pth"

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

:: Usar pythonw.exe para que NO haya ventana de consola
set PYTHONW=%INSTALL_DIR%\python\pythonw.exe
set AGENT_PATH=%INSTALL_DIR%\alma-agent.py

:: Scheduled Task: SYSTEM, al inicio, reinicio si falla
schtasks /Create /TN "ALMA Agent" /SC ONSTART /RU SYSTEM /RL HIGHEST /TR "\"%PYTHONW%\" \"%AGENT_PATH%\"" /F /DELAY 0000:30 >nul 2>&1
if %errorlevel% neq 0 (
    schtasks /Create /TN "ALMA Agent" /SC ONSTART /RU SYSTEM /TR "\"%PYTHONW%\" \"%AGENT_PATH%\"" /F >nul 2>&1
)

:: Configurar restart en failure (si se mata el proceso)
schtasks /Change /TN "ALMA Agent" /RL HIGHEST >nul 2>&1

:: Tarea adicional: cada 5 min verificar que esté corriendo
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
