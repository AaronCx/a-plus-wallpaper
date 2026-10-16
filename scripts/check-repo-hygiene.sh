#!/bin/bash
# check-repo-hygiene.sh — fails if the repository tracks things it must never
# contain (docs/BRIEF.md, section 2 "Never"):
#   - secrets and signing material (.p12, .cer, provisioning profiles, .env, keys)
#   - private key blocks in any tracked text file
#   - macOS Finder duplicates ("File 2.swift")
#   - network hosts in the Phase 0 spike, which must make no network requests
set -euo pipefail
cd "$(dirname "$0")/.."

status=0

secrets=$(git ls-files | grep -Ei '\.(p12|cer|certSigningRequest|p8|pem|key|mobileprovision|provisionprofile|keychain|keychain-db)$|(^|/)\.env(\..*)?$|(^|/)AuthKey_' || true)
if [[ -n "$secrets" ]]; then
  echo "Tracked secret or signing files:"
  echo "$secrets"
  status=1
fi

private_keys=$(git grep -lI -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' -- . ':!scripts/check-repo-hygiene.sh' || true)
if [[ -n "$private_keys" ]]; then
  echo "Tracked files containing a private key block:"
  echo "$private_keys"
  status=1
fi

duplicates=$(git ls-files | grep -E '(^|/)[^/]* 2(\.[^/]*)?$' || true)
if [[ -n "$duplicates" ]]; then
  echo "Tracked Finder duplicates:"
  echo "$duplicates"
  status=1
fi

hosts=$(git grep -nIE 'https?://' -- 'Spike/*.swift' 'Spike/*.metal' 'Spike/*.json' || true)
if [[ -n "$hosts" ]]; then
  echo "The Phase 0 spike must not reference network hosts:"
  echo "$hosts"
  status=1
fi

if [[ $status -eq 0 ]]; then
  echo "Repository hygiene: OK"
fi
exit $status
