-- Allboard — Supabase Database Migrations
-- Supabase Dashboard > SQL Editor > Bu dosyayı yapıştır ve çalıştır

-- ============================================================
-- 1. CLIENTS — Ana müşteri kaydı
-- ============================================================
create table if not exists clients (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users on delete set null,
  type         text check (type in ('individual','business')),
  status       text default 'pending' check (status in ('pending','in_review','approved','rejected')),
  personal     jsonb,  -- {firstName, lastName, dob, nationality, nationalId, phone, email}
  address      jsonb,  -- {street, city, district, postalCode, country}
  pep          jsonb,  -- {isPep, hasRelative, sourceOfFunds, monthlyVolume}
  company      jsonb,  -- {name, registryNo, country, type, activity} (KYB için)
  co_address   jsonb,  -- şirket adresi (KYB için)
  kyc_status   text default 'pending',
  aml_status   text default 'pending',
  risk_status  text default 'pending',
  risk_score   int,
  submitted_at timestamptz default now(),
  created_at   timestamptz default now()
);

-- ============================================================
-- 2. UBOS — Gerçek Faydalanıcılar (KYB)
-- ============================================================
create table if not exists ubos (
  id             uuid primary key default gen_random_uuid(),
  client_id      uuid references clients(id) on delete cascade,
  full_name      text,
  ownership_pct  numeric,
  position       text,
  ownership_type text  -- 'direct' | 'indirect'
);

-- ============================================================
-- 3. DOCUMENTS — Belge metadata
-- ============================================================
create table if not exists documents (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid references clients(id) on delete cascade,
  doc_type    text,   -- 'identity'|'address'|'tax'|'registry'|'aoa'|'signature'|'cgs'
  file_path   text,   -- Supabase Storage path: clients/{client_id}/{doc_type}/{filename}
  file_name   text,
  file_size   text,
  status      text default 'pending',  -- 'pending'|'in_review'|'approved'|'rejected'
  available   boolean default true,    -- false = "bu belge mevcut değil"
  uploaded_at timestamptz default now()
);

-- ============================================================
-- 4. CHAT_MESSAGES — Müşteri ↔ Compliance mesajları
-- ============================================================
create table if not exists chat_messages (
  id           uuid primary key default gen_random_uuid(),
  client_id    uuid references clients(id) on delete cascade,
  sender_type  text check (sender_type in ('client','staff')),
  sender_name  text,
  text         text not null,
  created_at   timestamptz default now()
);

-- ============================================================
-- 5. INTERVIEWS — Görüşme takvimi
-- ============================================================
create table if not exists interviews (
  id             uuid primary key default gen_random_uuid(),
  client_id      uuid references clients(id) on delete cascade,
  client_name    text,
  interview_type text,
  scheduled_at   timestamptz,
  staff_name     text,
  status         text default 'to_schedule' check (status in ('to_schedule','planned','completed')),
  notes          text,
  created_at     timestamptz default now()
);

-- ============================================================
-- 6. REALTIME — chat_messages için realtime etkinleştir
-- ============================================================
alter publication supabase_realtime add table chat_messages;
alter publication supabase_realtime add table clients;

-- ============================================================
-- 7. RLS POLİTİKALARI
-- ============================================================

-- CLIENTS
alter table clients enable row level security;
-- Müşteri kendi kaydını okuyabilir / yazabilir
create policy "client_select" on clients for select using (auth.uid() = user_id);
create policy "client_insert" on clients for insert with check (auth.uid() = user_id);
create policy "client_update" on clients for update using (auth.uid() = user_id);
-- Admin tümünü okuyabilir / güncelleyebilir (email metadata'ya göre)
create policy "admin_all" on clients for all
  using (auth.jwt() ->> 'email' = current_setting('app.admin_email', true));

-- UBOS
alter table ubos enable row level security;
create policy "ubo_owner" on ubos for all
  using (client_id in (select id from clients where user_id = auth.uid()));
create policy "ubo_admin" on ubos for all
  using (auth.jwt() ->> 'email' = current_setting('app.admin_email', true));

-- DOCUMENTS
alter table documents enable row level security;
create policy "doc_owner" on documents for all
  using (client_id in (select id from clients where user_id = auth.uid()));
create policy "doc_admin" on documents for all
  using (auth.jwt() ->> 'email' = current_setting('app.admin_email', true));

-- CHAT_MESSAGES
alter table chat_messages enable row level security;
create policy "chat_owner" on chat_messages for all
  using (client_id in (select id from clients where user_id = auth.uid()));
create policy "chat_admin" on chat_messages for all
  using (auth.jwt() ->> 'email' = current_setting('app.admin_email', true));

-- INTERVIEWS
alter table interviews enable row level security;
create policy "int_owner" on interviews for select
  using (client_id in (select id from clients where user_id = auth.uid()));
create policy "int_admin" on interviews for all
  using (auth.jwt() ->> 'email' = current_setting('app.admin_email', true));

-- ============================================================
-- 8. ADMIN E-POSTA AYARI
-- ⚠️  BU KOMUTU MUTLAKA ÇALIŞTIR — admin RLS policy'leri buna bağlı
-- Admin e-postanı aşağıya yaz ve komutu SQL Editor'da çalıştır:
-- ============================================================
alter database postgres set app.admin_email = 'REDACTED_EMAIL';

-- ============================================================
-- 9. STORAGE — documents bucket
-- Dashboard > Storage > New Bucket > Name: "documents" > Private
-- Aşağıdaki policy'leri de çalıştır:
-- ============================================================

-- Müşteri kendi klasörüne belge yükleyebilir
insert into storage.policies (name, bucket_id, operation, definition)
values (
  'client_upload',
  'documents',
  'INSERT',
  '(auth.uid())::text = (storage.foldername(name))[1]'
) on conflict do nothing;

-- Müşteri kendi belgelerini indirebilir; admin hepsini görebilir
insert into storage.policies (name, bucket_id, operation, definition)
values (
  'client_or_admin_select',
  'documents',
  'SELECT',
  '(auth.uid())::text = (storage.foldername(name))[1]
   OR auth.jwt() ->> ''email'' = current_setting(''app.admin_email'', true)'
) on conflict do nothing;

-- ============================================================
-- 10. MEVCUT KURULUMDA RLS KONTROL
-- SQL Editor'da çalıştırarak policy'lerin çalıştığını doğrula:
-- ============================================================
-- SELECT current_setting('app.admin_email', true);   -- admin emaili dönmeli
-- SELECT * FROM pg_policies WHERE tablename = 'clients';  -- policy listesi
