#!/bin/bash

# دانلود فایل اصلی پایتون اگر وجود نداشت
if [ ! -f "manager.py" ]; then
    echo "Downloading manager.py..."
    curl -Ls https://raw.githubusercontent.com/sasantech/v2ray-monitoring/main/manager.py -o manager.py
fi

# نصب کتابخانه مورد نیاز (اگر نصب نباشد)
pip3 install requests &> /dev/null

# اجرای فایل پایتون
python3 manager.py