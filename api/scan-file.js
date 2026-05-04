// Allboard — Vercel Serverless Function: VirusTotal File Hash Scan
// POST /api/scan-file
// Body: { sha256 }   — hex SHA-256 of the file, computed client-side
// Auth: Bearer <user supabase jwt>
// Returns: { status: 'clean' | 'flagged' | 'unknown', stats?: {...} }
//
// Required Vercel env vars:
//   VIRUSTOTAL_API_KEY  — VirusTotal public API key (free tier: 500 req/day)
//   SUPABASE_URL        — Project URL
//   SUPABASE_SERVICE_KEY — service_role key (for token verification)
//   ALLOWED_ORIGIN      — e.g. https://allboard.vercel.app

const https = require('https');
const { createClient } = require('@supabase/supabase-js');

function vtGet(sha256, apiKey) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'www.virustotal.com',
      path: `/api/v3/files/${sha256.toLowerCase()}`,
      method: 'GET',
      headers: { 'x-apikey': apiKey }
    };
    const req = https.request(options, (r) => {
      let data = '';
      r.on('data', chunk => { data += chunk; });
      r.on('end', () => resolve({ statusCode: r.statusCode, body: data }));
    });
    req.on('error', reject);
    req.setTimeout(8000, () => { req.destroy(new Error('VT request timeout')); });
    req.end();
  });
}

module.exports = async (req, res) => {
  const allowedOrigin = process.env.ALLOWED_ORIGIN || '';
  const requestOrigin = req.headers.origin || '';
  if (allowedOrigin && requestOrigin !== allowedOrigin) {
    res.setHeader('Access-Control-Allow-Origin', allowedOrigin);
  } else {
    res.setHeader('Access-Control-Allow-Origin', requestOrigin || allowedOrigin);
  }
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Vary', 'Origin');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  // Require a valid user JWT — prevents quota abuse by unauthenticated callers
  const token = (req.headers.authorization || '').replace('Bearer ', '').trim();
  if (!token) return res.status(401).json({ error: 'Unauthorized' });

  const supabaseUrl = process.env.SUPABASE_URL;
  const serviceKey  = process.env.SUPABASE_SERVICE_KEY;
  const apiKey      = process.env.VIRUSTOTAL_API_KEY;

  if (!supabaseUrl || !serviceKey) {
    return res.status(500).json({ error: 'Server misconfiguration' });
  }
  if (!apiKey) {
    // VT not configured — return unknown so upload can proceed
    return res.status(200).json({ status: 'unknown', reason: 'VT not configured' });
  }

  const sb = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  });

  const { data: { user }, error: authErr } = await sb.auth.getUser(token);
  if (authErr || !user) return res.status(401).json({ error: 'Invalid or expired token' });

  const { sha256 } = req.body || {};
  if (!sha256 || !/^[0-9a-f]{64}$/i.test(sha256)) {
    return res.status(400).json({ error: 'Invalid or missing sha256 hash' });
  }

  try {
    const vtResult = await vtGet(sha256, apiKey);

    if (vtResult.statusCode === 404) {
      // File not in VT database — treat as unknown, allow upload
      return res.status(200).json({ status: 'unknown' });
    }

    if (vtResult.statusCode === 429) {
      // Rate limit hit — fail open so users aren't blocked
      return res.status(200).json({ status: 'unknown', reason: 'rate_limited' });
    }

    if (vtResult.statusCode !== 200) {
      return res.status(200).json({ status: 'unknown', reason: `vt_${vtResult.statusCode}` });
    }

    const parsed = JSON.parse(vtResult.body);
    const stats = parsed?.data?.attributes?.last_analysis_stats || {};
    const malicious = (stats.malicious || 0) + (stats.suspicious || 0);

    if (malicious > 0) {
      return res.status(200).json({ status: 'flagged', stats });
    }
    return res.status(200).json({ status: 'clean', stats });

  } catch (err) {
    // VT unreachable — fail open, do not block legitimate users
    console.error('VT scan error:', err.message);
    return res.status(200).json({ status: 'unknown', reason: 'scan_error' });
  }
};
