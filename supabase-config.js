// VerifyFlow — Supabase Konfigürasyonu
// Supabase Dashboard > Project Settings > API > buradan al
//
// KURULUM:
// 1. supabase.com'da yeni proje oluştur
// 2. Dashboard > SQL Editor > migrations.sql içeriğini yapıştır ve çalıştır
// 3. Dashboard > Storage > "documents" adında Private bucket oluştur
// 4. Dashboard > Auth > Users > Admin kullanıcısı davet et
// 5. Aşağıdaki değerleri kendi projenle güncelle

const SUPABASE_URL  = 'https://PROJE_ID.supabase.co';  // <-- değiştir
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ANON_KEY';  // <-- değiştir

// Admin e-postası (migrations.sql'deki app.admin_email ile eşleşmeli)
const ADMIN_EMAIL = 'admin@seninsirket.com';  // <-- değiştir

// Supabase istemcisi oluştur
const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON, {
  auth: {
    persistSession: true,
    autoRefreshToken: true
  }
});

// Oturum kontrolü yardımcı fonksiyonu
async function getSession() {
  const { data: { session } } = await sb.auth.getSession();
  return session;
}

// Admin kontrolü
async function isAdmin() {
  const session = await getSession();
  if (!session) return false;
  return session.user.email === ADMIN_EMAIL;
}
