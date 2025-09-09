// Minimal configuration loader

export const config = {
  port: parseInt(process.env.PORT || "3000", 10),
  // Whitelist of allowed viewer DIDs or handles (comma-separated)
  whitelist: (process.env.WHITELIST || "").split(",").map(s => s.trim()).filter(Boolean),
  // Optional path to a whitelist file (JSON array or newline-delimited)
  whitelistFile: (process.env.WHITELIST_FILE || "").trim(),
  // Admin DID or handle, always allowed
  admin: (process.env.ADMIN || "").trim(),
  // If true and no whitelist present, allow anyone
  openAccess: String(process.env.OPEN_ACCESS || "false").toLowerCase() === "true",
  // Max follows to consider for the viewer
  maxFollows: parseInt(process.env.MAX_FOLLOWS || "150", 10),
  // Per-follow fetch limits (keep low to be gentle on the AppView)
  perFollowAuthorFeedLimit: parseInt(process.env.PER_FOLLOW_AUTHOR_FEED_LIMIT || "5", 10),
  perFollowLikesLimit: parseInt(process.env.PER_FOLLOW_LIKES_LIMIT || "10", 10),
  // Global cap per page
  pageSize: parseInt(process.env.PAGE_SIZE || "30", 10),
  // Safety labels to exclude (substring match on label values)
  blockedLabels: (process.env.BLOCKED_LABELS || "porn,sexual,nsfw,sexual-content").split(",").map(s => s.trim()).filter(Boolean),
  // Public domain used for did:web and service endpoint
  feedDomain: (process.env.FEED_DOMAIN || "blue.j4ck.xyz").trim(),
  feedScheme: (process.env.FEED_SCHEME || "https").trim(),
  serviceDid: (process.env.SERVICE_DID || "").trim(),
};

if (!config.serviceDid && config.feedDomain) {
  config.serviceDid = `did:web:${config.feedDomain}`;
}
