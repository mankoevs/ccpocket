#!/bin/zsh

set -u

export HOME=/Users/evgenymanko
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

readonly GIST_ID=d8154455bb0fa966be69102c571532c6
readonly GIST_FILE=ccpocket-bridge.json
readonly PRIMARY_URL=wss://macbook-air-5.tail9af04f.ts.net
readonly RUNTIME_DIR="$HOME/.ccpocket/remote-discovery"
readonly TUNNEL_LOG="$RUNTIME_DIR/cloudflared.log"
readonly DISCOVERY_FILE="$RUNTIME_DIR/$GIST_FILE"
readonly LAST_URL_FILE="$RUNTIME_DIR/last-cloudflare-url"

mkdir -p "$RUNTIME_DIR"

tunnel_pid=''
cleanup() {
  if [[ -n "$tunnel_pid" ]]; then
    /bin/kill "$tunnel_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

publish_url() {
  local fallback_url="$1"
  local fallback_ws_url="${fallback_url/https:/wss:}"
  /usr/bin/jq -n \
    --arg primary "$PRIMARY_URL" \
    --arg fallback "$fallback_ws_url" \
    '{version: 1, endpoints: [$primary, $fallback]}' > "$DISCOVERY_FILE"
  gh gist edit "$GIST_ID" -f "$GIST_FILE" "$DISCOVERY_FILE"
  print -r -- "$fallback_url" > "$LAST_URL_FILE"
}

while true; do
  : > "$TUNNEL_LOG"
  cloudflared tunnel \
    --url http://127.0.0.1:8765 \
    --no-autoupdate \
    --logfile "$TUNNEL_LOG" &
  tunnel_pid=$!

  fallback_url=''
  for _ in {1..90}; do
    fallback_url="$(/usr/bin/grep -Eo 'https://[-a-z0-9]+\.trycloudflare\.com' "$TUNNEL_LOG" | /usr/bin/tail -1)"
    if [[ -n "$fallback_url" ]]; then
      fallback_host="${fallback_url#https://}"
      fallback_ip="$(/usr/bin/curl -fsS --max-time 5 \
        --resolve cloudflare-dns.com:443:104.16.248.249 \
        -H 'accept: application/dns-json' \
        "https://cloudflare-dns.com/dns-query?name=$fallback_host&type=A" | \
        /usr/bin/jq -r '.Answer[]? | select(.type == 1) | .data' | \
        /usr/bin/head -1)"
      if [[ -n "$fallback_ip" ]] && \
        /usr/bin/curl -fsS --max-time 5 \
          --resolve "$fallback_host:443:$fallback_ip" \
          "$fallback_url/health" >/dev/null; then
        break
      fi
    fi
    fallback_url=''
    /bin/sleep 1
  done

  if [[ -n "$fallback_url" ]]; then
    previous_url="$(/bin/cat "$LAST_URL_FILE" 2>/dev/null || true)"
    if [[ "$fallback_url" != "$previous_url" ]]; then
      publish_url "$fallback_url"
    fi
  else
    /bin/kill "$tunnel_pid" 2>/dev/null || true
  fi

  wait "$tunnel_pid"
  /bin/sleep 3
done
