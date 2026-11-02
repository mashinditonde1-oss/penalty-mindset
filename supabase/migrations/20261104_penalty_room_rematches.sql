alter table public.penalty_rooms
  add column rematch_host boolean not null default false,
  add column rematch_guest boolean not null default false,
  add column rematch_room_id uuid references public.penalty_rooms(id) on delete set null,
  add column is_rematch boolean not null default false;

create or replace function public.request_penalty_room_rematch(p_room_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  r public.penalty_rooms%rowtype;
  v_room_id uuid := gen_random_uuid();
  v_other_id uuid;
  v_current_name text;
  v_other_name text;
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text;
  i integer;
begin
  if v_user_id is null then
    raise exception 'Sign in or continue as a guest to rematch';
  end if;

  select * into r from public.penalty_rooms where id = p_room_id for update;
  if not found or v_user_id not in (r.host_id, r.guest_id) then
    raise exception 'This match is not available to you';
  end if;
  if r.status <> 'completed' then
    raise exception 'A rematch is available after the shootout ends';
  end if;
  if r.rematch_room_id is not null then return r.rematch_room_id; end if;

  update public.penalty_rooms set
    rematch_host = rematch_host or v_user_id = r.host_id,
    rematch_guest = rematch_guest or v_user_id = r.guest_id,
    updated_at = now()
  where id = r.id
  returning * into r;

  if not r.rematch_host or not r.rematch_guest then return null; end if;

  v_other_id := case when v_user_id = r.host_id then r.guest_id else r.host_id end;
  v_current_name := case when v_user_id = r.host_id then r.host_name else r.guest_name end;
  v_other_name := case when v_user_id = r.host_id then r.guest_name else r.host_name end;

  loop
    v_code := '';
    for i in 1..10 loop
      v_code := v_code || substr(v_alphabet, floor(random() * length(v_alphabet) + 1)::integer, 1);
    end loop;
    exit when not exists (select 1 from public.penalty_rooms where code = v_code);
  end loop;

  insert into public.penalty_rooms(id, code, host_id, host_name, status, is_rematch)
  values (v_room_id, v_code, v_user_id, coalesce(v_current_name, 'Guest'), 'waiting', true);

  update public.penalty_rooms set
    guest_id = v_other_id,
    guest_name = coalesce(v_other_name, 'Guest'),
    status = 'playing',
    turn_started_at = now(),
    updated_at = now()
  where id = v_room_id;

  update public.penalty_rooms set rematch_room_id = v_room_id where id = r.id;
  return v_room_id;
end;
$$;
revoke all on function public.request_penalty_room_rematch(uuid) from public, anon, authenticated;
grant execute on function public.request_penalty_room_rematch(uuid) to authenticated;

