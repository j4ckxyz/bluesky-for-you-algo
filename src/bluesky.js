// Lightweight Bluesky AppView client using built-in fetch (Node >=18)

const APPVIEW = process.env.APPVIEW_BASE || 'https://public.api.bsky.app';

async function xrpc(method, params = {}) {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (v === undefined || v === null) continue;
    if (Array.isArray(v)) {
      v.forEach(val => q.append(k, String(val)));
    } else {
      q.set(k, String(v));
    }
  }
  const url = `${APPVIEW}/xrpc/${method}${q.toString() ? `?${q.toString()}` : ''}`;
  const res = await fetch(url, { headers: { 'accept': 'application/json' } });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`AppView ${method} ${res.status}: ${text}`);
  }
  return res.json();
}

export async function getFollows(actor, limit = 100, cursor) {
  return xrpc('app.bsky.graph.getFollows', { actor, limit, cursor });
}

export async function getAuthorFeed(actor, limit = 10, cursor) {
  return xrpc('app.bsky.feed.getAuthorFeed', { actor, limit, cursor });
}

export async function getActorLikes(actor, limit = 10, cursor) {
  return xrpc('app.bsky.feed.getActorLikes', { actor, limit, cursor });
}

export async function getPosts(uris) {
  if (!uris.length) return { posts: [] };
  return xrpc('app.bsky.feed.getPosts', { uris });
}

// Utility: flatten feed items to post URIs with metadata we care about
export function extractAuthorOriginalPosts(authorFeedItems = []) {
  const out = [];
  for (const item of authorFeedItems) {
    const post = item?.post;
    if (!post) continue;
    // exclude replies where parent author isn’t followed by viewer (we can’t easily know that here)
    // keep top-level or quotes
    const isReply = !!post?.reply;
    if (isReply) continue;
    out.push({ uri: post.uri, cid: post.cid, authorDid: post.author?.did, indexedAt: post?.indexedAt });
  }
  return out;
}

export function extractLikedPostUris(likes = []) {
  const out = [];
  for (const like of likes) {
    const subj = like?.subject || like?.subjectPost || like?.subject?.uri ? like.subject : null;
    const uri = subj?.uri || subj?.post?.uri || like?.subject?.uri || like?.uri;
    if (uri) out.push(uri);
  }
  return out;
}

export function nowIso() {
  return new Date().toISOString();
}

