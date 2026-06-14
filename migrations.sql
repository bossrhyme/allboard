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

-- RLS: admins tablosu — giriş yapmış kullanıcılar okuyabilir
-- (diğer tablolardaki "in (select email from admins)" policy'lerinin çalışması için gerekli)
alter table admins enable row level security;
create policy "admins_read_authenticated" on admins
  for select using (auth.role() = 'authenticated');
-- INSERT/UPDATE/DELETE: sadece service_role erişebilir (policy yok = yasak)

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

-- ============================================================
-- 13. PRE_REGISTRATIONS — Ön başvuru formu
-- ============================================================
create table if not exists pre_registrations (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  email         text not null,
  phone         text,
  account_type  text check (account_type in ('individual','corporate')),
  platforms     jsonb,    -- ['OKX','Binance',...]
  doc_checklist jsonb,    -- {identity:true, address:false, ...}
  doc_score     int,      -- kaç belgesi mevcut
  notes         text,
  status        text default 'pending' check (status in ('pending','approved','rejected')),
  user_id       uuid,     -- kullanıcı oluşturulunca set edilir
  created_at    timestamptz default now()
);

alter table pre_registrations enable row level security;

-- Herkes INSERT yapabilir (form göndermek için auth gerekmez)
create policy "prereg_public_insert" on pre_registrations
  for insert with check (true);

-- Sadece admin okuyabilir/güncelleyebilir
create policy "prereg_admin_all" on pre_registrations
  for all using (auth.jwt() ->> 'email' in (select email from admins));

-- ============================================================
-- 14. GÜVENLİK & KVKK/GDPR UYUM PAKETİ
-- ⚠️  Bu bloğu Supabase SQL Editor'da çalıştır
-- ============================================================

-- 14a. Admins tablosu — sadece kendi kaydını okuyabilsin
--      (diğer tablolardaki "in (select email from admins)" policy'leri çalışsın diye)
drop policy if exists "admins_read_authenticated" on admins;
create policy "admins_read_self" on admins
  for select using (auth.jwt() ->> 'email' = email);

-- 14b. PII maskeleme fonksiyonu
create or replace function mask_pii(data jsonb) returns jsonb
language plpgsql security definer as $$
begin
  if data is null then return null; end if;
  if data ? 'personal' then
    data = jsonb_set(data, '{personal,nationalId}',  '"[GİZLİ]"'::jsonb, false);
    data = jsonb_set(data, '{personal,phone}',       '"[GİZLİ]"'::jsonb, false);
    data = jsonb_set(data, '{personal,dob}',         '"[GİZLİ]"'::jsonb, false);
    data = jsonb_set(data, '{personal,email}',       '"[GİZLİ]"'::jsonb, false);
    data = jsonb_set(data, '{personal,firstName}',   '"[GİZLİ]"'::jsonb, false);
    data = jsonb_set(data, '{personal,lastName}',    '"[GİZLİ]"'::jsonb, false);
  end if;
  if data ? 'address' then
    data = jsonb_set(data, '{address,street}',       '"[GİZLİ]"'::jsonb, false);
    data = jsonb_set(data, '{address,postalCode}',   '"[GİZLİ]"'::jsonb, false);
  end if;
  if data ? 'pep' then
    data = jsonb_set(data, '{pep,sourceOfFunds}',    '"[GİZLİ]"'::jsonb, false);
    data = jsonb_set(data, '{pep,monthlyVolume}',    '"[GİZLİ]"'::jsonb, false);
  end if;
  return data;
end;
$$;

-- 14c. Audit trigger — PII maskelenmiş hâliyle kaydet (KVKK Md.12 / GDPR Art.32)
create or replace function log_changes() returns trigger
language plpgsql security definer as $$
begin
  insert into audit_logs(table_name, row_id, action, old_data, new_data, actor)
  values (
    TG_TABLE_NAME,
    coalesce(NEW.id, OLD.id),
    TG_OP,
    case when TG_OP = 'DELETE' then mask_pii(to_jsonb(OLD)) else null end,
    case when TG_OP <> 'DELETE' then mask_pii(to_jsonb(NEW)) else null end,
    (current_setting('request.jwt.claims', true)::jsonb) ->> 'email'
  );
  return coalesce(NEW, OLD);
end;
$$;

-- 14d. Audit log veri saklama — 90 günden eski kayıtları sil (GDPR Art.5(1)(e))
-- Önce pg_cron extension'ını aktif et: Dashboard > Extensions > pg_cron
-- Sonra aşağıdaki satırı çalıştır:
-- select cron.schedule('delete-old-audit-logs','0 3 * * *',
--   $$delete from audit_logs where created_at < now() - interval ''90 days''$$);

-- 14e. Pre-registration spam koruması — aynı email 24 saatte max 3 başvuru
create or replace function check_prereg_rate_limit()
returns trigger language plpgsql as $$
begin
  if (select count(*) from pre_registrations
      where email = NEW.email
      and created_at > now() - interval '24 hours') >= 3 then
    raise exception 'Çok fazla başvuru. Lütfen 24 saat sonra tekrar deneyin.';
  end if;
  return NEW;
end;
$$;

drop trigger if exists prereg_rate_limit on pre_registrations;
create trigger prereg_rate_limit
  before insert on pre_registrations
  for each row execute function check_prereg_rate_limit();

-- ============================================================
-- 15. RLS DOĞRULAMA & ZORLAMA (FORCE) — veri sızıntısı denetimi
-- ⚠️  Bu bloğu Supabase SQL Editor'da çalıştır.
-- En yaygın Supabase sızıntısı: bir tabloda RLS'in kapalı kalması.
-- Aşağıdaki sorgu RLS'i KAPALI olan tüm public tabloları listeler.
-- Sonuç BOŞ gelmelidir. Satır dönerse o tablo herkese açıktır!
-- ============================================================
-- 15a. Denetim: RLS kapalı olan tabloları bul
select tablename, rowsecurity
from pg_tables
where schemaname = 'public' and rowsecurity = false;
-- (Boş sonuç = güvenli. Satır gelirse o tabloya RLS ekle.)

-- 15b. FORCE RLS — tablo sahibi (postgres/service_role hariç) bile
--      politikalara tabi olur. Yetkisiz erişime karşı ekstra kalkan.
alter table clients          force row level security;
alter table ubos             force row level security;
alter table documents        force row level security;
alter table chat_messages    force row level security;
alter table interviews       force row level security;
alter table audit_logs       force row level security;
alter table pre_registrations force row level security;
alter table admins           force row level security;

-- 15c. Denetim: politikası OLMAYAN ama RLS açık tabloları bul
--      (RLS açık + politika yok = o tablo tamamen kilitli, yanlışlıkla
--       erişim engellenmiş olabilir; kontrol et)
select t.tablename
from pg_tables t
left join pg_policies p on p.schemaname = t.schemaname and p.tablename = t.tablename
where t.schemaname = 'public' and t.rowsecurity = true and p.policyname is null
group by t.tablename;

-- 15d. Tüm aktif politikaları listele (gözden geçirme için)
-- select tablename, policyname, cmd, qual from pg_policies
--   where schemaname = 'public' order by tablename, cmd;

-- ============================================================
-- 16. KVKK/GDPR — SİLME HAKKI (Right to Erasure)
-- Bir müşterinin tüm verisini (belgeler hariç storage) siler.
-- Storage dosyaları ayrıca Dashboard veya API ile silinmelidir.
-- Kullanım: select erase_client('<client_uuid>');
-- ============================================================
create or replace function erase_client(p_client_id uuid)
returns void language plpgsql security definer as $$
begin
  delete from chat_messages where client_id = p_client_id;
  delete from interviews    where client_id = p_client_id;
  delete from documents     where client_id = p_client_id;
  delete from ubos          where client_id = p_client_id;
  delete from clients       where id = p_client_id;
end;
$$;
-- Sadece adminler çalıştırabilsin (security definer ile çalışır ama
-- çağrı yetkisini admin'e kısıtlamak için EXECUTE iznini ayarla):
revoke all on function erase_client(uuid) from public, anon, authenticated;
