-- FTS Selfie Event v154
-- Promote an existing purely local manual printer event to the server without
-- changing its event token. Keeping the token stable preserves local SD-card
-- registrations, manifests, print queues and event-folder identity.

create or replace function public.fts_printer_promote_local_event_v154(
  p_device_token text,
  p_session_token text,
  p_event_token text,
  p_title text,
  p_event_date date,
  p_location text,
  p_short_code text,
  p_storage_mode text,
  p_studio_config jsonb,
  p_logo_items jsonb,
  p_photo_branding text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_ctx jsonb;
  v_customer_id uuid;
  v_event_id uuid;
  v_existing_customer uuid;
  v_short text;
  v_title text:=trim(coalesce(p_title,''));
  v_date date:=coalesce(p_event_date,(now() at time zone 'Europe/Luxembourg')::date);
  v_location text:=nullif(trim(coalesce(p_location,'')),'');
  v_mode text:=lower(trim(coalesce(p_storage_mode,'')));
begin
  v_ctx:=public.fts_printer_validate_session_v72(p_device_token,p_session_token);
  if coalesce((v_ctx->>'valid')::boolean,false) is not true then
    raise exception 'Printer-Sitzung ist nicht gültig' using errcode='42501';
  end if;
  if coalesce(v_ctx->>'role','')<>'printer_admin' then
    raise exception 'Nur Printer-Administratoren können lokale Events online freigeben' using errcode='42501';
  end if;
  if v_title='' then raise exception 'Eventname fehlt'; end if;
  if coalesce(p_event_token,'') !~ '^local_[a-z0-9]+$' then
    raise exception 'Lokale Event-ID ist ungültig';
  end if;
  if v_mode not in ('online','hybrid') then
    raise exception 'Zielmodus muss online oder hybrid sein';
  end if;

  select id into v_customer_id
  from public.fts_selfie_customers
  where token='fts-printer-manual'
  limit 1;
  if v_customer_id is null then raise exception 'FTS Printer Manual-Kunde fehlt'; end if;

  select id,customer_id,short_code
    into v_event_id,v_existing_customer,v_short
  from public.fts_selfie_events
  where token=p_event_token
  limit 1;

  if v_event_id is not null and v_existing_customer<>v_customer_id then
    raise exception 'Event-ID ist bereits anderweitig vergeben' using errcode='23505';
  end if;

  if v_event_id is null then
    v_event_id:=gen_random_uuid();
    v_short:=nullif(trim(coalesce(p_short_code,'')),'');
    if v_short is null then
      v_short:='M'||to_char(v_date,'YYMMDD')||upper(substr(replace(v_event_id::text,'-',''),1,4));
    end if;

    insert into public.fts_selfie_events(
      id,customer_id,token,title,subtitle,event_date,location,overlay_text,
      expires_at,short_code,photo_branding,operation_mode,local_camera_photos,
      event_days,active,poster_bilingual,tablet_attention,storage_mode,logo_items
    ) values(
      v_event_id,v_customer_id,p_event_token,v_title,null,v_date,v_location,null,
      greatest(v_date,current_date)::timestamp + interval '90 days',
      v_short,case when p_photo_branding='bottom' then 'bottom' else 'none' end,
      'print_only',true,jsonb_build_array(v_date::text),true,false,false,v_mode,
      coalesce(p_logo_items,'[]'::jsonb)
    );
  else
    update public.fts_selfie_events
    set title=v_title,
        event_date=v_date,
        location=v_location,
        expires_at=greatest(v_date,current_date)::timestamp + interval '90 days',
        photo_branding=case when p_photo_branding='bottom' then 'bottom' else 'none' end,
        operation_mode='print_only',
        local_camera_photos=true,
        event_days=jsonb_build_array(v_date::text),
        active=true,
        storage_mode=v_mode,
        logo_items=coalesce(p_logo_items,'[]'::jsonb)
    where id=v_event_id;
  end if;

  insert into public.fts_selfie_event_studio(event_id,config,updated_at)
  values(
    v_event_id,
    coalesce(p_studio_config,'{}'::jsonb) || jsonb_build_object(
      'printer_manual',true,
      'manual_design_version',154
    ),
    now()
  )
  on conflict(event_id) do update
  set config=excluded.config,updated_at=now();

  return jsonb_build_object(
    'ok',true,
    'event_token',p_event_token,
    'event_id',v_event_id,
    'short_code',v_short,
    'storage_mode',v_mode
  );
end;
$$;

revoke all on function public.fts_printer_promote_local_event_v154(
  text,text,text,text,date,text,text,text,jsonb,jsonb,text
) from public;
grant execute on function public.fts_printer_promote_local_event_v154(
  text,text,text,text,date,text,text,text,jsonb,jsonb,text
) to anon,authenticated;
