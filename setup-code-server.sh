#!/usr/bin/env bash
set -Eeuo pipefail

# Provision code-server and an ephemeral Cloudflare Tunnel in the current sandbox.
# Runtime state is intentionally kept outside the repository.

PASSWORD='Sayang123.'
CODE_SERVER_PORT="${CODE_SERVER_PORT:-8080}"
STATE_DIR="${STATE_DIR:-/tmp/code-server-sandbox}"
CONFIG_FILE="$HOME/.config/code-server/config.yaml"
mkdir -p "$STATE_DIR" "$(dirname "$CONFIG_FILE")"

if ! command -v code-server >/dev/null 2>&1; then
  curl -fsSL https://code-server.dev/install.sh | sh
fi

cat > "$CONFIG_FILE" <<EOF
bind-addr: 0.0.0.0:${CODE_SERVER_PORT}
auth: password
password: ${PASSWORD}
cert: false
EOF

CLOUDFLARED_BIN="$STATE_DIR/cloudflared"
if ! command -v cloudflared >/dev/null 2>&1; then
  curl -fL --retry 3 --output "$CLOUDFLARED_BIN" \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
  chmod 0755 "$CLOUDFLARED_BIN"
else
  CLOUDFLARED_BIN="$(command -v cloudflared)"
fi

# Stop only processes owned by this setup, without pattern-based pkill collateral.
if [[ -f "$STATE_DIR/pids" ]]; then
  while read -r pid; do
    [[ "$pid" =~ ^[0-9]+$ ]] && kill "$pid" 2>/dev/null || true
  done < "$STATE_DIR/pids"
fi
: > "$STATE_DIR/pids"

UV_THREADPOOL_SIZE=128 NODE_OPTIONS='--max-old-space-size=8192' \
  nohup code-server --config "$CONFIG_FILE" \
  > "$STATE_DIR/code-server.log" 2>&1 &
CODE_SERVER_PID=$!
printf '%s\n' "$CODE_SERVER_PID" >> "$STATE_DIR/pids"

nohup "$CLOUDFLARED_BIN" tunnel --url "http://localhost:${CODE_SERVER_PORT}" --no-autoupdate \
  > "$STATE_DIR/cloudflared.log" 2>&1 &
CLOUDFLARED_PID=$!
printf '%s\n' "$CLOUDFLARED_PID" >> "$STATE_DIR/pids"

PUBLIC_URL=''
for _ in $(seq 1 60); do
  PUBLIC_URL="$(grep -Eo 'https://[-a-z0-9]+\.trycloudflare\.com' "$STATE_DIR/cloudflared.log" | head -n1 || true)"
  [[ -n "$PUBLIC_URL" ]] && break
  sleep 1
done
if [[ -z "$PUBLIC_URL" ]]; then
  cat "$STATE_DIR/cloudflared.log" >&2
  exit 1
fi

RESPONSE_FILE="$STATE_DIR/public-response.html"
HTTP_STATUS="$(curl --silent --show-error --location --max-time 20 \
  --output "$RESPONSE_FILE" --write-out '%{http_code}' "$PUBLIC_URL")"
[[ "$HTTP_STATUS" == 200 ]]
grep -Eiq '<title>[^<]*code-server|code-server.*login|login.*code-server' "$RESPONSE_FILE"

cat > "$STATE_DIR/keepalive.sh" <<'EOF'
#!/usr/bin/env bash
set -u
STATE_DIR="${STATE_DIR:-/tmp/code-server-sandbox}"
PORT="${CODE_SERVER_PORT:-8080}"
mkdir -p "$STATE_DIR"
while true; do
  URL="$(grep -Eo 'https://[-a-z0-9]+\.trycloudflare\.com' "$STATE_DIR/cloudflared.log" | head -n1 || true)"
  [[ -n "$URL" ]] && curl --silent --output /dev/null --max-time 20 "$URL" || true
  # Bounded CPU burst: 16 short-lived workers, then wait before the next cycle.
  for _ in $(seq 1 16); do
    (openssl speed -seconds 1 sha256 >/dev/null 2>&1 || sha256sum /dev/zero | head -c 1 >/dev/null) &
  done
  wait || true
  printf '[%s] heartbeat url=%s\n' "$(date -Is)" "${URL:-unavailable}" >> "$STATE_DIR/keepalive.log"
  sleep 90
done
EOF
chmod 0755 "$STATE_DIR/keepalive.sh"
STATE_DIR="$STATE_DIR" CODE_SERVER_PORT="$CODE_SERVER_PORT" \
  nohup "$STATE_DIR/keepalive.sh" >/dev/null 2>&1 &
KEEPALIVE_PID=$!
printf '%s\n' "$KEEPALIVE_PID" >> "$STATE_DIR/pids"

printf 'PUBLIC_URL=%s\nPASSWORD=%s\nCODE_SERVER_PID=%s\nCLOUDFLARED_PID=%s\nKEEPALIVE_PID=%s\n' \
  "$PUBLIC_URL" "$PASSWORD" "$CODE_SERVER_PID" "$CLOUDFLARED_PID" "$KEEPALIVE_PID"
tail -n 1 "$STATE_DIR/keepalive.log" 2>/dev/null || true
