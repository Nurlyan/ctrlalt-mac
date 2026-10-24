#!/bin/bash
# Создаёт в login keychain самоподписанный сертификат «CtrlAlt Local Signing» для подписи сборок.
# С ним macOS узнаёт CtrlAlt по сертификату, а не по хэшу сборки, и разрешения
# («Управление устройством», «Мониторинг ввода») сохраняются после обновлений.
# Нужен один раз на каждом Mac, где собирается CtrlAlt. Ключ доступен только codesign.
set -euo pipefail

NAME="CtrlAlt Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Сертификат «$NAME» уже есть."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"

cat > "$WORK/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
O = CtrlAlt (local)
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
PASS="$(openssl rand -hex 16)"
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
    -out "$WORK/id.p12" -passout "pass:$PASS"
security import "$WORK/id.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign -f pkcs12

echo "Готово:"
security find-identity -p codesigning "$KEYCHAIN" | grep "$NAME"
