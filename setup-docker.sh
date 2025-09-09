#!/usr/bin/env bash
set -euo pipefail

echo "== Bluesky For You: Docker setup =="

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker is not installed. Install Docker and re-run." >&2
  exit 1
fi

IMAGE_DEFAULT="bsky-for-you"
CONTAINER_DEFAULT="bsky-for-you"
DOMAIN_DEFAULT="${FEED_DOMAIN:-blue.j4ck.xyz}"
ADMIN_DEFAULT="${ADMIN:-}"
WHITELIST_DEFAULT="${WHITELIST:-}"
APPVIEW_DEFAULT="${APPVIEW_BASE:-https://public.api.bsky.app}"
HOST_PORT_DEFAULT="${HOST_PORT:-3000}"

read -rp "Feed domain (FEED_DOMAIN) [${DOMAIN_DEFAULT}]: " FEED_DOMAIN_INP || true
FEED_DOMAIN=${FEED_DOMAIN_INP:-$DOMAIN_DEFAULT}

read -rp "Admin DID (ADMIN) [${ADMIN_DEFAULT}]: " ADMIN_INP || true
ADMIN=${ADMIN_INP:-$ADMIN_DEFAULT}

read -rp "Whitelist DIDs, comma-separated (leave empty to use a file) [${WHITELIST_DEFAULT}]: " WHITELIST_INP || true
WHITELIST=${WHITELIST_INP:-$WHITELIST_DEFAULT}

WHITELIST_FILE=""
if [[ -z "${WHITELIST}" ]]; then
  read -rp "Path to whitelist file (optional, JSON array or newline list): " WHITELIST_FILE || true
fi

read -rp "AppView base (APPVIEW_BASE) [${APPVIEW_DEFAULT}]: " APPVIEW_BASE_INP || true
APPVIEW_BASE=${APPVIEW_BASE_INP:-$APPVIEW_DEFAULT}

read -rp "Host port to bind (127.0.0.1:<port>) [${HOST_PORT_DEFAULT}]: " HOST_PORT_INP || true
HOST_PORT=${HOST_PORT_INP:-$HOST_PORT_DEFAULT}

read -rp "Docker image name [${IMAGE_DEFAULT}]: " IMAGE_INP || true
IMAGE=${IMAGE_INP:-$IMAGE_DEFAULT}

read -rp "Docker container name [${CONTAINER_DEFAULT}]: " CONTAINER_INP || true
CONTAINER=${CONTAINER_INP:-$CONTAINER_DEFAULT}

echo
echo "Summary:";
echo "  FEED_DOMAIN    = ${FEED_DOMAIN}"
echo "  ADMIN          = ${ADMIN}"
echo "  WHITELIST      = ${WHITELIST}"
echo "  WHITELIST_FILE = ${WHITELIST_FILE}"
echo "  APPVIEW_BASE   = ${APPVIEW_BASE}"
echo "  Host port      = ${HOST_PORT}"
echo "  Image          = ${IMAGE}"
echo "  Container      = ${CONTAINER}"
echo
read -rp "Proceed to build and run? [y/N]: " CONFIRM || true
if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
  echo "Aborted."
  exit 1
fi

echo "Building image ${IMAGE}..."
docker build -t "${IMAGE}" .

echo "Stopping old container (if any)..."
docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true

RUN_ARGS=(
  -d --name "${CONTAINER}" --restart unless-stopped
  -p 127.0.0.1:"${HOST_PORT}":3000
  -e FEED_DOMAIN="${FEED_DOMAIN}"
  -e ADMIN="${ADMIN}"
  -e APPVIEW_BASE="${APPVIEW_BASE}"
)

if [[ -n "${WHITELIST}" ]]; then
  RUN_ARGS+=( -e WHITELIST="${WHITELIST}" )
elif [[ -n "${WHITELIST_FILE}" ]]; then
  RUN_ARGS+=( -e WHITELIST_FILE=/whitelist.txt -v "${WHITELIST_FILE}":/whitelist.txt:ro )
fi

echo "Running container ${CONTAINER}..."
docker run "${RUN_ARGS[@]}" "${IMAGE}"

echo
echo "Done. Next steps:"
cat <<EOT
- Ensure your Nginx serves did:web statically:
  Path: /.well-known/did.json
  Contents:
  {
    "@context": ["https://www.w3.org/ns/did/v1"],
    "id": "did:web:${FEED_DOMAIN}",
    "service": [{ "id": "#bsky_fg", "type": "BskyFeedGenerator", "serviceEndpoint": "https://${FEED_DOMAIN}" }]
  }
- Proxy /xrpc/ and /health to http://127.0.0.1:${HOST_PORT}
- Test:
  curl -i https://${FEED_DOMAIN}/.well-known/did.json
  curl -i https://${FEED_DOMAIN}/xrpc/app.bsky.feed.describeFeedGenerator
  curl -i https://${FEED_DOMAIN}/health

When ready, run ./publish-feed.sh to publish the feed record to Bluesky.
EOT

