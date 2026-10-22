-- FTS Selfie Event v153
-- Material/stock changes must wake the Print Station without periodic polling.

do $$
declare t text;
begin
  foreach t in array array[
    'fts_selfie_print_stock_config_v70',
    'fts_selfie_print_stock_ledger_v70',
    'fts_selfie_print_stock_reservations_v70'
  ]
  loop
    if to_regclass('public.'||t) is not null then
      execute format('drop trigger if exists fts_print_stock_signal_v153 on public.%I',t);
      execute format(
        'create trigger fts_print_stock_signal_v153 after insert or update or delete on public.%I for each statement execute function public.fts_touch_print_signal_v150()',
        t
      );
    end if;
  end loop;
end $$;
