#!/bin/zsh
# One-time setup: create a self-signed code-signing certificate so the
# app's signing identity stays stable across rebuilds. macOS ties TCC
# (Login Items, accessibility, etc.) to the signature's cdhash chain;
# ad-hoc signing produces a fresh cdhash on every build, which causes
# permissions to silently reset. A stable cert solves this.
#
# Idempotent. Safe to re-run. Stores the cert in the user's login
# keychain — no admin password required.
set -euo pipefail

CERT_NAME="Claude Counter Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning "$KEYCHAIN" \
    | grep -q "$CERT_NAME"; then
    echo "Already installed: $CERT_NAME"
    security find-identity -v -p codesigning "$KEYCHAIN" \
        | grep "$CERT_NAME"
    exit 0
fi

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT

cat > "$WORK/cert.cnf" <<'CNF'
[ req ]
default_bits        = 2048
prompt              = no
distinguished_name  = dn
x509_extensions     = v3_req

[ dn ]
CN = Claude Counter Local Signing

[ v3_req ]
basicConstraints       = critical, CA:false
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
CNF

echo "Generating self-signed code-signing cert (10-year validity)..."
openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout "$WORK/key.pem" \
    -out "$WORK/cert.pem" \
    -days 3650 \
    -config "$WORK/cert.cnf" 2>/dev/null

PASS="local"
# `-legacy` forces RC2/SHA1 PKCS12 which `security import` understands.
# Modern OpenSSL defaults to AES/SHA256 which macOS rejects.
openssl pkcs12 -export -legacy \
    -inkey "$WORK/key.pem" \
    -in "$WORK/cert.pem" \
    -out "$WORK/cert.p12" \
    -name "$CERT_NAME" \
    -passout "pass:$PASS" 2>/dev/null

echo "Importing into login keychain..."
security import "$WORK/cert.p12" \
    -k "$KEYCHAIN" \
    -P "$PASS" \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null

# Allow codesign to use the private key without a GUI prompt every time.
# Will trigger a one-time keychain password prompt the first time codesign
# is run; after that it's silent.
security set-key-partition-list \
    -S "apple-tool:,apple:,codesign:" \
    -s \
    -k "" \
    "$KEYCHAIN" >/dev/null 2>&1 || true

echo ""
echo "Done. The app will now sign with: $CERT_NAME"
echo "TCC permissions and SMAppService Login Item registration will"
echo "persist across rebuilds as long as this cert exists."
