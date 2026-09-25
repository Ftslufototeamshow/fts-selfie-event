-- FTS MySelfie v94 · SumUp is the global guest-payment provider.
-- One server-side SumUp API key is used for all events. New events inherit SumUp automatically.

alter table public.fts_selfie_print_settings
  alter column payment_provider set default 'sumup',
  alter column sumup_environment set default 'live';

alter table public.fts_selfie_print_orders
  alter column payment_provider set default 'sumup',
  alter column sumup_environment set default 'live';

update public.fts_selfie_print_settings
set payment_provider='sumup',sumup_environment='live',updated_at=now()
where billing_mode='guest_paypal';

create or replace function public.fts_selfie_init_print_settings_v94()
returns trigger
language plpgsql
security definer
set search_path='public'
as $$
begin
  insert into public.fts_selfie_print_settings(
    event_id,enabled,unit_price_cents,currency,paypal_environment,billing_mode,
    payment_provider,sumup_environment,updated_at
  )
  values(new.id,false,200,'EUR','sandbox','guest_paypal','sumup','live',now())
  on conflict(event_id) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_fts_selfie_init_print_settings_v94 on public.fts_selfie_events;
create trigger trg_fts_selfie_init_print_settings_v94
after insert on public.fts_selfie_events
for each row execute function public.fts_selfie_init_print_settings_v94();

-- fts_admin_get_print_settings_v47 and fts_admin_set_print_settings_v47 are replaced
-- in production by migration v94 so opening/saving any event preserves SumUp/live.
