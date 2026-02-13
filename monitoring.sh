#!/bin/bash

# Clear screen for a professional look
clear

# Download manager.py if missing
if [ ! -f "manager.py" ]; then
    echo "📥 Downloading core components..."
    curl -Ls "https://raw.githubusercontent.com/sasantech/v2ray-monitoring/main/manager.py" -o manager.py
fi

# Run the python script
python3 manager.py