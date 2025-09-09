Bluesky For You Feed Generator
==============================

Inspired by the Twitter algorithm. Built with GPT-5. Not used to train LLMs.

This is a minimal custom feed generator for Bluesky that implements a “For You” timeline using only public AppView endpoints and Node’s built-in `fetch` (no external dependencies).

Highlights
- For You logic: in-network recency + out-of-network via likes from people you follow, scored with recency decay and social proof.
- Mixing and heuristics: 50/50 in/out network target, basic safety label filtering, author diversity cap.
- Whitelist: only approved viewers can use the feed; admin always allowed.
- Zero deps: works on Node 18+ out-of-the-box, or in Docker.

Endpoints
- `GET /xrpc/app.bsky.feed.getFeedSkeleton?viewer=<did>&limit=<n>&cursor=<cursor>`
- `GET /xrpc/app.bsky.feed.describeFeedGenerator`
- `GET /.well-known/did.json`
- `GET /health`

Environment
- `PORT` (default `3000`)
- `WHITELIST` — comma-separated DIDs or handles; can be left empty to use `WHITELIST_FILE`
- `WHITELIST_FILE` — optional path to file with JSON array or newline-separated DIDs/handles (auto-reloaded)
- `OPEN_ACCESS` — set `true` to allow all when no whitelist provided (default `false`)
- `ADMIN` — DID or handle always allowed
- `APPVIEW_BASE` — AppView base (default `https://public.api.bsky.app`)
- `MAX_FOLLOWS` — max follows to consider (default `150`)
- `PER_FOLLOW_AUTHOR_FEED_LIMIT` (default `5`)
- `PER_FOLLOW_LIKES_LIMIT` (default `10`)
- `PAGE_SIZE` — default page size (default `30`)
- `BLOCKED_LABELS` — comma list (default `porn,sexual,nsfw,sexual-content`)
- `FEED_DOMAIN` — public domain for did:web and service endpoint (default `blue.j4ck.xyz`)
- `FEED_SCHEME` — `https` or `http` (default `https`)
- `SERVICE_DID` — override for service DID (default `did:web:<FEED_DOMAIN>`) 

Quick start (Node)
1. Node >= 18 is required.
2. Start the server:
   - `ADMIN=did:plc:youradmindid WHITELIST=did:plc:friend1,did:plc:friend2 npm start`
3. Open `http://localhost:3000/xrpc/app.bsky.feed.getFeedSkeleton?viewer=<your-did>`

Quick start (Docker)
```
docker build -t bsky-for-you .
docker run -p 3000:3000 \
  -e ADMIN=did:plc:youradmindid \
  -e WHITELIST=did:plc:friend1,did:plc:friend2 \
  -e SERVICE_DID=did:web:feed.example.com \
  -e APPVIEW_BASE=https://public.api.bsky.app \
  --name bsky-for-you bsky-for-you
```

Register the feed
- Create an `app.bsky.feed.generator` record in the admin account’s repo with `did`/`serviceDid` pointing to your feed generator service and metadata (name/description/avatar).
- AppView will call your service’s `app.bsky.feed.getFeedSkeleton` with `viewer`, `limit`, `cursor` and hydrate results.

did:web hosting
- Point your domain (e.g., `blue.j4ck.xyz`) to this service and ensure TLS.
- This server serves `/.well-known/did.json` dynamically from `FEED_DOMAIN` and `SERVICE_DID`:
  - Example did.json:
    - `id`: `did:web:blue.j4ck.xyz`
    - `service[0].type`: `BskyFeedGenerator`
    - `service[0].serviceEndpoint`: `https://blue.j4ck.xyz`
  - If you use a reverse proxy (Nginx), you can either proxy `/.well-known/did.json` to the app or serve a static file that matches these values.

How it works (brief)
- In-network: recent, top-level posts from the authors you follow.
- Out-of-network: posts liked by your followings.
- Engagement: batched `app.bsky.feed.getPosts` for likes/reposts/replies.
- Scoring: in-network boost, social proof, log-engagement, time decay, reply downrank.
- Mixing: target ~50% in / 50% out; cap 3 per author per page.
- Safety: filters posts with labels matching `BLOCKED_LABELS`.

Notes
- Cursor is a simple offset. For stronger stability, use deterministic cursors.
- Keep per-follow limits modest to respect public AppView rate limits.
- Access control: by default, only `ADMIN` and `WHITELIST` can use the feed. To open access, set `OPEN_ACCESS=true`.

License
- MIT — see `LICENSE`.

One-command setup
- `./setup-docker.sh` — interactive Docker build/run helper.
- `./publish-feed.sh` — publish the `app.bsky.feed.generator` record (after Docker is running and DNS/TLS are set).

setup-docker.sh
- Prompts for FEED_DOMAIN, ADMIN, WHITELIST (or a whitelist file), host port, and AppView base.
- Builds the image, replaces any old container, and starts a new one bound to 127.0.0.1:<port>.
- Prints the did:web JSON and Nginx hints to finish public hosting.

publish-feed.sh
- Prompts for domain (to compute `did:web:<domain>`), handle and app password, feed rkey, name, and description.
- Creates a session on your PDS (default `https://bsky.social`) and publishes `app.bsky.feed.generator`.
- Prints the feed URI (`at://...`) and a direct link you can open in Bluesky.

Systemd (optional)
- Example unit at `/etc/systemd/system/bsky-for-you.service`:
```
[Unit]
Description=Bluesky For You Feed (Docker)
After=network.target docker.service
Requires=docker.service

[Service]
Restart=always
RestartSec=5
TimeoutStartSec=0
ExecStartPre=-/usr/bin/docker rm -f bsky-for-you
ExecStart=/usr/bin/docker run --name bsky-for-you --restart unless-stopped \
  -p 127.0.0.1:3000:3000 \
  -e FEED_DOMAIN=blue.j4ck.xyz \
  -e ADMIN=did:plc:YOUR_ADMIN_DID \
  -e WHITELIST=did:plc:FRIEND1,did:plc:FRIEND2 \
  -e APPVIEW_BASE=https://public.api.bsky.app \
  bsky-for-you
ExecStop=/usr/bin/docker stop bsky-for-you

[Install]
WantedBy=multi-user.target
```
- Enable:
  - `sudo systemctl daemon-reload`
  - `sudo systemctl enable --now bsky-for-you`
  - Logs: `journalctl -u bsky-for-you -f`
