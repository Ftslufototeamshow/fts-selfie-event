-- FTS MySelfie v42 · per-event LUMOREX / VIMA Show toggle
-- Applied to production Supabase on 2026-09-21.
-- The existing fts-lumorex-feed already checks fts_lumorex_event_links_v1.enabled.

create or replace function public.fts_admin_get_lumorex_status_v2(
  p_admin_code text,
  p_event_token text
)
returns table(
  event_token text,
  enabled boolean,
  has_feed_token boolean
)
language plpgsql
security definer
set search_path='public'
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

  insert into public.fts_lumorex_event_links_v1(event_id,feed_token,enabled)
  values(v_event.id,public.fts_lumorex_new_token_v1(),true)
  on conflict(event_id) do nothing;

  return query
  select v_event.token,coalesce(l.enabled,false),coalesce(l.feed_token,'')<>''
  from public.fts_lumorex_event_links_v1 l
  where l.event_id=v_event.id;
end;
$$;

create or replace function public.fts_admin_set_lumorex_enabled_v2(
  p_admin_code text,
  p_event_token text,
  p_enabled boolean
)
returns boolean
language plpgsql
security definer
set search_path='public'
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

  insert into public.fts_lumorex_event_links_v1(event_id,feed_token,enabled)
  values(v_event.id,public.fts_lumorex_new_token_v1(),coalesce(p_enabled,false))
  on conflict(event_id) do update set enabled=excluded.enabled;

  return coalesce(p_enabled,false);
end;
$$;

create or replace function public.fts_admin_lumorex_status_all_v2(
  p_admin_code text
)
returns table(
  event_token text,
  enabled boolean
)
language plpgsql
security definer
set search_path='public'
as $$
begin
  if not public.fts_selfie_admin_ok(p_admin_code) then
    raise exception 'Ungültiger Gerätezugang/Admin-Code';
  end if;

  return query
  select e.token,coalesce(l.enabled,false)
  from public.fts_selfie_events e
  left join public.fts_lumorex_event_links_v1 l on l.event_id=e.id;
end;
$$;

grant execute on function public.fts_admin_get_lumorex_status_v2(text,text) to anon,authenticated;
grant execute on function public.fts_admin_set_lumorex_enabled_v2(text,text,boolean) to anon,authenticated;
grant execute on function public.fts_admin_lumorex_status_all_v2(text) to anon,authenticated;
