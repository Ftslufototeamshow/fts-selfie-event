-- FTS Selfie Event v151
-- Event-driven Print Station refresh signal. Exposes only a revision counter/timestamp,
-- never order, customer, payment or photo data.

create table if not exists public.fts_selfie_print_signal_v150 (
  id integer primary key check (id=1),
  revision bigint not null default 0,
  changed_at timestamptz not null default now()
);

insert into public.fts_selfie_print_signal_v150(id,revision,changed_at)
values(1,0,now())
on conflict(id) do nothing;

alter table public.fts_selfie_print_signal_v150 enable row level security;
revoke all on table public.fts_selfie_print_signal_v150 from public,anon,authenticated;
grant select on table public.fts_selfie_print_signal_v150 to anon,authenticated;

drop policy if exists fts_print_signal_read_v150 on public.fts_selfie_print_signal_v150;
create policy fts_print_signal_read_v150
on public.fts_selfie_print_signal_v150
for select to anon,authenticated
using (id=1);

create or replace function public.fts_touch_print_signal_v150()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  update public.fts_selfie_print_signal_v150
  set revision=revision+1,changed_at=now()
  where id=1;
  return null;
end;
$$;

revoke all on function public.fts_touch_print_signal_v150() from public,anon,authenticated;

do $$
declare t text;
begin
  foreach t in array array[
    'fts_selfie_print_orders',
    'fts_selfie_print_jobs',
    'fts_selfie_payments',
    'fts_selfie_print_settings'
  ]
  loop
    if to_regclass('public.'||t) is not null then
      execute format('drop trigger if exists fts_print_signal_v150 on public.%I',t);
      execute format(
        'create trigger fts_print_signal_v150 after insert or update or delete on public.%I for each statement execute function public.fts_touch_print_signal_v150()',
        t
      );
    end if;
  end loop;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public'
      and tablename='fts_selfie_print_signal_v150'
  ) then
    alter publication supabase_realtime add table public.fts_selfie_print_signal_v150;
  end if;
end $$;
