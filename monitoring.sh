#!/bin/bash

# نصب پیش‌نیازها
sudo apt update && sudo apt install -y python3 python3-pip curl
pip3 install requests

# نصب Xray در صورت عدم وجود
if ! command -v xray &> /dev/null; then
    echo "Installing Xray..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fi

# اجرای اسکریپت پایتون
python3 manager.py