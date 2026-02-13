
import os, json, subprocess, time, requests, re, shutil, random, base64
from urllib.parse import urlparse, parse_qs, unquote

# --- COLORS ---
G, R, Y, B, C, W = '\033[92m', '\033[91m', '\033[93m', '\033[94m', '\033[96m', '\033[0m'
BOLD = '\033[1m'

# --- FILES ---
SCRIPT_PATH = os.path.realpath(__file__)
CONFIG_FILE = "saved_configs.json"
SETTINGS_FILE = "bot_settings.json"
MSG_HISTORY_FILE = "msg_history.json"
SERVICE_NAME = "v2ray-monitor.service"

# --- CORE FUNCTIONS ---
def find_xray():
    path = shutil.which("xray")
    return path if path else "/usr/local/bin/xray"

def load_data(file):
    if os.path.exists(file):
        with open(file, "r") as f:
            try: return json.load(f)
            except: return [] if "configs" in file or "history" in file else {}
    return [] if "configs" in file or "history" in file else {}

def save_data(file, data):
    with open(file, "w") as f:
        json.dump(data, f, indent=4)

def send_telegram(message):
    settings = load_data(SETTINGS_FILE)
    token = settings.get("bot_token")
    cids = settings.get("chat_id", "")
    if not token or not cids: return
    
    chat_list = [x.strip() for x in cids.split(',')]
    for cid in chat_list:
        url = f"https://api.telegram.org/bot{token}/sendMessage"
        try:
            r = requests.post(url, json={"chat_id": cid, "text": message}, timeout=10).json()
            if r.get("ok"):
                history = load_data(MSG_HISTORY_FILE)
                history.append({"chat_id": cid, "id": r["result"]["message_id"], "time": time.time()})
                save_data(MSG_HISTORY_FILE, history)
        except: pass

def test_config(conf, xray_path):
    test_port = random.randint(20000, 30000)
    outbound = {
        "protocol": conf.get('protocol', 'vless'),
        "settings": {"vnext": [{"address": conf['address'], "port": conf['port'], "users": [{"id": conf['uuid'], "encryption": "none" if conf.get('protocol')=='vless' else "auto"}]}]},
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

# --- SERVICE MANAGEMENT ---
def manage_service(action):
    if action == "install":
        content = f"[Unit]\nDescription=V2Ray Monitor\nAfter=network.target\n\n[Service]\nType=simple\nUser=root\nWorkingDirectory={os.path.dirname(SCRIPT_PATH)}\nExecStart=/usr/bin/python3 {SCRIPT_PATH}\nEnvironment=\"AUTORUN=true\"\nRestart=always\n\n[Install]\nWantedBy=multi-user.target"
        with open(f"/etc/systemd/system/{SERVICE_NAME}", "w") as f: f.write(content)
        subprocess.run(["systemctl", "daemon-reload"], check=True)
        subprocess.run(["systemctl", "enable", SERVICE_NAME], check=True)
        subprocess.run(["systemctl", "restart", SERVICE_NAME], check=True)
    elif action == "stop":
        subprocess.run(["systemctl", "stop", SERVICE_NAME], check=True)
        subprocess.run(["systemctl", "disable", SERVICE_NAME], check=True)

# --- MONITOR ---
def monitor_mode(xray_path):
    print(f"{G}🚀 Monitoring Started...{W}")
    send_telegram("🚀 Monitoring System Started!")
    last_alert, last_status = {}, {}
    while True:
        configs = load_data(CONFIG_FILE)
        now = time.time()
        for c in configs:
            name = c.get('name', 'Unknown')
            is_up = test_config(c, xray_path)
            if is_up:
                if last_status.get(name) == False: send_telegram(f"🟢 FIXED: [{name}] is back ONLINE!")
                last_status[name], last_alert[name] = True, 0
                print(f"{G}✅ {name}: UP{W}")
            else:
                last_status[name] = False
                if now - last_alert.get(name, 0) > 600:
                    send_telegram(f"🚨 ALERT: [{name}] is DOWN!")
                    last_alert[name] = now
                print(f"{R}❌ {name}: DOWN{W}")
        time.sleep(30)

# --- MAIN MENU ---
def main():
    path = find_xray()
    if os.environ.get("AUTORUN") == "true": monitor_mode(path); return

    while True:
        os.system('clear')
        print(f"{C}{BOLD}V2RAY MONITOR MANAGER{W}")
        print(f"1. {B}Add Config (VLESS/VMess){W}")
        print(f"2. {B}List & Delete Nodes{W}")
        print(f"3. {B}Bot Settings (Update Token/ID){W}")
        print(f"4. {G}START MONITOR (Background Service){W}")
        print(f"5. {R}STOP MONITOR & Service{W}")
        print(f"6. Exit")
        
        choice = input(f"\n{BOLD}Select: {W}")
        
        if choice == "1":
            link = input("Link: ")
            # (منطق parse_config را اینجا قرار دهید)
            # مختصرا:
            p = {"name": "Test", "address": "1.1.1.1", "port": 443, "uuid": "...", "protocol": "vless", "type": "tcp", "header": "http", "security": "none"} 
            # جایگزین کردن پارس واقعی:
            # p = parse_logic(link) 
            d = load_data(CONFIG_FILE)
            d.append(p); save_data(CONFIG_FILE, d)
        elif choice == "2":
            d = load_data(CONFIG_FILE)
            for i, c in enumerate(d): print(f"{i+1}. {c['name']} ({c['protocol']})")
            idx = input("ID to delete: ")
            if idx.isdigit(): d.pop(int(idx)-1); save_data(CONFIG_FILE, d)
        elif choice == "3":
            t = input("New Token: ")
            c = input("Chat IDs (comma separated): ")
            save_data(SETTINGS_FILE, {"bot_token": t, "chat_id": c})
            print(f"{G}Settings Updated. Restarting service...{W}")
            if os.path.exists(f"/etc/systemd/system/{SERVICE_NAME}"): manage_service("install")
        elif choice == "4":
            manage_service("install")
            print(f"{G}Service installed and started!{W}")
            time.sleep(2)
        elif choice == "5":
            manage_service("stop")
            print(f"{R}Service stopped and disabled.{W}")
            time.sleep(2)
        elif choice == "6": break

if __name__ == "__main__": main()