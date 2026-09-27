-- Build 126 · administrator-approved misprints, safe replacement, staff daily report
create table if not exists public.fts_selfie_printer_misprints_v126 (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.fts_selfie_events(id) on delete cascade,
  target_kind text not null check (target_kind in ('SELFIE','LOCAL')),
  target_unit_id uuid not null,
  target_job_id uuid not null,
  operator_user_id uuid references public.fts_selfie_printer_users_v72(id) on delete set null,
  approved_by uuid not null references public.fts_selfie_printer_users_v72(id) on delete restrict,
  reason_code text not null,
  reason_note text,
  replacement_unit_id uuid,
  replacement_local_job_id uuid,
  created_at timestamptz not null default now(),
  unique(target_kind,target_unit_id)
);
create index if not exists fts_selfie_printer_misprints_v126_event_created_idx
  on public.fts_selfie_printer_misprints_v126(event_id,created_at desc);
alter table public.fts_selfie_printer_misprints_v126 enable row level security;

-- Production functions deployed with Build 126:
-- fts_printer_verify_admin_v126
-- fts_printer_selfie_misprint_candidates_v126
-- fts_printer_admin_resolve_selfie_v126
-- fts_printer_admin_local_misprint_v126
-- fts_printer_admin_local_not_printed_v126
-- fts_printer_staff_daily_v126
-- They verify the current printer session, require a valid enabled printer_admin
-- and personal admin code for resolutions, audit operator/admin/reason, prevent
-- duplicate replacements per physical unit, and expose staff totals only to admins.
