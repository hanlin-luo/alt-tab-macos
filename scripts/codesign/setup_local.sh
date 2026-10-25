#!/usr/bin/env bash

# Sets up the local self-signed code-signing identity used to sign a locally built AltTab.app.
#
# The identity lives in its own keychain (alttab-signing.keychain-db) rather than in the login
# keychain, for two reasons:
#
#   - `security set-key-partition-list` is what lets codesign use a private key without asking the
#     user for permission. Applying it needs the keychain's password, which the owner of the login
#     keychain may not want to hand over to a build script.
#   - Without that partition list, codesign blocks forever on a keychain prompt that a
#     non-interactive shell can never answer (the ACL ends up in the "apple-tool:" partition while
#     codesign is in the "apple:" one, so securityd asks the user to authorize the partition).
#
# The certificate is also added to the trust settings for code signing, so Gatekeeper accepts the
# locally built app.
set -euo pipefail
cd "$(dirname "$0")/../.."

KEYCHAIN_NAME="alttab-signing"
KEYCHAIN="$HOME/Library/Keychains/${KEYCHAIN_NAME}.keychain-db"
PASSWORD_FILE="scripts/codesign/${KEYCHAIN_NAME}.pass"
IDENTITY="Local Self-Signed"
CERTIFICATE_FILE="scripts/codesign/codesign"

# The password is generated once and kept next to the certificate material (both gitignored). It
# protects nothing but this throwaway local signing key.
if [ -f "$PASSWORD_FILE" ]; then
	password=$(cat "$PASSWORD_FILE")
else
	password=$(openssl rand -base64 24 | tr -d '/+=')
	printf '%s' "$password" >"$PASSWORD_FILE"
	chmod 600 "$PASSWORD_FILE"
fi

if [ ! -f "$CERTIFICATE_FILE.key" ] || [ ! -f "$CERTIFICATE_FILE.crt" ]; then
	./scripts/codesign/generate_selfsigned_certificate.sh "$CERTIFICATE_FILE" "$password"
else
	echo "reusing the existing certificate $CERTIFICATE_FILE.crt"
	# Re-wrap it with the current password: the PKCS#12 container password and the keychain
	# password are the same secret, so the container can always be re-imported. The certificate
	# itself is kept, so the TCC grants (Accessibility, Screen Recording) the user already gave to
	# a build signed with it stay valid.
	./scripts/codesign/export_pkcs12.sh "$CERTIFICATE_FILE" "$password"
fi

# (Re)create the signing keychain so its state is known: unlocked, with the partition list applied.
security delete-keychain "$KEYCHAIN" 2>/dev/null || true
security create-keychain -p "$password" "$KEYCHAIN"
security unlock-keychain -p "$password" "$KEYCHAIN"
# No -t and no -l on purpose: "-t" sets an auto-lock timeout and "-l" locks the keychain when the
# system sleeps. Either one makes the next codesign ask the user for the keychain password — a
# prompt a build script must never raise. The keychain holds a throwaway local signing key.
security set-keychain-settings "$KEYCHAIN"
# -A: any application may use the key. The partition list below is what keeps that from turning
# into an interactive prompt.
security import "$CERTIFICATE_FILE.p12" -P "$password" -A -k "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$KEYCHAIN"

# Make the keychain findable by codesign without dropping the user's own keychains.
keychains=$(security list-keychains | tr -d '"' | grep -v "^$KEYCHAIN$")
security list-keychains -s "$KEYCHAIN" $keychains

# Trust the certificate for code signing, so the locally built app passes Gatekeeper. Re-adding a
# certificate that is already trusted asks the user to authorize the change (a prompt a setup script
# must not raise), so check the trust settings first.
if security dump-trust-settings 2>/dev/null | grep -q "Local Self-Signed"; then
	echo "certificate already trusted for code signing"
else
	security add-trusted-cert -r trustRoot -p codeSign "$CERTIFICATE_FILE.crt"
fi

echo "signing identity ready: $IDENTITY (keychain $KEYCHAIN_NAME)"
security find-identity -v -p codesigning | grep "$IDENTITY" | head -1
