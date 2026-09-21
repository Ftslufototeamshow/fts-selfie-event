-- FTS MySelfie v36 · Social sharing, posting permission and photo selection
-- Applied to production Supabase on 2026-09-21.

create table if not exists public.fts_event_social_permissions_v36 (
  event_id uuid primary key references public.fts_selfie_events(id) on delete cascade,
  fts_can_post boolean not null default false,
  granted_at timestamptz,
  revoked_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.fts_event_social_permissions_v36 enable row level security;
revoke all on table public.fts_event_social_permissions_v36 from public, anon, authenticated;

create table if not exists public.fts_event_social_photos_v36 (
  photo_id uuid primary key references public.fts_selfie_photos(id) on delete cascade,
  selected boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.fts_event_social_photos_v36 enable row level security;
revoke all on table public.fts_event_social_photos_v36 from public, anon, authenticated;

create or replace function public.fts_customer_social_status_v36(p_customer_token text)
returns table(event_token text,event_title text,organizer_name text,location text,fts_can_post boolean,updated_at timestamptz)
language sql security definer set search_path='public'
as $$
  select e.token,e.title,c.name,e.location,coalesce(s.fts_can_post,false),s.updated_at
  from public.fts_selfie_events e
  join public.fts_selfie_customers c on c.id=e.customer_id
  left join public.fts_event_social_permissions_v36 s on s.event_id=e.id
  where c.token=p_customer_token and c.active=true and e.active=true and e.archived_at is null and e.expires_at>now()
  order by e.event_date desc,e.created_at desc;
$$;

create or replace function public.fts_customer_set_fts_post_permission_v36(p_customer_token text,p_event_token text,p_allowed boolean)
returns boolean language plpgsql security definer set search_path='public'
as $$
declare v_event_id uuid;
begin
  select e.id into v_event_id
  from public.fts_selfie_events e
  join public.fts_selfie_customers c on c.id=e.customer_id
  where c.token=p_customer_token and c.active=true and e.token=p_event_token
    and e.active=true and e.archived_at is null and e.expires_at>now()
  limit 1;
  if v_event_id is null then raise exception 'Event not available'; end if;

  insert into public.fts_event_social_permissions_v36(event_id,fts_can_post,granted_at,revoked_at,updated_at)
  values(v_event_id,coalesce(p_allowed,false),
    case when coalesce(p_allowed,false) then now() else null end,
    case when coalesce(p_allowed,false) then null else now() end,
    now())
  on conflict(event_id) do update set
    fts_can_post=excluded.fts_can_post,
    granted_at=case when excluded.fts_can_post then coalesce(public.fts_event_social_permissions_v36.granted_at,now()) else public.fts_event_social_permissions_v36.granted_at end,
    revoked_at=case when excluded.fts_can_post then null else now() end,
    updated_at=now();
  return true;
end;
$$;

create or replace function public.fts_admin_social_status_v36(p_admin_code text,p_event_token text)
returns table(event_token text,event_title text,organizer_name text,location text,fts_can_post boolean,updated_at timestamptz)
language plpgsql security definer set search_path='public'
as $$
begin
  if not public.fts_selfie_admin_ok(p_admin_code) then raise exception 'Unauthorized'; end if;
  return query
  select e.token,e.title,c.name,e.location,coalesce(s.fts_can_post,false),s.updated_at
  from public.fts_selfie_events e
  join public.fts_selfie_customers c on c.id=e.customer_id
  left join public.fts_event_social_permissions_v36 s on s.event_id=e.id
  where e.token=p_event_token
  limit 1;
end;
$$;

create or replace function public.fts_get_event_social_copy_v36(p_event_token text)
returns table(event_token text,event_title text,organizer_name text,location text)
language sql security definer set search_path='public'
as $$
  select e.token,e.title,c.name,e.location
  from public.fts_selfie_events e
  join public.fts_selfie_customers c on c.id=e.customer_id
  where (e.token=p_event_token or (e.short_code is not null and upper(e.short_code)=upper(p_event_token)))
    and c.active=true and e.active=true and e.archived_at is null and e.expires_at>now()
  limit 1;
$$;

create or replace function public.fts_get_customer_designs_v36(p_customer_token text)
returns table(event_token text,event_title text,event_subtitle text,event_date date,event_day date,photo_id uuid,designed_path text,created_at timestamptz,social_selected boolean)
language sql security definer set search_path='public'
as $$
  select e.token,e.title,e.subtitle,e.event_date,coalesce(p.event_day,e.event_date),
         p.id,p.designed_path,p.created_at,coalesce(sp.selected,true)
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

create or replace function public.fts_customer_set_social_photo_v36(p_customer_token text,p_photo_id uuid,p_selected boolean)
returns boolean language plpgsql security definer set search_path='public'
as $$
declare v_ok boolean;
begin
  select exists(
    select 1
    from public.fts_selfie_photos p
    join public.fts_selfie_events e on e.id=p.event_id
    join public.fts_selfie_customers c on c.id=e.customer_id
    where p.id=p_photo_id and c.token=p_customer_token and c.active=true
      and e.active=true and e.archived_at is null and e.expires_at>now()
      and coalesce(p.is_test,false)=false and p.trashed_at is null
      and nullif(trim(coalesce(p.designed_path,'')),'') is not null
  ) into v_ok;
  if not v_ok then raise exception 'Photo not available'; end if;

  insert into public.fts_event_social_photos_v36(photo_id,selected,updated_at)
  values(p_photo_id,coalesce(p_selected,false),now())
  on conflict(photo_id) do update set selected=excluded.selected,updated_at=now();
  return true;
end;
$$;

create or replace function public.fts_admin_social_photo_status_v36(p_admin_code text,p_event_token text)
returns table(photo_id uuid,social_selected boolean)
language plpgsql security definer set search_path='public'
as $$
begin
  if not public.fts_selfie_admin_ok(p_admin_code) then raise exception 'Unauthorized'; end if;
  return query
  select p.id,coalesce(sp.selected,true)
  from public.fts_selfie_photos p
  join public.fts_selfie_events e on e.id=p.event_id
  left join public.fts_event_social_photos_v36 sp on sp.photo_id=p.id
  where e.token=p_event_token and p.trashed_at is null and coalesce(p.is_test,false)=false
    and nullif(trim(coalesce(p.designed_path,'')),'') is not null;
end;
$$;

grant execute on function public.fts_customer_social_status_v36(text) to anon, authenticated;
grant execute on function public.fts_customer_set_fts_post_permission_v36(text,text,boolean) to anon, authenticated;
grant execute on function public.fts_admin_social_status_v36(text,text) to anon, authenticated;
grant execute on function public.fts_get_event_social_copy_v36(text) to anon, authenticated;
grant execute on function public.fts_get_customer_designs_v36(text) to anon, authenticated;
grant execute on function public.fts_customer_set_social_photo_v36(text,uuid,boolean) to anon, authenticated;
grant execute on function public.fts_admin_social_photo_status_v36(text,text) to anon, authenticated;


drop policy if exists fts_social_permissions_no_direct on public.fts_event_social_permissions_v36;
create policy fts_social_permissions_no_direct
on public.fts_event_social_permissions_v36
for all to anon, authenticated
using (false)
with check (false);

drop policy if exists fts_social_photos_no_direct on public.fts_event_social_photos_v36;
create policy fts_social_photos_no_direct
on public.fts_event_social_photos_v36
for all to anon, authenticated
using (false)
with check (false);
