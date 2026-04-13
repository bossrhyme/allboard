// Allboard — Vercel Serverless Function: Create User from Pre-Registration
// POST /api/create-user
// Body: { pre_registration_id, email, name }
// Auth: Bearer <admin supabase jwt>
//
// Required Vercel env vars:
//   SUPABASE_URL         — Project URL
//   SUPABASE_SERVICE_KEY — service_role secret key

const { createClient } = require('@supabase/supabase-js');

module.exports = async (req, res) => {
  // CORS preflight
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
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

  // 4. Body parse
  const { pre_registration_id, email, name } = req.body || {};
  if (!pre_registration_id || !email) {
    return res.status(400).json({ error: 'Missing required fields: pre_registration_id, email' });
  }

  // 5. Kullanıcıya davet emaili gönder (magic link ile giriş yapar)
  const { data: inv, error: invErr } = await sb.auth.admin.inviteUserByEmail(email, {
    data: { full_name: name || '' }
  });
  if (invErr) return res.status(400).json({ error: invErr.message });

  // 6. Pre-registration kaydını güncelle
  const { error: updErr } = await sb.from('pre_registrations')
    .update({ status: 'approved', user_id: inv.user.id })
    .eq('id', pre_registration_id);

  if (updErr) {
    // Kullanıcı oluşturuldu ama kayıt güncellenemedi — hata logla ama başarı dön
    console.error('pre_registrations update error:', updErr.message);
  }

  return res.status(200).json({ success: true, user_id: inv.user.id });
};
