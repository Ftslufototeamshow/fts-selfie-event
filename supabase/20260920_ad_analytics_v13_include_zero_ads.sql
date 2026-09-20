-- Include configured ads with zero activity in v13 reports.

create or replace function public.fts_admin_event_ad_stats_v13(
  p_admin_code text,
  p_event_token text
)
returns table(
  ad_key text,
  ad_name text,
  views bigint,
  clicks bigint,
  unique_clickers bigint,
  click_rate numeric
)
language plpgsql
security definer
set search_path=public
as $$
declare
  v_token text;
begin
  select d.event_token::text into v_token
  from public.fts_admin_dashboard_events(p_admin_code) d
  where d.event_token::text=p_event_token::text
  limit 1;

  if v_token is null then
    raise exception 'Not authorized for this event';
  end if;

  return query
  with configured as (
    select trim(x->>'path') as ad_key,
           left(coalesce(nullif(trim(x->>'name'),''),'Werbung'),100) as ad_name
    from public.fts_selfie_events e,
         jsonb_array_elements(coalesce(e.ad_items,'[]'::jsonb)) x
    where e.token=v_token and coalesce(trim(x->>'path'),'')<>''
  ),
  observed as (
    select a.ad_key,
           coalesce(nullif(max(a.ad_name) filter(where a.ad_name<>''),''),'Werbung') as ad_name
    from public.fts_event_ad_events_v13 a
    where a.event_token=v_token
    group by a.ad_key
  ),
  keys as (
    select ad_key,max(ad_name) as ad_name
    from (
      select * from configured
      union all
      select * from observed
    ) q
    group by ad_key
  ),
  agg as (
    select
      a.ad_key,
      count(*) filter(where a.action='view')::bigint as views,
      count(*) filter(where a.action='click')::bigint as clicks,
      count(distinct nullif(a.session_id,'')) filter(where a.action='click')::bigint as unique_clickers
    from public.fts_event_ad_events_v13 a
    where a.event_token=v_token
    group by a.ad_key
  )
  select
    k.ad_key,
    k.ad_name,
    coalesce(g.views,0)::bigint,
    coalesce(g.clicks,0)::bigint,
    coalesce(g.unique_clickers,0)::bigint,
    case when coalesce(g.views,0)>0
      then round((coalesce(g.unique_clickers,0)::numeric/g.views::numeric)*100,1)
      else 0
    end
  from keys k
  left join agg g using(ad_key)
  order by coalesce(g.clicks,0) desc,coalesce(g.views,0) desc,k.ad_name;
end;
$$;

create or replace function public.fts_get_shared_event_report_v13(
  p_share_token text
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_event_token text;
  v_base jsonb;
  v_ads jsonb;
  v_started_at timestamptz;
begin
  v_base := public.fts_get_shared_event_report_v12(p_share_token);
  if v_base is null then return null; end if;

  select r.event_token into v_event_token
  from public.fts_event_report_shares_v12 r
  where r.share_token=p_share_token
    and r.enabled=true
    and r.expires_at>now()
  limit 1;

  select m.started_at into v_started_at
  from public.fts_analytics_meta_v13 m
  where m.key='ad_tracking';

  with configured as (
    select trim(x->>'path') as ad_key,
           left(coalesce(nullif(trim(x->>'name'),''),'Werbung'),100) as ad_name
    from public.fts_selfie_events e,
         jsonb_array_elements(coalesce(e.ad_items,'[]'::jsonb)) x
    where e.token=v_event_token and coalesce(trim(x->>'path'),'')<>''
  ),
  observed as (
    select a.ad_key,
           coalesce(nullif(max(a.ad_name) filter(where a.ad_name<>''),''),'Werbung') as ad_name
    from public.fts_event_ad_events_v13 a
    where a.event_token=v_event_token
    group by a.ad_key
  ),
  keys as (
    select ad_key,max(ad_name) as ad_name
    from (
      select * from configured
      union all
      select * from observed
    ) q
    group by ad_key
  ),
  agg as (
    select
      a.ad_key,
      count(*) filter(where a.action='view')::bigint as views,
      count(*) filter(where a.action='click')::bigint as clicks,
      count(distinct nullif(a.session_id,'')) filter(where a.action='click')::bigint as unique_clickers
    from public.fts_event_ad_events_v13 a
    where a.event_token=v_event_token
    group by a.ad_key
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'ad_key',k.ad_key,
      'name',k.ad_name,
      'views',coalesce(g.views,0),
      'clicks',coalesce(g.clicks,0),
      'unique_clickers',coalesce(g.unique_clickers,0),
      'click_rate',case when coalesce(g.views,0)>0
        then round((coalesce(g.unique_clickers,0)::numeric/g.views::numeric)*100,1)
        else 0 end
    ) order by coalesce(g.clicks,0) desc,coalesce(g.views,0) desc,k.ad_name
  ),'[]'::jsonb)
  into v_ads
  from keys k
  left join agg g using(ad_key);

  return v_base
    || jsonb_build_object(
      'ad_tracking_started_at',v_started_at,
      'ads',v_ads
    );
end;
$$;
