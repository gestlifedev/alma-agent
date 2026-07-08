@echo off
setlocal enabledelayedexpansion

:: ==========================================
::  ALMA CLI v2.1 — Control local del agente
:: ==========================================

:: Usar el Python embebido (en la misma carpeta que este script)
set PYTHON=%~dp0python\python.exe

set COMMAND_FILE=%~dp0alma-command.json
set RESPONSE_FILE=%~dp0alma-response.json

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

:: Esperar respuesta (max 10s)
set TRIES=0
:wait_response
timeout /t 1 /nobreak > nul
set /a TRIES+=1
if exist "%RESPONSE_FILE%" goto :show_response
if !TRIES! LSS 10 goto :wait_response

echo [ALMA] Timeout: el agente no responde. ¿Está corriendo?
echo        Verifica con: schtasks /Run /TN "ALMA Agent"
del "%COMMAND_FILE%" 2>nul
exit /b 1

:show_response
:: Leer y mostrar respuesta
if exist "%PYTHON%" (
    "%PYTHON%" -c "import json; d=json.load(open('%RESPONSE_FILE%')); print(d.get('message','') or json.dumps(d.get('data',''), indent=2))" 2>nul
) else (
    echo [ALMA] ERROR: Python embebido no encontrado en %PYTHON%
)
del "%RESPONSE_FILE%" 2>nul
del "%COMMAND_FILE%" 2>nul
exit /b 0

:help
echo.
echo   ALMA Agent CLI v2.1
echo   ===================
echo.
echo   alma-cli status                  Ver estado del agente
echo   alma-cli stop                    Detener el agente
echo   alma-cli restart                 Reiniciar el agente
echo   alma-cli update                  Forzar verificacion de actualizacion
echo   alma-cli config server HOST      Cambiar servidor
echo   alma-cli config name NOMBRE      Cambiar nombre del agente
echo   alma-cli config retry N          Cambiar reintentos (segundos)
echo   alma-cli config auto_update ON   ON/OFF
echo.
exit /b 0
