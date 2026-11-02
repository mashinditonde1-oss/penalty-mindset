-- Shareable penalty rooms for signed-in and anonymous Auth users.
create table public.penalty_rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{10}$'),
  host_id uuid not null references auth.users(id) on delete cascade,
  guest_id uuid references auth.users(id) on delete set null,
  host_name text not null check (char_length(trim(host_name)) between 1 and 24),
  guest_name text check (guest_name is null or char_length(trim(guest_name)) between 1 and 24),
  status text not null default 'waiting' check (status in ('waiting', 'playing', 'completed')),
  kick_no smallint not null default 0 check (kick_no between 0 and 50),
  score_host smallint not null default 0 check (score_host between 0 and 30),
  score_guest smallint not null default 0 check (score_guest between 0 and 30),
  saves_host smallint not null default 0 check (saves_host between 0 and 30),
  saves_guest smallint not null default 0 check (saves_guest between 0 and 30),
  pending_host boolean not null default false,
  pending_guest boolean not null default false,
  score_history jsonb not null default '[]'::jsonb check (jsonb_typeof(score_history) = 'array'),
  last_shot_direction text check (last_shot_direction in ('left', 'center', 'right')),
  last_save_direction text check (last_save_direction in ('left', 'center', 'right')),
  last_goal boolean,
  winner_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours',
  constraint penalty_room_not_self check (guest_id is null or host_id <> guest_id)
);

create index penalty_rooms_host_active_idx on public.penalty_rooms (host_id, status, updated_at desc);
create index penalty_rooms_guest_active_idx on public.penalty_rooms (guest_id, status, updated_at desc);

create table public.penalty_room_moves (
  room_id uuid not null references public.penalty_rooms(id) on delete cascade,
  kick_no smallint not null check (kick_no between 0 and 49),
  player_id uuid not null references auth.users(id) on delete cascade,
  player_side text not null check (player_side in ('host', 'guest')),
  role text not null check (role in ('shooter', 'keeper')),
  direction text not null check (direction in ('left', 'center', 'right')),
  created_at timestamptz not null default now(),
  primary key (room_id, kick_no, player_id)
);

alter table public.penalty_rooms enable row level security;
alter table public.penalty_room_moves enable row level security;

revoke all on public.penalty_rooms from anon, authenticated;
revoke all on public.penalty_room_moves from anon, authenticated;
grant select on public.penalty_rooms to authenticated;
grant insert (id, code, host_id, host_name) on public.penalty_rooms to authenticated;
grant select, insert on public.penalty_room_moves to authenticated;

create policy "Room players can read their rooms"
  on public.penalty_rooms for select to authenticated
  using ((select auth.uid()) = host_id or (select auth.uid()) = guest_id);

create policy "Players can create a clean room"
  on public.penalty_rooms for insert to authenticated
  with check (
    (select auth.uid()) = host_id
    and guest_id is null
    and status = 'waiting'
    and kick_no = 0
    and score_host = 0 and score_guest = 0
    and saves_host = 0 and saves_guest = 0
    and not pending_host and not pending_guest
    and score_history = '[]'::jsonb
    and last_shot_direction is null
    and last_save_direction is null
    and last_goal is null
    and winner_id is null
  );

create policy "Players can read only their own room moves"
  on public.penalty_room_moves for select to authenticated
  using ((select auth.uid()) = player_id);

create policy "Players can submit only their own room moves"
  on public.penalty_room_moves for insert to authenticated
  with check ((select auth.uid()) = player_id);

create or replace function private.guard_penalty_room_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.host_id is distinct from (select auth.uid())
     or new.code !~ '^[A-HJ-NP-Z2-9]{10}$'
     or new.status <> 'waiting'
     or new.guest_id is not null
     or new.kick_no <> 0
     or new.score_host <> 0 or new.score_guest <> 0
     or new.saves_host <> 0 or new.saves_guest <> 0
     or new.pending_host or new.pending_guest
     or new.score_history <> '[]'::jsonb
     or new.last_shot_direction is not null
     or new.last_save_direction is not null
     or new.last_goal is not null
     or new.winner_id is not null
  then
    raise exception 'A new room must start in a clean waiting state';
  end if;
  return new;
end;
$$;

create trigger penalty_rooms_guard_insert
  before insert on public.penalty_rooms
  for each row execute function private.guard_penalty_room_insert();
revoke all on function private.guard_penalty_room_insert() from public, anon, authenticated;

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
begin
  if new.player_id is distinct from (select auth.uid()) then
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

create trigger penalty_room_moves_validate
  before insert on public.penalty_room_moves
  for each row execute function private.validate_penalty_room_move();
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
    updated_at = now()
  where id = r.id;
  return new;
end;
$$;

create trigger penalty_room_moves_resolve
  after insert on public.penalty_room_moves
  for each row execute function private.resolve_penalty_room_move();
revoke all on function private.resolve_penalty_room_move() from public, anon, authenticated;

