#!/bin/zsh
# 在登录钥匙串里生成一个自签名代码签名证书「QuickTrans Dev」，只需执行一次。
# 用固定证书签名后，重新编译不会让「辅助功能」授权和钥匙串访问失效（临时签名每次编译都会变）。
set -euo pipefail
NAME="QuickTrans Dev"
if security find-certificate -c "$NAME" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1; then
  echo "证书「$NAME」已存在"; exit 0
fi
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.conf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$TMP/cert.p12" -passout pass:quicktrans -legacy 2>/dev/null \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" -out "$TMP/cert.p12" -passout pass:quicktrans
security import "$TMP/cert.p12" -k ~/Library/Keychains/login.keychain-db -P quicktrans -T /usr/bin/codesign
echo "已生成证书「$NAME」"
