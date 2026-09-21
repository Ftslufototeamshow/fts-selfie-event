-- FTS MySelfie v45 · PayPal Sandbox Fotodruck
-- Production migration applied in Supabase on 2026-09-22.
-- Sandbox only. No PayPal credentials are stored in this file.

create table if not exists public.fts_selfie_print_settings (
  event_id uuid primary key references public.fts_selfie_events(id) on delete cascade,
  enabled boolean not null default false,
  print_starts_at timestamptz,
  print_ends_at timestamptz,
  unit_price_cents integer not null default 200 check (unit_price_cents = 200),
  currency text not null default 'EUR' check (currency = 'EUR'),
  paypal_environment text not null default 'sandbox' check (paypal_environment in ('sandbox','live')),
  updated_at timestamptz not null default now()
);

create table if not exists public.fts_selfie_print_orders (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.fts_selfie_events(id) on delete cascade,
  guest_session_id text not null,
  paypal_environment text not null default 'sandbox' check (paypal_environment in ('sandbox','live')),
  paypal_order_id text unique,
  paypal_capture_id text unique,
  payment_status text not null default 'CREATED'
    check (payment_status in ('CREATED','APPROVED','PENDING','COMPLETED','DENIED','DECLINED','FAILED','CANCELLED','REFUNDED','REVERSED','ERROR')),
  print_status text not null default 'BLOCKED'
    check (print_status in ('BLOCKED','READY','PRINTED','CANCELLED')),
  unit_price_cents integer not null default 200 check (unit_price_cents = 200),
  quantity_total integer not null check (quantity_total between 1 and 50),
  total_cents integer not null check (total_cents > 0),
  currency text not null default 'EUR' check (currency = 'EUR'),
  request_key uuid not null default gen_random_uuid() unique,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  paid_at timestamptz,
  printed_at timestamptz,
  cancelled_at timestamptz
);

create table if not exists public.fts_selfie_print_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.fts_selfie_print_orders(id) on delete cascade,
  photo_id uuid references public.fts_selfie_photos(id) on delete set null,
  designed_path_snapshot text not null,
  quantity integer not null check (quantity between 1 and 20),
  unit_price_cents integer not null default 200 check (unit_price_cents = 200),
  line_total_cents integer not null check (line_total_cents > 0),
  created_at timestamptz not null default now(),
  unique(order_id, photo_id)
);

create table if not exists public.fts_selfie_payments (
  id uuid primary key default gen_random_uuid(),
  print_order_id uuid not null references public.fts_selfie_print_orders(id) on delete cascade,
  paypal_order_id text,
  paypal_capture_id text,
  provider_event_id text unique,
  event_type text not null,
  status text not null,
  amount_cents integer,
  currency text,
  verified boolean not null default false,
  details jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now()
);

create table if not exists public.fts_selfie_print_jobs (
  id uuid primary key default gen_random_uuid(),
  print_order_id uuid not null unique references public.fts_selfie_print_orders(id) on delete cascade,
  event_id uuid not null references public.fts_selfie_events(id) on delete cascade,
  status text not null default 'READY' check (status in ('READY','PRINTED','CANCELLED')),
  created_at timestamptz not null default now(),
  printed_at timestamptz
);

create index if not exists fts_selfie_print_orders_event_idx
  on public.fts_selfie_print_orders(event_id, created_at desc);
create index if not exists fts_selfie_print_orders_session_idx
  on public.fts_selfie_print_orders(guest_session_id, created_at desc);
create index if not exists fts_selfie_print_items_order_idx
  on public.fts_selfie_print_order_items(order_id);
create index if not exists fts_selfie_payments_order_idx
  on public.fts_selfie_payments(print_order_id, received_at desc);
create index if not exists fts_selfie_print_jobs_event_idx
  on public.fts_selfie_print_jobs(event_id, created_at desc);

alter table public.fts_selfie_print_settings enable row level security;
alter table public.fts_selfie_print_orders enable row level security;
alter table public.fts_selfie_print_order_items enable row level security;
alter table public.fts_selfie_payments enable row level security;
alter table public.fts_selfie_print_jobs enable row level security;

