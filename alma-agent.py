#!/usr/bin/env python3
"""
ALMA Agent v2.0 — Agente Remoto Gestlife
- Sin consola (usar pythonw.exe)
- Control local por archivo de comandos (alma-cli.bat)
- Auto-update desde GitHub
- Full remote control via WebSocket
"""
import asyncio
import json
import os
import sys
import socket
import platform
import hashlib
import base64
import subprocess
import urllib.request
import time
import signal
from datetime import datetime
from pathlib import Path

# === CONFIG ===
CONFIG_FILE = "alma-agent-config.json"
COMMAND_FILE = "alma-command.json"      # comandos locales (alma-cli.bat escribe aquí)
RESPONSE_FILE = "alma-response.json"     # respuestas a comandos locales
VERSION = "2.0.0"
GITHUB_REPO = "gestlifedev/alma-agent"
GITHUB_API = f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest"
AGENT_SCRIPT = "alma-agent.py"

DEFAULT_CONFIG = {
    "server_host": "ai.gestlife.com",
    "server_port": 9555,
    "agent_name": socket.gethostname(),
    "retry_seconds": 10,
    "ping_interval": 30,
    "auto_update": True,
    "update_check_interval": 3600
}

# === UTILIDADES ===
def load_config():
    try:
        with open(CONFIG_FILE) as f:
            return {**DEFAULT_CONFIG, **json.load(f)}
    except:
        return dict(DEFAULT_CONFIG)

def save_config(cfg):
    with open(CONFIG_FILE, "w") as f:
        json.dump(cfg, f, indent=2)

def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except:
        return None

def save_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)

config = load_config()

# === AUTO-UPDATE ===
def check_update():
    if not config.get("auto_update", True):
        return None
    try:
        req = urllib.request.Request(GITHUB_API, headers={"User-Agent": "ALMA-Agent/2.0"})
        data = json.loads(urllib.request.urlopen(req, timeout=10).read())
        latest = data.get("tag_name", "").lstrip("v")
        if latest and latest != VERSION:
            url = f"https://raw.githubusercontent.com/{GITHUB_REPO}/master/{AGENT_SCRIPT}"
            return {"version": latest, "url": url, "body": data.get("body", "")}
    except Exception as e:
        pass
    return None

def do_update(release_info):
    current_file = os.path.abspath(__file__)
    backup = current_file + ".bak"
    
    try:
        print(f"[ALMA] Actualizando a v{release_info['version']}...")
        new_code = urllib.request.urlopen(release_info["url"], timeout=60).read()
        
        # Backup
        with open(backup, "wb") as f:
            with open(current_file, "rb") as orig:
                f.write(orig.read())
        
        # Write new
        with open(current_file, "wb") as f:
            f.write(new_code)
        
        print("[ALMA] Reiniciando tras actualización...")
        os.execv(sys.executable, [sys.executable] + sys.argv)
    except Exception as e:
        print(f"[ALMA] Update failed: {e}")
        if os.path.exists(backup):
            os.rename(backup, current_file)

