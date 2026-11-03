create or replace function private.guard_penalty_tournament_room_guest()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.guest_id is null and new.guest_id is not null and new.tournament_match_id is not null
     and not exists (
       select 1 from public.penalty_tournament_matches m
       where m.id = new.tournament_match_id
         and new.guest_id in (m.player_a_id, m.player_b_id)
     ) then
    raise exception 'Only the assigned tournament opponent can join this match';
  end if;
  return new;
end;
$$;
revoke all on function private.guard_penalty_tournament_room_guest() from public, anon, authenticated;
create trigger penalty_rooms_guard_tournament_guest
  before update of guest_id on public.penalty_rooms
  for each row execute function private.guard_penalty_tournament_room_guest();

