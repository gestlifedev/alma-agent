@echo off
REM ========================================
REM  ALMA Agent - Build EXE (Windows)
REM  Ejecutar en Windows con Python instalado
REM ========================================

echo ========================================
echo   ALMA Agent - Generador de EXE
echo ========================================
echo.

cd /d "%~dp0"

echo [1/3] Instalando PyInstaller...
pip install pyinstaller --quiet

echo [2/3] Generando EXE...
pyinstaller --onefile --noconsole --name "ALMA-Agent" --icon=NUL alma-agent.py

echo [3/3] EXE generado en dist\ALMA-Agent.exe
echo.
echo ✅ Listo para distribuir
echo.
pause
