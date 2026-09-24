-- FTS Printer v92 · Tagesalben / Tagesnummerierung
-- Applied to production on 2026-09-24.

alter table public.fts_selfie_printer_local_jobs_v80
  add column if not exists event_day date;

update public.fts_selfie_printer_local_jobs_v80 l
set event_day = coalesce(
  (select r.event_day from public.fts_selfie_printer_local_reservations_v80 r where r.local_job_id=l.id limit 1),
  e.event_date,
  (l.created_at at time zone 'Europe/Luxembourg')::date
)
from public.fts_selfie_events e
where e.id=l.event_id and l.event_day is null;

alter table public.fts_selfie_printer_local_jobs_v80
  alter column event_day set not null;

do $$
begin
  if exists (
    select 1 from pg_constraint
    where conrelid='public.fts_selfie_printer_local_jobs_v80'::regclass
      and conname='fts_selfie_printer_local_jobs_v80_event_id_customer_code_key'
  ) then
    alter table public.fts_selfie_printer_local_jobs_v80
      drop constraint fts_selfie_printer_local_jobs_v80_event_id_customer_code_key;
  end if;
end $$;

create unique index if not exists fts_local_jobs_event_day_code_uq
  on public.fts_selfie_printer_local_jobs_v80(event_id,event_day,customer_code);

create table if not exists public.fts_selfie_printer_local_counters_v92(
  event_id uuid not null references public.fts_selfie_events(id) on delete cascade,
  event_day date not null,
  source_label text not null,
  last_number integer not null default 0 check(last_number>=0),
  updated_at timestamptz not null default now(),
  primary key(event_id,event_day,source_label)
);

alter table public.fts_selfie_printer_local_counters_v92 enable row level security;

create or replace function public.fts_printer_create_local_job_v92(
  p_device_token text,
  p_session_token text,
  p_event_token text,
  p_event_day date,
  p_local_job_id uuid,
  p_source_type text,
  p_source_label text,
  p_quantity integer
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_ctx jsonb;
  v_event_id uuid;
  v_event public.fts_selfie_events%rowtype;
  v_label text;
  v_number integer;
  v_code text;
  v_existing public.fts_selfie_printer_local_jobs_v80%rowtype;
  v_snapshot jsonb;
  v_available integer;
  v_day date;
  v_reserve_until timestamptz;
begin
  if p_local_job_id is null then raise exception 'Local-Job-ID fehlt'; end if;
  if p_quantity is null or p_quantity<1 then raise exception 'Menge muss mindestens 1 sein'; end if;

  v_ctx:=public.fts_printer_session_context_v80(p_device_token,p_session_token);
  v_event_id:=public.fts_selfie_resolve_event_id_v50(p_event_token);
  if v_event_id is null then raise exception 'Event nicht gefunden'; end if;

  select * into v_event from public.fts_selfie_events where id=v_event_id;
  v_day:=coalesce(p_event_day,v_event.event_date,(now() at time zone 'Europe/Luxembourg')::date);

  if v_event.event_days is not null
     and jsonb_typeof(v_event.event_days)='array'
     and jsonb_array_length(v_event.event_days)>0
     and not exists (
       select 1 from jsonb_array_elements_text(v_event.event_days) d(day_text)
       where d.day_text=v_day::text
     )
  then
    raise exception 'Der gewählte Veranstaltungstag gehört nicht zu diesem Event';
  end if;

  v_label:=upper(regexp_replace(trim(coalesce(p_source_label,'')),'[^A-Z0-9]','','g'));
  if v_label='' then v_label:='L'; end if;
  if upper(coalesce(p_source_type,'')) not in ('SD','WIFI','LOCAL') then raise exception 'Ungültige Quelle'; end if;

  select * into v_existing
  from public.fts_selfie_printer_local_jobs_v80
  where id=p_local_job_id;

  if found then
    return jsonb_build_object(
      'ok',true,'job_id',v_existing.id,'customer_code',v_existing.customer_code,
      'status',v_existing.status,'quantity',v_existing.quantity_total
    );
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_event_id::text||'|'||v_day::text||'|'||v_label,92));

  update public.fts_selfie_printer_local_reservations_v80
  set status='EXPIRED',updated_at=now()
  where event_id=v_event_id and status='HELD' and expires_at<now();

  v_snapshot:=public.fts_selfie_stock_snapshot_v70(v_event_id);
  if coalesce((v_snapshot->>'managed')::boolean,false) then
    v_available:=coalesce((v_snapshot->>'safe_available')::integer,0);
    if v_available<p_quantity then
      raise exception 'Nicht genug sicherer Materialbestand (% verfügbar, % benötigt)',v_available,p_quantity using errcode='P0001';
    end if;
  end if;

  insert into public.fts_selfie_printer_local_counters_v92(event_id,event_day,source_label,last_number)
  values(v_event_id,v_day,v_label,1)
  on conflict(event_id,event_day,source_label) do update
  set last_number=public.fts_selfie_printer_local_counters_v92.last_number+1,
      updated_at=now()
  returning last_number into v_number;

  v_code:=v_label||lpad(v_number::text,3,'0');
  v_reserve_until:=greatest(coalesce(v_event.expires_at,now()+interval '1 day'),now()+interval '1 day');

  insert into public.fts_selfie_printer_local_jobs_v80(
    id,event_id,event_day,customer_code,source_type,source_label,quantity_total,status,created_by,device_label
  ) values(
    p_local_job_id,v_event_id,v_day,v_code,upper(p_source_type),v_label,p_quantity,'WAITING',
    (v_ctx->>'user_id')::uuid,v_ctx->>'device_label'
  );

  if coalesce((v_snapshot->>'managed')::boolean,false) then
    insert into public.fts_selfie_printer_local_reservations_v80(
      local_job_id,event_id,event_day,quantity,status,expires_at
    ) values(
      p_local_job_id,v_event_id,v_day,p_quantity,'HELD',v_reserve_until
    );
  end if;

  insert into public.fts_selfie_printer_audit_v72(user_id,event_id,action,quantity,device_label,details)
  values(
    (v_ctx->>'user_id')::uuid,v_event_id,'LOCAL_JOB_CREATED',p_quantity,v_ctx->>'device_label',
    jsonb_build_object(
      'local_job_id',p_local_job_id,'customer_code',v_code,'event_day',v_day,
      'source_type',upper(p_source_type),'source_label',v_label,'reservation_until',v_reserve_until
    )
  );

  return jsonb_build_object(
    'ok',true,'job_id',p_local_job_id,'customer_code',v_code,'status','WAITING',
    'quantity',p_quantity,'event_day',v_day
  );
