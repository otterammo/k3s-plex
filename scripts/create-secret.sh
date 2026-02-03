#!/usr/bin/env bash
set -euo pipefail

# Create Plex claim token secret.
# Usage: PLEX_CLAIM_TOKEN=... ./scripts/create-secret.sh
# Get claim token from: https://www.plex.tv/claim/
# Token is valid for 4 minutes and only needed for initial setup.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

set -a
if [ -f "$ROOT_DIR/.env" ]; then
  # shellcheck disable=SC1090
  source "$ROOT_DIR/.env"
fi
set +a

PLEX_CLAIM_TOKEN="${PLEX_CLAIM_TOKEN:-}"

if [ -z "$PLEX_CLAIM_TOKEN" ]; then
  echo "⚠️  Warning: PLEX_CLAIM_TOKEN not set. Plex will start unclaimed."
  echo "   Visit https://www.plex.tv/claim/ to get a claim token."
  PLEX_CLAIM_TOKEN=""
fi

kubectl create namespace plex --dry-run=client -o yaml | kubectl apply -f -
kubectl -n plex create secret generic plex-claim-token \
  --from-literal=PLEX_CLAIM="$PLEX_CLAIM_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Plex claim token secret applied in namespace plex"
