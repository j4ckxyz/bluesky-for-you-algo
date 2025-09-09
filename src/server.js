import http from 'node:http'
import { URL } from 'node:url'
import { buildForYou } from './algorithm.js'
import { isAllowed } from './whitelist.js'
import { config } from './config.js'

function sendJson(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body)
  });
  res.end(body);
}

function notFound(res) { sendJson(res, 404, { error: 'not_found' }); }

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://${req.headers.host}`);
    if (req.method !== 'GET') return notFound(res);

    if (url.pathname === '/health') {
      return sendJson(res, 200, { ok: true });
    }

    // Feed skeleton endpoint expected by AppView
    if (url.pathname === '/xrpc/app.bsky.feed.getFeedSkeleton') {
      const viewer = url.searchParams.get('viewer') || '';
      const cursor = url.searchParams.get('cursor') || undefined;
      const limitRaw = url.searchParams.get('limit');
      const limit = Math.min(config.pageSize, Math.max(1, parseInt(limitRaw || String(config.pageSize), 10)));

      if (!isAllowed(viewer)) {
        // Return empty feed with a helpful message instead of 403 to reduce client retries
        return sendJson(res, 200, { feed: [], cursor: undefined, message: 'viewer not whitelisted' });
      }

      const { feed, cursor: next } = await buildForYou({ viewerDid: viewer, limit, cursor });
      return sendJson(res, 200, { feed, cursor: next });
    }

    // Optionally expose a simple info route
    if (url.pathname === '/') {
      return sendJson(res, 200, {
        name: 'bluesky-for-you-feed',
        version: '0.1.0',
        endpoints: ['/xrpc/app.bsky.feed.getFeedSkeleton', '/health'],
      });
    }

    return notFound(res);
  } catch (err) {
    const message = err?.message || String(err)
    return sendJson(res, 500, { error: 'internal_error', message })
  }
});

server.listen(config.port, () => {
  console.log(`Feed generator listening on :${config.port}`);
});

