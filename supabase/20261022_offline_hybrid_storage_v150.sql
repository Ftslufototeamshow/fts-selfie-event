-- FTS Selfie Event v150
-- Per-event local / online / hybrid storage modes.
-- Existing events stay online by default. Existing v9/v74 RPC signatures are not changed.

alter table public.fts_selfie_events
  add column if not exists storage_mode text not null default 'online';

update public.fts_selfie_events
set storage_mode='online'
where storage_mode is null or storage_mode not in ('local','online','hybrid');

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='fts_selfie_events_storage_mode_check'
      and conrelid='public.fts_selfie_events'::regclass
  ) then
    alter table public.fts_selfie_events
      add constraint fts_selfie_events_storage_mode_check
      check (storage_mode in ('local','online','hybrid'));
  end if;
end $$;

create or replace function public.fts_admin_set_event_storage_mode_v150(
  p_admin_code text,p_event_token text,p_storage_mode text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_mode text:=lower(trim(coalesce(p_storage_mode,'')));
begin
  if not public.fts_selfie_admin_ok(p_admin_code) then
    raise exception 'Ungültiger Gerätezugang/Admin-Code';
  end if;
  if v_mode not in ('local','online','hybrid') then raise exception 'Ungültiger Speichermodus'; end if;
  update public.fts_selfie_events set storage_mode=v_mode where token=p_event_token;
  if not found then raise exception 'Event nicht gefunden'; end if;
  return jsonb_build_object('ok',true,'storage_mode',v_mode);
end;
$$;

revoke all on function public.fts_admin_set_event_storage_mode_v150(text,text,text) from public;
grant execute on function public.fts_admin_set_event_storage_mode_v150(text,text,text) to anon,authenticated;

create or replace function public.fts_admin_get_event_storage_mode_v150(
  p_admin_code text,p_event_token text
)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_mode text;
begin
  if not public.fts_selfie_admin_ok(p_admin_code) then
    raise exception 'Ungültiger Gerätezugang/Admin-Code';
  end if;
  select storage_mode into v_mode from public.fts_selfie_events where token=p_event_token;
  if v_mode is null then raise exception 'Event nicht gefunden'; end if;
  return v_mode;
end;
$$;

revoke all on function public.fts_admin_get_event_storage_mode_v150(text,text) from public;
grant execute on function public.fts_admin_get_event_storage_mode_v150(text,text) to anon,authenticated;

create or replace function public.fts_printer_set_event_storage_mode_v150(
  p_device_token text,p_session_token text,p_event_token text,p_storage_mode text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_ctx jsonb;
  v_mode text:=lower(trim(coalesce(p_storage_mode,'')));
begin
  v_ctx:=public.fts_printer_validate_session_v72(p_device_token,p_session_token);
  if coalesce((v_ctx->>'valid')::boolean,false) is not true then
    raise exception 'Printer-Sitzung ist nicht gültig' using errcode='42501';
  end if;
  if coalesce(v_ctx->>'role','')<>'printer_admin' then
    raise exception 'Nur Printer-Administratoren können den Speichermodus ändern' using errcode='42501';
  end if;
  if v_mode not in ('local','online','hybrid') then raise exception 'Ungültiger Speichermodus'; end if;
  update public.fts_selfie_events set storage_mode=v_mode where token=p_event_token;
  if not found then raise exception 'Event nicht gefunden'; end if;
  return jsonb_build_object('ok',true,'storage_mode',v_mode);
end;
$$;

revoke all on function public.fts_printer_set_event_storage_mode_v150(text,text,text,text) from public;
grant execute on function public.fts_printer_set_event_storage_mode_v150(text,text,text,text) to anon,authenticated;

create or replace function public.fts_printer_events_v150(
  p_device_token text,p_session_token text
)
returns table(
  event_token text,short_code text,event_title text,subtitle text,overlay_text text,organizer_name text,
  location text,event_date date,expires_at timestamptz,print_enabled boolean,print_starts_at timestamptz,
  print_ends_at timestamptz,print_window_active boolean,operation_mode text,local_camera_photos boolean,
  event_days jsonb,accent text,photo_branding text,logo_items jsonb,decoration_items jsonb,
  studio_config jsonb,stock jsonb,storage_mode text
)
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_ctx jsonb;
begin
  v_ctx:=public.fts_printer_validate_session_v72(p_device_token,p_session_token);
  if coalesce((v_ctx->>'valid')::boolean,false) is not true then
    raise exception 'Printer-Sitzung ist nicht gültig' using errcode='42501';
  end if;
  return query
  select e.token,e.short_code,e.title,e.subtitle,e.overlay_text,c.name,e.location,e.event_date,e.expires_at,
         coalesce(ps.enabled,false),ps.print_starts_at,ps.print_ends_at,
         (coalesce(ps.enabled,false) and (ps.print_starts_at is null or ps.print_starts_at<=now()) and (ps.print_ends_at is null or ps.print_ends_at>now())),
         coalesce(e.operation_mode,'selfie_print'),coalesce(e.local_camera_photos,false),coalesce(e.event_days,'[]'::jsonb),
         coalesce(e.accent,'#d9b56d'),coalesce(e.photo_branding,'bottom'),coalesce(e.logo_items,'[]'::jsonb),
         coalesce(e.decoration_items,'[]'::jsonb),coalesce(st.config,'{}'::jsonb),
         public.fts_selfie_stock_snapshot_v70(e.id),coalesce(e.storage_mode,'online')
  from public.fts_selfie_events e
  join public.fts_selfie_customers c on c.id=e.customer_id
  left join public.fts_selfie_print_settings ps on ps.event_id=e.id
  left join public.fts_selfie_event_studio st on st.event_id=e.id
  where e.archived_at is null
    and (coalesce(ps.enabled,false) or coalesce(e.local_camera_photos,false) or coalesce(e.operation_mode,'selfie_print')='print_only')
    and coalesce(e.expires_at,now()+interval '1 day')>now()-interval '14 days'
  order by case when e.event_date=current_date then 0 when e.event_date>current_date then 1 else 2 end,
           abs(e.event_date-current_date),e.created_at desc;
end;
$$;

revoke all on function public.fts_printer_events_v150(text,text) from public;
grant execute on function public.fts_printer_events_v150(text,text) to anon,authenticated;
