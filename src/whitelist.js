import { config } from './config.js'
import fs from 'node:fs'
import path from 'node:path'

function matches(entry, viewer) {
  if (!entry) return false;
  const e = entry.toLowerCase();
  const v = (viewer || '').toLowerCase();
  // allow exact DID match or handle/hostname substring match
  return e === v || v.includes(e) || e.includes(v);
}

let cached = { list: config.whitelist.slice(), mtimeMs: 0 };

function tryLoadWhitelistFile() {
  const file = config.whitelistFile;
  if (!file) return;
  try {
    const st = fs.statSync(file);
    if (st.mtimeMs <= cached.mtimeMs) return; // unchanged
    const raw = fs.readFileSync(file, 'utf8');
    let arr = [];
    try {
      const j = JSON.parse(raw);
      if (Array.isArray(j)) arr = j.map(String);
    } catch {
      arr = raw.split(/\r?\n/).map(s => s.trim()).filter(Boolean);
    }
    cached = { list: arr, mtimeMs: st.mtimeMs };
  } catch {
    // ignore
  }
}

export function currentWhitelist() {
  tryLoadWhitelistFile();
  const base = cached.list.length ? cached.list : config.whitelist;
  const plusAdmin = config.admin ? Array.from(new Set([...base, config.admin])) : base;
  return plusAdmin;
}

export function isAllowed(viewer) {
  if (!viewer) return false;
  if (config.admin && matches(config.admin, viewer)) return true;
  const list = currentWhitelist();
  if (config.openAccess && list.length === 0) return true; // explicit open mode
  if (list.length === 0) return false; // closed by default when no whitelist
  return list.some(w => matches(w, viewer));
}
