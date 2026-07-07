#!/usr/bin/env python3
"""
ALMA Agent v1.0 — Agente Remoto Gestlife
Auto-actualizable desde GitHub: gestlifedev/alma-agent
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
from datetime import datetime

# === CONFIG ===
CONFIG_FILE = "alma-agent-config.json"
VERSION = "1.0.0"
GITHUB_REPO = "gestlifedev/alma-agent"
GITHUB_API = f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest"

DEFAULT_CONFIG = {
    "server_host": "46.27.219.187",
    "server_port": 9555,
    "agent_name": socket.gethostname(),
    "retry_seconds": 10,
    "ping_interval": 30,
    "auto_update": True,
    "update_check_interval": 3600  # 1 hora
}

def load_config():
    try:
        with open(CONFIG_FILE) as f:
            return {**DEFAULT_CONFIG, **json.load(f)}
    except:
        return dict(DEFAULT_CONFIG)

def save_config(cfg):
    with open(CONFIG_FILE, "w") as f:
        json.dump(cfg, f, indent=2)

config = load_config()

# === AUTO-UPDATE ===
def check_update():
    """Verifica si hay nueva versión en GitHub."""
    if not config.get("auto_update", True):
        return None
    try:
        req = urllib.request.Request(GITHUB_API, headers={"User-Agent": "ALMA-Agent"})
        data = json.loads(urllib.request.urlopen(req, timeout=10).read())
        latest = data.get("tag_name", "").lstrip("v")
        if latest and latest != VERSION:
            return {
                "version": latest,
                "url": data.get("html_url", ""),
                "assets": data.get("assets", []),
                "body": data.get("body", "")
            }
    except Exception as e:
        print(f"[ALMA] Update check failed: {e}")
    return None

def do_update(release_info):
    """Descarga e instala la nueva versión."""
    print(f"[ALMA] Nueva versión disponible: {release_info['version']}")
    try:
        # Buscar el asset del agente
        agent_asset = None
        for asset in release_info.get("assets", []):
            if "alma-agent" in asset.get("name", "").lower() and asset.get("name", "").endswith(".py"):
                agent_asset = asset
                break
        
        if not agent_asset:
            # No hay asset, descargar raw del repo
            url = f"https://raw.githubusercontent.com/{GITHUB_REPO}/master/alma-agent.py"
        else:
            url = agent_asset["browser_download_url"]
        
        print(f"[ALMA] Descargando: {url}")
        new_code = urllib.request.urlopen(url, timeout=60).read()
        
        # Backup del actual
        current_file = __file__ if __file__ else sys.argv[0]
        backup = current_file + ".bak"
        with open(backup, "wb") as f:
            with open(current_file, "rb") as orig:
                f.write(orig.read())
        
        # Escribir nueva versión
        with open(current_file, "wb") as f:
            f.write(new_code)
        
        print(f"[ALMA] Actualizado a v{release_info['version']}. Reiniciando...")
        os.execv(sys.executable, [sys.executable] + sys.argv)
        
    except Exception as e:
        print(f"[ALMA] Update failed: {e}")
        # Restaurar backup
        backup = (__file__ if __file__ else sys.argv[0]) + ".bak"
        if os.path.exists(backup):
            os.rename(backup, __file__ if __file__ else sys.argv[0])

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
        raise Exception(f"Handshake failed")
    return reader, writer

async def ws_send(writer, message):
    data = message.encode('utf-8')
    frame = bytearray([0x81])
    length = len(data)
    if length < 126: frame.append(length)
    elif length < 65536: frame.append(126); frame.extend(length.to_bytes(2, 'big'))
    else: frame.append(127); frame.extend(length.to_bytes(8, 'big'))
    frame.extend(data)
    writer.write(bytes(frame))
    await writer.drain()

async def ws_recv(reader):
    try:
        header = await asyncio.wait_for(reader.readexactly(2), timeout=120)
    except: return None
    opcode = header[0] & 0x0F
    if opcode == 0x08: return None
    length = header[1] & 0x7F
    if length == 126: length = int.from_bytes(await reader.readexactly(2), 'big')
    elif length == 127: length = int.from_bytes(await reader.readexactly(8), 'big')
    payload = await reader.readexactly(length)
    return payload.decode('utf-8', errors='ignore')

async def run_command(command):
    try:
        proc = await asyncio.create_subprocess_shell(
            command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=60)
        return {
            "exit_code": proc.returncode,
            "stdout": stdout.decode('utf-8', errors='replace')[:5000],
            "stderr": stderr.decode('utf-8', errors='replace')[:2000]
        }
    except asyncio.TimeoutError:
        return {"exit_code": -1, "stdout": "", "stderr": "Timeout (60s)"}
    except Exception as e:
        return {"exit_code": -1, "stdout": "", "stderr": str(e)}

async def agent_loop():
    cfg = load_config()
    host = cfg["server_host"]
    port = cfg["server_port"]
    name = cfg["agent_name"]
    last_update_check = 0
    
    print(f"[ALMA] v{VERSION} — Conectando a {host}:{port} como '{name}'")
    
    while True:
        try:
            # Auto-update check
            now = asyncio.get_event_loop().time()
            if now - last_update_check > cfg.get("update_check_interval", 3600):
                update = check_update()
                if update:
                    print(f"[ALMA] ¡Actualización disponible! v{update['version']}")
                    do_update(update)
                last_update_check = now
            
            reader, writer = await ws_connect(host, port)
            print(f"[ALMA] ✅ Conectado al Bridge")
            
            # Registrar
            await ws_send(writer, json.dumps({
                "type": "register",
                "name": name,
                "os": platform.system() + " " + platform.release(),
                "hostname": socket.gethostname(),
                "version": VERSION
            }))
            
            last_ping = now
            
            while True:
                try:
                    msg = await asyncio.wait_for(ws_recv(reader), timeout=5)
                except asyncio.TimeoutError:
                    now = asyncio.get_event_loop().time()
                    if now - last_ping > cfg["ping_interval"]:
                        await ws_send(writer, json.dumps({"type": "ping"}))
                        last_ping = now
                    continue
                
                if msg is None:
                    print("[ALMA] 🔌 Servidor cerró conexión")
                    break
                
                try:
                    data = json.loads(msg)
                    msg_type = data.get("type", "")
                    
                    if msg_type == "pong":
                        pass
                    elif msg_type == "command":
                        cmd = data.get("command", "")
                        cmd_id = data.get("command_id", "")
                        print(f"[ALMA] ⚡ Ejecutando: {cmd}")
                        result = await run_command(cmd)
                        await ws_send(writer, json.dumps({
                            "type": "result",
                            "command_id": cmd_id,
                            "result": result
                        }))
                        print(f"[ALMA] ✅ Resultado: exit={result['exit_code']}")
                    elif msg_type == "get_status":
                        await ws_send(writer, json.dumps({
                            "type": "status",
                            "hostname": socket.gethostname(),
                            "os": platform.system(),
                            "version": VERSION
                        }))
                        
                except json.JSONDecodeError:
                    pass
            
            writer.close()
            
        except (ConnectionRefusedError, OSError) as e:
            print(f"[ALMA] ❌ Conexión: {e}. Reintentando en {cfg['retry_seconds']}s...")
        except Exception as e:
            print(f"[ALMA] ❌ Error: {e}. Reintentando en {cfg['retry_seconds']}s...")
        
        await asyncio.sleep(cfg["retry_seconds"])

def main():
    print("=" * 50)
    print("  🤖 ALMA Agent v" + VERSION)
    print("  Gestlife Bridge System")
    print(f"  Servidor: {config['server_host']}:{config['server_port']}")
    print(f"  Nombre:   {config['agent_name']}")
    print(f"  Auto-update: {'ON' if config.get('auto_update',True) else 'OFF'}")
    print("=" * 50)
    
    if not os.path.exists(CONFIG_FILE):
        save_config(config)
        print(f"[ALMA] Config guardada en {CONFIG_FILE}")
    
    # Check update on startup
    print("[ALMA] Verificando actualizaciones...")
    update = check_update()
    if update:
        print(f"[ALMA] 🆕 Nueva versión: v{update['version']}")
        do_update(update)
    else:
        print("[ALMA] ✅ Versión actual")
    
    try:
        asyncio.run(agent_loop())
    except KeyboardInterrupt:
        print("\n[ALMA] 👋 Detenido")

if __name__ == "__main__":
    main()
