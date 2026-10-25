#!/usr/bin/env bash
#
# export_pkcs12.sh — wrap a key + certificate into a PKCS#12 container.
#
# Usage: export_pkcs12.sh <certificateFileBase> <password>
# Writes <certificateFileBase>.p12 next to <certificateFileBase>.key / .crt.
set -euo pipefail

certificateFile="$1"
certificatePassword="$2"

openssl_version=$(openssl version)
# openssl v3.x and v4.x require to pass -legacy
# see https://www.misterpki.com/openssl-pkcs12-legacy/
# Without it the PKCS#12 uses PBES2/AES-256-CBC, which macOS's `security import` rejects with
# "MAC verification failed during PKCS12 import" — the legacy RC2/3DES encoding is the one it
# understands.
if [[ $openssl_version == OpenSSL\ 3* || $openssl_version == OpenSSL\ 4* ]]; then
	flag="-legacy"
else
	flag=""
fi

openssl pkcs12 $flag -export -inkey "$certificateFile.key" -in "$certificateFile.crt" \
	-out "$certificateFile.p12" -passout "pass:$certificatePassword"