revoke all on public.fts_selfie_print_settings from public, anon, authenticated;
revoke all on public.fts_selfie_print_orders from public, anon, authenticated;
revoke all on public.fts_selfie_print_order_items from public, anon, authenticated;
revoke all on public.fts_selfie_payments from public, anon, authenticated;
revoke all on public.fts_selfie_print_jobs from public, anon, authenticated;

drop policy if exists "deny direct print settings" on public.fts_selfie_print_settings;
create policy "deny direct print settings" on public.fts_selfie_print_settings
  for all to anon, authenticated using (false) with check (false);
drop policy if exists "deny direct print orders" on public.fts_selfie_print_orders;
create policy "deny direct print orders" on public.fts_selfie_print_orders
  for all to anon, authenticated using (false) with check (false);
drop policy if exists "deny direct print order items" on public.fts_selfie_print_order_items;
create policy "deny direct print order items" on public.fts_selfie_print_order_items
  for all to anon, authenticated using (false) with check (false);
drop policy if exists "deny direct print payments" on public.fts_selfie_payments;
create policy "deny direct print payments" on public.fts_selfie_payments
  for all to anon, authenticated using (false) with check (false);
drop policy if exists "deny direct print jobs" on public.fts_selfie_print_jobs;
create policy "deny direct print jobs" on public.fts_selfie_print_jobs
  for all to anon, authenticated using (false) with check (false);

create or replace function public.fts_get_guest_selfies_v45(
  p_event_token text,
  p_guest_session_id text
)
returns table(photo_id uuid,designed_path text,created_at timestamptz)
language sql
security definer
set search_path='public'
as $$
  select p.id,p.designed_path,p.created_at
  from public.fts_selfie_photos p
  join public.fts_selfie_events e on e.id=p.event_id
  join public.fts_selfie_customers c on c.id=e.customer_id
  where (e.token=p_event_token or (e.short_code is not null and upper(e.short_code)=upper(p_event_token)))
    and c.active=true and e.active=true and e.archived_at is null and e.expires_at>now()
    and p.trashed_at is null and coalesce(p.is_test,false)=false
    and p.designed_path is not null
    and p.guest_session_id=nullif(trim(coalesce(p_guest_session_id,'')),'')
  order by p.created_at desc
  limit 100;
$$;

create or replace function public.fts_admin_get_print_settings_v45(
  p_admin_code text,p_event_token text
)
returns table(enabled boolean,print_starts_at timestamptz,print_ends_at timestamptz,unit_price_cents integer,currency text,paypal_environment text)
language plpgsql security definer set search_path='public'
as $$
declare v_event_id uuid;
begin
  if not public.fts_selfie_admin_ok(p_admin_code) then raise exception 'Ungültiger Gerätezugang/Admin-Code'; end if;
  select e.id into v_event_id from public.fts_selfie_events e
  where e.token=p_event_token or upper(coalesce(e.short_code,''))=upper(p_event_token) limit 1;
  if v_event_id is null then raise exception 'Event nicht gefunden'; end if;
  insert into public.fts_selfie_print_settings(event_id) values(v_event_id) on conflict(event_id) do nothing;
  return query select s.enabled,s.print_starts_at,s.print_ends_at,s.unit_price_cents,s.currency,s.paypal_environment
  from public.fts_selfie_print_settings s where s.event_id=v_event_id;
end;
$$;

create or replace function public.fts_admin_set_print_settings_v45(
  p_admin_code text,p_event_token text,p_enabled boolean,
  p_print_starts_at timestamptz default null,p_print_ends_at timestamptz default null
)
returns void
language plpgsql security definer set search_path='public'
as $$
declare v_event_id uuid;
begin
  if not public.fts_selfie_admin_ok(p_admin_code) then raise exception 'Ungültiger Gerätezugang/Admin-Code'; end if;
  if p_print_starts_at is not null and p_print_ends_at is not null and p_print_ends_at <= p_print_starts_at then
    raise exception 'Druck-Ende muss nach Druck-Start liegen';
  end if;
  select e.id into v_event_id from public.fts_selfie_events e
  where e.token=p_event_token or upper(coalesce(e.short_code,''))=upper(p_event_token) limit 1;
  if v_event_id is null then raise exception 'Event nicht gefunden'; end if;
  insert into public.fts_selfie_print_settings(event_id,enabled,print_starts_at,print_ends_at,unit_price_cents,currency,paypal_environment,updated_at)
  values(v_event_id,coalesce(p_enabled,false),p_print_starts_at,p_print_ends_at,200,'EUR','sandbox',now())
  on conflict(event_id) do update set enabled=excluded.enabled,print_starts_at=excluded.print_starts_at,
    print_ends_at=excluded.print_ends_at,unit_price_cents=200,currency='EUR',paypal_environment='sandbox',updated_at=now();
