#!/usr/bin/env bash
set -euo pipefail

echo "== Bluesky For You: Publish feed record =="

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required." >&2
  exit 1
fi

have_jq=1; command -v jq >/dev/null 2>&1 || have_jq=0

req() { # METHOD URL BODY OUTFILE HTTP_CODE_VAR [AUTH]
  local METHOD="$1" URL="$2" BODY="${3:-}" OUT="$4" VAR="$5" AUTH="${6:-}"
  local CODE
  if [[ -n "$BODY" ]]; then
    if [[ -n "$AUTH" ]]; then
      CODE=$(curl -sS -o "$OUT" -w "%{http_code}" -X "$METHOD" \
        -H 'Content-Type: application/json' -H 'Accept: application/json' \
        -H "Authorization: Bearer $AUTH" --data "$BODY" "$URL")
    else
      CODE=$(curl -sS -o "$OUT" -w "%{http_code}" -X "$METHOD" \
        -H 'Content-Type: application/json' -H 'Accept: application/json' \
        --data "$BODY" "$URL")
    fi
  else
    if [[ -n "$AUTH" ]]; then
      CODE=$(curl -sS -o "$OUT" -w "%{http_code}" -H 'Accept: application/json' \
        -H "Authorization: Bearer $AUTH" "$URL")
    else
      CODE=$(curl -sS -o "$OUT" -w "%{http_code}" -H 'Accept: application/json' "$URL")
    fi
  fi
  printf -v "$VAR" "%s" "$CODE"
}

parse_json() { # FILE KEY VAR [fallback]
  local FILE="$1" KEY="$2" VAR="$3" FALL="${4:-}"
  if [[ $have_jq -eq 1 ]]; then
    local VAL; VAL=$(jq -r ".$KEY // empty" "$FILE" 2>/dev/null || true)
    printf -v "$VAR" "%s" "${VAL:-$FALL}"
  elif command -v python3 >/dev/null 2>&1; then
    local VAL
    VAL=$(python3 - "$FILE" "$KEY" <<'PY' || true
import sys,json
f=sys.argv[1]; k=sys.argv[2]
try:
  with open(f,'r') as fh:
    j=json.load(fh)
  v=j
  for part in k.split('.'):
    v=v.get(part,{}) if isinstance(v,dict) else {}
  if isinstance(v,dict): print("")
  else: print(v)
except: print("")
PY
    )
    printf -v "$VAR" "%s" "${VAL:-$FALL}"
  else
    printf -v "$VAR" "%s" "$FALL"
  fi
}

read -rp "Feed domain (did:web:<domain>) [blue.j4ck.xyz]: " FEED_DOMAIN || true
FEED_DOMAIN=${FEED_DOMAIN:-blue.j4ck.xyz}
SERVICE_DID="did:web:${FEED_DOMAIN}"

read -rp "Your PDS base (e.g., https://bsky.social or https://pds.example): " PDS_BASE
read -rp "Your handle (e.g., you.bsky.social): " IDENTIFIER
read -srp "App password (hidden): " APP_PASSWORD; echo

read -rp "Feed rkey [for-you]: " RKEY || true; RKEY=${RKEY:-for-you}
read -rp "Display name [For You]: " DISPLAY_NAME || true; DISPLAY_NAME=${DISPLAY_NAME:-For You}
read -rp "Description [In/out-network with social proof.]: " DESCRIPTION || true; DESCRIPTION=${DESCRIPTION:-In/out-network with social proof.}

echo "Checking PDS: $PDS_BASE"
CODE=0; req GET "${PDS_BASE%/}/xrpc/com.atproto.server.describeServer" "" /tmp/pds.json CODE
if [[ "$CODE" != "200" ]]; then
  echo "PDS check failed (HTTP $CODE). Body:" >&2
  sed -n '1,160p' /tmp/pds.json >&2
  exit 1
fi

# Optional: check did:web presence and warn if mismatch
if CODE2=$(curl -sS -o /tmp/did.json -w "%{http_code}" "https://${FEED_DOMAIN}/.well-known/did.json"); then
  if [[ "$CODE2" == "200" ]]; then
    IDVAL=""; parse_json /tmp/did.json id IDVAL
    if [[ "$IDVAL" != "$SERVICE_DID" ]]; then
      echo "Warning: did.json id ('$IDVAL') != $SERVICE_DID" >&2
    fi
  else
    echo "Note: did.json at https://${FEED_DOMAIN}/.well-known/did.json returned HTTP $CODE2" >&2
  fi
fi

echo "Logging in as $IDENTIFIER ..."
CODE=0; req POST "${PDS_BASE%/}/xrpc/com.atproto.server.createSession" \
  "{\"identifier\":\"$IDENTIFIER\",\"password\":\"$APP_PASSWORD\"}" \
  /tmp/session.json CODE
if [[ "$CODE" != "200" ]]; then
  echo "Login failed (HTTP $CODE). Body:" >&2
  sed -n '1,160p' /tmp/session.json | sed 's/\("accessJwt"\s*:\s*"\)[^"]*/\1(redacted)/' >&2
  exit 1
fi

ACCESS_JWT=""; ACCOUNT_DID=""
parse_json /tmp/session.json accessJwt ACCESS_JWT
parse_json /tmp/session.json did ACCOUNT_DID
if [[ -z "$ACCESS_JWT" || -z "$ACCOUNT_DID" || "$ACCESS_JWT" == "null" || "$ACCOUNT_DID" == "null" ]]; then
  echo "Login response incomplete. Body (redacted):" >&2
  sed -n '1,120p' /tmp/session.json | sed 's/\("accessJwt"\s*:\s*"\)[^"]*/\1(redacted)/' >&2
  exit 1
fi
echo "Logged in. DID: $ACCOUNT_DID"

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
REC="{\"$type\":\"app.bsky.feed.generator\",\"did\":\"$SERVICE_DID\",\"displayName\":\"$DISPLAY_NAME\",\"description\":\"$DESCRIPTION\",\"createdAt\":\"$NOW\"}"

echo "Publishing app.bsky.feed.generator (rkey=$RKEY) ..."
CODE=0; req POST "${PDS_BASE%/}/xrpc/com.atproto.repo.putRecord" \
  "{\"repo\":\"$ACCOUNT_DID\",\"collection\":\"app.bsky.feed.generator\",\"rkey\":\"$RKEY\",\"record\":$REC}" \
  /tmp/put.json CODE "$ACCESS_JWT"
if [[ "$CODE" != "200" && "$CODE" != "201" ]]; then
  echo "Publish failed (HTTP $CODE). Body:" >&2
  sed -n '1,200p' /tmp/put.json >&2
  exit 1
fi

FEED_URI="at://${ACCOUNT_DID}/app.bsky.feed.generator/${RKEY}"
FEED_LINK="https://bsky.app/profile/${ACCOUNT_DID}/feed/${RKEY}"
echo
echo "Published!"
echo "- Feed URI:   $FEED_URI"
echo "- Open link:  $FEED_LINK"
echo "- Service DID: $SERVICE_DID"
echo
echo "If it doesn't show up immediately, verify:"
echo "- did:web: curl -s https://${FEED_DOMAIN}/.well-known/did.json | jq"
echo "- describe:  curl -s https://${FEED_DOMAIN}/xrpc/app.bsky.feed.describeFeedGenerator | jq"
