-- FTS Selfie Event v11 follow-up: preserve offline selfies captured during allowed windows.

drop function if exists public.fts_register_photo_v11(text,text,text,text);

create or replace function public.fts_register_photo_v11(
  p_event_token text,
  p_original_path text,
  p_designed_path text,
  p_guest_session_id text default null,
  p_captured_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text;
  v_lifecycle public.fts_event_lifecycle_v11%rowtype;
  v_captured_local timestamp without time zone := timezone('Europe/Luxembourg',coalesce(p_captured_at,now()));
  v_now timestamptz := now();
  v_first_date date;
  v_first_start time;
  v_allowed boolean := false;
  v_photo_id uuid;
begin
  if coalesce(p_captured_at,now()) > v_now + interval '5 minutes'
     or coalesce(p_captured_at,now()) < v_now - interval '7 days'
  then
    raise exception 'Invalid capture time';
  end if;

  select e.event_token::text into v_token
  from public.fts_get_event(p_event_token) e
  limit 1;

  if v_token is null then
    raise exception 'Event not found';
  end if;

  select * into v_lifecycle
  from public.fts_event_lifecycle_v11
  where event_token=v_token;

  if not found then
    select public.fts_register_photo_v10(
      p_event_token,p_original_path,p_designed_path,p_guest_session_id
    ) into v_photo_id;
    return v_photo_id;
  end if;

  select exists(
    select 1
    from jsonb_array_elements(coalesce(v_lifecycle.schedule,'[]'::jsonb)) x
    where v_captured_local::date=(x->>'date')::date
      and v_captured_local::time >= coalesce(nullif(x->>'start',''),'00:00')::time
      and v_captured_local::time <= coalesce(nullif(x->>'end',''),'23:59')::time
  ) into v_allowed;

  if not v_allowed and v_lifecycle.test_days_before>0 then
    select (x->>'date')::date,
           coalesce(nullif(x->>'start',''),'00:00')::time
      into v_first_date,v_first_start
    from jsonb_array_elements(coalesce(v_lifecycle.schedule,'[]'::jsonb)) x
    order by (x->>'date')::date, coalesce(nullif(x->>'start',''),'00:00')::time
    limit 1;

    if v_first_date is not null
       and v_captured_local::date >= (v_first_date-v_lifecycle.test_days_before)
       and (
         v_captured_local::date < v_first_date
         or (v_captured_local::date=v_first_date and v_captured_local::time < v_first_start)
       )
    then
      v_allowed := true;
    end if;
  end if;

  if not v_allowed then
    raise exception 'Uploads are closed for this event';
  end if;

  select public.fts_register_photo_v10(
    p_event_token,p_original_path,p_designed_path,p_guest_session_id
  ) into v_photo_id;
  return v_photo_id;
end;
$$;

revoke all on function public.fts_register_photo_v11(text,text,text,text,timestamptz) from public;
grant execute on function public.fts_register_photo_v11(text,text,text,text,timestamptz) to anon, authenticated;
