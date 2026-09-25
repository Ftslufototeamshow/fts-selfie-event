-- FTS Selfie Event v97
-- Remove the artificial 12-banner cap. Events may store any practical number
-- of advertising flyers/banners; browser/storage limits remain the only bounds.

create or replace function public.fts_admin_set_event_ads_v2(
  p_admin_code text,
  p_event_token text,
  p_ads_enabled boolean,
  p_ad_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_real_token text;
  v_items jsonb := coalesce(p_ad_items,'[]'::jsonb);
  v_clean jsonb;
begin
  if not public.fts_selfie_admin_ok(p_admin_code) then
    raise exception 'Ungültiger Gerätezugang/Admin-Code';
  end if;

  select e.token into v_real_token
  from public.fts_selfie_events e
  where e.token=p_event_token
     or (e.short_code is not null and upper(e.short_code)=upper(p_event_token))
  limit 1;

  if v_real_token is null then raise exception 'Event nicht gefunden'; end if;
  if jsonb_typeof(v_items)<>'array' then v_items:='[]'::jsonb; end if;

  if exists(
    select 1 from jsonb_array_elements(v_items) x
    where coalesce(trim(x->>'path'),'')=''
  ) then
    raise exception 'Ungültiger Banner-Pfad';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'path', trim(x->>'path'),
    'name', left(coalesce(nullif(trim(x->>'name'),''),'Werbung'),100),
    'link', left(coalesce(trim(x->>'link'),''),500),
    'active', case when lower(coalesce(x->>'active','true'))='false' then false else true end,
    'start_date', case when coalesce(x->>'start_date','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then x->>'start_date' else '' end,
    'end_date', case when coalesce(x->>'end_date','') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then x->>'end_date' else '' end
  ) order by ord),'[]'::jsonb)
  into v_clean
  from jsonb_array_elements(v_items) with ordinality as t(x,ord);

  update public.fts_selfie_events e
  set ads_enabled=coalesce(p_ads_enabled,false),
      ad_items=v_clean
  where e.token=v_real_token;

  return jsonb_build_object(
    'ok',true,
    'event_token',v_real_token,
    'ads_enabled',coalesce(p_ads_enabled,false),
    'count',jsonb_array_length(v_clean)
  );
end;
$function$;