# === CONTROL LOCAL (lee comandos de alma-command.json) ===
def process_local_commands():
    """Procesa comandos escritos por alma-cli.bat"""
    cmd_data = load_json(COMMAND_FILE)
    if not cmd_data:
        return
    
    command = cmd_data.get("command", "")
    params = cmd_data.get("params", {})
    cmd_id = cmd_data.get("command_id", "")
    
    response = {"command_id": cmd_id, "ok": False, "message": ""}
    
    try:
        if command == "stop":
            response["ok"] = True
            response["message"] = "Agente detenido"
            save_json(RESPONSE_FILE, response)
            os._exit(0)
        
        elif command == "status":
            response["ok"] = True
            response["data"] = {
                "running": True,
                "version": VERSION,
                "name": config["agent_name"],
                "server": f"{config['server_host']}:{config['server_port']}",
                "auto_update": config.get("auto_update", True)
            }
        
        elif command == "config":
            key = params.get("key", "")
            value = params.get("value", "")
            valid_keys = ["server_host", "server_port", "agent_name", "retry_seconds",
                         "ping_interval", "auto_update", "update_check_interval"]
            if key in valid_keys:
                # Convertir tipos
                if key in ("server_port", "retry_seconds", "ping_interval", "update_check_interval"):
                    value = int(value)
                elif key == "auto_update":
                    value = value.lower() in ("true", "1", "yes", "on")
                config[key] = value
                save_config(config)
                response["ok"] = True
                response["message"] = f"Config '{key}' = {value}"
            else:
                response["message"] = f"Clave inválida: {key}. Válidas: {', '.join(valid_keys)}"
        
        elif command == "update":
            update = check_update()
            if update:
                response["ok"] = True
                response["message"] = f"Descargando v{update['version']}..."
                save_json(RESPONSE_FILE, response)
                os.unlink(COMMAND_FILE)  # borrar comando antes de reiniciar
                do_update(update)
                return
            else:
                response["ok"] = True
                response["message"] = "Ya está en la última versión"
        
        elif command == "restart":
            response["ok"] = True
            response["message"] = "Reiniciando..."
            save_json(RESPONSE_FILE, response)
            os.unlink(COMMAND_FILE)
            os.execv(sys.executable, [sys.executable] + sys.argv)
        
        else:
            response["message"] = f"Comando desconocido: {command}"
    
    except Exception as e:
        response["message"] = f"Error: {e}"
    
    save_json(RESPONSE_FILE, response)
    # Borrar comando procesado
    try:
        os.unlink(COMMAND_FILE)
    except:
        pass

# === WEBSOCKET CLIENT (sin dependencias) ===
async def ws_connect(host, port):
    reader, writer = await asyncio.open_connection(host, port)
    key = base64.b64encode(os.urandom(16)).decode()
    request = (
        f"GET / HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        f"Upgrade: websocket\r\n"
        f"Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        f"Sec-WebSocket-Version: 13\r\n"
        f"\r\n"
    )
    writer.write(request.encode())
    await writer.drain()
    response = (await reader.readuntil(b"\r\n\r\n")).decode()
    if "101" not in response:
        raise Exception("Handshake failed")
    return reader, writer

async def ws_send(writer, message):
    data = message.encode('utf-8')
    frame = bytearray([0x81])
    length = len(data)
    if length < 126:
        frame.append(length)
    elif length < 65536:
        frame.append(126)
        frame.extend(length.to_bytes(2, 'big'))
    else:
        frame.append(127)
        frame.extend(length.to_bytes(8, 'big'))
    frame.extend(data)
    writer.write(bytes(frame))
    await writer.drain()

async def ws_recv(reader):
    try:
        header = await asyncio.wait_for(reader.readexactly(2), timeout=120)
    except:
        return None
    opcode = header[0] & 0x0F
    if opcode == 0x08:
        return None
    length = header[1] & 0x7F
    if length == 126:
        length = int.from_bytes(await reader.readexactly(2), 'big')
    elif length == 127:
        length = int.from_bytes(await reader.readexactly(8), 'big')
    payload = await reader.readexactly(length)
    return payload.decode('utf-8', errors='ignore')

