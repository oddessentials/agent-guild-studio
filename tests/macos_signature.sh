#!/bin/bash
# Checks tools/macos/sign.sh without Apple's credentials or network: it refuses to start without its
# credentials, and check_app refuses an app that isn't hardened, asks for entitlements or isn't signed
# with the Developer ID. Given the packaged app, it also checks that the app is hardened and asks for
# no entitlements, so only the Developer ID signature stands between it and a release.
#   tests/macos_signature.sh [AgentGuildStudio.app]
set -euo pipefail
sign="$(cd "$(dirname "$0")/.." && pwd)/tools/macos/sign.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

# expect <name> <message> <command...>: the command fails, saying the message.
expect() {
  local name=$1 want=$2 out
  shift 2
  if out=$("$@" 2>&1); then
    echo "FAIL $name: it passed"
    failures=$((failures + 1))
  elif ! grep -qF -- "$want" <<< "$out"; then
    echo "FAIL $name: $out"
    failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}
check() { bash -c 'source "$1" && check_app "$2"' _ "$sign" "$1"; }

expect 'signing refuses to start without its credentials' \
  'These signing credentials are missing: APPLE_DEVELOPER_ID_APPLICATION_P12 APPLE_P12_PASSWORD APPLE_NOTARY_KEY_P8 ASC_KEY_ID ASC_ISSUER_ID' \
  env -i PATH="$PATH" HOME="$HOME" bash "$sign" "$work/in.zip" "$work/out/signed.zip"
[ ! -e "$work/out" ] || { echo "FAIL signing made $work/out without its credentials"; failures=$((failures + 1)); }

app="$work/Tiny.app"
mkdir -p "$app/Contents/MacOS"
cp /usr/bin/true "$app/Contents/MacOS/Tiny"
cat > "$app/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Tiny</string>
  <key>CFBundleIdentifier</key><string>com.oddessentials.agentguildstudio.test</string>
  <key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
EOF
cat > "$work/jit.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.cs.allow-jit</key><true/></dict></plist>
EOF

codesign --force -s - "$app" 2> /dev/null
expect 'an app without the hardened runtime is refused' 'does not use the hardened runtime' check "$app"
codesign --force -s - --options runtime --entitlements "$work/jit.plist" "$app" 2> /dev/null
expect 'an app that asks for entitlements is refused' 'has entitlements' check "$app"
codesign --force -s - --options runtime "$app" 2> /dev/null
expect 'an ad-hoc signed app is refused' 'is not signed with the Developer ID Application certificate' check "$app"
if [ $# -gt 0 ]; then
  expect 'the packaged app is hardened, asks for no entitlements, and is refused only for its ad-hoc signature' \
    'is not signed with the Developer ID Application certificate' check "$1"
fi

[ "$failures" -eq 0 ] || { echo "$failures check(s) failed"; exit 1; }
