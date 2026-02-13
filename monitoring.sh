#!/bin/bash

# بررسی نصب بودن پیش‌نیازها
if ! command -v python3 &> /dev/null; then
    echo "Installing Python3..."
    apt update && apt install python3 python3-pip curl -y
fi

# دانلود فایل اصلی پایتون اگر وجود نداشت
if [ ! -f "manager.py" ]; then
    echo "Downloading manager.py..."
    curl -Ls https://raw.githubusercontent.com/sasantech/v2ray-monitoring/main/manager.py -o manager.py
fi

# اجرای فایل پایتون
python3 manager.py
