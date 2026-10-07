#!/bin/bash
cd /home/drmj/newapp

echo "📦 Building WebSpace..."
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

npm run build

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "🚀 Installing WebSpace system-wide (requires sudo)..."
    sudo apt-get install -y ./dist/webspace_1.0.0_amd64.deb
    echo "🎉 Installation complete!"
else
    echo "❌ Build failed. Please check the errors above."
    exit 1
fi
