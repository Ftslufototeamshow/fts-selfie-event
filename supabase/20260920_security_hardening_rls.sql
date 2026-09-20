-- 2026-09-20 · Supabase security hardening
-- Enables RLS on previously exposed internal tables and limits browser access.

create or replace function public.nexora_rls_my_family_license_ids()
returns setof uuid
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select fm.family_license_id
  from public.family_members fm
  where fm.user_id = auth.uid();
$$;

revoke all on function public.nexora_rls_my_family_license_ids() from public;
grant execute on function public.nexora_rls_my_family_license_ids() to authenticated;

alter table public.documents enable row level security;
alter table public.settings enable row level security;
alter table public.family_licenses enable row level security;
alter table public.family_members enable row level security;
alter table public.employee_device_limits enable row level security;
alter table public.user_voice_preferences enable row level security;
alter table public.employee_invitation_delivery enable row level security;
alter table public.tester_invitation_delivery enable row level security;

revoke all on table public.documents from anon;
revoke all on table public.settings from anon;
revoke all on table public.family_licenses from anon;
revoke all on table public.family_members from anon;
revoke all on table public.employee_device_limits from anon;
revoke all on table public.user_voice_preferences from anon;
revoke all on table public.employee_invitation_delivery from anon;
revoke all on table public.tester_invitation_delivery from anon;

revoke all on table public.documents from authenticated;
revoke all on table public.settings from authenticated;
revoke all on table public.employee_invitation_delivery from authenticated;
revoke all on table public.tester_invitation_delivery from authenticated;

drop policy if exists "family members can read own family license" on public.family_licenses;
create policy "family members can read own family license"
on public.family_licenses for select to authenticated
using (
  (select auth.uid()) is not null
  and id in (select public.nexora_rls_my_family_license_ids())
);

drop policy if exists "family members can read own family group" on public.family_members;
create policy "family members can read own family group"
on public.family_members for select to authenticated
using (
  (select auth.uid()) is not null
  and family_license_id in (select public.nexora_rls_my_family_license_ids())
);

drop policy if exists "users can read own employee device limit" on public.employee_device_limits;
create policy "users can read own employee device limit"
on public.employee_device_limits for select to authenticated
using (
  (select auth.uid()) is not null
  and employee_user_id = (select auth.uid())
);

drop policy if exists "users can read own voice preference" on public.user_voice_preferences;
create policy "users can read own voice preference"
on public.user_voice_preferences for select to authenticated
using ((select auth.uid()) is not null and user_id = (select auth.uid()));

drop policy if exists "users can insert own voice preference" on public.user_voice_preferences;
create policy "users can insert own voice preference"
on public.user_voice_preferences for insert to authenticated
with check ((select auth.uid()) is not null and user_id = (select auth.uid()));

drop policy if exists "users can update own voice preference" on public.user_voice_preferences;
create policy "users can update own voice preference"
on public.user_voice_preferences for update to authenticated
using ((select auth.uid()) is not null and user_id = (select auth.uid()))
with check ((select auth.uid()) is not null and user_id = (select auth.uid()));

drop policy if exists "users can delete own voice preference" on public.user_voice_preferences;
create policy "users can delete own voice preference"
on public.user_voice_preferences for delete to authenticated
using ((select auth.uid()) is not null and user_id = (select auth.uid()));

grant select on table public.family_licenses to authenticated;
grant select on table public.family_members to authenticated;
grant select on table public.employee_device_limits to authenticated;
grant select, insert, update, delete on table public.user_voice_preferences to authenticated;

drop policy if exists "no direct browser access to documents" on public.documents;
create policy "no direct browser access to documents"
on public.documents for all to anon, authenticated
using (false) with check (false);

drop policy if exists "no direct browser access to settings" on public.settings;
create policy "no direct browser access to settings"
on public.settings for all to anon, authenticated
using (false) with check (false);

drop policy if exists "no direct browser access to employee delivery logs" on public.employee_invitation_delivery;
create policy "no direct browser access to employee delivery logs"
on public.employee_invitation_delivery for all to anon, authenticated
using (false) with check (false);

drop policy if exists "no direct browser access to tester delivery logs" on public.tester_invitation_delivery;
create policy "no direct browser access to tester delivery logs"
on public.tester_invitation_delivery for all to anon, authenticated
using (false) with check (false);
