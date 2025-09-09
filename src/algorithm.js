import { getFollows, getAuthorFeed, getActorLikes, getPosts, extractAuthorOriginalPosts, extractLikedPostUris } from './bluesky.js'
import { config } from './config.js'

function clamp(n, min, max) { return Math.max(min, Math.min(max, n)); }

function hoursSince(iso) {
  if (!iso) return 1e6;
  const t = new Date(iso).getTime();
  const now = Date.now();
  return Math.max(0, (now - t) / (1000 * 60 * 60));
}

function scorePost(features) {
  const {
    inNetwork,
    likedByFollows = 0,
    repostedByFollows = 0,
    likeCount = 0,
    repostCount = 0,
    replyCount = 0,
    indexedAt,
    isReply = false,
  } = features;

  const ageH = hoursSince(indexedAt);
  const freshness = Math.exp(-0.07 * ageH); // fast time-decay

  const social = clamp(likedByFollows, 0, 3) * 1.2 + clamp(repostedByFollows, 0, 2) * 1.0;
  const engLog = Math.log1p(likeCount * 1.0 + repostCount * 0.7 + replyCount * 0.5);

  const base = (inNetwork ? 1.6 : 0.0) + social + 0.3 * engLog;
  const penalty = (isReply ? 0.2 : 0);

  return (base - penalty) * freshness;
}

function mixInOutNetwork(sorted, desiredTotal, inShare = 0.5) {
  const inN = Math.floor(desiredTotal * inShare);
  const outN = desiredTotal - inN;
  const inItems = sorted.filter(x => x.inNetwork).slice(0, inN);
  const outItems = sorted.filter(x => !x.inNetwork).slice(0, outN);
  // backfill if one side is short
  const combined = [...inItems, ...outItems];
  if (combined.length < desiredTotal) {
    for (const x of sorted) {
      if (combined.length >= desiredTotal) break;
      if (!combined.find(y => y.uri === x.uri)) combined.push(x);
    }
  }
  return combined;
}

function enforceAuthorDiversity(items, perAuthorMax = 3) {
  const counts = new Map();
  const out = [];
  for (const it of items) {
    const a = it.authorDid || 'unknown';
    const c = counts.get(a) || 0;
    if (c >= perAuthorMax) continue;
    counts.set(a, c + 1);
    out.push(it);
  }
  return out;
}

export async function buildForYou({ viewerDid, limit = 30, cursor }) {
  // Primitive cursor: numeric offset in sorted list. Not stable across time.
  const offset = Number.isFinite(Number(cursor)) ? parseInt(cursor, 10) : 0;

  // Step 1: get follows (cap to keep requests reasonable)
  const follows = [];
  let fCursor;
  while (follows.length < config.maxFollows) {
    const page = await getFollows(viewerDid, Math.min(100, config.maxFollows - follows.length), fCursor).catch(() => ({ follows: [] }));
    (page.follows || []).forEach(f => follows.push({ did: f?.did, handle: f?.handle }));
    if (!page.cursor || (page.follows || []).length === 0) break;
    fCursor = page.cursor;
  }
  const followDids = follows.map(f => f.did).filter(Boolean);

  // Step 2: In-network candidates from authors' feeds
  const inNetworkCandidates = [];
  for (const did of followDids) {
    const feedPage = await getAuthorFeed(did, config.perFollowAuthorFeedLimit).catch(() => ({ feed: [] }));
    const posts = extractAuthorOriginalPosts(feedPage.feed);
    posts.forEach(p => inNetworkCandidates.push({ uri: p.uri, authorDid: p.authorDid, indexedAt: p.indexedAt }));
  }

  // Step 3: Out-of-network candidates via likes by your follows
  const likedByMap = new Map(); // postUri -> count of follows who liked
  const oonUris = new Set();
  for (const did of followDids) {
    const likesPage = await getActorLikes(did, config.perFollowLikesLimit).catch(() => ({ likes: [] }));
    const likedUris = extractLikedPostUris(likesPage.likes || likesPage.records || []);
    for (const uri of likedUris) {
      likedByMap.set(uri, (likedByMap.get(uri) || 0) + 1);
      oonUris.add(uri);
    }
  }

  // Step 4: Fetch engagement for a batch of candidates to aid scoring
  const allUris = [
    ...Array.from(new Set(inNetworkCandidates.map(c => c.uri))),
    ...Array.from(oonUris),
  ].slice(0, 500); // hard cap

  const postsMeta = await getPosts(allUris).catch(() => ({ posts: [] }));
  const metaByUri = new Map();
  for (const p of (postsMeta.posts || [])) {
    metaByUri.set(p.uri, {
      likeCount: p?.likeCount || 0,
      repostCount: p?.repostCount || 0,
      replyCount: p?.replyCount || 0,
      indexedAt: p?.indexedAt || p?.record?.createdAt,
      authorDid: p?.author?.did,
      labels: (p?.labels || []).map(l => l?.val).filter(Boolean),
      isReply: !!p?.record?.reply,
    });
  }

  // Step 5: Construct feature rows and score
  const candidates = [];
  const seen = new Set();
  function push(uri, inNetwork) {
    if (!uri || seen.has(uri)) return;
    seen.add(uri);
    const m = metaByUri.get(uri) || {};
    const likedByFollows = likedByMap.get(uri) || 0;
    candidates.push({
      uri,
      inNetwork,
      authorDid: m.authorDid,
      indexedAt: m.indexedAt,
      likeCount: m.likeCount,
      repostCount: m.repostCount,
      replyCount: m.replyCount,
      likedByFollows,
      isReply: m.isReply,
      labels: m.labels || [],
    });
  }

  inNetworkCandidates.forEach(c => push(c.uri, true));
  oonUris.forEach(uri => push(uri, false));

  // Safety filtering
  const blocked = new Set((config.blockedLabels || []).map(s => s.toLowerCase()));
  const safe = candidates.filter(c => !c.labels?.some(l => blocked.has(String(l).toLowerCase())));

  // Scoring
  safe.forEach(c => { c.score = scorePost(c); });
  safe.sort((a, b) => b.score - a.score);

  // Mixing and diversity
  const mixed = mixInOutNetwork(safe, Math.max(limit + offset, limit), 0.5);
  const diverse = enforceAuthorDiversity(mixed, 3);

  const page = diverse.slice(offset, offset + limit);
  const nextCursor = diverse.length > offset + limit ? String(offset + limit) : undefined;

  // Return skeleton items
  const feed = page.map(item => ({ post: item.uri }));
  return { feed, cursor: nextCursor };
}