end;
$$;

create or replace function public.fts_selfie_apply_payment_capture_v45(
  p_print_order_id uuid,p_paypal_order_id text,p_capture_id text,p_status text,
  p_amount_cents integer,p_currency text,p_provider_event_id text default null,
  p_event_type text default 'CAPTURE_API',p_verified boolean default true,p_details jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql security definer set search_path='public'
as $$
declare
  v_order public.fts_selfie_print_orders%rowtype;
  v_status text := upper(trim(coalesce(p_status,'')));
  v_payment_status text;
begin
  if coalesce(p_verified,false) is not true then raise exception 'Unverified PayPal payment event'; end if;

  select * into v_order from public.fts_selfie_print_orders
  where id=p_print_order_id and paypal_order_id=p_paypal_order_id for update;
  if not found then raise exception 'Druckauftrag nicht gefunden'; end if;

  if upper(coalesce(p_currency,'')) <> v_order.currency or p_amount_cents <> v_order.total_cents then
    update public.fts_selfie_print_orders set payment_status='ERROR',print_status='BLOCKED',
      last_error='PayPal amount/currency mismatch',updated_at=now() where id=v_order.id;
    raise exception 'PayPal Betrag oder Währung stimmt nicht';
  end if;

  v_payment_status := case
    when v_status='COMPLETED' then 'COMPLETED'
    when v_status='PENDING' then 'PENDING'
    when v_status in ('DENIED','DECLINED','FAILED') then 'DENIED'
    when v_status='REFUNDED' then 'REFUNDED'
    when v_status='REVERSED' then 'REVERSED'
    else 'ERROR'
  end;

  insert into public.fts_selfie_payments(print_order_id,paypal_order_id,paypal_capture_id,provider_event_id,event_type,status,amount_cents,currency,verified,details)
  values(v_order.id,p_paypal_order_id,nullif(p_capture_id,''),nullif(p_provider_event_id,''),coalesce(nullif(p_event_type,''),'CAPTURE_API'),
    v_payment_status,p_amount_cents,upper(p_currency),true,coalesce(p_details,'{}'::jsonb))
  on conflict(provider_event_id) do nothing;

  if v_payment_status='COMPLETED' then
    update public.fts_selfie_print_orders
    set paypal_capture_id=coalesce(nullif(p_capture_id,''),paypal_capture_id),payment_status='COMPLETED',
      print_status=case when print_status='PRINTED' then 'PRINTED' else 'READY' end,
      paid_at=coalesce(paid_at,now()),last_error=null,updated_at=now()
    where id=v_order.id;
    insert into public.fts_selfie_print_jobs(print_order_id,event_id,status)
    values(v_order.id,v_order.event_id,'READY') on conflict(print_order_id) do nothing;
  elsif v_payment_status='PENDING' then
    update public.fts_selfie_print_orders
    set paypal_capture_id=coalesce(nullif(p_capture_id,''),paypal_capture_id),payment_status='PENDING',print_status='BLOCKED',updated_at=now()
    where id=v_order.id and payment_status<>'COMPLETED';
  elsif v_payment_status in ('REFUNDED','REVERSED') then
    update public.fts_selfie_print_orders
    set paypal_capture_id=coalesce(nullif(p_capture_id,''),paypal_capture_id),payment_status=v_payment_status,
      print_status=case when print_status='PRINTED' then 'PRINTED' else 'CANCELLED' end,updated_at=now()
    where id=v_order.id;
    update public.fts_selfie_print_jobs
    set status=case when status='PRINTED' then 'PRINTED' else 'CANCELLED' end where print_order_id=v_order.id;
  else
    update public.fts_selfie_print_orders
    set paypal_capture_id=coalesce(nullif(p_capture_id,''),paypal_capture_id),payment_status=v_payment_status,
      print_status='BLOCKED',last_error=case when v_payment_status='ERROR' then 'Unexpected PayPal status: '||v_status else null end,updated_at=now()
    where id=v_order.id and payment_status<>'COMPLETED';
  end if;

  return (select jsonb_build_object('order_id',o.id,'payment_status',o.payment_status,'print_status',o.print_status,
    'paypal_order_id',o.paypal_order_id,'paypal_capture_id',o.paypal_capture_id,'paid_at',o.paid_at)
    from public.fts_selfie_print_orders o where o.id=v_order.id);
end;
$$;

create or replace function public.fts_admin_print_orders_v45(p_admin_code text,p_event_token text default null)
returns table(order_id uuid,event_token text,event_title text,quantity_total integer,total_cents integer,currency text,
  payment_status text,print_status text,paypal_order_id text,paypal_capture_id text,created_at timestamptz,paid_at timestamptz,printed_at timestamptz)
language plpgsql security definer set search_path='public'
as $$
begin
  if not public.fts_selfie_admin_ok(p_admin_code) then raise exception 'Ungültiger Gerätezugang/Admin-Code'; end if;
  return query
  select o.id,e.token,e.title,o.quantity_total,o.total_cents,o.currency,o.payment_status,o.print_status,
    o.paypal_order_id,o.paypal_capture_id,o.created_at,o.paid_at,o.printed_at
  from public.fts_selfie_print_orders o join public.fts_selfie_events e on e.id=o.event_id
  where p_event_token is null or e.token=p_event_token or upper(coalesce(e.short_code,''))=upper(p_event_token)
  order by o.created_at desc limit 500;
end;
$$;

create or replace function public.fts_admin_print_order_items_v45(p_admin_code text,p_event_token text)
returns table(order_id uuid,photo_id uuid,designed_path text,quantity integer)
language plpgsql security definer set search_path='public'
as $$
begin
  if not public.fts_selfie_admin_ok(p_admin_code) then raise exception 'Ungültiger Gerätezugang/Admin-Code'; end if;
  return query
  select i.order_id,i.photo_id,i.designed_path_snapshot,i.quantity
  from public.fts_selfie_print_order_items i
  join public.fts_selfie_print_orders o on o.id=i.order_id
  join public.fts_selfie_events e on e.id=o.event_id
  where e.token=p_event_token or upper(coalesce(e.short_code,''))=upper(p_event_token)
  order by o.created_at desc,i.created_at asc;
end;
$$;

create or replace function public.fts_admin_mark_printed_v45(p_admin_code text,p_order_id uuid)
returns boolean
language plpgsql security definer set search_path='public'
as $$
begin
  if not public.fts_selfie_admin_ok(p_admin_code) then raise exception 'Ungültiger Gerätezugang/Admin-Code'; end if;
  update public.fts_selfie_print_orders
  set print_status='PRINTED',printed_at=coalesce(printed_at,now()),updated_at=now()
  where id=p_order_id and payment_status='COMPLETED' and print_status='READY';
  if not found then return false; end if;
  update public.fts_selfie_print_jobs set status='PRINTED',printed_at=coalesce(printed_at,now())
  where print_order_id=p_order_id and status='READY';
  return true;
end;
$$;

revoke all on function public.fts_selfie_apply_payment_capture_v45(uuid,text,text,text,integer,text,text,text,boolean,jsonb) from public,anon,authenticated;
grant execute on function public.fts_selfie_apply_payment_capture_v45(uuid,text,text,text,integer,text,text,text,boolean,jsonb) to service_role;
grant execute on function public.fts_get_guest_selfies_v45(text,text) to anon,authenticated;
grant execute on function public.fts_admin_get_print_settings_v45(text,text) to anon,authenticated;
grant execute on function public.fts_admin_set_print_settings_v45(text,text,boolean,timestamptz,timestamptz) to anon,authenticated;
grant execute on function public.fts_admin_print_orders_v45(text,text) to anon,authenticated;
grant execute on function public.fts_admin_print_order_items_v45(text,text) to anon,authenticated;
grant execute on function public.fts_admin_mark_printed_v45(text,uuid) to anon,authenticated;
