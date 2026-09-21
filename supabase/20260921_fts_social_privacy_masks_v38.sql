-- FTS MySelfie v38 · professional social privacy workflow
-- Applied to production Supabase on 2026-09-21.

alter table public.fts_event_social_photos_v36
  add column if not exists privacy_masks jsonb not null default '[]'::jsonb;

create or replace function public.fts_get_customer_designs_v38(p_customer_token text)
returns table(
  event_token text,
  event_title text,
  event_subtitle text,
  event_date date,
  event_day date,
  photo_id uuid,
  designed_path text,
  created_at timestamptz,
  social_selected boolean,
  privacy_masks jsonb
)
language sql
security definer
set search_path='public'
as $$
  select e.token,e.title,e.subtitle,e.event_date,coalesce(p.event_day,e.event_date),
         p.id,p.designed_path,p.created_at,coalesce(sp.selected,true),
         coalesce(sp.privacy_masks,'[]'::jsonb)
  from public.fts_selfie_photos p
  join public.fts_selfie_events e on e.id=p.event_id
  join public.fts_selfie_customers c on c.id=e.customer_id
  left join public.fts_event_social_photos_v36 sp on sp.photo_id=p.id
  where c.token=p_customer_token and c.active=true
    and e.active=true and e.archived_at is null and e.expires_at>now()
    and coalesce(p.is_test,false)=false
    and p.trashed_at is null
    and nullif(trim(coalesce(p.designed_path,'')),'') is not null
    and exists(select 1 from storage.objects so where so.bucket_id='fts-selfie-live' and so.name=p.designed_path)
  order by e.event_date desc,coalesce(p.event_day,e.event_date) desc,p.created_at desc;
$$;

create or replace function public.fts_customer_set_privacy_masks_v38(
  p_customer_token text,
  p_photo_id uuid,
  p_masks jsonb
)
returns boolean
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_ok boolean;
  v_masks jsonb := coalesce(p_masks,'[]'::jsonb);
begin
  if jsonb_typeof(v_masks) <> 'array' or jsonb_array_length(v_masks) > 30 then
    raise exception 'Invalid privacy masks';
  end if;

  select exists(
    select 1
    from public.fts_selfie_photos p
    join public.fts_selfie_events e on e.id=p.event_id
    join public.fts_selfie_customers c on c.id=e.customer_id
    where p.id=p_photo_id
      and c.token=p_customer_token
      and c.active=true
      and e.active=true
      and e.archived_at is null
      and e.expires_at>now()
      and coalesce(p.is_test,false)=false
      and p.trashed_at is null
      and nullif(trim(coalesce(p.designed_path,'')),'') is not null
  ) into v_ok;

  if not v_ok then raise exception 'Photo not available'; end if;

  insert into public.fts_event_social_photos_v36(photo_id,selected,privacy_masks,updated_at)
  values(p_photo_id,true,v_masks,now())
  on conflict(photo_id) do update set privacy_masks=excluded.privacy_masks,updated_at=now();

  return true;
end;
$$;

create or replace function public.fts_admin_social_photo_status_v38(
  p_admin_code text,
  p_event_token text
)
returns table(photo_id uuid,social_selected boolean,privacy_masks jsonb)
language plpgsql
security definer
set search_path='public'
as $$
begin
  if not public.fts_selfie_admin_ok(p_admin_code) then raise exception 'Unauthorized'; end if;

  return query
  select p.id,coalesce(sp.selected,true),coalesce(sp.privacy_masks,'[]'::jsonb)
  from public.fts_selfie_photos p
  join public.fts_selfie_events e on e.id=p.event_id
  left join public.fts_event_social_photos_v36 sp on sp.photo_id=p.id
  where e.token=p_event_token
    and p.trashed_at is null
    and coalesce(p.is_test,false)=false
    and nullif(trim(coalesce(p.designed_path,'')),'') is not null;
end;
$$;

create or replace function public.fts_admin_set_privacy_masks_v38(
  p_admin_code text,
  p_photo_id uuid,
  p_masks jsonb
)
returns boolean
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_masks jsonb := coalesce(p_masks,'[]'::jsonb);
begin
  if not public.fts_selfie_admin_ok(p_admin_code) then raise exception 'Unauthorized'; end if;
  if jsonb_typeof(v_masks) <> 'array' or jsonb_array_length(v_masks) > 30 then
    raise exception 'Invalid privacy masks';
  end if;
  if not exists(
    select 1 from public.fts_selfie_photos p
    where p.id=p_photo_id
      and p.trashed_at is null
      and coalesce(p.is_test,false)=false
  ) then
    raise exception 'Photo not available';
  end if;

  insert into public.fts_event_social_photos_v36(photo_id,selected,privacy_masks,updated_at)
  values(p_photo_id,true,v_masks,now())
  on conflict(photo_id) do update set privacy_masks=excluded.privacy_masks,updated_at=now();

  return true;
end;
$$;

grant execute on function public.fts_get_customer_designs_v38(text) to anon, authenticated;
grant execute on function public.fts_customer_set_privacy_masks_v38(text,uuid,jsonb) to anon, authenticated;
grant execute on function public.fts_admin_social_photo_status_v38(text,text) to anon, authenticated;
grant execute on function public.fts_admin_set_privacy_masks_v38(text,uuid,jsonb) to anon, authenticated;
