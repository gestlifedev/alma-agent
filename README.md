# ALMA Agent v2.0 — Agente Remoto Gestlife

Agente para Windows sin dependencias. Control remoto total desde Hermes via Bridge Server.

## Qué hace

- Se conecta al Bridge Server y ejecuta comandos remotos
- Auto-update desde GitHub (cada hora)
- Control local por comandos de consola
- Sin ventana — corre en background con pythonw.exe
- Persistente — se inicia con Windows y se re-ejecuta si falla

## Instalación (Windows, un solo click)

1. Descargar `alma-agent-v2.0.zip` del release
2. Descomprimir en una carpeta
3. Click derecho en `setup.bat` → Ejecutar como administrador
4. Listo. El agente ya está corriendo.

**El ZIP incluye Python embebido** — no necesitas instalar nada.

## Comandos locales

Abre `cmd` en `C:\Program Files\ALMA Agent`:

```
alma-cli status                 Ver si está corriendo
alma-cli stop                   Detener agente
alma-cli restart                Reiniciar
alma-cli update                 Forzar actualización
alma-cli config server HOST     Cambiar servidor
alma-cli config name NOMBRE     Cambiar nombre
```

## Dashboard

https://ai.gestlife.com:9557

## Release v2.0

- [x] Python embebido (no requiere instalación)
- [x] Sin consola (pythonw.exe)
- [x] Control local por archivo de comandos
- [x] Persistencia con Scheduled Task (SYSTEM)
- [x] Auto-restart si el proceso muere
- [x] Comandos locales: status, stop, config, update
- [x] Configuración remota desde el bridge
- [x] Bridge mejorado: comandos en tiempo real
