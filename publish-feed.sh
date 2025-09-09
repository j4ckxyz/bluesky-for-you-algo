#!/usr/bin/env bash
set -euo pipefail

echo "== Bluesky For You: Publish feed record =="

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required." >&2
  exit 1
fi

JQ_OK=1
if ! command -v jq >/dev/null 2>&1; then
  JQ_OK=0
fi

read -rp "Feed domain used for did:web (e.g., blue.j4ck.xyz): " FEED_DOMAIN
SERVICE_DID="did:web:${FEED_DOMAIN}"

read -rp "PDS base (default https://bsky.social): " PDS_BASE || true
PDS_BASE=${PDS_BASE:-https://bsky.social}

read -rp "Your handle (e.g., you.bsky.social): " IDENTIFIER
read -srp "App password (hidden): " APP_PASSWORD; echo

read -rp "Feed rkey identifier (default for-you): " RKEY || true
RKEY=${RKEY:-for-you}
read -rp "Display name (default For You): " DISPLAY_NAME || true
DISPLAY_NAME=${DISPLAY_NAME:-For You}
read -rp "Description (default In/out-network with social proof): " DESCRIPTION || true
DESCRIPTION=${DESCRIPTION:-In/out-network with social proof.}

echo "Creating session at ${PDS_BASE}..."
SESSION_JSON=$(curl -fsSL -X POST -H 'Content-Type: application/json' \
  -d "{\"identifier\":\"${IDENTIFIER}\",\"password\":\"${APP_PASSWORD}\"}" \
  "${PDS_BASE}/xrpc/com.atproto.server.createSession")

if [[ ${JQ_OK} -eq 1 ]]; then
  ACCESS_JWT=$(printf '%s' "$SESSION_JSON" | jq -r .accessJwt)
  ACCOUNT_DID=$(printf '%s' "$SESSION_JSON" | jq -r .did)
else
  # Fallback parsing via Python (installed by default on most systems)
  if command -v python3 >/dev/null 2>&1; then
    ACCESS_JWT=$(python3 - <<PY
import sys, json
j=json.load(sys.stdin)
print(j.get('accessJwt',''))
PY
    <<<"$SESSION_JSON")
    ACCOUNT_DID=$(python3 - <<PY
import sys, json
j=json.load(sys.stdin)
print(j.get('did',''))
PY
    <<<"$SESSION_JSON")
  else
    echo "Error: need jq or python3 to parse JSON response." >&2
    exit 1
  fi
fi

if [[ -z "${ACCESS_JWT}" || -z "${ACCOUNT_DID}" || "${ACCESS_JWT}" == "null" || "${ACCOUNT_DID}" == "null" ]]; then
  echo "Login failed. Response was:" >&2
  echo "$SESSION_JSON" >&2
  exit 1
fi

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Publishing app.bsky.feed.generator record..."
PUT_RESP=$(curl -fsS -X POST -H "Authorization: Bearer ${ACCESS_JWT}" -H 'Content-Type: application/json' \
  -d "{\"repo\":\"${ACCOUNT_DID}\",\"collection\":\"app.bsky.feed.generator\",\"rkey\":\"${RKEY}\",\"record\":{\"$type\":\"app.bsky.feed.generator\",\"did\":\"${SERVICE_DID}\",\"displayName\":\"${DISPLAY_NAME}\",\"description\":\"${DESCRIPTION}\",\"createdAt\":\"${NOW}\"}}" \
  "${PDS_BASE}/xrpc/com.atproto.repo.putRecord") || {
    echo "Failed to publish record. Response:" >&2
    echo "$PUT_RESP" >&2
    exit 1
}

FEED_URI="at://${ACCOUNT_DID}/app.bsky.feed.generator/${RKEY}"
FEED_LINK="https://bsky.app/profile/${ACCOUNT_DID}/feed/${RKEY}"

echo
echo "Published!"
echo "- Feed URI:   ${FEED_URI}"
echo "- Open link:  ${FEED_LINK}"
echo "- Service DID: ${SERVICE_DID}"
echo
echo "If it doesn't show up immediately, verify:"
echo "- did:web: curl -s https://${FEED_DOMAIN}/.well-known/did.json"
echo "- describe:  curl -s https://${FEED_DOMAIN}/xrpc/app.bsky.feed.describeFeedGenerator"

