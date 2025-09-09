import { config } from './config.js'

function matches(entry, viewer) {
  if (!entry) return false;
  const e = entry.toLowerCase();
  const v = (viewer || '').toLowerCase();
  // allow exact DID match or handle/hostname substring match
  return e === v || v.includes(e) || e.includes(v);
}

export function isAllowed(viewer) {
  if (!viewer) return false;
  if (config.admin && matches(config.admin, viewer)) return true;
  if (!config.whitelist.length) return true; // if no whitelist set, open access
  return config.whitelist.some(w => matches(w, viewer));
}

