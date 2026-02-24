#!/bin/bash

# بروزرسانی مخازن
sudo apt update

# نصب پایتون و کتابخانه requests از طریق مخازن سیستم (برای جلوگیری از خطای PIP)
sudo apt install -y python3 python3-pip python3-requests curl

# نصب Xray در صورت عدم وجود
if ! command -v xray &> /dev/null; then
    echo "Installing Xray core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fi

# بررسی وجود فایل اصلی پایتون
if [ ! -f "manager.py" ]; then
    echo "Error: manager.py not found in current directory!"
    exit 1
fi

# اجرای اسکریپت
python3 manager.py