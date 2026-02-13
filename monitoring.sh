#!/bin/bash

# --- نصب پیش‌نیازها ---
if ! command -v python3 &> /dev/null; then
    echo "Installing Python3..."
    apt update && apt install python3 python3-pip curl -y
fi

# --- ساخت فایل پایتون ---
cat << 'EOF' > manager.py
import os, json, subprocess, time, requests, re, shutil, random, base64
from urllib.parse import urlparse, parse_qs, unquote

# --- COLORS ---
G, R, Y, B, C, W = '\033[92m', '\033[91m', '\033[93m', '\033[94m', '\033[96m', '\033[0m'
BOLD = '\033[1m'

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
            node_name = unquote(p.fragment) if p.fragment else f"VLESS_{random.randint(100,999)}"
            return {
                "protocol": "vless", "name": node_name, "uuid": p.username, 
                "address": p.hostname, "port": int(p.port), 
                "type": q.get('type', ['tcp'])[0], 
                "header": q.get('headerType', ['none'])[0], 
                "security": q.get('security', ['none'])[0]
            }
        elif link.startswith("vmess://"):
            data = json.loads(base64.b64decode(link[8:]).decode('utf-8'))
            node_name = data.get('ps', f"VM_{random.randint(100,999)}")
            return {
                "protocol": "vmess", "name": node_name, "uuid": data.get('id'), 
                "address": data.get('add'), "port": int(data.get('port')), 
                "type": data.get('net', 'tcp'), "header": data.get('type', 'none'), "security": "none"
            }
    except: return None

def test_config(conf):
    xray_path = shutil.which("xray") or "/usr/local/bin/xray"
    test_port = random.randint(20000, 30000)
    outbound = {
        "protocol": conf['protocol'],
        "settings": {"vnext": [{"address": conf['address'], "port": conf['port'], "users": [{"id": conf['uuid'], "encryption": "none" if conf['protocol']=='vless' else "auto"}]}]},
        "streamSettings": {"network": conf.get('type', 'tcp'), "security": conf.get('security', 'none'), "tcpSettings": {"header": {"type": "http"}} if conf.get('header') == "http" else {}}
    }
    tmp = f"t_{test_port}.json"
    start_time = time.time() # شروع زمان‌سنجی
    try:
        save_data(tmp, {"log": {"loglevel": "none"}, "inbounds": [{"port": test_port, "listen": "127.0.0.1", "protocol": "socks"}], "outbounds": [outbound]})
        proc = subprocess.Popen([xray_path, "-c", tmp], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(2) # صبر برای بالا آمدن هسته
        
        res = subprocess.check_output(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--socks5", f"127.0.0.1:{test_port}", "http://www.google.com/gen_204", "--connect-timeout", "5"]).decode().strip()
        end_time = time.time() # پایان زمان‌سنجی
        
        proc.terminate()
        if res in ["204", "200"]:
            ping = int((end_time - start_time - 2) * 1000) # محاسبه پینگ خالص (منهای زمان لود)
            return True, max(ping, 10) # حداقل پینگ ۱۰ میلی‌ثانیه
        return False, 0
    except: return False, 0
    finally:
        if os.path.exists(tmp): os.remove(tmp)

def monitor_mode():
    print(f"{G}🚀 Monitoring Started with Ping Detection...{W}")
    last_status = {}
    while True:
        configs = load_data(CONFIG_FILE)
        settings = load_data(SETTINGS_FILE)
        for c in configs:
            name = c.get('name', 'Unknown')
            is_up, ping = test_config(c)
            
            if is_up:
                status_text = f"✅ {name}: UP ({ping}ms)"
                print(f"{G}{status_text}{W}")
                if last_status.get(name) == False:
                    msg = f"🟢 FIXED: [{name}] is back ONLINE!\n⚡ Ping: {ping}ms"
                    for cid in settings.get('chat_id', '').split(','):
                        requests.post(f"https://api.telegram.org/bot{settings.get('bot_token')}/sendMessage", json={"chat_id": cid.strip(), "text": msg})
                last_status[name] = True
            else:
                print(f"{R}❌ {name}: DOWN{W}")
                if last_status.get(name, True): # فقط بار اول که قطع شد خبر بده
                    msg = f"🚨 ALERT: [{name}] is DOWN!"
                    for cid in settings.get('chat_id', '').split(','):
                        requests.post(f"https://api.telegram.org/bot{settings.get('bot_token')}/sendMessage", json={"chat_id": cid.strip(), "text": msg})
                last_status[name] = False
        time.sleep(30)

def main():
    if os.environ.get("AUTORUN") == "true": monitor_mode(); return
    while True:
        os.system('clear')
        print(f"{C}{BOLD}V2RAY MONITOR MANAGER v6.0{W}")
        print(f"1. {B}Add Config{W}\n2. {B}List & Delete{W}\n3. {B}Bot Settings{W}\n4. {G}START{W}\n5. {R}STOP{W}\n6. Exit")
        ch = input(f"\nSelect: ")
        if ch == "1":
            link = input("\nPaste Link: ")
            p = parse_config(link)
            if p:
                d = load_data(CONFIG_FILE); d.append(p); save_data(CONFIG_FILE, d)
                print(f"{G}Node '{p['name']}' added!{W}"); time.sleep(1)
        elif ch == "3":
            t = input("Token: "); c = input("Chat IDs (111,222): ")
            save_data(SETTINGS_FILE, {"bot_token": t, "chat_id": c})
        elif ch == "4":
            content = f"[Unit]\nDescription=V2Ray Monitor\n[Service]\nType=simple\nUser=root\nWorkingDirectory={os.getcwd()}\nExecStart=/usr/bin/python3 {os.getcwd()}/manager.py\nEnvironment=\"AUTORUN=true\"\nRestart=always\n[Install]\nWantedBy=multi-user.target"
            with open(f"/etc/systemd/system/{SERVICE_NAME}", "w") as f: f.write(content)
            subprocess.run(["systemctl", "daemon-reload", "enable", "--now", SERVICE_NAME], shell=True)
            print(f"{G}Monitoring Started in Background!{W}"); time.sleep(2)
        elif ch == "5":
            subprocess.run(["systemctl", "disable", "--now", SERVICE_NAME], shell=True)
            print(f"{R}Stopped!{W}"); time.sleep(2)
        elif ch == "6": break

if __name__ == "__main__": main()
EOF

# --- اجرا ---
python3 manager.py