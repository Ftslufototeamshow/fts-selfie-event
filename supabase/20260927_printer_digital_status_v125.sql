-- Build 125 · Digital QR + login metadata/avatar
alter table public.fts_selfie_printer_users_v72 add column if not exists avatar_path text;

create table if not exists public.fts_selfie_printer_digital_downloads_v125 (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  event_id uuid not null references public.fts_selfie_events(id) on delete cascade,
  created_by uuid references public.fts_selfie_printer_users_v72(id) on delete set null,
  bucket text not null default 'fts-selfie-digital',
  storage_path text not null,
  file_name text not null,
  mime_type text not null default 'image/jpeg',
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now()+interval '7 days'),
  download_count integer not null default 0,
  last_downloaded_at timestamptz
);
alter table public.fts_selfie_printer_digital_downloads_v125 enable row level security;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('fts-selfie-digital','fts-selfie-digital',false,10485760,array['image/jpeg','image/png']::text[])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

-- Production also contains fts_printer_login_v125 and fts_printer_validate_session_v125.
-- They return logged_in_at and avatar_path while preserving the v72 authentication rules.
