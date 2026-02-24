#!/bin/bash

# --- تنظیمات آدرس گیت‌هاب شما ---
# نام کاربری و نام مخزن خود را اینجا جایگزین کنید
GH_USER="sasantech"
GH_REPO="v2ray-monitoring"

# --- رفع ارور Externally Managed Environment ---
echo "Installing Python requirements..."
sudo apt update
sudo apt install -y python3-requests curl unzip

# --- نصب Xray ---
if ! command -v xray &> /dev/null; then
    echo "Installing Xray core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fi

# --- دانلود فایل پایتون از گیت‌هاب ---
# این بخش باعث می‌شود ارور 'can't open file manager.py' برطرف شود
echo "Downloading manager script..."
curl -Ls "https://raw.githubusercontent.com/$GH_USER/$GH_REPO/main/manager.py" -o manager.py

# --- اجرای اسکریپت ---
if [ -f "manager.py" ]; then
    python3 manager.py
else
    echo "Error: Could not download manager.py from GitHub!"
    exit 1
fi