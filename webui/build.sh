#!/system/bin/sh
# Build the WebUI. Uses Termux Node.js (android platform).
# Run from the webui/ directory or from the repo root.
set -e
cd "$(dirname "$0")"
NODE=/data/data/com.termux/files/usr/bin/node
if ! [ -x "$NODE" ]; then
  NODE=$(command -v node)
fi
"$NODE" node_modules/.bin/tsc -b
"$NODE" node_modules/.bin/vite build
echo "Build complete → ../webroot/"
