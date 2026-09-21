#!/bin/sh
#
# Fetches a user's code and runs it.
#
# This is the whole trick behind functions: the platform doesn't build an image
# per deploy, it runs *this* image and tells it where the code is. One image on
# disk however many people deploy, and a deploy is an upload rather than a
# build.
#
# Everything it needs arrives as environment variables:
#
#   DEPLEAZY_CODE_URL      where to fetch the zip
#   DEPLEAZY_CODE_SHA256   what it should hash to
#   PORT                   what the app should listen on (8080)
#
set -eu

log() { echo "[depleazy] $*"; }
die() { echo "[depleazy] $*" >&2; exit 1; }

# Refuse to unpack anything bigger than this. A zip of a few hundred kilobytes
# can expand to gigabytes and fill the node's disk — for everyone on it, not
# just the account that uploaded it.
MAX_UNPACKED_BYTES=${DEPLEAZY_MAX_UNPACKED_BYTES:-536870912} # 512 MiB

[ -n "${DEPLEAZY_CODE_URL:-}" ] || die "DEPLEAZY_CODE_URL is not set"
[ -n "${DEPLEAZY_CODE_SHA256:-}" ] || die "DEPLEAZY_CODE_SHA256 is not set"

# No .zip suffix: busybox's mktemp wants the X's at the end of the template,
# and unzip is given the path directly so the extension buys nothing.
archive=$(mktemp /tmp/code.XXXXXX)
trap 'rm -f "$archive"' EXIT

log "fetching code"
curl --fail --silent --show-error --location \
  --max-time "${DEPLEAZY_FETCH_TIMEOUT:-120}" \
  --output "$archive" "$DEPLEAZY_CODE_URL" ||
  die "could not download the code"

# Checked before anything is unpacked, not after. An archive that isn't what
# core meant to send is not something to start unwrapping and looking at.
actual=$(sha256sum "$archive" | cut -d' ' -f1)
[ "$actual" = "$DEPLEAZY_CODE_SHA256" ] ||
  die "the code doesn't match its checksum (wanted $DEPLEAZY_CODE_SHA256, got $actual)"

# A zip can name a file "../../etc/passwd" or an absolute path, and some
# extractors will happily write there. Read the listing first and refuse the
# whole thing rather than trusting unzip to be careful.
listing=$(unzip -Z1 "$archive") || die "the code isn't a readable zip"

# Collected rather than checked in a loop: `while` after a pipe runs in a
# subshell, so exiting from inside one only ends the subshell. That would leave
# a refusal looking like it worked while the script carried on unpacking.
unsafe=$(printf '%s\n' "$listing" | grep -E '^/|(^|/)\.\./' | head -1 || true)
[ -z "$unsafe" ] || die "the zip contains an unsafe path: $unsafe"

unpacked=$(unzip -Zt "$archive" | awk '{print $3}')
case "$unpacked" in
*[!0-9]* | "") log "couldn't read the unpacked size; continuing" ;;
*)
  [ "$unpacked" -le "$MAX_UNPACKED_BYTES" ] ||
    die "the code unpacks to ${unpacked} bytes, over the ${MAX_UNPACKED_BYTES} limit"
  ;;
esac

log "unpacking"
unzip -q -o "$archive" -d /app || die "could not unpack the code"
cd /app

# A zip made by right-clicking a folder has everything one level down. Step
# into it rather than making people rezip their work the way we happen to want.
if [ ! -e package.json ] && [ ! -e index.js ]; then
  only=$(find /app -mindepth 1 -maxdepth 1 -type d | head -2)
  if [ "$(printf '%s\n' "$only" | wc -l)" -eq 1 ] && [ -n "$only" ]; then
    log "using $only as the project root"
    cd "$only"
  fi
fi

# What to run, in the order that keeps signals working. `node <file>` makes the
# app PID 1, so a stop actually reaches it; going through npm puts a process in
# between that forwards signals unreliably, which turns every stop into a
# ten-second wait for the kill.
start_file=""
if [ -f package.json ]; then
  main=$(node -p "try{require('./package.json').main||''}catch(e){''}" 2>/dev/null || echo "")
  [ -n "$main" ] && [ -f "$main" ] && start_file="$main"
fi
[ -z "$start_file" ] && [ -f index.js ] && start_file="index.js"
[ -z "$start_file" ] && [ -f server.js ] && start_file="server.js"

if [ -n "$start_file" ]; then
  log "starting $start_file on port ${PORT:-8080}"
  exec node "$start_file"
fi

if [ -f package.json ] &&
  node -e "process.exit(require('./package.json').scripts?.start?0:1)" 2>/dev/null; then
  log "starting via npm start on port ${PORT:-8080}"
  exec npm start
fi

die "nothing to run: expected index.js, server.js, a \"main\" in package.json, or a start script"
