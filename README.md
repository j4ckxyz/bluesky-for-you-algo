Bluesky For You Feed Generator
==============================

This is a minimal custom feed generator for Bluesky that implements a “For You” algorithm inspired by Twitter/The Algorithm. It uses only public AppView endpoints and Node’s built-in `fetch` (no external dependencies), so it’s easy to host.

Highlights
- For You logic: in-network recency + out-of-network via likes from people you follow, scored with recency decay and social proof.
- Mixing and heuristics: 50/50 in/out network target, basic safety label filtering, author diversity cap.
- Whitelist: only approved viewers can use the feed; admin always allowed.
- Zero deps: works on Node 18+ out-of-the-box, or in Docker.

How it maps to “The Algorithm”
- Candidate sources: in-network (authors you follow) and OON via social proof (posts liked by your follows). This mirrors the Earlybird/UTEG + social proof candidate sourcing at a smaller scale using public data.
- Ranking: a lightweight scoring function combining in-network boost, number of follows who liked/reposted, engagement counts (likes/reposts/replies), and strong time decay (freshness).
- Filters/mixing: caps per author, basic NSFW label exclusion, and target mixing ratio between in- and out-of-network similar to Home Mixer heuristics.

Endpoints
- `GET /xrpc/app.bsky.feed.getFeedSkeleton?viewer=<did>&limit=<n>&cursor=<cursor>`
- `GET /health`

Environment
- `PORT` (default `3000`)
- `WHITELIST` — comma-separated DIDs or handles; empty = open access
- `ADMIN` — DID or handle always allowed
- `APPVIEW_BASE` — AppView base (default `https://public.api.bsky.app`)
- `MAX_FOLLOWS` — max follows to consider (default `150`)
- `PER_FOLLOW_AUTHOR_FEED_LIMIT` (default `5`)
- `PER_FOLLOW_LIKES_LIMIT` (default `10`)
- `PAGE_SIZE` — default page size (default `30`)
- `BLOCKED_LABELS` — comma list (default `porn,sexual,nsfw,sexual-content`)

Run locally
1. Node >= 18 is required.
2. Set env vars and start:
   - `ADMIN=did:plc:youradmindid WHITELIST=did:plc:friend1,did:plc:friend2 npm start`
3. Open `http://localhost:3000/xrpc/app.bsky.feed.getFeedSkeleton?viewer=<your-did>`

Docker
```
docker build -t bsky-for-you .
docker run -p 3000:3000 \
  -e ADMIN=did:plc:youradmindid \
  -e WHITELIST=did:plc:friend1,did:plc:friend2 \
  --name bsky-for-you bsky-for-you
```

Registering the feed
Use Bluesky’s custom feed flow:
- Create an `app.bsky.feed.generator` record in the admin account’s repo with `serviceDid` pointing to your feed generator service and metadata (name/description/avatar).
- AppView will call your service’s `app.bsky.feed.getFeedSkeleton` with `viewer`, `limit`, `cursor` and hydrate results.

Design notes
- In-network: takes recent, top-level posts from your followings’ author feeds.
- OON: collects posts liked by your followings (`app.bsky.feed.getActorLikes`).
- Engagement: batches `app.bsky.feed.getPosts` to get like/repost/reply counts for ranking.
- Scoring: in-network boost, +1.2 per follow-like (cap 3), +1.0 per follow-repost (placeholder), +0.3*log(engagement), strong exponential time decay, reply downrank.
- Mixing: targets ~50% in/50% OON, then enforces per-author cap of 3 per page.
- Safety: filters posts with labels matching `BLOCKED_LABELS`.

Caveats & next steps
- The ranking is intentionally simple; you can add topic signals, author reputation, and embedding similarity when available.
- Cursoring is a simple offset; for stability across time, consider deterministic cursor tokens based on sorted IDs and timestamps.
- You may add a small cache (e.g., LRU) to avoid refetching follows/likes within short intervals.
- To include repost social proof, parse `getAuthorFeed` items with `reason` as reposts from your follows and increment `repostedByFollows`.

Security & rate limits
- This implementation only hits public AppView. Respect rate limits by keeping per-follow limits small and adding simple backoff if needed.

