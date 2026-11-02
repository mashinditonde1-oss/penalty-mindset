-- Give every online room turn a shared deadline and resolve missing choices.
alter table public.penalty_rooms
  add column if not exists turn_started_at timestamptz not null default now();

create or replace function public.join_penalty_room(p_code text, p_guest_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_room_id uuid;
  v_guest_name text := left(trim(regexp_replace(coalesce(p_guest_name, 'Guest'), '[<>]', '', 'g')), 24);
begin
  if v_user_id is null then
    raise exception 'Sign in or continue as a guest before joining a room';
  end if;
  if v_guest_name = '' then v_guest_name := 'Guest'; end if;

  select id into v_room_id
  from public.penalty_rooms
  where code = upper(trim(p_code))
    and status = 'waiting'
    and guest_id is null
    and expires_at > now()
    and host_id <> v_user_id
  for update;

  if not found then
    raise exception 'That room code is invalid, full, or expired';
  end if;

  update public.penalty_rooms
     set guest_id = v_user_id,
         guest_name = v_guest_name,
         status = 'playing',
         turn_started_at = now(),
         updated_at = now()
   where id = v_room_id and status = 'waiting' and guest_id is null;

  if not found then
    raise exception 'Someone just joined that room. Try another code.';
  end if;
  return v_room_id;
end;
$$;
revoke all on function public.join_penalty_room(text, text) from public, anon, authenticated;
grant execute on function public.join_penalty_room(text, text) to authenticated;

create or replace function private.validate_penalty_room_move()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.penalty_rooms%rowtype;
  shooter_side text;
  expected_role text;
  expected_player uuid;
  is_timeout_move boolean := coalesce(current_setting('penalty.room_timeout', true), '') = 'on';
begin
  if new.player_id is distinct from (select auth.uid()) and not is_timeout_move then
    raise exception 'A player can submit only their own room choice';
  end if;

  select * into r from public.penalty_rooms where id = new.room_id for update;
  if not found or r.status <> 'playing' then
    raise exception 'This room is not accepting choices';
  end if;
  if new.kick_no <> r.kick_no then
    raise exception 'This choice is for an old or future kick';
  end if;

  shooter_side := case when mod(r.kick_no, 2) = 0 then 'host' else 'guest' end;
  expected_role := case when new.player_side = shooter_side then 'shooter' else 'keeper' end;
  expected_player := case when new.player_side = 'host' then r.host_id else r.guest_id end;
  if new.player_side not in ('host', 'guest')
     or new.player_id is distinct from expected_player
     or new.role <> expected_role
  then
    raise exception 'Invalid player side or role for this kick';
  end if;
  return new;
end;
$$;
revoke all on function private.validate_penalty_room_move() from public, anon, authenticated;

create or replace function private.resolve_penalty_room_move()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.penalty_rooms%rowtype;
  move_count smallint;
  shooter_side text;
  keeper_side text;
  shooter_id uuid;
  keeper_id uuid;
  shot_dir text;
  save_dir text;
  scored boolean;
  next_kick smallint;
  new_score_host smallint;
  new_score_guest smallint;
  new_saves_host smallint;
  new_saves_guest smallint;
  remaining_host integer;
  remaining_guest integer;
  is_complete boolean;
  won_by uuid;
  new_history jsonb;
begin
  select * into r from public.penalty_rooms where id = new.room_id for update;
  select count(*)::smallint into move_count
    from public.penalty_room_moves
    where room_id = new.room_id and kick_no = new.kick_no;

  if move_count < 2 then
    update public.penalty_rooms
       set pending_host = (new.player_side = 'host'),
           pending_guest = (new.player_side = 'guest'),
           updated_at = now()
     where id = r.id;
    return new;
  end if;

  shooter_side := case when mod(new.kick_no, 2) = 0 then 'host' else 'guest' end;
  keeper_side := case when shooter_side = 'host' then 'guest' else 'host' end;
  shooter_id := case when shooter_side = 'host' then r.host_id else r.guest_id end;
  keeper_id := case when keeper_side = 'host' then r.host_id else r.guest_id end;
  select direction into shot_dir from public.penalty_room_moves
    where room_id = r.id and kick_no = new.kick_no and player_id = shooter_id;
  select direction into save_dir from public.penalty_room_moves
    where room_id = r.id and kick_no = new.kick_no and player_id = keeper_id;

  scored := shot_dir <> save_dir;
  new_score_host := r.score_host + case when scored and shooter_side = 'host' then 1 else 0 end;
  new_score_guest := r.score_guest + case when scored and shooter_side = 'guest' then 1 else 0 end;
  new_saves_host := r.saves_host + case when not scored and keeper_side = 'host' then 1 else 0 end;
  new_saves_guest := r.saves_guest + case when not scored and keeper_side = 'guest' then 1 else 0 end;
  next_kick := r.kick_no + 1;
  new_history := r.score_history || jsonb_build_array(jsonb_build_object(
    'kick_no', r.kick_no,
    'shooter_side', shooter_side,
    'scored', scored,
    'shot_direction', shot_dir,
    'save_direction', save_dir
  ));

  select count(*)::integer into remaining_host
    from generate_series(next_kick::integer, 9) n where mod(n, 2) = 0;
  select count(*)::integer into remaining_guest
    from generate_series(next_kick::integer, 9) n where mod(n, 2) = 1;
  is_complete := next_kick >= 50
    or (next_kick = 10 and new_score_host <> new_score_guest)
    or (next_kick < 10 and (new_score_host > new_score_guest + remaining_guest
      or new_score_guest > new_score_host + remaining_host))
    or (next_kick >= 12 and mod(next_kick, 2) = 0 and new_score_host <> new_score_guest);
  won_by := case when new_score_host > new_score_guest then r.host_id
                 when new_score_guest > new_score_host then r.guest_id else null end;

  update public.penalty_rooms set
    kick_no = next_kick,
    score_host = new_score_host,
    score_guest = new_score_guest,
    saves_host = new_saves_host,
    saves_guest = new_saves_guest,
    pending_host = false,
    pending_guest = false,
    score_history = new_history,
    last_shot_direction = shot_dir,
    last_save_direction = save_dir,
    last_goal = scored,
    status = case when is_complete then 'completed' else 'playing' end,
    winner_id = case when is_complete then won_by else null end,
    turn_started_at = now(),
    updated_at = now()
  where id = r.id;
  return new;
end;
$$;
revoke all on function private.resolve_penalty_room_move() from public, anon, authenticated;

create or replace function public.expire_penalty_room_turn(p_room_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.penalty_rooms%rowtype;
  side text;
  player uuid;
  shooter_side text;
  move_role text;
  direction text;
begin
  select * into r from public.penalty_rooms where id = p_room_id for update;
  if not found or (select auth.uid()) not in (r.host_id, r.guest_id) then
    raise exception 'This room is not available to you';
  end if;
  if r.status <> 'playing' or r.turn_started_at > now() - interval '10 seconds' then
    return false;
  end if;

  shooter_side := case when mod(r.kick_no, 2) = 0 then 'host' else 'guest' end;
  perform set_config('penalty.room_timeout', 'on', true);
  foreach side in array array['host', 'guest'] loop
    player := case when side = 'host' then r.host_id else r.guest_id end;
    if not exists (
      select 1 from public.penalty_room_moves
      where room_id = r.id and kick_no = r.kick_no and player_id = player
    ) then
      move_role := case when side = shooter_side then 'shooter' else 'keeper' end;
      direction := case floor(random() * 3)::integer
        when 0 then 'left' when 1 then 'center' else 'right' end;
      insert into public.penalty_room_moves
        (room_id, kick_no, player_id, player_side, role, direction)
      values (r.id, r.kick_no, player, side, move_role, direction)
      on conflict (room_id, kick_no, player_id) do nothing;
    end if;
  end loop;
  return true;
end;
$$;
revoke all on function public.expire_penalty_room_turn(uuid) from public, anon, authenticated;
grant execute on function public.expire_penalty_room_turn(uuid) to authenticated;

