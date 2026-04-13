// Allboard — Supabase Configuration TEMPLATE
// ─────────────────────────────────────────────────────────────────
// DO NOT put real credentials here.
// This file is a template committed to git.
//
// SETUP (two options):
//
// Option A — Vercel Deploy (recommended):
//   1. Go to Vercel Dashboard > Project > Settings > Environment Variables
//   2. Add:  SUPABASE_URL   = https://your-project.supabase.co
//            SUPABASE_ANON  = your-anon-key
//            ADMIN_EMAIL    = your-admin@email.com
//   3. Redeploy — build.js will generate supabase-config.js automatically
//
// Option B — Local development:
//   1. Copy this file: cp supabase-config.example.js supabase-config.js
//   2. Fill in the values below
//   3. supabase-config.js is in .gitignore — it will NOT be committed
// ─────────────────────────────────────────────────────────────────

const SUPABASE_URL  = 'https://YOUR_PROJECT_ID.supabase.co';
const SUPABASE_ANON = 'YOUR_ANON_KEY';
const ADMIN_EMAIL   = 'your-admin@email.com';

const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON, {
  auth: {
    persistSession: true,
    autoRefreshToken: true
  }
});

async function getSession() {
  const { data: { session } } = await sb.auth.getSession();
  return session;
}

async function isAdmin() {
  const session = await getSession();
  if (!session) return false;
  return session.user.email === ADMIN_EMAIL;
}
