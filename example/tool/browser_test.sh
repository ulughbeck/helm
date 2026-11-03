#!/usr/bin/env bash
# Runs the browser integration test once per launch URL in headless Chrome.
#
# Needs a chromedriver with the same major version as Chrome:
#   CHROMEDRIVER=/path/to/chromedriver tool/browser_test.sh
# Set CHROME_EXECUTABLE if Flutter does not find Chrome.
set -euo pipefail
cd "$(dirname "$0")/.."

driver="${CHROMEDRIVER:-chromedriver}"
port=8123
"$driver" --port=4444 >/dev/null 2>&1 &
driver_pid=$!
trap 'kill "$driver_pid" 2>/dev/null || true' EXIT
sleep 1

run() {
  echo "== $1 ${2:-}"
  flutter drive --driver=test_driver/integration_test.dart --target=integration_test/browser_test.dart \
    -d web-server --browser-name=chrome --headless --web-port=$port \
    --web-launch-url="http://localhost:$port$1" ${2:-}
}

run /
run /shop
run /does-not-exist
run '/!home/products/123'
run /sub/shop --base-href=/sub/
