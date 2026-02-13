#!/bin/bash
if ! command -v python3 &> /dev/null; then
    apt update && apt install python3 python3-pip curl -y
fi
if [ ! -f "manager.py" ]; then
    curl -Ls https://raw.githubusercontent.com/sasantech/v2ray-monitoring/main/manager.py -o manager.py
fi
python3 manager.py

