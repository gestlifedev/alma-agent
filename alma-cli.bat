@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

:: ==========================================
::  ALMA CLI — Control local del agente
:: ==========================================

set COMMAND_FILE=alma-command.json
set RESPONSE_FILE=alma-response.json

if "%1"=="" goto :help

:: Generar ID único para el comando
set CMD_ID=%random%%random%

:: Escribir comando
(
echo {
echo     "command_id": "%CMD_ID%",
echo     "command": "%1",
echo     "params": {
) > "%COMMAND_FILE%"

if not "%2"=="" (
    echo         "key": "%2",>> "%COMMAND_FILE%"
)
if not "%3"=="" (
    echo         "value": "%3" >> "%COMMAND_FILE%"
) else (
    echo         "value": "" >> "%COMMAND_FILE%"
)

(
echo     }
echo }
) >> "%COMMAND_FILE%"

:: Esperar respuesta
set TRIES=0
:wait_response
timeout /t 1 /nobreak > nul
set /a TRIES+=1
if exist "%RESPONSE_FILE%" goto :show_response
if !TRIES! LSS 10 goto :wait_response

echo [ALMA] Timeout esperando respuesta (agente no responde)
del "%COMMAND_FILE%" 2>nul
exit /b 1

:show_response
:: Leer y mostrar respuesta
for /f "usebackq tokens=*" %%a in (`python -c "import json; d=json.load(open('%RESPONSE_FILE%')); print(d.get('message','') or json.dumps(d.get('data',''), indent=2))" 2>nul`) do echo %%a
del "%RESPONSE_FILE%" 2>nul
exit /b 0

:help
echo.
echo   ALMA Agent CLI - Comandos locales
echo   =================================
echo.
echo   alma-cli status                  Ver estado del agente
echo   alma-cli stop                    Detener el agente
echo   alma-cli restart                 Reiniciar el agente
echo   alma-cli update                  Forzar verificacion de actualizacion
echo   alma-cli config server HOST      Cambiar servidor
echo   alma-cli config name NOMBRE      Cambiar nombre del agente
echo   alma-cli config retry N          Cambiar reintentos (segundos)
echo   alma-cli config auto_update ON   Activar/desactivar auto-update
echo.
exit /b 0