end;
$function$;

create or replace function public.fts_printer_reset_local_day_v92(
  p_device_token text,
  p_session_token text,
  p_event_token text,
  p_event_day date
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $function$
declare
  v_session jsonb;
  v_event_id uuid;
  v_count integer;
begin
  v_session:=public.fts_printer_validate_session_v72(p_device_token,p_session_token);
  if coalesce((v_session->>'valid')::boolean,false) is not true then
    raise exception 'Printer-Sitzung ist nicht gültig' using errcode='42501';
  end if;
  if coalesce(v_session->>'role','')<>'printer_admin' then
    raise exception 'Nur Printer-Administratoren dürfen einen Tageszähler zurücksetzen' using errcode='42501';
  end if;

  v_event_id:=public.fts_selfie_resolve_event_id_v50(p_event_token);
  if v_event_id is null then raise exception 'Event nicht gefunden'; end if;

  select count(*) into v_count
  from public.fts_selfie_printer_local_jobs_v80
  where event_id=v_event_id and event_day=p_event_day;

  if v_count>0 then
    return jsonb_build_object(
      'ok',false,'reason','DAY_HAS_JOBS',
      'message','Für diesen Veranstaltungstag existieren bereits Druckaufträge. Die Nummerierung wird nicht zurückgesetzt.'
    );
  end if;

  delete from public.fts_selfie_printer_local_counters_v92
  where event_id=v_event_id and event_day=p_event_day;

  insert into public.fts_selfie_printer_audit_v72(user_id,event_id,action,quantity,device_label,details)
  values(
    (v_session->>'user_id')::uuid,v_event_id,'LOCAL_DAY_RESET',0,'FTS Printer',
    jsonb_build_object('event_day',p_event_day)
  );

  return jsonb_build_object('ok',true,'event_day',p_event_day,'next_number',1);
end;
$function$;

grant execute on function public.fts_printer_create_local_job_v92(text,text,text,date,uuid,text,text,integer) to anon,authenticated;
grant execute on function public.fts_printer_reset_local_day_v92(text,text,text,date) to anon,authenticated;
