#!/bin/bash
cd /home/drmj/newapp
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
npm install electron --save-dev && npm start
