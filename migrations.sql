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

-- ============================================================
-- 8. ADMINS TABLOSU — admin email listesi (current_setting yerine)
-- Supabase SQL Editor'da superuser yetkisi gerekmediği için
-- current_setting() yaklaşımı yerine bu tablo kullanılır.
-- ============================================================
create table if not exists admins (
  email text primary key
);

-- Admin emailini ekle
-- ⚠️  Kendi admin emailinle değiştir, bu satırı SQL Editor'da çalıştır:
-- insert into admins (email) values ('YOUR_ADMIN_EMAIL') on conflict do nothing;

-- CLIENTS
alter table clients enable row level security;
-- Müşteri kendi kaydını okuyabilir / yazabilir
create policy "client_select" on clients for select using (auth.uid() = user_id);
create policy "client_insert" on clients for insert with check (auth.uid() = user_id);
create policy "client_update" on clients for update using (auth.uid() = user_id);
-- Admin tümünü okuyabilir / güncelleyebilir (admins tablosuna göre)
create policy "admin_all" on clients for all
  using (auth.jwt() ->> 'email' in (select email from admins));

-- UBOS
alter table ubos enable row level security;
create policy "ubo_owner" on ubos for all
  using (client_id in (select id from clients where user_id = auth.uid()));
create policy "ubo_admin" on ubos for all
  using (auth.jwt() ->> 'email' in (select email from admins));

-- DOCUMENTS
alter table documents enable row level security;
create policy "doc_owner" on documents for all
  using (client_id in (select id from clients where user_id = auth.uid()));
create policy "doc_admin" on documents for all
  using (auth.jwt() ->> 'email' in (select email from admins));

-- CHAT_MESSAGES
alter table chat_messages enable row level security;
create policy "chat_owner" on chat_messages for all
  using (client_id in (select id from clients where user_id = auth.uid()));
create policy "chat_admin" on chat_messages for all
  using (auth.jwt() ->> 'email' in (select email from admins));

-- INTERVIEWS
alter table interviews enable row level security;
create policy "int_owner" on interviews for select
  using (client_id in (select id from clients where user_id = auth.uid()));
create policy "int_admin" on interviews for all
  using (auth.jwt() ->> 'email' in (select email from admins));

-- ============================================================
-- 9. STORAGE — documents bucket
-- Dashboard > Storage > New Bucket > Name: "documents" > Private
-- Aşağıdaki policy'leri Storage > Policies bölümünden ekle:
--   INSERT: (auth.uid())::text = (storage.foldername(name))[1]
--   SELECT: (auth.uid())::text = (storage.foldername(name))[1]
--           OR auth.jwt() ->> 'email' IN (SELECT email FROM admins)
-- ============================================================

-- ============================================================
-- 10. DOĞRULAMA
-- ============================================================
-- SELECT * FROM admins;                                 -- email listesi
-- SELECT * FROM pg_policies WHERE tablename = 'clients'; -- policy listesi

-- ============================================================
-- 11. AUDIT LOG — her INSERT/UPDATE/DELETE'i kaydeder
-- ============================================================
create table if not exists audit_logs (
  id         uuid primary key default gen_random_uuid(),
  table_name text,
  row_id     uuid,
  action     text,   -- 'INSERT' | 'UPDATE' | 'DELETE'
  old_data   jsonb,
  new_data   jsonb,
  actor      text,   -- JWT email veya null
  created_at timestamptz default now()
);

create or replace function log_changes() returns trigger language plpgsql security definer as $$
begin
  insert into audit_logs(table_name, row_id, action, old_data, new_data, actor)
  values (
    TG_TABLE_NAME,
    coalesce(NEW.id, OLD.id),
    TG_OP,
    case when TG_OP = 'DELETE' then to_jsonb(OLD) else null end,
    case when TG_OP <> 'DELETE' then to_jsonb(NEW) else null end,
    (current_setting('request.jwt.claims', true)::jsonb) ->> 'email'
  );
  return coalesce(NEW, OLD);
end;
$$;

create trigger clients_audit
  after insert or update or delete on clients
  for each row execute function log_changes();

create trigger documents_audit
  after insert or update or delete on documents
  for each row execute function log_changes();

alter table audit_logs enable row level security;
create policy "audit_admin" on audit_logs for select
  using (auth.jwt() ->> 'email' in (select email from admins));

-- ============================================================
-- 12. STATUS STATE MACHINE — geçersiz durum geçişini engeller
--   pending → in_review → approved | rejected
-- ============================================================
create or replace function validate_status_transition() returns trigger language plpgsql as $$
begin
  if OLD.status = NEW.status then return NEW; end if;
  if OLD.status = 'pending'   and NEW.status = 'in_review'  then return NEW; end if;
  if OLD.status = 'in_review' and NEW.status in ('approved','rejected') then return NEW; end if;
  raise exception 'Invalid status transition: % -> %', OLD.status, NEW.status;
end;
$$;

create trigger clients_status_machine
  before update of status on clients
  for each row execute function validate_status_transition();
