#!/usr/bin/env bash
# Generate a locally-trusted TLS certificate for the ClawServer.
#
# Preferred: mkcert (https://github.com/FiloSottile/mkcert)
#   brew install mkcert
#   mkcert -install      # installs root CA into system trust store
#
# The generated cert is trusted by macOS and Safari/Chrome automatically.
# To trust it on iOS: AirDrop the rootCA.pem to your iPhone, then go to
#   Settings → General → VPN & Device Management → install the profile, then
#   Settings → General → About → Certificate Trust Settings → enable it.
#
# Fallback: openssl self-signed (works but browsers/iOS will warn)
set -euo pipefail

CERT_DIR="$(cd "$(dirname "$0")/.." && pwd)/certs"
mkdir -p "$CERT_DIR"

# Collect the Mac's LAN IP (first non-loopback IPv4)
LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "")

if command -v mkcert &>/dev/null; then
  echo "▶ Using mkcert…"
  mkcert -install 2>/dev/null || true

  DOMAINS="localhost 127.0.0.1 ::1"
  if [[ -n "$LAN_IP" ]]; then
    DOMAINS="$DOMAINS $LAN_IP"
    echo "  Including LAN IP: $LAN_IP"
  fi

  cd "$CERT_DIR"
  # shellcheck disable=SC2086
  mkcert -cert-file server.crt -key-file server.key $DOMAINS

  echo ""
  echo "✓ Certificate written to certs/server.crt and certs/server.key"
  echo ""
  echo "Add these lines to .env:"
  echo "  TLS_CERT=certs/server.crt"
  echo "  TLS_KEY=certs/server.key"
  if [[ -n "$LAN_IP" ]]; then
    echo ""
    echo "  SERVER_HOST=0.0.0.0   # to accept LAN connections"
    echo "  # Then connect from iPhone at: https://$LAN_IP:4242"
  fi

  # Print root CA path for iOS installation
  ROOT_CA=$(mkcert -CAROOT)/rootCA.pem
  if [[ -f "$ROOT_CA" ]]; then
    echo ""
    echo "iOS trust: AirDrop $ROOT_CA to your iPhone, install the profile,"
    echo "then enable it in Settings → General → About → Certificate Trust Settings."
  fi
else
  echo "▶ mkcert not found — falling back to openssl self-signed cert"
  echo "  (install mkcert for a properly trusted cert: brew install mkcert)"
  echo ""

  SUBJ="/CN=ClawServer/O=DiscoClaw"
  SAN="subjectAltName=DNS:localhost,IP:127.0.0.1"
  if [[ -n "$LAN_IP" ]]; then
    SAN="$SAN,IP:$LAN_IP"
  fi

  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$CERT_DIR/server.key" \
    -out "$CERT_DIR/server.crt" \
    -days 825 \
    -subj "$SUBJ" \
    -addext "$SAN" 2>/dev/null

  echo "✓ Self-signed certificate written to certs/server.crt and certs/server.key"
  echo ""
  echo "Add these lines to .env:"
  echo "  TLS_CERT=certs/server.crt"
  echo "  TLS_KEY=certs/server.key"
  echo ""
  echo "WARNING: Self-signed certs will show a security warning in browsers."
  echo "On iOS you must manually trust the cert in Settings → General → About"
  echo "→ Certificate Trust Settings after installing it."
fi
