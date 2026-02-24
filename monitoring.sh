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
    for attempt in range(2):
        test_port = random.randint(30000, 40000)
        stream = {"network": conf.get('type', 'tcp'), "security": conf.get('security', 'none')}
        
        if conf.get('header') == 'http':
            header_obj = {"type": "http", "request": {"version": "1.1", "method": "GET", "headers": {
                "Host": [conf.get('sni') if conf.get('sni') else conf['address']],
                "User-Agent": ["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0"],
                "Accept-Encoding": ["gzip, deflate"], "Connection": ["keep-alive"]}}}
            if conf.get('path'): header_obj["request"]["path"] = [conf.get('path')]
            stream["tcpSettings"] = {"header": header_obj}
        
        if conf['security'] == 'reality':
            stream["realitySettings"] = {"fingerprint": "chrome", "serverName": conf.get('sni'), "publicKey": conf.get('pbk'), "shortId": conf.get('sid')}
        elif conf['security'] == 'tls':
            stream["tlsSettings"] = {"serverName": conf.get('sni'), "allowInsecure": True}

        config = {"log": {"loglevel": "none"}, "inbounds": [{"port": test_port, "listen": "127.0.0.1", "protocol": "socks", "settings": {"udp": True}}],
                  "outbounds": [{"protocol": "vless", "settings": {"vnext": [{"address": conf['address'], "port": conf['port'], "users": [{"id": conf['uuid'], "encryption": "none"}]}]}, "streamSettings": stream}]}
        
        tmp_file = f"test_{test_port}.json"
        save_data(tmp_file, config)
        try:
            process = subprocess.Popen([xray_bin, "-c", tmp_file], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(10) 
            res = subprocess.run(["curl", "-4", "-o", "/dev/null", "-sk", "-x", f"socks5h://127.0.0.1:{test_port}", "-w", "%{time_total}", "http://1.1.1.1/generate_204", "--connect-timeout", "15"], capture_output=True, text=True)
            latency = int(float(res.stdout.strip()) * 1000) if res.returncode == 0 else 0
            process.terminate(); process.wait()
            if latency > 0:
                if os.path.exists(tmp_file): os.remove(tmp_file)
                return True, latency
        except:
            if 'process' in locals(): process.kill(); process.wait()
        finally:
            if os.path.exists(tmp_file): os.remove(tmp_file)
        if attempt == 0: time.sleep(3)
    return False, 0

def send_tg(msg):
    s = load_data(SETTINGS_FILE)
    if s and s.get('token') and s.get('chat_id'):
        url = f"https://api.telegram.org/bot{s['token']}/sendMessage"
        try: requests.post(url, json={"chat_id": s['chat_id'], "text": msg, "parse_mode": "Markdown"})
        except: pass

def monitor_mode():
    send_tg("🚀 *Monitoring System v7.9 Started*")
    last_status = {}
    last_alert_time = {} 

    while True:
        configs = load_data(CONFIG_FILE)
        current_time = time.time()
        for c in configs:
            name = c['name']
            up, ping = test_config(c)
            
            if up:
                if last_status.get(name) == False:
                    send_tg(f"✅ *Node Reconnected*\n👤 Name: `{name}`\n🟢 Status: `Online` \n⚡ Ping: `{ping}ms` ")
                last_status[name] = True
            else:
                # اگر نود قطع باشد: یا بار اول است، یا ۱۰ دقیقه از آخرین هشدار گذشته
                if last_status.get(name, True) == True or (current_time - last_alert_time.get(name, 0) > 600):
                    send_tg(f"🚨 *Node Down!*\n👤 Name: `{name}`\n🔴 Status: `Offline` \n⚠️ Check your server!")
                    last_alert_time[name] = current_time
                last_status[name] = False
        time.sleep(30)

def main():
    if os.environ.get("AUTORUN") == "true": monitor_mode(); return
    while True:
        os.system('clear')
        print(f"{C}{BOLD}V2RAY MONITOR MANAGER v7.9{W}")
        print(f"{Y}Alert Mode: Every 10 Minutes | Accurate Ping Active{W}")
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
                    idx = input(f"\nEnter ID to Delete: ")
                    if idx.isdigit() and 0 < int(idx) <= len(d):
                        del d[int(idx)-1]; save_data(CONFIG_FILE, d); print(f"{G}Deleted!{W}")
                time.sleep(2)
            elif ch == "3":
                t = input("Token: "); c = input("Chat ID/Channel (@name or -100...): "); save_data(SETTINGS_FILE, {"token": t, "chat_id": c})
                send_tg("✅ Bot connected successfully!")
            elif ch == "4":
                path = os.getcwd()
                content = f"[Unit]\nDescription=V2Monitor\n[Service]\nType=simple\nUser=root\nWorkingDirectory={path}\nExecStart=/usr/bin/python3 {path}/manager.py\nEnvironment=\"AUTORUN=true\"\nRestart=always\n[Install]\nWantedBy=multi-user.target"
                with open(f"/etc/systemd/system/{SERVICE_NAME}", "w") as f: f.write(content)
                subprocess.run(["systemctl", "daemon-reload"]); subprocess.run(["systemctl", "enable", "--now", SERVICE_NAME])
                print(f"{G}Monitoring Started!{W}"); time.sleep(1)
            elif ch == "5":
                subprocess.run(["systemctl", "disable", "--now", SERVICE_NAME]); print(f"{R}Stopped!{W}"); time.sleep(1)
            elif ch == "6":
                print(f"\n{Y}Testing all nodes...{W}")
                for c in load_data(CONFIG_FILE):
                    up, ping = test_config(c)
                    st = f"{G}ONLINE{W}" if up else f"{R}OFFLINE{W}"
                    print(f"Node: {c['name']:<18} | {st} | {ping}ms")
                input("\nEnter to return...")
            elif ch == "0": break
        except: break

if __name__ == "__main__": main()