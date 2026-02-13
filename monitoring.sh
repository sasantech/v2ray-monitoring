#!/bin/bash

# --- تنظیمات اولیه و پیش‌نیازها ---
if ! command -v python3 &> /dev/null; then
    echo "Installing Python3..."
    apt update && apt install python3 python3-pip curl -y
fi

# --- ساخت فایل پایتون به صورت خودکار ---
cat << 'EOF' > manager.py
import os, json, subprocess, time, requests, re, shutil, random, base64
from urllib.parse import urlparse, parse_qs, unquote

# --- COLORS ---
G, R, Y, B, C, W = '\033[92m', '\033[91m', '\033[93m', '\033[94m', '\033[96m', '\033[0m'
BOLD = '\033[1m'

# --- FILES ---
SCRIPT_PATH = os.path.realpath(__file__)
CONFIG_FILE = "saved_configs.json"
SETTINGS_FILE = "bot_settings.json"
SERVICE_NAME = "v2ray-monitor.service"

def load_data(file):
    if os.path.exists(file):
        with open(file, "r") as f:
            try: return json.load(f)
            except: return [] if "configs" in file else {}
    return [] if "configs" in file else {}

def save_data(file, data):
    with open(file, "w") as f:
        json.dump(data, f, indent=4)

def parse_config(link):
    try:
        if link.startswith("vless://"):
            p = urlparse(link); q = parse_qs(p.query)
            return {"protocol": "vless", "name": unquote(p.fragment) if p.fragment else f"Node_{random.randint(10,99)}", "uuid": p.username, "address": p.hostname, "port": int(p.port), "type": q.get('type', ['tcp'])[0], "header": q.get('headerType', ['none'])[0], "security": q.get('security', ['none'])[0]}
        elif link.startswith("vmess://"):
            data = json.loads(base64.b64decode(link[8:]).decode('utf-8'))
            return {"protocol": "vmess", "name": data.get('ps', "Node"), "uuid": data.get('id'), "address": data.get('add'), "port": int(data.get('port')), "type": data.get('net', 'tcp'), "header": data.get('type', 'none'), "security": "none"}
    except: return None

def send_telegram(message):
    settings = load_data(SETTINGS_FILE)
    token = settings.get("bot_token")
    cids = settings.get("chat_id", "")
    if not token or not cids: return
    for cid in [x.strip() for x in cids.split(',')]:
        url = f"https://api.telegram.org/bot{token}/sendMessage"
        try: requests.post(url, json={"chat_id": cid, "text": message}, timeout=10)
        except: pass

def test_config(conf):
    xray_path = shutil.which("xray") or "/usr/local/bin/xray"
    test_port = random.randint(20000, 30000)
    outbound = {
        "protocol": conf['protocol'],
        "settings": {"vnext": [{"address": conf['address'], "port": conf['port'], "users": [{"id": conf['uuid'], "encryption": "none" if conf['protocol']=='vless' else "auto"}]}]},
        "streamSettings": {"network": conf.get('type', 'tcp'), "tcpSettings": {"header": {"type": "http"}} if conf.get('header') == "http" else {}}
    }
    tmp = f"t_{test_port}.json"
    try:
        save_data(tmp, {"log": {"loglevel": "none"}, "inbounds": [{"port": test_port, "listen": "127.0.0.1", "protocol": "socks"}], "outbounds": [outbound]})
        proc = subprocess.Popen([xray_path, "-c", tmp], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(5)
        res = subprocess.check_output(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--socks5", f"127.0.0.1:{test_port}", "http://www.google.com/gen_204", "--connect-timeout", "10"]).decode().strip()
        proc.terminate()
        return res in ["204", "200"]
    except: return False
    finally:
        if os.path.exists(tmp): os.remove(tmp)

def monitor_mode():
    print(f"{G}🚀 Monitoring Started...{W}")
    send_telegram("🚀 مانیتورینگ نودها فعال شد!")
    last_alert, last_status = {}, {}
    while True:
        configs = load_data(CONFIG_FILE)
        now = time.time()
        for c in configs:
            name = c.get('name', 'Unknown')
            is_up = test_config(c)
            if is_up:
                if last_status.get(name) == False: send_telegram(f"🟢 FIXED: [{name}] is ONLINE!")
                last_status[name], last_alert[name] = True, 0
                print(f"{G}✅ {name}: UP{W}")
            else:
                last_status[name] = False
                if now - last_alert.get(name, 0) > 600:
                    send_telegram(f"🚨 ALERT: [{name}] is DOWN!")
                    last_alert[name] = now
                print(f"{R}❌ {name}: DOWN{W}")
        time.sleep(30)

def main():
    if os.environ.get("AUTORUN") == "true": monitor_mode(); return
    while True:
        os.system('clear')
        print(f"{C}{BOLD}V2RAY MONITOR MANAGER{W}")
        print(f"1. {B}Add Config{W}\n2. {B}List & Delete{W}\n3. {B}Bot Settings{W}\n4. {G}START{W}\n5. {R}STOP{W}\n6. Exit")
        ch = input(f"\nSelect: ")
        if ch == "1":
            link = input("Link: "); p = parse_config(link)
            if p:
                d = load_data(CONFIG_FILE); d.append(p); save_data(CONFIG_FILE, d)
                print(f"{G}Added!{W}"); time.sleep(1)
        elif ch == "3":
            t = input("Token: "); c = input("Chat IDs: ")
            save_data(SETTINGS_FILE, {"bot_token": t, "chat_id": c})
        elif ch == "4":
            content = f"[Unit]\nDescription=V2Ray Monitor\n[Service]\nType=simple\nUser=root\nWorkingDirectory={os.getcwd()}\nExecStart=/usr/bin/python3 {os.getcwd()}/manager.py\nEnvironment=\"AUTORUN=true\"\nRestart=always\n[Install]\nWantedBy=multi-user.target"
            with open(f"/etc/systemd/system/{SERVICE_NAME}", "w") as f: f.write(content)
            subprocess.run(["systemctl", "daemon-reload", "enable", "--now", SERVICE_NAME], shell=True)
            print(f"{G}Service Started!{W}"); time.sleep(2)
        elif ch == "5":
            subprocess.run(["systemctl", "disable", "--now", SERVICE_NAME], shell=True)
            print(f"{R}Stopped!{W}"); time.sleep(2)
        elif ch == "6": break

if __name__ == "__main__": main()
EOF

# --- اجرای نهایی ---
python3 manager.py