-- Build 123 · RP-108 per-printer counter + reset RPC
-- Applied to production on 2026-09-26. Kept here so repository and DB stay in sync.

alter table public.fts_selfie_printer_consumables_v81
  add column if not exists rp108_remaining integer,
  add column if not exists rp108_started_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname='fts_selfie_printer_consumables_v81_rp108_remaining_check'
  ) then
    alter table public.fts_selfie_printer_consumables_v81
      add constraint fts_selfie_printer_consumables_v81_rp108_remaining_check
      check (rp108_remaining is null or (rp108_remaining between 0 and 108));
  end if;
end $$;

create or replace function public.fts_printer_consume_components_v81(
  p_event_id uuid,p_printer_key text,p_quantity integer default 1
) returns void
language plpgsql security definer set search_path to 'public'
as $function$
begin
  if p_event_id is null or nullif(trim(coalesce(p_printer_key,'')),'') is null or coalesce(p_quantity,0)<=0 then return; end if;
  update public.fts_selfie_printer_consumables_v81
  set paper_remaining=case when paper_remaining is null then null else greatest(0,paper_remaining-p_quantity) end,
      film_remaining=case when film_remaining is null then null else greatest(0,film_remaining-p_quantity) end,
      rp108_remaining=case when rp108_remaining is null then null else greatest(0,rp108_remaining-p_quantity) end,
      last_print_at=now(),updated_at=now()
  where event_id=p_event_id and printer_key=p_printer_key;
end;
$function$;

create or replace function public.fts_printer_consumables_v123(
  p_device_token text,p_session_token text,p_event_token text
) returns table(
  printer_key text,paper_remaining integer,film_remaining integer,rp108_remaining integer,
  paper_loaded_at timestamptz,film_loaded_at timestamptz,rp108_started_at timestamptz,
  last_print_at timestamptz,updated_at timestamptz
)
language plpgsql security definer set search_path to 'public'
as $function$
declare v_event_id uuid;
begin
  perform public.fts_printer_session_context_v80(p_device_token,p_session_token);
  v_event_id:=public.fts_selfie_resolve_event_id_v50(p_event_token);
  return query
  select c.printer_key,c.paper_remaining,c.film_remaining,c.rp108_remaining,
         c.paper_loaded_at,c.film_loaded_at,c.rp108_started_at,c.last_print_at,c.updated_at
  from public.fts_selfie_printer_consumables_v81 c
  where c.event_id=v_event_id order by c.printer_key;
end;
$function$;

create or replace function public.fts_printer_start_rp108_v123(
  p_device_token text,p_session_token text,p_event_token text,p_printer_key text
) returns jsonb
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_ctx jsonb; v_event_id uuid; v_before jsonb; v_after jsonb;
  v_before_available integer; v_delta integer:=0; v_managed boolean:=false;
  v_day date:=(now() at time zone 'Europe/Luxembourg')::date;
begin
  v_ctx:=public.fts_printer_session_context_v80(p_device_token,p_session_token);
  v_event_id:=public.fts_selfie_resolve_event_id_v50(p_event_token);
  if v_event_id is null then raise exception 'Event nicht gefunden'; end if;
  if nullif(trim(coalesce(p_printer_key,'')),'') is null then raise exception 'Printer-Key fehlt'; end if;

  v_before:=public.fts_selfie_stock_snapshot_v70(v_event_id);
  v_managed:=coalesce((v_before->>'managed')::boolean,false);
  if v_managed then
    v_before_available:=coalesce((v_before->>'safe_available')::integer,0);
    v_delta:=108-v_before_available;
    if v_delta<>0 then
      insert into public.fts_selfie_print_stock_ledger_v70(event_id,event_day,kind,quantity_delta,source,note)
      values(v_event_id,v_day,'CORRECTION',v_delta,'PRINTER_APP_RP108_RESET',
             'Neues RP-108 Set gestartet; sicherer Bestand auf 108 gesetzt');
    end if;
  end if;

  insert into public.fts_selfie_printer_consumables_v81(event_id,printer_key)
  values(v_event_id,p_printer_key) on conflict(event_id,printer_key) do nothing;

  update public.fts_selfie_printer_consumables_v81
  set paper_remaining=18,film_remaining=54,rp108_remaining=108,
      paper_loaded_at=now(),film_loaded_at=now(),rp108_started_at=now(),updated_at=now()
  where event_id=v_event_id and printer_key=p_printer_key;

  v_after:=public.fts_selfie_stock_snapshot_v70(v_event_id);
  insert into public.fts_selfie_printer_audit_v72(user_id,event_id,action,quantity,device_label,details)
  values((v_ctx->>'user_id')::uuid,v_event_id,'RP108_SET_STARTED',108,v_ctx->>'device_label',
         jsonb_build_object('printer_key',p_printer_key,'safe_available_before',v_before->'safe_available',
                            'safe_available_after',v_after->'safe_available','correction_delta',v_delta,
                            'paper_remaining',18,'film_remaining',54,'rp108_remaining',108));
  return jsonb_build_object('ok',true,'printer_key',p_printer_key,'paper_remaining',18,
                            'film_remaining',54,'rp108_remaining',108,'stock',v_after);
end;
$function$;
