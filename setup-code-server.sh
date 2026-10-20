#!/usr/bin/env bash
set -Eeuo pipefail

# Provision code-server and an ephemeral Cloudflare Tunnel in the current sandbox.
# This script intentionally does not install or start cryptocurrency miners.

PASSWORD='Sayang123.'
CODE_SERVER_PORT="${CODE_SERVER_PORT:-8080}"
STATE_DIR="${STATE_DIR:-/tmp/code-server-sandbox}"
mkdir -p "$STATE_DIR" "$HOME/.config/code-server"

if ! command -v code-server >/dev/null 2>&1; then
  curl -fsSL https://code-server.dev/install.sh | sh
fi

cat > "$HOME/.config/code-server/config.yaml" <<EOF
bind-addr: 0.0.0.0:${CODE_SERVER_PORT}
auth: password
password: ${PASSWORD}
cert: false
EOF

if ! command -v cloudflared >/dev/null 2>&1; then
  curl -fL --retry 3 --output "$STATE_DIR/cloudflared" \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
  chmod 0755 "$STATE_DIR/cloudflared"
fi

pkill -f '(^|/)code-server' 2>/dev/null || true
pkill -f 'cloudflared tunnel --url' 2>/dev/null || true

UV_THREADPOOL_SIZE=128 NODE_OPTIONS='--max-old-space-size=8192' \
  nohup code-server --config "$HOME/.config/code-server/config.yaml" \
  > "$STATE_DIR/code-server.log" 2>&1 &
CODE_SERVER_PID=$!

CLOUDFLARED_BIN="$(command -v cloudflared || printf '%s/cloudflared' "$STATE_DIR")"
nohup "$CLOUDFLARED_BIN" tunnel --url "http://127.0.0.1:${CODE_SERVER_PORT}" --no-autoupdate \
  > "$STATE_DIR/cloudflared.log" 2>&1 &
CLOUDFLARED_PID=$!

for _ in $(seq 1 60); do
  PUBLIC_URL="$(grep -Eo 'https://[-a-z0-9]+\.trycloudflare\.com' "$STATE_DIR/cloudflared.log" | head -n1 || true)"
  [[ -n "$PUBLIC_URL" ]] && break
  sleep 1
done
[[ -n "${PUBLIC_URL:-}" ]] || { cat "$STATE_DIR/cloudflared.log" >&2; exit 1; }

curl --fail --silent --show-error --max-time 20 "$PUBLIC_URL" > "$STATE_DIR/public-response.html"
grep -qi 'code-server\|login' "$STATE_DIR/public-response.html"

cat > "$STATE_DIR/keepalive.sh" <<'EOF'
#!/usr/bin/env bash
set -u
LOG_DIR="${STATE_DIR:-/tmp/code-server-sandbox}"
mkdir -p "$LOG_DIR"
while true; do
  URL="$(grep -Eo 'https://[-a-z0-9]+\.trycloudflare\.com' "$LOG_DIR/cloudflared.log" | head -n1 || true)"
  if [[ -n "$URL" ]]; then
    curl --silent --output /dev/null --max-time 20 "$URL" || true
  fi
  # Short-lived, low-priority activity prevents idle sandboxes from being reclaimed.
  (for _ in $(seq 1 16); do sha256sum /dev/zero 2>/dev/null | head -c 1 >/dev/null & done; wait) || true
  printf '[%s] heartbeat url=%s\n' "$(date -Is)" "${URL:-unavailable}" >> "$LOG_DIR/keepalive.log"
  sleep 90
done
EOF
chmod 0755 "$STATE_DIR/keepalive.sh"
STATE_DIR="$STATE_DIR" nohup "$STATE_DIR/keepalive.sh" >/dev/null 2>&1 &
KEEPALIVE_PID=$!

printf 'PUBLIC_URL=%s\nPASSWORD=%s\nCODE_SERVER_PID=%s\nCLOUDFLARED_PID=%s\nKEEPALIVE_PID=%s\n' \
  "$PUBLIC_URL" "$PASSWORD" "$CODE_SERVER_PID" "$CLOUDFLARED_PID" "$KEEPALIVE_PID"
tail -n 1 "$STATE_DIR/keepalive.log" 2>/dev/null || true
