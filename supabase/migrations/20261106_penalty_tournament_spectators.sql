create or replace function public.create_penalty_tournament_room(p_match_id uuid, p_room_id uuid, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.penalty_tournament_matches%rowtype;
  t public.penalty_tournaments%rowtype;
  v_user_id uuid := (select auth.uid());
  v_other_id uuid;
  v_name text;
  v_other_name text;
begin
  select * into m from public.penalty_tournament_matches where id = p_match_id for update;
  if not found or v_user_id is null or v_user_id not in (m.player_a_id, m.player_b_id) then
    raise exception 'You are not a player in this fixture';
  end if;
  select * into t from public.penalty_tournaments where id = m.tournament_id for update;
  if t.status <> 'playing' or m.status <> 'pending' or m.room_id is not null then
    raise exception 'This fixture already has a room';
  end if;
  if exists (
    select 1 from public.penalty_tournament_matches active
    where active.tournament_id = m.tournament_id and active.id <> m.id
      and active.status in ('waiting', 'playing')
      and (active.player_a_id in (m.player_a_id, m.player_b_id) or active.player_b_id in (m.player_a_id, m.player_b_id))
  ) then
    raise exception 'One of these players is already in another live fixture';
  end if;
  if upper(trim(p_code)) !~ '^[A-HJ-NP-Z2-9]{10}$' then raise exception 'Invalid room code'; end if;
  select display_name into v_name from public.penalty_tournament_players where tournament_id = m.tournament_id and player_id = v_user_id;
  v_other_id := case when v_user_id = m.player_a_id then m.player_b_id else m.player_a_id end;
  select display_name into v_other_name from public.penalty_tournament_players where tournament_id = m.tournament_id and player_id = v_other_id;
  insert into public.penalty_rooms(id, code, host_id, host_name, tournament_match_id)
  values (p_room_id, upper(trim(p_code)), v_user_id, v_name, m.id);
  update public.penalty_tournament_matches
    set room_id = p_room_id, room_code = upper(trim(p_code)), status = 'waiting'
    where id = m.id;
  return jsonb_build_object('id', p_room_id, 'code', upper(trim(p_code)), 'opponent_id', v_other_id, 'opponent_name', v_other_name);
end;
$$;
revoke all on function public.create_penalty_tournament_room(uuid, uuid, text) from public, anon;
grant execute on function public.create_penalty_tournament_room(uuid, uuid, text) to authenticated;

create or replace function public.get_penalty_tournament_live(p_tournament_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  live_matches jsonb;
begin
  if not private.is_penalty_tournament_player(p_tournament_id) then
    raise exception 'You are not in this tournament';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'match_id', m.id,
    'player_a_id', m.player_a_id,
    'player_b_id', m.player_b_id,
    'player_a_name', a.display_name,
    'player_b_name', b.display_name,
    'status', m.status,
    'room_status', r.status,
    'host_name', r.host_name,
    'guest_name', r.guest_name,
    'score_host', coalesce(r.score_host, 0),
    'score_guest', coalesce(r.score_guest, 0),
    'kick_no', coalesce(r.kick_no, 0),
    'pending_host', coalesce(r.pending_host, false),
    'pending_guest', coalesce(r.pending_guest, false),
    'score_history', coalesce(r.score_history, '[]'::jsonb),
    'turn_started_at', r.turn_started_at
  ) order by m.created_at), '[]'::jsonb)
  into live_matches
  from public.penalty_tournament_matches m
  join public.penalty_tournament_players a on a.tournament_id = m.tournament_id and a.player_id = m.player_a_id
  join public.penalty_tournament_players b on b.tournament_id = m.tournament_id and b.player_id = m.player_b_id
  left join public.penalty_rooms r on r.id = m.room_id
  where m.tournament_id = p_tournament_id and m.status in ('waiting', 'playing');
  return live_matches;
end;
$$;
revoke all on function public.get_penalty_tournament_live(uuid) from public, anon;
grant execute on function public.get_penalty_tournament_live(uuid) to authenticated;

