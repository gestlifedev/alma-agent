@echo off
title ALMA Agent v1.0.1 — Instalador
cd /d "%~dp0"
echo.
echo ============================================
echo   ALMA Agent v1.0.1
echo   Gestlife Bridge System
echo ============================================
echo.
echo Este instalador configurara el agente en este equipo.
echo.

:: Verificar si Python existe en PATH o instalado
where python >nul 2>&1
if %errorlevel%==0 (
    echo [OK] Python encontrado
    set PYTHON_CMD=python
    goto :install_agent
)

where python3 >nul 2>&1
if %errorlevel%==0 (
    echo [OK] Python3 encontrado
    set PYTHON_CMD=python3
    goto :install_agent
)

:: Buscar Python en ubicaciones comunes
for %%p in (
    "%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
    "%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
    "%PROGRAMFILES%\Python311\python.exe"
    "%PROGRAMFILES%\Python312\python.exe"
    "C:\Python311\python.exe"
    "C:\Python312\python.exe"
) do (
    if exist %%p (
        echo [OK] Python encontrado en %%p
        set PYTHON_CMD=%%p
        goto :install_agent
    )
)

echo [ERROR] Python no encontrado.
echo.
echo Descargando Python 3.11.9...
curl -L -o "%TEMP%\python-installer.exe" "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
if not exist "%TEMP%\python-installer.exe" (
    echo [ERROR] No se pudo descargar Python. Instalalo manualmente de python.org
    pause
    exit /b 1
)
echo Instalando Python (puede tardar)...
"%TEMP%\python-installer.exe" /quiet InstallAllUsers=1 PrependPath=1 Include_test=0
del "%TEMP%\python-installer.exe"

:: Refrescar PATH
set "PATH=%PATH%;%PROGRAMFILES%\Python311;%PROGRAMFILES%\Python311\Scripts;%LOCALAPPDATA%\Programs\Python\Python311;%LOCALAPPDATA%\Programs\Python\Python311\Scripts"
set PYTHON_CMD=python

:install_agent
echo.
echo Instalando ALMA Agent...

:: Directorio de instalacion
set "INSTALL_DIR=%PROGRAMFILES%\ALMA Agent"
mkdir "%INSTALL_DIR%" 2>nul

:: Copiar agente
copy /Y "alma-agent.py" "%INSTALL_DIR%\alma-agent.py" >nul

:: Crear configuracion
echo { > "%INSTALL_DIR%\alma-agent-config.json"
echo   "server_host": "ai.gestlife.com", >> "%INSTALL_DIR%\alma-agent-config.json"
echo   "server_port": 9555, >> "%INSTALL_DIR%\alma-agent-config.json"
echo   "agent_name": "%COMPUTERNAME%", >> "%INSTALL_DIR%\alma-agent-config.json"
echo   "retry_seconds": 10, >> "%INSTALL_DIR%\alma-agent-config.json"
echo   "ping_interval": 30, >> "%INSTALL_DIR%\alma-agent-config.json"
echo   "auto_update": true, >> "%INSTALL_DIR%\alma-agent-config.json"
echo   "update_check_interval": 3600 >> "%INSTALL_DIR%\alma-agent-config.json"
echo } >> "%INSTALL_DIR%\alma-agent-config.json"

echo [OK] Agente instalado en %INSTALL_DIR%

:: Programar inicio con Windows
echo Configurando inicio automatico...
schtasks /create /tn "ALMA Agent" /tr "\"%PYTHON_CMD%\" \"%INSTALL_DIR%\alma-agent.py\"" /sc onstart /ru SYSTEM /rl HIGHEST /f >nul 2>&1
if %errorlevel%==0 (
    echo [OK] El agente se iniciara con Windows
) else (
    echo [AVISO] No se pudo crear tarea programada. El agente no arrancara solo.
)

:: Iniciar ahora
echo.
echo Iniciando ALMA Agent...
start "ALMA Agent" /MIN "%PYTHON_CMD%" "%INSTALL_DIR%\alma-agent.py"

echo.
echo ============================================
echo   ALMA Agent instalado!
echo   Dashboard: https://ai.gestlife.com:9557
echo ============================================
echo.
pause
