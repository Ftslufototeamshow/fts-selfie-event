-- FTS Selfie scan analytics + shareable customer reports v12

alter table public.fts_event_scans_v11
  add column if not exists device_type text not null default '',
  add column if not exists browser_language text not null default '',
  add column if not exists browser_timezone text not null default '',
  add column if not exists country_code text not null default '',
  add column if not exists session_id text not null default '';

create unique index if not exists fts_event_scans_v11_event_session_uidx
  on public.fts_event_scans_v11(event_token, session_id)
  where session_id <> '';

create table if not exists public.fts_event_report_shares_v12 (
  event_token text primary key,
  share_token text not null unique default gen_random_uuid()::text,
  enabled boolean not null default true,
  expires_at timestamptz not null default (now() + interval '90 days'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.fts_event_report_shares_v12 enable row level security;
revoke all on public.fts_event_report_shares_v12 from anon, authenticated;

create or replace function public.fts_admin_event_scan_stats_v12(
  p_admin_code text
)
returns table(
  event_token text,
  scan_count bigint,
  scan_today bigint,
  unique_sessions bigint
)
language sql
security definer
set search_path = public
as $$
  with allowed as (
    select d.event_token::text as event_token
    from public.fts_admin_dashboard_events(p_admin_code) d
  ),
  agg as (
    select s.event_token,
           count(*)::bigint as scan_count,
           count(*) filter (
             where timezone('Europe/Luxembourg',s.scanned_at)::date =
                   timezone('Europe/Luxembourg',now())::date
           )::bigint as scan_today,
           count(distinct nullif(s.session_id,''))::bigint as unique_sessions
    from public.fts_event_scans_v11 s
    group by s.event_token
  )
  select a.event_token,
         coalesce(g.scan_count,0),
         coalesce(g.scan_today,0),
         coalesce(g.unique_sessions,0)
  from allowed a
  left join agg g using(event_token);
$$;

create or replace function public.fts_admin_event_scan_daily_v12(
  p_admin_code text,
  p_event_token text
)
returns table(
  scan_day date,
  scan_count bigint,
  unique_sessions bigint
)
language plpgsql
security definer
set search_path = public
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
  select timezone('Europe/Luxembourg',s.scanned_at)::date as scan_day,
         count(*)::bigint,
         count(distinct nullif(s.session_id,''))::bigint
  from public.fts_event_scans_v11 s
  where s.event_token=p_event_token::text
  group by 1
  order by 1;
end;
$$;

create or replace function public.fts_admin_event_scan_hourly_v12(
  p_admin_code text,
  p_event_token text
)
returns table(
  scan_day date,
  scan_hour integer,
  scan_count bigint,
  unique_sessions bigint
)
language plpgsql
security definer
set search_path = public
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
  select timezone('Europe/Luxembourg',s.scanned_at)::date,
         extract(hour from timezone('Europe/Luxembourg',s.scanned_at))::integer,
         count(*)::bigint,
         count(distinct nullif(s.session_id,''))::bigint
  from public.fts_event_scans_v11 s
  where s.event_token=p_event_token::text
  group by 1,2
  order by 1,2;
end;
$$;

create or replace function public.fts_admin_event_scan_devices_v12(
  p_admin_code text,
  p_event_token text
)
returns table(
  device_type text,
  scan_count bigint
)
language plpgsql
security definer
set search_path = public
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
  select coalesce(nullif(s.device_type,''),'Unbekannt') as device_type,
         count(*)::bigint
  from public.fts_event_scans_v11 s
  where s.event_token=p_event_token::text
  group by 1
  order by 2 desc,1;
end;
$$;

create or replace function public.fts_admin_event_scan_countries_v12(
  p_admin_code text,
  p_event_token text
)
returns table(
  country_code text,
  scan_count bigint
)
language plpgsql
security definer
set search_path = public
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
  select coalesce(nullif(s.country_code,''),'XX') as country_code,
         count(*)::bigint
  from public.fts_event_scans_v11 s
  where s.event_token=p_event_token::text
  group by 1
  order by 2 desc,1;
end;
$$;

create or replace function public.fts_admin_event_scan_timeline_v12(
  p_admin_code text,
  p_event_token text,
  p_limit integer default 300
)
returns table(
  scanned_at timestamptz,
  device_type text,
  country_code text,
  browser_language text
)
language plpgsql
security definer
set search_path = public
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
  select s.scanned_at,
         coalesce(nullif(s.device_type,''),'Unbekannt'),
         coalesce(nullif(s.country_code,''),'XX'),
         coalesce(nullif(s.browser_language,''),'')
  from public.fts_event_scans_v11 s
  where s.event_token=p_event_token::text
  order by s.scanned_at desc
  limit greatest(1,least(coalesce(p_limit,300),1000));
end;
$$;

create or replace function public.fts_admin_get_or_create_report_share_v12(
  p_admin_code text,
  p_event_token text
)
returns table(
  share_token text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.fts_admin_dashboard_events(p_admin_code) d
    where d.event_token::text = p_event_token::text
  ) then
    raise exception 'Not authorized for this event';
  end if;

  insert into public.fts_event_report_shares_v12(event_token,enabled,expires_at,updated_at)
  values(p_event_token::text,true,now()+interval '90 days',now())
  on conflict(event_token) do update set
    enabled=true,
    expires_at=case
      when public.fts_event_report_shares_v12.expires_at < now()+interval '30 days'
      then now()+interval '90 days'
      else public.fts_event_report_shares_v12.expires_at
    end,
    updated_at=now();

  return query
  select r.share_token,r.expires_at
  from public.fts_event_report_shares_v12 r
  where r.event_token=p_event_token::text;
end;
$$;

create or replace function public.fts_get_shared_event_report_v12(
  p_share_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event_token text;
  v_event public.fts_selfie_events%rowtype;
  v_result jsonb;
begin
  select r.event_token into v_event_token
  from public.fts_event_report_shares_v12 r
  where r.share_token=p_share_token
    and r.enabled=true
    and r.expires_at>now()
  limit 1;

  if v_event_token is null then
    return null;
  end if;

  select * into v_event
  from public.fts_selfie_events e
  where e.token=v_event_token
  limit 1;

  if not found then
    return null;
  end if;

  select jsonb_build_object(
    'title',v_event.title,
    'subtitle',coalesce(v_event.subtitle,''),
    'location',coalesce(v_event.location,''),
    'event_days',coalesce(v_event.event_days,'[]'::jsonb),
    'generated_at',now(),
    'scan_tracking_started_at','2026-09-20T02:13:54Z',
    'summary',jsonb_build_object(
      'selfies',(
        select count(*) from public.fts_selfie_photos p
        where p.event_id=v_event.id and p.is_test=false and p.trashed_at is null
      ),
      'qr_scans',(
        select count(*) from public.fts_event_scans_v11 s where s.event_token=v_event_token
      ),
      'unique_sessions',(
        select count(distinct nullif(s.session_id,'')) from public.fts_event_scans_v11 s where s.event_token=v_event_token
      )
    ),
    'daily',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'day',d.day_date::text,
          'selfies',(
            select count(*) from public.fts_selfie_photos p
            where p.event_id=v_event.id and p.is_test=false and p.trashed_at is null and p.event_day=d.day_date
          ),
          'qr_scans',(
            select count(*) from public.fts_event_scans_v11 s
            where s.event_token=v_event_token and timezone('Europe/Luxembourg',s.scanned_at)::date=d.day_date
          ),
          'unique_sessions',(
            select count(distinct nullif(s.session_id,'')) from public.fts_event_scans_v11 s
            where s.event_token=v_event_token and timezone('Europe/Luxembourg',s.scanned_at)::date=d.day_date
          )
        ) order by d.day_date
      )
      from (
        select distinct q.day_date
        from (
          select jsonb_array_elements_text(coalesce(v_event.event_days,'[]'::jsonb))::date as day_date
          union
          select p.event_day as day_date
          from public.fts_selfie_photos p
          where p.event_id=v_event.id and p.event_day is not null
          union
          select timezone('Europe/Luxembourg',s.scanned_at)::date as day_date
          from public.fts_event_scans_v11 s
          where s.event_token=v_event_token
        ) q
        where q.day_date is not null
      ) d
    ),'[]'::jsonb),
    'hourly',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'day',q.scan_day::text,
          'hour',q.scan_hour,
          'qr_scans',q.qr_scans,
          'unique_sessions',q.unique_sessions
        ) order by q.scan_day,q.scan_hour
      )
      from (
        select timezone('Europe/Luxembourg',s.scanned_at)::date as scan_day,
               extract(hour from timezone('Europe/Luxembourg',s.scanned_at))::integer as scan_hour,
               count(*)::bigint as qr_scans,
               count(distinct nullif(s.session_id,''))::bigint as unique_sessions
        from public.fts_event_scans_v11 s
        where s.event_token=v_event_token
        group by 1,2
      ) q
    ),'[]'::jsonb),
    'devices',coalesce((
      select jsonb_agg(
        jsonb_build_object('device',q.device_type,'count',q.cnt)
        order by q.cnt desc,q.device_type
      )
      from (
        select coalesce(nullif(s.device_type,''),'Unbekannt') as device_type,
               count(*)::bigint as cnt
        from public.fts_event_scans_v11 s
        where s.event_token=v_event_token
        group by 1
      ) q
    ),'[]'::jsonb),
    'countries',coalesce((
      select jsonb_agg(
        jsonb_build_object('country',q.country_code,'count',q.cnt)
        order by q.cnt desc,q.country_code
      )
      from (
        select coalesce(nullif(s.country_code,''),'XX') as country_code,
               count(*)::bigint as cnt
        from public.fts_event_scans_v11 s
        where s.event_token=v_event_token
        group by 1
      ) q
    ),'[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.fts_admin_event_scan_stats_v12(text) from public;
revoke all on function public.fts_admin_event_scan_daily_v12(text,text) from public;
revoke all on function public.fts_admin_event_scan_hourly_v12(text,text) from public;
revoke all on function public.fts_admin_event_scan_devices_v12(text,text) from public;
revoke all on function public.fts_admin_event_scan_countries_v12(text,text) from public;
revoke all on function public.fts_admin_event_scan_timeline_v12(text,text,integer) from public;
revoke all on function public.fts_admin_get_or_create_report_share_v12(text,text) from public;
revoke all on function public.fts_get_shared_event_report_v12(text) from public;

grant execute on function public.fts_admin_event_scan_stats_v12(text) to anon, authenticated;
grant execute on function public.fts_admin_event_scan_daily_v12(text,text) to anon, authenticated;
grant execute on function public.fts_admin_event_scan_hourly_v12(text,text) to anon, authenticated;
grant execute on function public.fts_admin_event_scan_devices_v12(text,text) to anon, authenticated;
grant execute on function public.fts_admin_event_scan_countries_v12(text,text) to anon, authenticated;
grant execute on function public.fts_admin_event_scan_timeline_v12(text,text,integer) to anon, authenticated;
grant execute on function public.fts_admin_get_or_create_report_share_v12(text,text) to anon, authenticated;
grant execute on function public.fts_get_shared_event_report_v12(text) to anon, authenticated;
