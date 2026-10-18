#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# This helper runs only the demo project; it never reads native Firebase config.
if curl --silent --max-time 1 http://127.0.0.1:9030/ >/dev/null; then
  echo 'Port 9030 is occupied; stop the existing test server first.' >&2
  exit 1
fi
node -e "if(require('./tool/rules-tests/node_modules/firebase/package.json').version!=='12.19.0')throw Error('The test SDK must match the pinned FlutterFire browser SDK');"
test_sdk_dir=$(mktemp -d)
sdk_pid=''
cleanup() {
  if [ -n "$sdk_pid" ]; then kill "$sdk_pid" 2>/dev/null || true; wait "$sdk_pid" 2>/dev/null || true; fi
  rm -rf "$test_sdk_dir"
}
trap cleanup EXIT
tool/rules-tests/node_modules/.bin/esbuild tool/rules-tests/browser-sdk.mjs --bundle --format=esm --platform=browser --target=es2022 --outfile="$test_sdk_dir/firebase-sdk.js"
python3 tool/serve_test_sdk.py --directory "$test_sdk_dir" --port 9030 >"$test_sdk_dir/server.log" 2>&1 &
sdk_pid=$!
for attempt in {1..30}; do
  if curl --silent --max-time 1 http://127.0.0.1:9030/firebase-sdk.js >/dev/null; then break; fi
  if ! kill -0 "$sdk_pid" 2>/dev/null; then cat "$test_sdk_dir/server.log"; exit 1; fi
  sleep 1
done
tool/rules-tests/node_modules/.bin/firebase emulators:exec --only auth,firestore --project demo-bashahisab --config firebase.emulator-tests.json 'flutter test test/emulator/repository_emulator_browser_test.dart --platform chrome --dart-define=V3_ENABLED=true --reporter expanded'
