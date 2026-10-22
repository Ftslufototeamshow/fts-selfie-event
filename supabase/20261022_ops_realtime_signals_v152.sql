-- FTS Selfie Event v152
-- Minimal event-driven signals for Cockpit/poster and mobile printer admin.
-- Signals contain revision/timestamp only; no customer, payment or photo data.

create table if not exists public.fts_selfie_ops_signal_v152 (
  id integer primary key check (id=1),
  revision bigint not null default 0,
  changed_at timestamptz not null default now()
);

insert into public.fts_selfie_ops_signal_v152(id,revision,changed_at)
values(1,0,now())
on conflict(id) do nothing;

alter table public.fts_selfie_ops_signal_v152 enable row level security;
revoke all on table public.fts_selfie_ops_signal_v152 from public,anon,authenticated;
grant select on table public.fts_selfie_ops_signal_v152 to anon,authenticated;

drop policy if exists fts_ops_signal_read_v152 on public.fts_selfie_ops_signal_v152;
create policy fts_ops_signal_read_v152
on public.fts_selfie_ops_signal_v152
for select to anon,authenticated
using (id=1);

create or replace function public.fts_touch_ops_signal_v152()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  update public.fts_selfie_ops_signal_v152
  set revision=revision+1,changed_at=now()
  where id=1;
  return null;
end;
$$;

revoke all on function public.fts_touch_ops_signal_v152() from public,anon,authenticated;

do $$
declare t text;
begin
  foreach t in array array[
    'fts_selfie_events',
    'fts_selfie_photos',
    'fts_lumorex_event_links_v1',
    'fts_selfie_printer_issue_requests_v127'
  ]
  loop
    if to_regclass('public.'||t) is not null then
      execute format('drop trigger if exists fts_ops_signal_v152 on public.%I',t);
      execute format(
        'create trigger fts_ops_signal_v152 after insert or update or delete on public.%I for each statement execute function public.fts_touch_ops_signal_v152()',
        t
      );
    end if;
  end loop;
end $$;

create table if not exists public.fts_selfie_printer_admin_signal_v152 (
  id integer primary key check (id=1),
  revision bigint not null default 0,
  changed_at timestamptz not null default now()
);

insert into public.fts_selfie_printer_admin_signal_v152(id,revision,changed_at)
values(1,0,now())
on conflict(id) do nothing;

alter table public.fts_selfie_printer_admin_signal_v152 enable row level security;
revoke all on table public.fts_selfie_printer_admin_signal_v152 from public,anon,authenticated;
grant select on table public.fts_selfie_printer_admin_signal_v152 to anon,authenticated;

drop policy if exists fts_printer_admin_signal_read_v152 on public.fts_selfie_printer_admin_signal_v152;
create policy fts_printer_admin_signal_read_v152
on public.fts_selfie_printer_admin_signal_v152
for select to anon,authenticated
using (id=1);

create or replace function public.fts_touch_printer_admin_signal_v152()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  update public.fts_selfie_printer_admin_signal_v152
  set revision=revision+1,changed_at=now()
  where id=1;
  return null;
end;
$$;

revoke all on function public.fts_touch_printer_admin_signal_v152() from public,anon,authenticated;

do $$
declare t text;
begin
  foreach t in array array[
    'fts_selfie_printer_issue_requests_v127',
    'fts_selfie_printer_issue_messages_v127',
    'fts_selfie_printer_consumables_v81',
    'fts_selfie_printer_local_jobs_v80',
    'fts_selfie_print_orders',
    'fts_selfie_print_jobs',
    'fts_selfie_payments',
    'fts_selfie_print_settings'
  ]
  loop
    if to_regclass('public.'||t) is not null then
      execute format('drop trigger if exists fts_printer_admin_signal_v152 on public.%I',t);
      execute format(
        'create trigger fts_printer_admin_signal_v152 after insert or update or delete on public.%I for each statement execute function public.fts_touch_printer_admin_signal_v152()',
        t
      );
    end if;
  end loop;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='fts_selfie_ops_signal_v152'
  ) then
    alter publication supabase_realtime add table public.fts_selfie_ops_signal_v152;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='fts_selfie_printer_admin_signal_v152'
  ) then
    alter publication supabase_realtime add table public.fts_selfie_printer_admin_signal_v152;
  end if;
end $$;