async def run_command(command):
    """Ejecuta comando en shell de Windows con timeout."""
    try:
        if sys.platform == "win32":
            proc = await asyncio.create_subprocess_shell(
                command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
        else:
            proc = await asyncio.create_subprocess_shell(
                command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=120)
        return {
            "exit_code": proc.returncode,
            "stdout": stdout.decode('utf-8', errors='replace')[:10000],
            "stderr": stderr.decode('utf-8', errors='replace')[:5000]
        }
    except asyncio.TimeoutError:
        return {"exit_code": -1, "stdout": "", "stderr": "Timeout (120s)"}
    except Exception as e:
        return {"exit_code": -1, "stdout": "", "stderr": str(e)}

async def agent_loop():
    """Loop principal: conecta al bridge, procesa comandos remotos y locales."""
    cfg = load_config()
    host = cfg["server_host"]
    port = cfg["server_port"]
    name = cfg["agent_name"]
    last_update_check = 0
    last_local_check = 0

    while True:
        try:
            now = time.time()

            # Auto-update check (cada hora)
            if now - last_update_check > cfg.get("update_check_interval", 3600):
                update = check_update()
                if update:
                    do_update(update)
                last_update_check = now

            # Conectar al Bridge
            reader, writer = await ws_connect(host, port)

            # Registrar
            await ws_send(writer, json.dumps({
                "type": "register",
                "name": name,
                "os": platform.system() + " " + platform.release(),
                "hostname": socket.gethostname(),
                "version": VERSION,
                "local_ip": socket.gethostbyname(socket.gethostname())
            }))

            last_ping = now

            while True:
                # Verificar comandos locales cada 3 segundos
                now = time.time()
                if now - last_local_check > 3:
                    if os.path.exists(COMMAND_FILE):
                        process_local_commands()
                    last_local_check = now

                # Leer del WebSocket
                try:
                    msg = await asyncio.wait_for(ws_recv(reader), timeout=2)
                except asyncio.TimeoutError:
                    now = time.time()
                    if now - last_ping > cfg["ping_interval"]:
                        await ws_send(writer, json.dumps({"type": "ping"}))
                        last_ping = now
                    continue

                if msg is None:
                    break

                try:
                    data = json.loads(msg)
                    msg_type = data.get("type", "")

                    if msg_type == "pong":
                        pass
                    elif msg_type == "command":
                        cmd = data.get("command", "")
                        cmd_id = data.get("command_id", "")
                        result = await run_command(cmd)
                        await ws_send(writer, json.dumps({
                            "type": "result",
                            "command_id": cmd_id,
                            "result": result
                        }))
                    elif msg_type == "get_status":
                        await ws_send(writer, json.dumps({
                            "type": "status",
                            "hostname": socket.gethostname(),
                            "os": platform.system() + " " + platform.release(),
                            "version": VERSION,
                            "name": name,
                            "local_ip": socket.gethostbyname(socket.gethostname())
                        }))
                    elif msg_type == "config_update":
                        # El servidor puede cambiar config remotamente
                        for k, v in data.get("config", {}).items():
                            if k in DEFAULT_CONFIG:
                                cfg[k] = v
                        save_config(cfg)
                        await ws_send(writer, json.dumps({
                            "type": "config_updated",
                            "config": cfg
                        }))
                except json.JSONDecodeError:
                    pass

            writer.close()

        except (ConnectionRefusedError, OSError) as e:
            pass
        except Exception as e:
            pass

        # Esperar antes de reintentar
        retry = cfg.get("retry_seconds", 10)
        # Durante la espera, seguir procesando comandos locales
        for _ in range(retry):
            await asyncio.sleep(1)
            if os.path.exists(COMMAND_FILE):
                process_local_commands()

def main():
    # Redirigir stdout/stderr a archivo si se ejecuta con pythonw.exe (sin consola)
    if sys.platform == "win32" and not sys.stdout.isatty():
        log_dir = os.path.dirname(os.path.abspath(__file__))
        log_file = os.path.join(log_dir, "alma-agent.log")
        sys.stdout = open(log_file, "a", buffering=1)
        sys.stderr = sys.stdout
        print(f"\n[ALMA v{VERSION}] Iniciado: {datetime.now().isoformat()}")

    print(f"[ALMA] v{VERSION} — {config['agent_name']} → {config['server_host']}:{config['server_port']}")

    if not os.path.exists(CONFIG_FILE):
        save_config(config)

    # Verificar actualización al iniciar
    update = check_update()
    if update:
        do_update(update)

    try:
        asyncio.run(agent_loop())
    except KeyboardInterrupt:
        print("[ALMA] Detenido por usuario")
    except Exception as e:
        print(f"[ALMA] Error fatal: {e}")

if __name__ == "__main__":
    main()
