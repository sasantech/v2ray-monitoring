#!/bin/bash

# --- Check Core Requirement ---
if ! command -v xray &> /dev/null; then
    echo "Xray core not found. Installing..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fi

# --- Create Python Manager ---
cat << 'EOF' > manager.py
#!/usr/bin/python3
import os, json, subprocess, time, requests, shutil, random, base64
from urllib.parse import urlparse, parse_qs, unquote

# --- Colors & Constants ---
G, R, Y, B, C, W = '\033[92m', '\033[91m', '\033[93m', '\033[94m', '\033[96m', '\033[0m'
BOLD = '\033[1m'
CONFIG_FILE = "saved_configs.json"
SETTINGS_FILE = "bot_settings.json"
SERVICE_NAME = "v2ray-monitor.service"

def load_data(file):
    try:
        if os.path.exists(file):
            with open(file, "r") as f: return json.load(f)
    except: pass
    return [] if "configs" in file or "saved" in file else {}

def save_data(file, data):
    with open(file, "w") as f: json.dump(data, f, indent=4)

def parse_config(link):
    try:
        link = link.strip()
        if link.startswith("vless://"):
            p = urlparse(link); q = parse_qs(p.query)
            return {
                "protocol": "vless", "name": unquote(p.fragment) or "Node",
                "uuid": p.username, "address": p.hostname, "port": int(p.port),
                "type": q.get('type', ['tcp'])[0], "header": q.get('headerType', ['none'])[0],
                "security": q.get('security', ['none'])[0], "sni": q.get('sni', [''])[0],
                "pbk": q.get('pbk', [''])[0], "sid": q.get('sid', [''])[0], "path": q.get('path', [''])[0]
            }
        return None
    except: return None

