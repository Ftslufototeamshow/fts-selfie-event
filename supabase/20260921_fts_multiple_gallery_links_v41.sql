-- FTS MySelfie v41 · multiple post-event gallery links
-- Applied to production Supabase on 2026-09-21.

alter table public.fts_event_lifecycle_v11
  add column if not exists gallery_links jsonb not null default '[]'::jsonb;

update public.fts_event_lifecycle_v11
set gallery_links = jsonb_build_array(
  jsonb_build_object('label','Selfies ansehen','url',gallery_url)
)
where coalesce(trim(gallery_url),'') <> ''
  and (gallery_links is null or gallery_links = '[]'::jsonb);

create or replace function public.fts_get_event_lifecycle_v41(p_event_token text)
returns table(
  schedule jsonb,
  gallery_url text,
  gallery_links jsonb,
  gallery_available_at text,
  link_expires_at text,
  test_days_before integer
)
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_token text;
begin
  select e.event_token::text into v_token
  from public.fts_get_event(p_event_token) e
  limit 1;

  if v_token is null then
    return;
  end if;

  return query
  select
    l.schedule,
    case
      when nullif(l.gallery_available_at,'') is not null
       and timezone('Europe/Luxembourg',now()) >= l.gallery_available_at::timestamp
      then l.gallery_url
      else ''
    end,
    case
      when nullif(l.gallery_available_at,'') is not null
       and timezone('Europe/Luxembourg',now()) >= l.gallery_available_at::timestamp
      then coalesce(l.gallery_links,'[]'::jsonb)
      else '[]'::jsonb
    end,
    l.gallery_available_at,
    l.link_expires_at,
    l.test_days_before
  from public.fts_event_lifecycle_v11 l
  where l.event_token=v_token;
end;
$$;

create or replace function public.fts_admin_get_event_lifecycle_v41(
  p_admin_code text,
  p_event_token text
)
returns table(
  schedule jsonb,
  gallery_url text,
  gallery_links jsonb,
  gallery_available_at text,
  link_expires_at text,
  test_days_before integer
)
language plpgsql
security definer
set search_path='public'
as $$
begin
  if not exists (
    select 1
    from public.fts_admin_dashboard_events(p_admin_code) d
    where d.event_token::text = p_event_token::text
  ) then
    raise exception 'Not authorized for this event';
  end if;

  return query
  select
    l.schedule,
    l.gallery_url,
    coalesce(l.gallery_links,'[]'::jsonb),
    l.gallery_available_at,
    l.link_expires_at,
    l.test_days_before
  from public.fts_event_lifecycle_v11 l
  where l.event_token=p_event_token::text;
end;
$$;

create or replace function public.fts_admin_set_event_lifecycle_v41(
  p_admin_code text,
  p_event_token text,
  p_schedule jsonb,
  p_gallery_url text default '',
  p_gallery_links jsonb default '[]'::jsonb,
  p_gallery_available_at text default '',
  p_link_expires_at text default '',
  p_test_days_before integer default 0
)
returns void
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_links jsonb := coalesce(p_gallery_links,'[]'::jsonb);
begin
  if not exists (
    select 1
    from public.fts_admin_dashboard_events(p_admin_code) d
    where d.event_token::text = p_event_token::text
  ) then
    raise exception 'Not authorized for this event';
  end if;

  if jsonb_typeof(v_links) <> 'array' then
    raise exception 'gallery_links must be an array';
  end if;

  if jsonb_array_length(v_links) > 50 then
    raise exception 'Too many gallery links';
  end if;

  insert into public.fts_event_lifecycle_v11(
    event_token,schedule,gallery_url,gallery_links,gallery_available_at,link_expires_at,test_days_before,updated_at
  )
  values(
    p_event_token::text,
    coalesce(p_schedule,'[]'::jsonb),
    coalesce(p_gallery_url,''),
    v_links,
    coalesce(p_gallery_available_at,''),
    coalesce(p_link_expires_at,''),
    greatest(0,coalesce(p_test_days_before,0)),
    now()
  )
  on conflict(event_token) do update set
    schedule=excluded.schedule,
    gallery_url=excluded.gallery_url,
    gallery_links=excluded.gallery_links,
    gallery_available_at=excluded.gallery_available_at,
    link_expires_at=excluded.link_expires_at,
    test_days_before=excluded.test_days_before,
    updated_at=now();
end;
$$;

grant execute on function public.fts_get_event_lifecycle_v41(text) to anon,authenticated;
grant execute on function public.fts_admin_get_event_lifecycle_v41(text,text) to anon,authenticated;
grant execute on function public.fts_admin_set_event_lifecycle_v41(text,text,jsonb,text,jsonb,text,text,integer) to anon,authenticated;
