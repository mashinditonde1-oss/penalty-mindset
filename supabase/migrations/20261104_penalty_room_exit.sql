alter table public.penalty_rooms
  drop constraint penalty_rooms_status_check,
  add constraint penalty_rooms_status_check
    check (status in ('waiting', 'playing', 'completed', 'disconnected')),
  add column left_by uuid references auth.users(id) on delete set null;

create or replace function public.leave_penalty_room(p_room_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
begin
  if v_user_id is null then
    raise exception 'Sign in or continue as a guest before leaving a room';
  end if;
  if not exists (
    select 1 from public.penalty_rooms
    where id = p_room_id and v_user_id in (host_id, guest_id)
  ) then
    raise exception 'This room is not available to you';
  end if;

  update public.penalty_rooms
     set status = 'disconnected',
         left_by = v_user_id,
         updated_at = now(),
         expires_at = now() + interval '24 hours'
   where id = p_room_id and status = 'playing';

  if found then return true; end if;
  return false;
end;
$$;
revoke all on function public.leave_penalty_room(uuid) from public, anon, authenticated;
grant execute on function public.leave_penalty_room(uuid) to authenticated;

