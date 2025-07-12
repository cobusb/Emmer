#!/bin/bash

# Emmer VS Code Extension Installation Script

echo "🚀 Setting up Emmer VS Code Extension..."

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is required but not installed."
    echo "Please install Node.js from https://nodejs.org/"
    exit 1
fi

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo "❌ npm is required but not installed."
    echo "Please install npm or use a Node.js installer that includes npm."
    exit 1
fi

# Check if VS Code is installed
if ! command -v code &> /dev/null; then
    echo "⚠️  VS Code CLI not found. You may need to install the 'code' command."
    echo "In VS Code, go to Command Palette (Ctrl+Shift+P) and run 'Shell Command: Install code command in PATH'"
fi

echo "📦 Installing dependencies..."
npm install

echo "🔨 Compiling TypeScript..."
npm run compile

echo "✅ Extension setup complete!"
echo ""
echo "To develop the extension:"
echo "1. Open this folder in VS Code"
echo "2. Press F5 to launch the extension in debug mode"
echo "3. Open an Emmer project in the new VS Code window"
echo ""
echo "To package the extension:"
echo "1. Install vsce: npm install -g vsce"
echo "2. Package: vsce package"
echo "3. Install the .vsix file in VS Code"
echo ""
echo "Happy coding! 🎉"
