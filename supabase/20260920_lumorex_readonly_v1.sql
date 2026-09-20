-- MySelfie <-> LUMOREX read-only integration v1
-- Isolated to MySelfie tables. No Nexora objects are referenced or modified.

create table if not exists public.fts_lumorex_event_links_v1 (
  event_id uuid primary key references public.fts_selfie_events(id) on delete cascade,
  feed_token text not null unique,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.fts_lumorex_event_links_v1 enable row level security;
revoke all on public.fts_lumorex_event_links_v1 from anon, authenticated;

drop policy if exists "no direct browser access to lumorex links" on public.fts_lumorex_event_links_v1;
create policy "no direct browser access to lumorex links"
on public.fts_lumorex_event_links_v1
for all to anon, authenticated
using(false) with check(false);

create or replace function public.fts_lumorex_new_token_v1()
returns text
language sql
volatile
security definer
set search_path=public
as $$
  select 'lx_' || replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');
$$;

revoke all on function public.fts_lumorex_new_token_v1() from public;

insert into public.fts_lumorex_event_links_v1(event_id,feed_token)
select e.id, public.fts_lumorex_new_token_v1()
from public.fts_selfie_events e
where not exists (
  select 1 from public.fts_lumorex_event_links_v1 l where l.event_id=e.id
);

create or replace function public.fts_lumorex_create_link_for_event_v1()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  insert into public.fts_lumorex_event_links_v1(event_id,feed_token)
  values(new.id,public.fts_lumorex_new_token_v1())
  on conflict(event_id) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_fts_lumorex_event_link_v1 on public.fts_selfie_events;
create trigger trg_fts_lumorex_event_link_v1
after insert on public.fts_selfie_events
for each row execute function public.fts_lumorex_create_link_for_event_v1();

create or replace function public.fts_admin_get_lumorex_link_v1(
  p_admin_code text,
  p_event_token text
)
returns table(
  event_id uuid,
  event_token text,
  event_title text,
  feed_token text
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_event public.fts_selfie_events%rowtype;
begin
  if not public.fts_selfie_admin_ok(p_admin_code) then
    raise exception 'Ungültiger Gerätezugang/Admin-Code';
  end if;

  select e.* into v_event
  from public.fts_selfie_events e
  where e.token=p_event_token
     or upper(coalesce(e.short_code,''))=upper(p_event_token)
  limit 1;

  if not found then
    raise exception 'Event nicht gefunden';
  end if;

  insert into public.fts_lumorex_event_links_v1(event_id,feed_token)
  values(v_event.id,public.fts_lumorex_new_token_v1())
  on conflict on constraint fts_lumorex_event_links_v1_pkey do nothing;

  return query
  select v_event.id,v_event.token,v_event.title,l.feed_token
  from public.fts_lumorex_event_links_v1 l
  where l.event_id=v_event.id and l.enabled=true;
end;
$$;

revoke all on function public.fts_admin_get_lumorex_link_v1(text,text) from public;
grant execute on function public.fts_admin_get_lumorex_link_v1(text,text) to anon,authenticated;
