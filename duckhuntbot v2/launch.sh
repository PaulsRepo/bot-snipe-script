#!/bin/bash
# DuckHunt Bot Launcher

echo "============================================"
echo "  DuckHunt IRC Bot Launcher"
echo "============================================"
echo ""

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed!"
    echo "Please install Python 3.6 or higher."
    exit 1
fi

# Check if config file exists
if [ ! -f "bot_config.ini" ]; then
    echo "Warning: bot_config.ini not found!"
    echo "Creating default configuration..."
    python3 duckhunt_bot_v2.py --create-config 2>/dev/null || echo "Please edit bot_config.ini before running."
    exit 1
fi

# Show menu
echo "Select bot version to run:"
echo "1) Full-featured bot (v2) - Recommended"
echo "2) Basic bot (v1) - Simple version"
echo "3) Edit configuration"
echo "4) View logs"
echo "5) Exit"
echo ""
read -p "Enter choice [1-5]: " choice

case $choice in
    1)
        echo ""
        echo "Starting DuckHunt Bot v2..."
        echo "Press Ctrl+C to stop"
        echo ""
        python3 duckhunt_bot_v2.py
        ;;
    2)
        echo ""
        echo "Starting DuckHunt Bot v1..."
        echo "Press Ctrl+C to stop"
        echo ""
        python3 duckhunt_bot.py
        ;;
    3)
        if command -v nano &> /dev/null; then
            nano bot_config.ini
        elif command -v vi &> /dev/null; then
            vi bot_config.ini
        else
            echo "Please edit bot_config.ini with your text editor"
        fi
        ;;
    4)
        if [ -f "duckhunt_bot.log" ]; then
            tail -f duckhunt_bot.log
        else
            echo "No log file found. Run the bot first."
        fi
        ;;
    5)
        echo "Goodbye!"
        exit 0
        ;;
    *)
        echo "Invalid choice!"
        exit 1
        ;;
esac