def test_config(conf):
    xray_bin = "/usr/local/bin/xray"
    
    # --- منطق دو بار تست برای جلوگیری از گزارش غلط ---
    for attempt in range(2):
        test_port = random.randint(22000, 28000)
        stream = {"network": conf.get('type', 'tcp'), "security": conf.get('security', 'none')}
        
        if conf.get('header') == 'http':
            stream["tcpSettings"] = {"header": {"type": "http", "request": {"version": "1.1", "method": "GET", "path": [conf.get('path', '/')], "headers": {"Host": [conf.get('sni', conf['address'])]}}}}
        
        if conf['security'] == 'reality':
            stream["realitySettings"] = {"fingerprint": "chrome", "serverName": conf.get('sni'), "publicKey": conf.get('pbk'), "shortId": conf.get('sid')}
        elif conf['security'] == 'tls':
            stream["tlsSettings"] = {"serverName": conf.get('sni'), "allowInsecure": True}

        config = {
            "log": {"loglevel": "none"}, 
            "inbounds": [{"port": test_port, "listen": "127.0.0.1", "protocol": "socks"}],
            "outbounds": [{
                "protocol": "vless", 
                "settings": {"vnext": [{"address": conf['address'], "port": conf['port'], "users": [{"id": conf['uuid'], "encryption": "none"}]}]}, 
                "streamSettings": stream
            }]
        }
        
        tmp_file = f"test_{test_port}.json"
        save_data(tmp_file, config)
        start_time = time.time()
        
        try:
            process = subprocess.Popen([xray_bin, "-c", tmp_file], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(3) # فرصت به هسته برای لود شدن
            
            # تست با IPv4 و تایم‌اوت ۱۵ ثانیه برای پایداری
            res = subprocess.run([
                "curl", "-4", "-sx", f"socks5h://127.0.0.1:{test_port}", 
                "-o", "/dev/null", "-w", "%{http_code}", 
                "http://www.google.com/gen_204", "--connect-timeout", "15"
            ], capture_output=True, text=True)
            
            latency = int((time.time() - start_time - 3) * 1000)
            process.terminate()
            process.wait() # بستن کامل پروسه
            
            if res.stdout.strip() in ["204", "200"]:
                if os.path.exists(tmp_file): os.remove(tmp_file)
                return True, max(latency, 10) # اگر وصل بود، برمی‌گرداند
        except:
            if 'process' in locals(): process.kill()
        finally:
            if os.path.exists(tmp_file): os.remove(tmp_file)
        
        # اگر تست اول شکست خورد، ۱ ثانیه صبر کن و دوباره تست کن
        if attempt == 0:
            time.sleep(1)
            
    return False, 0 # اگر هر دو بار شکست خورد

def send_tg(msg):
    s = load_data(SETTINGS_FILE)
    if s and s.get('token') and s.get('chat_id'):
        url = f"https://api.telegram.org/bot{s['token']}/sendMessage"
        try: requests.post(url, json={"chat_id": s['chat_id'], "text": msg, "parse_mode": "Markdown"})
        except: pass

def monitor_mode():
    configs = load_data(CONFIG_FILE)
    start_report = "🚀 *Monitoring System Started*\n" + "═" * 20 + "\n"
    if not configs:
        start_report += "⚠️ No nodes found in list!"
    else:
        start_report += f"📊 Testing `{len(configs)}` nodes (Double-Check Mode)...\n\n"
        for c in configs:
            up, ping = test_config(c)
            status_icon = "🟢" if up else "🔴"
            ping_text = f"`{ping}ms`" if up else "`---`"
            start_report += f"{status_icon} `{c['name']}`: {ping_text}\n"
    
    send_tg(start_report)
    
    last_status = {}
    while True:
        configs = load_data(CONFIG_FILE)
        for c in configs:
            name = c['name']
            up, ping = test_config(c)
            if up and last_status.get(name) == False:
                send_tg(f"✅ *Node Reconnected*\n👤 Name: `{name}`\n🟢 Status: `Online` \n⚡ Ping: `{ping}ms`")
            elif not up and last_status.get(name, True) == True:
                send_tg(f"🚨 *Node Down!*\n👤 Name: `{name}`\n🔴 Status: `Offline` \n⚠️ Check your server!")
            last_status[name] = up
        time.sleep(30)

def main():
    if os.environ.get("AUTORUN") == "true": monitor_mode(); return
    while True:
        os.system('clear')
        print(f"{C}{BOLD}V2RAY MONITOR MANAGER v7.4 (Anti-False-Positive){W}")
        print("-" * 30)
        print(f" 1. Add Config\n 2. List & Delete Nodes\n 3. Bot Settings\n 4. START Monitoring\n 5. STOP Monitoring\n 6. Manual Check\n 0. Exit")
        try:
            ch = input(f"\nSelection: ")
            if ch == "1":
                link = input("\nLink: "); p = parse_config(link)
                if p:
                    d = load_data(CONFIG_FILE); d.append(p); save_data(CONFIG_FILE, d); print(f"{G}Added!{W}")
                time.sleep(1)
            elif ch == "2":
                d = load_data(CONFIG_FILE)
                if not d: print(f"{R}List is empty!{W}")
                else:
                    print(f"\n{BOLD}Current Nodes:{W}")
                    for i, c in enumerate(d): print(f"{i+1}. {c['name']} ({c['address']})")
                    idx = input(f"\nEnter ID to Delete (or Enter to cancel): ")
                    if idx.isdigit() and 0 < int(idx) <= len(d):
                        del d[int(idx)-1]; save_data(CONFIG_FILE, d); print(f"{G}Deleted!{W}")
                time.sleep(2)
            elif ch == "3":
                t = input("Token: "); c = input("Chat ID: "); save_data(SETTINGS_FILE, {"token": t, "chat_id": c})
                send_tg("✅ Bot connected successfully!")
            elif ch == "4":
                path = os.getcwd()
                content = f"[Unit]\nDescription=V2Monitor\n[Service]\nType=simple\nUser=root\nWorkingDirectory={path}\nExecStart=/usr/bin/python3 {path}/manager.py\nEnvironment=\"AUTORUN=true\"\nRestart=always\n[Install]\nWantedBy=multi-user.target"
                with open(f"/etc/systemd/system/{SERVICE_NAME}", "w") as f: f.write(content)
                subprocess.run(["systemctl", "daemon-reload"]); subprocess.run(["systemctl", "enable", "--now", SERVICE_NAME])
                print(f"{G}Monitoring Started! Check Telegram.{W}"); time.sleep(1)
            elif ch == "5":
                subprocess.run(["systemctl", "disable", "--now", SERVICE_NAME]); print(f"{R}Stopped!{W}"); time.sleep(1)
            elif ch == "6":
                print(f"\n{Y}Checking nodes (Double-Check enabled)...{W}")
                for c in load_data(CONFIG_FILE):
                    up, ping = test_config(c)
                    print(f"Node: {c['name']:<18} | {'ONLINE' if up else 'OFFLINE'} | {ping}ms")
                input("\nEnter to return...")
            elif ch == "0": break
        except: break

if __name__ == "__main__": main()
EOF
# --- Run ---
python3 manager.py