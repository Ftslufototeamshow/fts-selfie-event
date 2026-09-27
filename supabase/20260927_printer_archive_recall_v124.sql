-- Build 124 · server-backed archive photo lookup for paid/collected selfies
create or replace function public.fts_printer_archived_photos_v124(
  p_device_token text,
  p_session_token text,
  p_event_token text,
  p_limit integer default 500
)
returns table(
  archive_id uuid,
  photo_id uuid,
  designed_path text,
  original_path text,
  quantity integer,
  archived_at timestamptz
)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_event_id uuid;
begin
  perform public.fts_printer_session_context_v80(p_device_token,p_session_token);
  v_event_id:=public.fts_selfie_resolve_event_id_v50(p_event_token);
  if v_event_id is null then raise exception 'Event nicht gefunden'; end if;

  return query
  select o.id,i.photo_id,i.designed_path_snapshot,p.original_path,i.quantity,o.pickup_archived_at
  from public.fts_selfie_print_orders o
  join public.fts_selfie_print_order_items i on i.order_id=o.id
  left join public.fts_selfie_photos p on p.id=i.photo_id
  where o.event_id=v_event_id
    and o.pickup_status='ARCHIVED'
    and not exists(
      select 1 from public.fts_selfie_printer_archive_hidden_v82 h
      where h.kind='SELFIE' and h.item_id=o.id
    )
  order by o.pickup_archived_at desc,i.created_at
  limit greatest(1,least(coalesce(p_limit,500),2000));
end;
$function$;
