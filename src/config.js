// Minimal configuration loader

export const config = {
  port: parseInt(process.env.PORT || "3000", 10),
  // Whitelist of allowed viewer DIDs or handles (comma-separated)
  whitelist: (process.env.WHITELIST || "").split(",").map(s => s.trim()).filter(Boolean),
  // Admin DID or handle, always allowed
  admin: (process.env.ADMIN || "").trim(),
  // Max follows to consider for the viewer
  maxFollows: parseInt(process.env.MAX_FOLLOWS || "150", 10),
  // Per-follow fetch limits (keep low to be gentle on the AppView)
  perFollowAuthorFeedLimit: parseInt(process.env.PER_FOLLOW_AUTHOR_FEED_LIMIT || "5", 10),
  perFollowLikesLimit: parseInt(process.env.PER_FOLLOW_LIKES_LIMIT || "10", 10),
  // Global cap per page
  pageSize: parseInt(process.env.PAGE_SIZE || "30", 10),
  // Safety labels to exclude (substring match on label values)
  blockedLabels: (process.env.BLOCKED_LABELS || "porn,sexual,nsfw,sexual-content").split(",").map(s => s.trim()).filter(Boolean),
};

