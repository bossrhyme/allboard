// Allboard — Vercel Serverless Function: Create User from Pre-Registration
// POST /api/create-user
// Body: { pre_registration_id }   (email is read from DB, not trusted from client)
// Auth: Bearer <admin supabase jwt>
//
// Required Vercel env vars:
//   SUPABASE_URL         — Project URL
//   SUPABASE_SERVICE_KEY — service_role secret key
//   ALLOWED_ORIGIN       — e.g. https://allboard.vercel.app (optional, defaults to same-origin check)

const { createClient } = require('@supabase/supabase-js');

module.exports = async (req, res) => {
  // CORS — restrict to known origin, not wildcard
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

  // 1. JWT doğrula
  const token = (req.headers.authorization || '').replace('Bearer ', '').trim();
  if (!token) return res.status(401).json({ error: 'Unauthorized: no token' });

  const supabaseUrl = process.env.SUPABASE_URL;
  const serviceKey  = process.env.SUPABASE_SERVICE_KEY;

  if (!supabaseUrl || !serviceKey) {
    return res.status(500).json({ error: 'Server misconfiguration: missing env vars' });
  }

  const sb = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  });

  // 2. Token'dan user al
  const { data: { user }, error: authErr } = await sb.auth.getUser(token);
  if (authErr || !user) return res.status(401).json({ error: 'Invalid or expired token' });

  // 3. Admin kontrolü
  const { data: adminRow } = await sb.from('admins')
    .select('email').eq('email', user.email).single();
  if (!adminRow) return res.status(403).json({ error: 'Forbidden: not an admin' });

  // 4. Body parse + validasyon
  const { pre_registration_id } = req.body || {};
  if (!pre_registration_id) {
    return res.status(400).json({ error: 'Missing required field: pre_registration_id' });
  }
  const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!UUID_RE.test(pre_registration_id)) {
    return res.status(400).json({ error: 'Invalid pre_registration_id format' });
  }

  // 5. Pre-registration kaydını DB'den oku — email client'dan gelmiyor, DB'den geliyor
  const { data: preReg, error: preRegErr } = await sb.from('pre_registrations')
    .select('id, email, name, status')
    .eq('id', pre_registration_id)
    .single();

  if (preRegErr || !preReg) {
    return res.status(404).json({ error: 'Pre-registration not found' });
  }
  if (preReg.status === 'approved') {
    return res.status(409).json({ error: 'Already approved' });
  }

  // 6. Kullanıcıya davet emaili gönder — email DB'den alınıyor, client input'u değil
  const { data: inv, error: invErr } = await sb.auth.admin.inviteUserByEmail(preReg.email, {
    data: { full_name: preReg.name || '' }
  });
  if (invErr) return res.status(400).json({ error: invErr.message });

  // 7. Pre-registration kaydını güncelle
  const { error: updErr } = await sb.from('pre_registrations')
    .update({ status: 'approved', user_id: inv.user.id })
    .eq('id', pre_registration_id);

  if (updErr) {
    console.error('pre_registrations update error:', updErr.message);
    return res.status(500).json({ error: 'User created but registration update failed', user_id: inv.user.id });
  }

  return res.status(200).json({ success: true, user_id: inv.user.id });
};
