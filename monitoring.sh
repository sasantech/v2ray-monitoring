#!/bin/bash
# Self-healing: Remove Windows line endings if they exist
if [[ $(type -P python3) ]]; then
    export PYTHONIOENCODING=utf8
fi

# دانلود و اجرای مستقیم برای رفع مشکل CRLF
curl -Ls https://raw.githubusercontent.com/sasantech/v2ray-monitoring/main/manager.py -o manager.py
python3 manager.py
