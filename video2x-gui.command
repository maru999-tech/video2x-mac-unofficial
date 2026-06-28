#!/bin/bash
# Finder でダブルクリックすると GUI が起動します
# Double-click in Finder to launch the GUI / 在访达中双击启动 GUI
cd "$(dirname "$0")"
exec python3 gui.py
