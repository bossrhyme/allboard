// Allboard — Test Kullanıcısı Seed Script
// ─────────────────────────────────────────────────────────────────
// Çalıştırmadan önce aşağıdaki 4 satırı doldurun:
//
//   SUPABASE_URL         → Dashboard > Settings > API > Project URL
//   SUPABASE_SERVICE_KEY → Dashboard > Settings > API > service_role (secret)
//   TEST_EMAIL           → Giriş için kullanılacak e-posta
//   TEST_PASSWORD        → Giriş için kullanılacak şifre (min 6 karakter)
//
// Çalıştırma:
//   npm install @supabase/supabase-js   (bir kez)
//   node seed.js
// ─────────────────────────────────────────────────────────────────

const SUPABASE_URL         = 'https://YOUR_PROJECT_ID.supabase.co';
const SUPABASE_SERVICE_KEY = 'YOUR_SERVICE_ROLE_KEY';
const TEST_EMAIL           = 'test@allboard.co';
const TEST_PASSWORD        = 'Test1234!';

// ─────────────────────────────────────────────────────────────────

const { createClient } = require('@supabase/supabase-js');

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false }
});

async function seed() {
  console.log('⏳ Test kullanıcısı oluşturuluyor...\n');

  // ── 1. Auth kullanıcısı ──────────────────────────────────────────
  const { data: authData, error: authErr } = await sb.auth.admin.createUser({
    email: TEST_EMAIL,
    password: TEST_PASSWORD,
    email_confirm: true
  });

  if (authErr) {
    // Kullanıcı zaten varsa devam et
    if (authErr.message && authErr.message.includes('already')) {
      console.log('ℹ️  Auth kullanıcısı zaten mevcut, data eklemeye devam ediliyor...');
      // Mevcut kullanıcının ID'sini bul
      const { data: listData } = await sb.auth.admin.listUsers();
      const existing = listData.users.find(u => u.email === TEST_EMAIL);
      if (!existing) { console.error('✗ Kullanıcı bulunamadı.'); process.exit(1); }
      return seedData(existing.id);
    }
    console.error('✗ Auth hatası:', authErr.message);
    process.exit(1);
  }

  const userId = authData.user.id;
  console.log('✓ Auth kullanıcısı oluşturuldu:', TEST_EMAIL);
  await seedData(userId);
}

async function seedData(userId) {

  // ── 2. Clients kaydı ────────────────────────────────────────────
  const clientPayload = {
    user_id:     userId,
    type:        'individual',
    status:      'approved',
    kyc_status:  'approved',
    aml_status:  'approved',
    risk_status: 'approved',
    risk_score:  12,
    personal: {
      firstName:  'Ahmet',
      lastName:   'Kaya',
      dob:        '1985-06-15',
      nationality:'Türk',
      nationalId: '12345678901',
      phone:      '+90 532 000 0000',
      email:      TEST_EMAIL
    },
    address: {
      street:     'Bağdat Caddesi 142/3',
      city:       'İstanbul',
      district:   'Kadıköy',
      postalCode: '34710',
      country:    'Türkiye'
    },
    pep: {
      isPep:         false,
      hasRelative:   false,
      sourceOfFunds: 'salary',
      monthlyVolume: '10000-50000'
    }
  };

  const { data: clientData, error: clientErr } = await sb
    .from('clients')
    .insert(clientPayload)
    .select('id')
    .single();

  if (clientErr) {
    console.error('✗ Client insert hatası:', clientErr.message);
    process.exit(1);
  }

  const clientId = clientData.id;
  console.log('✓ Client kaydı oluşturuldu (id:', clientId + ')');

  // ── 3. Belgeler ─────────────────────────────────────────────────
  const docs = [
    { doc_type: 'identity', file_name: 'kimlik_on_yuz.pdf',       file_size: '1.2 MB', status: 'approved', available: true, file_path: null },
    { doc_type: 'address',  file_name: 'ikametgah_belgesi.pdf',   file_size: '0.8 MB', status: 'approved', available: true, file_path: null },
    { doc_type: 'tax',      file_name: 'vergi_levhasi.pdf',       file_size: '0.5 MB', status: 'approved', available: true, file_path: null }
  ].map(d => ({ ...d, client_id: clientId }));

  const { error: docsErr } = await sb.from('documents').insert(docs);
  if (docsErr) {
    console.error('✗ Documents insert hatası:', docsErr.message);
    process.exit(1);
  }
  console.log('✓ 3 belge eklendi (identity, address, tax)');

  // ── 4. Chat mesajları ────────────────────────────────────────────
  const now = Date.now();
  const messages = [
    {
      client_id:   clientId,
      sender_type: 'staff',
      sender_name: 'Allboard',
      text:        'Merhaba Ahmet Bey! Başvurunuzu aldık ve inceleme sürecini başlattık. Belgeleriniz için teşekkür ederiz. Herhangi bir sorunuz olursa buradan iletişime geçebilirsiniz.',
      created_at:  new Date(now - 4 * 60 * 60 * 1000).toISOString()
    },
    {
      client_id:   clientId,
      sender_type: 'client',
      sender_name: 'Ahmet Kaya',
      text:        'Teşekkürler. Belgelerimi yükledim, süreci buradan takip edebilir miyim?',
      created_at:  new Date(now - 3 * 60 * 60 * 1000).toISOString()
    },
    {
      client_id:   clientId,
      sender_type: 'staff',
      sender_name: 'Allboard',
      text:        'Evet, profilinizin Doğrulama sekmesinden anlık olarak takip edebilirsiniz. Belgeleriniz incelendi, KYC doğrulaması ve AML taraması başarıyla tamamlandı.',
      created_at:  new Date(now - 2 * 60 * 60 * 1000).toISOString()
    },
    {
      client_id:   clientId,
      sender_type: 'staff',
      sender_name: 'Allboard',
      text:        'Harika haber! 🎉 Başvurunuz tüm doğrulama aşamalarını başarıyla geçti ve onaylandı. Artık onaylı bir üyesiniz. İyi günler dileriz!',
      created_at:  new Date(now - 30 * 60 * 1000).toISOString()
    }
  ];

  const { error: chatErr } = await sb.from('chat_messages').insert(messages);
  if (chatErr) {
    console.error('✗ Chat messages insert hatası:', chatErr.message);
    process.exit(1);
  }
  console.log('✓ 4 chat mesajı eklendi\n');

  // ── 5. Özet ─────────────────────────────────────────────────────
  console.log('═══════════════════════════════════════════');
  console.log('  TEST KULLANICISI HAZIR');
  console.log('═══════════════════════════════════════════');
  console.log('  E-posta  :', TEST_EMAIL);
  console.log('  Şifre    :', TEST_PASSWORD);
  console.log('  Ad Soyad : Ahmet Kaya');
  console.log('  Durum    : Onaylandı ✓');
  console.log('───────────────────────────────────────────');
  console.log('  Giriş    : allboard.vercel.app → Giriş Yap');
  console.log('═══════════════════════════════════════════\n');
}

seed().catch(err => {
  console.error('Beklenmeyen hata:', err.message);
  process.exit(1);
});
