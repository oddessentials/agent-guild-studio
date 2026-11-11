#!/bin/bash
# Signs a packaged Studio app with the Developer ID Application certificate and the hardened runtime,
# notarizes and staples it, and zips it again, as agent-guild's installers/macos/build.sh does for its
# installers. The kits are already inside the app, so the signature covers the app as it ships.
#   tools/macos/sign.sh <unsigned zip> <signed zip>
# Takes APPLE_DEVELOPER_ID_APPLICATION_P12, APPLE_P12_PASSWORD, APPLE_NOTARY_KEY_P8, ASC_KEY_ID and
# ASC_ISSUER_ID from the environment. Sourced, it only defines check_app.
set -euo pipefail
TEAM=H3FY62W58W
fail() { echo "$*" >&2; exit 1; }

# The app as a person gets it: every Mach-O file hardened, asking for no entitlements and signed with
# the Developer ID, and Gatekeeper accepting the stapled ticket.
check_app() {
  local app=$1 file info entitlements out
  [ -d "$app" ] || fail "There is no app at $app."
  codesign --verify --deep --strict "$app" || fail "$app is not validly signed."
  while IFS= read -r -d '' file; do
    case "$(file -b "$file")" in Mach-O*) ;; *) continue ;; esac
    info=$(codesign -dvv "$file" 2>&1)
    grep -q '^CodeDirectory .*flags=.*runtime' <<< "$info" || fail "$file does not use the hardened runtime."
    # Godot's export writes an empty dictionary; Studio runs without any entitlement.
    entitlements=$(codesign -d --entitlements - --xml "$file" 2> /dev/null)
    if [ -n "$entitlements" ] && [ "$(plutil -convert json -o - - <<< "$entitlements")" != '{}' ]; then
      fail "$file has entitlements: $entitlements"
    fi
    grep -q "^Authority=Developer ID Application: .* ($TEAM)\$" <<< "$info" || fail "$file is not signed with the Developer ID Application certificate."
  done < <(find "$app" -type f -print0)
  out=$(spctl --assess --type execute -vv "$app" 2>&1) || fail "Gatekeeper does not accept $app: $out"
  grep -q 'source=Notarized Developer ID' <<< "$out" || fail "Gatekeeper does not accept $app as notarized: $out"
}

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

[ $# -eq 2 ] || fail 'Usage: tools/macos/sign.sh <unsigned zip> <signed zip>'
in=$1 out=$2
missing=''
for var in APPLE_DEVELOPER_ID_APPLICATION_P12 APPLE_P12_PASSWORD APPLE_NOTARY_KEY_P8 ASC_KEY_ID ASC_ISSUER_ID; do
  [ -n "${!var:-}" ] || missing="$missing $var"
done
[ -z "$missing" ] || fail "These signing credentials are missing:$missing"
work=$(mktemp -d)
kc="$work/signing.keychain-db"
trap 'security delete-keychain "$kc" 2>/dev/null || true; rm -rf "$work"' EXIT

kcpw=$(openssl rand -hex 24)
security create-keychain -p "$kcpw" "$kc"
security set-keychain-settings -lut 21600 "$kc"
security unlock-keychain -p "$kcpw" "$kc"
(umask 077 && printf '%s' "$APPLE_DEVELOPER_ID_APPLICATION_P12" | base64 --decode > "$work/application.p12")
security import "$work/application.p12" -k "$kc" -f pkcs12 -P "$APPLE_P12_PASSWORD" -T /usr/bin/codesign > /dev/null
rm -f "$work/application.p12"
security set-key-partition-list -S apple-tool:,apple: -s -k "$kcpw" "$kc" > /dev/null
# shellcheck disable=SC2046
security list-keychains -d user -s "$kc" $(security list-keychains -d user | tr -d '"')
identity=$(security find-identity -v -p codesigning "$kc" | sed -n "s/.*\"\(Developer ID Application: .* ($TEAM)\)\"\$/\1/p" | head -n 1)
[ -n "$identity" ] || fail "The Developer ID Application identity for team $TEAM did not import."

key="$work/AuthKey_$ASC_KEY_ID.p8"
(umask 077 && printf '%s\n' "$APPLE_NOTARY_KEY_P8" > "$key")
notary=(--key "$key" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")

ditto -x -k "$in" "$work/stage"
app="$work/stage/AgentGuildStudio.app"
[ -d "$app" ] || fail "$in holds no AgentGuildStudio.app."
# The executable is the app's only Mach-O file, so signing the bundle signs it; check_app refuses any other.
codesign --force --timestamp --options runtime --keychain "$kc" -s "$identity" "$app"
codesign --verify --deep --strict "$app"

ditto -c -k --keepParent "$app" "$work/notarize.zip"
result=$(xcrun notarytool submit "$work/notarize.zip" "${notary[@]}" --wait --timeout 3h --output-format json)
status=$(plutil -extract status raw -o - - <<< "$result")
if [ "$status" != Accepted ]; then
  xcrun notarytool log "$(plutil -extract id raw -o - - <<< "$result")" "${notary[@]}" >&2 || true
  fail "Apple's notary service answered $status for $app."
fi
for attempt in 1 2 3 4 5; do
  xcrun stapler staple "$app" && xcrun stapler validate "$app" && break
  [ "$attempt" -lt 5 ] || fail "Apple's ticket service did not staple $app after 5 tries."
  sleep 60
done

mkdir -p "$(dirname "$out")"
ditto -c -k --keepParent "$app" "$out"
