-- Build 131 · manual per-printer material remainder
create or replace function public.fts_printer_set_material_counts_v131(
  p_device_token text,
  p_session_token text,
  p_event_token text,
  p_printer_key text,
  p_rp108_remaining integer,
  p_paper_remaining integer,
  p_film_remaining integer
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_ctx jsonb;
  v_event_id uuid;
  v_before jsonb;
  v_after jsonb;
begin
  v_ctx:=public.fts_printer_session_context_v80(p_device_token,p_session_token);
  v_event_id:=public.fts_selfie_resolve_event_id_v50(p_event_token);
  if v_event_id is null then raise exception 'Event nicht gefunden'; end if;
  if nullif(trim(coalesce(p_printer_key,'')),'') is null then raise exception 'Printer-Key fehlt'; end if;
  if p_rp108_remaining is null or p_rp108_remaining<0 or p_rp108_remaining>108 then raise exception 'RP-108 Restbestand muss zwischen 0 und 108 liegen'; end if;
  if p_paper_remaining is null or p_paper_remaining<0 or p_paper_remaining>18 then raise exception 'Papier-Restbestand muss zwischen 0 und 18 liegen'; end if;
  if p_film_remaining is null or p_film_remaining<0 or p_film_remaining>54 then raise exception 'Farbfilm-Restbestand muss zwischen 0 und 54 liegen'; end if;

  insert into public.fts_selfie_printer_consumables_v81(event_id,printer_key)
  values(v_event_id,p_printer_key)
  on conflict(event_id,printer_key) do nothing;

  select jsonb_build_object('rp108_remaining',rp108_remaining,'paper_remaining',paper_remaining,'film_remaining',film_remaining)
  into v_before
  from public.fts_selfie_printer_consumables_v81
  where event_id=v_event_id and printer_key=p_printer_key;

  update public.fts_selfie_printer_consumables_v81
  set rp108_remaining=p_rp108_remaining,paper_remaining=p_paper_remaining,film_remaining=p_film_remaining,updated_at=now()
  where event_id=v_event_id and printer_key=p_printer_key;

  select jsonb_build_object(
    'printer_key',printer_key,'rp108_remaining',rp108_remaining,'paper_remaining',paper_remaining,
    'film_remaining',film_remaining,'updated_at',updated_at
  ) into v_after
  from public.fts_selfie_printer_consumables_v81
  where event_id=v_event_id and printer_key=p_printer_key;

  insert into public.fts_selfie_printer_audit_v72(user_id,event_id,action,quantity,device_label,details)
  values((v_ctx->>'user_id')::uuid,v_event_id,'CONSUMABLE_MANUAL_SET',0,v_ctx->>'device_label',
    jsonb_build_object('printer_key',p_printer_key,'before',v_before,'after',v_after));

  return jsonb_build_object('ok',true,'material',v_after);
end;
$function$;
