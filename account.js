(() => {
  'use strict';
  const PROJECT_URL = 'https://obknxomnliwjdpsxcqkc.supabase.co';
  const PUBLIC_KEY = 'sb_publishable_Qe3gk5Wx48j_YhyJypoR8Q_2xmbnCNL';
  const PRODUCTION_URL = 'https://penalty-mindset.pages.dev/';
  function signupRedirectUrl() {
    const localHosts = ['localhost', '127.0.0.1', '[::1]'];
    return location.origin === 'null' || localHosts.includes(location.hostname)
      ? PRODUCTION_URL
      : `${location.origin}/`;
  }
  const $ = (s) => document.querySelector(s);
  const escape = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  const style = document.createElement('style');
  style.textContent = '.account-error{font-size:12px;color:#ff9b91;min-height:18px;margin:5px 0}.account-switch,.account-signout{width:100%;margin-top:12px}.friend-list{display:grid;gap:7px;margin-top:18px;max-height:260px;overflow:auto}.friend-entry{display:flex;align-items:center;justify-content:space-between;gap:8px;border-top:1px solid #ffffff12;padding:11px 0}.friend-entry strong{font-size:13px}.friend-entry small{display:block;color:#9bb0b8;font-size:11px}.friend-entry button{font-size:11px;padding:7px 10px}.account-tabs{display:flex;gap:7px;margin:8px 0 12px}.account-tabs button{flex:1}.rank-summary{color:#9bb0b8;font-size:12px;margin:5px 0 12px}.online-section-title{font:700 20px var(--display);text-transform:uppercase;letter-spacing:.04em;margin:18px 0 0}.online-choice{min-width:86px}.online-wait{color:#d6f36a;font-weight:700}.live-badge{display:inline-flex;gap:7px;align-items:center;color:#d6f36a;font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase}.live-badge:before{content:"";width:7px;height:7px;border-radius:50%;background:#d6f36a;box-shadow:0 0 10px #d6f36a}';
  style.textContent += '.modal{max-height:90vh;overflow:auto}.room-panel{border:1px solid #ffffff16;background:#ffffff06;border-radius:14px;padding:13px;margin-top:10px}.room-panel>.btn{width:100%;margin-top:10px}.room-panel .field{margin:12px 0 0}.room-share{display:grid;gap:8px;border-top:1px solid #ffffff18;margin-top:14px;padding-top:13px}.room-share strong{font:800 30px var(--display);letter-spacing:.12em;color:var(--lime);overflow-wrap:anywhere}.room-share small{font-size:11px;color:var(--muted);overflow-wrap:anywhere}.room-share[hidden]{display:none}';
  document.head.append(style);
  let session = readSession(), user = null, profile = null, friends = [], authMode = 'signin', savingMatch = false;
  let realtimeClient = null, realtimeChannel = null, activeOnlineId = null, activeOnlineMatch = null, activeOpponent = null, lastRenderedKick = 0, onlineRenderVersion = 0, onlineSubmitting = false;
  let roomIdentity = null, activeRoomMeta = null, activeRoomData = null, roomPollTimer = null, roomClockTimer = null, roomTimeoutKey = '', roomTimeoutBusy = false, roomPollBusy = false, lastRoomKick = -1, roomSubmitting = false, roomMatchStarted = false, onlineFieldResetTimer = null;
  try { realtimeClient = window.supabase?.createClient(PROJECT_URL, PUBLIC_KEY, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } }) || null; } catch { realtimeClient = null; }

  function readSession() { try { const old = JSON.parse(localStorage.getItem('pm-auth-session') || 'null'); const fragment = new URLSearchParams(location.hash.slice(1)); const access_token = fragment.get('access_token'); const refresh_token = fragment.get('refresh_token'); if (access_token && refresh_token) { const fresh = { access_token, refresh_token, expires_at: Math.floor(Date.now() / 1000) + Number(fragment.get('expires_in') || 3600) }; localStorage.setItem('pm-auth-session', JSON.stringify(fresh)); history.replaceState(null, '', location.pathname + location.search); return fresh; } return old; } catch { return null; } }
  function storeSession(value) { session = value; try { value ? localStorage.setItem('pm-auth-session', JSON.stringify(value)) : localStorage.removeItem('pm-auth-session'); } catch {} if (realtimeClient) realtimeClient.realtime.setAuth(value?.access_token || PUBLIC_KEY); }
  function say(target, message) { const el = $(target); if (el) el.textContent = message || ''; }
  function authHeaders(extra = {}) { return { apikey: PUBLIC_KEY, Authorization: `Bearer ${session?.access_token || PUBLIC_KEY}`, 'Content-Type': 'application/json', ...extra }; }
  async function refreshSession() {
    if (!session?.refresh_token) return false;
    const r = await fetch(`${PROJECT_URL}/auth/v1/token?grant_type=refresh_token`, { method: 'POST', headers: { apikey: PUBLIC_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ refresh_token: session.refresh_token }) });
    const d = await r.json().catch(() => ({}));
    if (!r.ok || !d.access_token) { storeSession(null); user = profile = null; return false; }
    storeSession({ ...d, expires_at: Math.floor(Date.now() / 1000) + (d.expires_in || 3600) });
    return true;
  }
  async function authRequest(path, options = {}) {
    if (session && session.expires_at && session.expires_at < Math.floor(Date.now() / 1000) + 30) await refreshSession();
    const r = await fetch(`${PROJECT_URL}${path}`, { ...options, headers: authHeaders(options.headers || {}) });
    const body = await r.json().catch(() => null);
    if (r.status === 401 && session?.refresh_token && await refreshSession()) return authRequest(path, options);
    if (!r.ok) throw new Error(body?.msg || body?.message || body?.error_description || body?.hint || 'Request failed. Please try again.');
    return body;
  }
  const rest = (table, query, options = {}) => authRequest(`/rest/v1/${table}${query ? `?${query}` : ''}`, options);
  const profileFor = async (id) => {
    const rows = await rest('penalty_profiles', `select=user_id,username,display_name&user_id=eq.${id}&limit=1`);
    return rows?.[0] || null;
  };
  function updateAccountUi() {
    $('#nameButton').hidden = Boolean(profile);
    $('#accountButton').textContent = profile ? `@${profile.username}` : user ? 'Finish profile' : 'Sign in';
    $('#friendsButton').textContent = `Friends${friends.filter((f) => f.status === 'pending' && f.recipient_id === user?.id).length ? ' · 1' : ''}`;
    if (profile && typeof window.penaltyMindsetSetName === 'function') window.penaltyMindsetSetName(profile.display_name);
  }
  async function loadAccount() {
    if (!session?.access_token) { updateAccountUi(); return; }
    try {
      if (!session.expires_at || session.expires_at < Math.floor(Date.now() / 1000) + 30) await refreshSession();
      if (!session) return updateAccountUi();
      user = await authRequest('/auth/v1/user');
      profile = await profileFor(user.id);
      if (!profile) {
        const suggested = (localStorage.getItem('pm-name') || user.email?.split('@')[0] || 'taker').toLowerCase().replace(/[^a-z0-9_]/g, '_').slice(0, 18);
        $('#profileHandle').value = suggested.length >= 3 ? suggested : 'taker_' + suggested;
        $('#profileDisplay').value = localStorage.getItem('pm-name') || user.email?.split('@')[0] || '';
        $('#profileModal').classList.add('open');
      }
      await loadFriends();
      connectRealtime();
    } catch (e) { say('#accountError', e.message); }
    updateAccountUi();
  }
  function connectRealtime() {
    if (!realtimeClient || !user || !session?.access_token) { say('#onlineError', 'Live connections are unavailable. Refresh and try again.'); return; }
    realtimeClient.realtime.setAuth(session.access_token);
    if (realtimeChannel) return;
    realtimeChannel = realtimeClient.channel(`penalty-live-${user.id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'penalty_online_matches' }, (payload) => {
        const id = payload.new?.id || payload.old?.id;
        if (id && id === activeOnlineId) refreshOnlineMatch();
        if ($('#onlineModal').classList.contains('open')) loadOnlineLobby();
      })
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') say('#onlineError', 'Live updates disconnected. Reopen the online lobby to reconnect.');
      });
  }
  async function setAuthMode(next) {
    authMode = next;
    $('#accountTitle').textContent = next === 'signup' ? 'Create your account' : 'Welcome back';
    $('#accountCopy').textContent = next === 'signup' ? 'Join the table, track your form, and find friends.' : 'Sign in to save your record and add friends.';
    $('#accountSubmit').textContent = next === 'signup' ? 'Create account' : 'Sign in';
    $('#accountSwitch').textContent = next === 'signup' ? 'Already have an account? Sign in' : 'New here? Create an account';
    $('#accountPassword').autocomplete = next === 'signup' ? 'new-password' : 'current-password';
    say('#accountError', '');
  }
  $('#accountButton').addEventListener('click', () => {
    if (user && profile) { $('#socialModal').classList.add('open'); loadFriends(); return; }
    $('#accountModal').classList.add('open');
  });
  $('#accountSwitch').addEventListener('click', () => setAuthMode(authMode === 'signin' ? 'signup' : 'signin'));
  $('#accountSubmit').addEventListener('click', async () => {
    const email = $('#accountEmail').value.trim(), password = $('#accountPassword').value;
    say('#accountError', '');
    if (!email || password.length < 8) return say('#accountError', 'Enter your email and a password of at least 8 characters.');
    $('#accountSubmit').disabled = true;
    try {
      const path = authMode === 'signup' ? '/auth/v1/signup?redirect_to=' + encodeURIComponent(signupRedirectUrl()) : '/auth/v1/token?grant_type=password';
      const r = await fetch(PROJECT_URL + path, { method: 'POST', headers: { apikey: PUBLIC_KEY, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) });
      const d = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(d.msg || d.message || d.error_description || 'Could not sign in.');
      if (!d.access_token) { say('#accountError', 'Check your email to confirm your account, then come back and sign in.'); return; }
      d.expires_at = Math.floor(Date.now() / 1000) + (d.expires_in || 3600);
      storeSession(d); $('#accountModal').classList.remove('open'); await loadAccount();
    } catch (e) { say('#accountError', e.message); }
    finally { $('#accountSubmit').disabled = false; }
  });
  $('#profileSave').addEventListener('click', async () => {
    if (!user) return;
    const username = $('#profileHandle').value.trim().toLowerCase(), display_name = $('#profileDisplay').value.trim();
    if (!/^[a-z0-9_]{3,18}$/.test(username)) return say('#profileError', 'Use 3–18 lowercase letters, numbers, or underscores.');
    if (!display_name || display_name.length > 24) return say('#profileError', 'Display name must be 1–24 characters.');
    $('#profileSave').disabled = true;
    try {
      await rest('penalty_profiles', 'on_conflict=user_id', { method: 'POST', headers: { Prefer: 'resolution=merge-duplicates,return=representation' }, body: JSON.stringify({ user_id: user.id, username, display_name }) });
      profile = await profileFor(user.id); $('#profileModal').classList.remove('open'); updateAccountUi(); connectRealtime(); await loadFriends();
    } catch (e) { say('#profileError', e.message); }
    finally { $('#profileSave').disabled = false; }
  });
  async function loadFriends() {
    if (!user) return;
    try {
      const links = await rest('penalty_friendships', `select=id,requester_id,recipient_id,status,created_at&or=(requester_id.eq.${user.id},recipient_id.eq.${user.id})&order=created_at.desc`);
      friends = links || [];
      const ids = [...new Set(friends.map((f) => f.requester_id === user.id ? f.recipient_id : f.requester_id))];
      const people = ids.length ? await rest('penalty_profiles', `select=user_id,username,display_name&user_id=in.(${ids.join(',')})`) : [];
      const byId = Object.fromEntries(people.map((p) => [p.user_id, p]));
      const list = $('#friendList'); list.replaceChildren();
      if (!friends.length) { const empty = document.createElement('p'); empty.className = 'rank-summary'; empty.textContent = 'No friends yet. Add someone by their exact handle.'; list.append(empty); }
      for (const f of friends) {
        const otherId = f.requester_id === user.id ? f.recipient_id : f.requester_id, person = byId[otherId];
        const row = document.createElement('div'); row.className = 'friend-entry';
        const details = document.createElement('div'); details.innerHTML = `<strong>${escape(person?.display_name || 'Player')}</strong><small>@${escape(person?.username || 'unknown')} · ${f.status === 'accepted' ? 'Friend' : f.recipient_id === user.id ? 'Incoming request' : 'Request sent'}</small>`;
        row.append(details);
        if (f.status === 'pending' && f.recipient_id === user.id) { const accept = document.createElement('button'); accept.className = 'btn btn-primary'; accept.textContent = 'Accept'; accept.addEventListener('click', () => acceptFriend(f.id)); row.append(accept); }
        if (f.status === 'pending' && f.requester_id === user.id) { const cancel = document.createElement('button'); cancel.className = 'quiet'; cancel.textContent = 'Cancel'; cancel.addEventListener('click', () => removeFriendRequest(f.id)); row.append(cancel); }
        list.append(row);
      }
      updateAccountUi();
    } catch (e) { say('#friendError', e.message); }
  }
  $('#sendFriend').addEventListener('click', async () => {
    if (!user || !profile) return say('#friendError', 'Sign in and choose a player handle first.');
    const handle = $('#friendHandle').value.trim().toLowerCase();
    if (!/^[a-z0-9_]{3,18}$/.test(handle)) return say('#friendError', 'Enter a valid player handle.');
    try {
      const matches = await rest('penalty_profiles', `select=user_id,username&username=eq.${encodeURIComponent(handle)}&limit=1`);
      if (!matches.length) throw new Error('No player found with that handle.');
      if (matches[0].user_id === user.id) throw new Error('That is your own handle.');
      await rest('penalty_friendships', '', { method: 'POST', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ requester_id: user.id, recipient_id: matches[0].user_id }) });
      $('#friendHandle').value = ''; say('#friendError', 'Request sent.'); await loadFriends();
    } catch (e) { say('#friendError', e.message); }
  });
  async function acceptFriend(id) { try { await rest('penalty_friendships', `id=eq.${id}&recipient_id=eq.${user.id}&status=eq.pending`, { method: 'PATCH', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ status: 'accepted', updated_at: new Date().toISOString() }) }); await loadFriends(); } catch (e) { say('#friendError', e.message); } }
  async function removeFriendRequest(id) { try { await rest('penalty_friendships', `id=eq.${id}&requester_id=eq.${user.id}&status=eq.pending`, { method: 'DELETE', headers: { Prefer: 'return=minimal' } }); await loadFriends(); } catch (e) { say('#friendError', e.message); } }
  const showEmpty = (target, message) => { const p = document.createElement('p'); p.className = 'rank-summary'; p.textContent = message; $(target).replaceChildren(p); };
  async function loadOnlineLobby() {
    const inviteHost = $('#onlineInvites'), friendHost = $('#onlineFriends');
    if (!user || !profile) { showEmpty('#onlineInvites', 'Sign in to see friend invites. Room play is open to everyone.'); showEmpty('#onlineFriends', 'Sign in and set a handle to challenge accepted friends.'); return; }
    if (!realtimeChannel) connectRealtime();
    try {
      const [matches, accepted] = await Promise.all([
        rest('penalty_online_matches', `select=id,inviter_id,invitee_id,status,score_inviter,score_invitee,updated_at&or=(inviter_id.eq.${user.id},invitee_id.eq.${user.id})&status=in.(invited,playing)&order=updated_at.desc`),
        Promise.resolve(friends.filter((f) => f.status === 'accepted'))
      ]);
      const ids = [...new Set([...matches.flatMap((m) => [m.inviter_id, m.invitee_id]), ...accepted.map((f) => f.requester_id === user.id ? f.recipient_id : f.requester_id)])].filter((id) => id !== user.id);
      const people = ids.length ? await rest('penalty_profiles', `select=user_id,username,display_name&user_id=in.(${ids.join(',')})`) : [];
      const byId = Object.fromEntries(people.map((p) => [p.user_id, p]));
      inviteHost.replaceChildren();
      if (!matches.length) showEmpty('#onlineInvites', 'No active invites. Challenge a friend below.');
      for (const m of matches) {
        const otherId = m.inviter_id === user.id ? m.invitee_id : m.inviter_id, other = byId[otherId];
        const row = document.createElement('div'); row.className = 'friend-entry';
        const details = document.createElement('div');
        const statusText = m.status === 'playing' ? `${m.score_inviter} – ${m.score_invitee} · live` : m.inviter_id === user.id ? 'Invitation sent' : 'Wants a shootout';
        details.innerHTML = `<strong>${escape(other?.display_name || 'Player')}</strong><small>@${escape(other?.username || '')} · ${statusText}</small>`;
        row.append(details);
        if (m.status === 'invited' && m.invitee_id === user.id) {
          const accept = document.createElement('button'); accept.className = 'btn btn-primary'; accept.textContent = 'Accept'; accept.addEventListener('click', () => answerOnlineInvite(m.id, true)); row.append(accept);
          const decline = document.createElement('button'); decline.className = 'quiet'; decline.textContent = 'Decline'; decline.addEventListener('click', () => answerOnlineInvite(m.id, false)); row.append(decline);
        } else if (m.status === 'playing') {
          const rejoin = document.createElement('button'); rejoin.className = 'btn btn-primary'; rejoin.textContent = 'Rejoin'; rejoin.addEventListener('click', () => openOnlineMatch(m.id)); row.append(rejoin);
        }
        inviteHost.append(row);
      }
      friendHost.replaceChildren();
      if (!accepted.length) showEmpty('#onlineFriends', 'Add and accept friends first, then challenge them here.');
      for (const f of accepted) {
        const otherId = f.requester_id === user.id ? f.recipient_id : f.requester_id, other = byId[otherId];
        if (!other) continue;
        const row = document.createElement('div'); row.className = 'friend-entry';
        const details = document.createElement('div'); details.innerHTML = `<strong>${escape(other.display_name)}</strong><small>@${escape(other.username)}</small>`;
        const challenge = document.createElement('button'); challenge.className = 'btn btn-primary'; challenge.textContent = 'Challenge'; challenge.addEventListener('click', () => createOnlineInvite(other.user_id));
        row.append(details, challenge); friendHost.append(row);
      }
    } catch (e) { say('#onlineError', e.message); }
  }

  function roomDisplayName() {
    const raw = profile?.display_name || localStorage.getItem('pm-name') || user?.email?.split('@')[0] || 'Guest';
    return String(raw).trim().replace(/[<>]/g, '').slice(0, 24) || 'Guest';
  }
  function newRoomCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    const bytes = new Uint8Array(10);
    crypto.getRandomValues(bytes);
    return Array.from(bytes, (byte) => alphabet[byte % alphabet.length]).join('');
  }
  function readSavedRoomSession() {
    try { return JSON.parse(localStorage.getItem('pm-room-session') || 'null'); } catch { return null; }
  }
  async function authUserForToken(accessToken) {
    if (!accessToken) return null;
    const r = await fetch(`${PROJECT_URL}/auth/v1/user`, { headers: { apikey: PUBLIC_KEY, Authorization: `Bearer ${accessToken}` } });
    return r.ok ? r.json().catch(() => null) : null;
  }
  async function refreshGuestSession(saved) {
    if (!saved?.refresh_token) return null;
    if (!saved.expires_at || saved.expires_at > Math.floor(Date.now() / 1000) + 45) return saved;
    const r = await fetch(`${PROJECT_URL}/auth/v1/token?grant_type=refresh_token`, {
      method: 'POST', headers: { apikey: PUBLIC_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ refresh_token: saved.refresh_token })
    });
    const d = await r.json().catch(() => ({}));
    if (!r.ok || !d.access_token) return null;
    d.expires_at = Math.floor(Date.now() / 1000) + (d.expires_in || 3600);
    try { localStorage.setItem('pm-room-session', JSON.stringify(d)); } catch {}
    return d;
  }
  async function getRoomIdentity() {
    const targetId = activeRoomMeta?.playerId;
    if (roomIdentity && (targetId ? roomIdentity.user.id === targetId : roomIdentity.permanent)) {
      if (roomIdentity.permanent) {
        if (session?.expires_at && session.expires_at < Math.floor(Date.now() / 1000) + 45) await refreshSession();
        if (session?.access_token) roomIdentity.session = session;
      } else {
        roomIdentity.session = await refreshGuestSession(roomIdentity.session) || roomIdentity.session;
      }
      return roomIdentity;
    }

    let mainIdentity = null;
    if (session?.access_token) {
      if (session.expires_at && session.expires_at < Math.floor(Date.now() / 1000) + 45) await refreshSession();
      if (session?.access_token) {
        const authUser = user?.id ? user : await authUserForToken(session.access_token);
        if (authUser?.id) mainIdentity = { user: authUser, session, permanent: !authUser.is_anonymous };
      }
    }

    let cachedIdentity = null;
    let saved = readSavedRoomSession();
    if (saved) {
      saved = await refreshGuestSession(saved);
      const authUser = saved?.access_token ? await authUserForToken(saved.access_token) : null;
      if (authUser?.id) cachedIdentity = { user: authUser, session: saved, permanent: !authUser.is_anonymous };
      else { try { localStorage.removeItem('pm-room-session'); } catch {} }
    }

    if (targetId) {
      const matched = [mainIdentity, cachedIdentity].find((candidate) => candidate?.user.id === targetId);
      if (!matched) throw new Error('This browser no longer has the room session. Reopen the room on the device that created or joined it.');
      roomIdentity = matched;
      return roomIdentity;
    }
    if (mainIdentity && !mainIdentity.user.is_anonymous) { roomIdentity = mainIdentity; return roomIdentity; }
    if (cachedIdentity && cachedIdentity.user.is_anonymous) { roomIdentity = cachedIdentity; return roomIdentity; }
    if (mainIdentity) { roomIdentity = mainIdentity; return roomIdentity; }
    if (cachedIdentity) { roomIdentity = cachedIdentity; return roomIdentity; }

    if (!realtimeClient) throw new Error('Guest rooms are unavailable right now. Refresh and try again.');
    const { data, error } = await realtimeClient.auth.signInAnonymously();
    if (error || !data?.session || !data.user) {
      const message = error?.message || 'Could not start a guest session.';
      if (/anonymous/i.test(message) && /disabled|not enabled|not allowed/i.test(message)) {
        throw new Error('Guest rooms need “Allow anonymous sign-ins” enabled in Supabase Auth settings.');
      }
      throw new Error(message);
    }
    const guestSession = data.session;
    guestSession.expires_at ||= Math.floor(Date.now() / 1000) + (guestSession.expires_in || 3600);
    try { localStorage.setItem('pm-room-session', JSON.stringify(guestSession)); } catch {}
    roomIdentity = { user: data.user, session: guestSession, permanent: false };
    return roomIdentity;
  }
  async function roomRequest(path, options = {}) {
    const identity = await getRoomIdentity();
    const headers = {
      apikey: PUBLIC_KEY,
      Authorization: `Bearer ${identity.session.access_token}`,
      'Content-Type': 'application/json',
      ...(options.headers || {})
    };
    const r = await fetch(`${PROJECT_URL}${path}`, { ...options, headers });
    const data = await r.json().catch(() => null);
    if (!r.ok) {
      const error = new Error(data?.message || data?.details || data?.hint || data?.error_description || `Room request failed (${r.status}).`);
      error.status = r.status;
      throw error;
    }
    return data;
  }
  function saveRoomMeta(meta) {
    activeRoomMeta = meta;
    try { localStorage.setItem('pm-active-room', JSON.stringify(meta)); } catch {}
  }
  function roomInviteUrl(code) {
    const url = new URL(location.pathname, location.origin);
    url.searchParams.set('room', code);
    return url.href;
  }
  function showRoomShare(meta) {
    $('#roomSharePanel').hidden = false;
    $('#roomCodeValue').textContent = meta.code;
    $('#roomShareHelp').textContent = `Share this link: ${roomInviteUrl(meta.code)} · Waiting for someone to join…`;
    $('#copyRoomButton').textContent = 'Copy invite link';
  }
  async function createRoom() {
    const button = $('#createRoomButton');
    button.disabled = true;
    say('#onlineError', 'Opening a room…');
    try {
      const identity = await getRoomIdentity();
      let created = false;
      for (let attempt = 0; attempt < 3 && !created; attempt++) {
        const code = newRoomCode(), id = crypto.randomUUID();
        try {
          await roomRequest('/rest/v1/penalty_rooms', {
            method: 'POST', headers: { Prefer: 'return=minimal' },
            body: JSON.stringify({ id, code, host_id: identity.user.id, host_name: roomDisplayName() })
          });
          saveRoomMeta({ id, code, side: 'host', playerId: identity.user.id });
          activeRoomData = null; roomMatchStarted = false; lastRoomKick = -1;
          showRoomShare(activeRoomMeta); say('#onlineError', 'Room ready. Share the code or link.');
          startRoomPolling(); created = true;
        } catch (e) { if (e.status !== 409 || attempt === 2) throw e; }
      }
      return created;
    } catch (e) { say('#onlineError', e.message); return false; }
    finally { button.disabled = false; }
  }
  async function joinRoom() {
    const button = $('#joinRoomButton');
    const code = $('#roomCodeInput').value.toUpperCase().replace(/[^A-HJ-NP-Z2-9]/g, '').slice(0, 10);
    $('#roomCodeInput').value = code;
    if (!/^[A-HJ-NP-Z2-9]{10}$/.test(code)) return say('#onlineError', 'Enter the 10-character room code.');
    button.disabled = true; say('#onlineError', 'Joining the room…');
    try {
      const identity = await getRoomIdentity();
      const id = await roomRequest('/rest/v1/rpc/join_penalty_room', {
        method: 'POST', body: JSON.stringify({ p_code: code, p_guest_name: roomDisplayName() })
      });
      saveRoomMeta({ id: String(id), code, side: 'guest', playerId: identity.user.id });
      activeRoomData = null; roomMatchStarted = false; lastRoomKick = -1;
      $('#roomSharePanel').hidden = true; $('#onlineModal').classList.remove('open');
      startRoomPolling(); await refreshActiveRoom();
    } catch (e) { say('#onlineError', e.message); }
    finally { button.disabled = false; }
  }
  function startRoomPolling() {
    clearInterval(roomPollTimer);
    roomPollTimer = setInterval(refreshActiveRoom, 800);
    refreshActiveRoom();
  }
  function stopRoomPolling() { clearInterval(roomPollTimer); clearInterval(roomClockTimer); roomPollTimer = roomClockTimer = null; roomTimeoutKey = ''; }
  async function refreshActiveRoom() {
    if (!activeRoomMeta || roomPollBusy) return;
    roomPollBusy = true;
    try {
      const rows = await roomRequest(`/rest/v1/penalty_rooms?select=id,code,host_id,guest_id,host_name,guest_name,status,left_by,kick_no,score_host,score_guest,saves_host,saves_guest,pending_host,pending_guest,score_history,winner_id,turn_started_at,updated_at&id=eq.${encodeURIComponent(activeRoomMeta.id)}&limit=1`);
      if (!rows?.length) {
        activeRoomMeta = activeRoomData = null;
        try { localStorage.removeItem('pm-active-room'); } catch {}
        stopRoomPolling();
        window.penaltyMindsetReturnHome?.('Match cleared. Back to the main screen.');
        return;
      }
      const previous = activeRoomData;
      activeRoomData = rows[0];
      if (activeRoomData.status === 'disconnected') {
        const opponentLeft = activeRoomData.left_by && activeRoomData.left_by !== roomIdentity?.user.id;
        activeRoomMeta = activeRoomData = null;
        try { localStorage.removeItem('pm-active-room'); } catch {}
        stopRoomPolling();
        window.penaltyMindsetReturnHome?.(opponentLeft ? 'Opponent disconnected. Back to the main screen.' : 'Match closed. Back to the main screen.');
        return;
      }
      if (activeRoomData.status === 'waiting') {
        showRoomShare(activeRoomMeta);
        $('#roomShareHelp').textContent = `Share this link: ${roomInviteUrl(activeRoomMeta.code)} · Waiting for someone to join…`;
        return;
      }
      if (!roomMatchStarted && window.penaltyMindsetBeginOnline) {
        roomMatchStarted = true; $('#onlineModal').classList.remove('open');
        window.penaltyMindsetBeginOnline();
      }
      if (previous && activeRoomData.kick_no > previous.kick_no) {
        const event = activeRoomData.score_history?.[activeRoomData.kick_no - 1];
        if (event) animateOnlineKick(event);
      }
      lastRoomKick = activeRoomData.kick_no;
      renderRoomState(activeRoomData);
      if (activeRoomData.status === 'completed') stopRoomPolling();
    } catch (e) { say('#onlineError', e.message); }
    finally { roomPollBusy = false; }
  }
  async function createOnlineInvite(friendId) {
    if (!user || !profile) { $('#accountModal').classList.add('open'); return; }
    say('#onlineError', 'Sending your challenge…');
    try {
      const rows = await rest('penalty_online_matches', '', { method: 'POST', headers: { Prefer: 'return=representation' }, body: JSON.stringify({ inviter_id: user.id, invitee_id: friendId }) });
      activeOnlineId = rows?.[0]?.id;
      if (!activeOnlineId) throw new Error('Challenge sent, but the match did not open.');
      $('#onlineModal').classList.remove('open');
      await openOnlineMatch(activeOnlineId);
    } catch (e) { say('#onlineError', e.message); }
  }
  async function answerOnlineInvite(id, accept) {
    try {
      await rest('penalty_online_matches', `id=eq.${id}&invitee_id=eq.${user.id}&status=eq.invited`, { method: 'PATCH', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ status: accept ? 'playing' : 'declined', updated_at: new Date().toISOString() }) });
      if (accept) { $('#onlineModal').classList.remove('open'); await openOnlineMatch(id); }
      else await loadOnlineLobby();
    } catch (e) { say('#onlineError', e.message); }
  }
  async function openOnlineMatch(id) {
    if (!user || !profile) return;
    activeRoomMeta = activeRoomData = null; roomMatchStarted = false; stopRoomPolling();
    try { localStorage.removeItem('pm-active-room'); } catch {}
    try {
      const rows = await rest('penalty_online_matches', `id=eq.${id}&limit=1`);
      if (!rows?.length) throw new Error('This shootout is no longer available.');
      activeOnlineId = id; activeOnlineMatch = rows[0];
      const otherId = user.id === activeOnlineMatch.inviter_id ? activeOnlineMatch.invitee_id : activeOnlineMatch.inviter_id;
      activeOpponent = await profileFor(otherId);
      lastRenderedKick = activeOnlineMatch.kick_no;
      if (window.penaltyMindsetBeginOnline) window.penaltyMindsetBeginOnline();
      renderOnlineState(activeOnlineMatch);
    } catch (e) { say('#onlineError', e.message); $('#onlineModal').classList.add('open'); }
  }
  async function refreshOnlineMatch() {
    if (!activeOnlineId || !user) return;
    try {
      const rows = await rest('penalty_online_matches', `id=eq.${activeOnlineId}&limit=1`);
      if (!rows?.length) return;
      activeOnlineMatch = rows[0];
      if (activeOnlineMatch.kick_no > lastRenderedKick) {
        const event = activeOnlineMatch.score_history?.[activeOnlineMatch.kick_no - 1];
        if (event) animateOnlineKick(event);
        lastRenderedKick = activeOnlineMatch.kick_no;
      }
      renderOnlineState(activeOnlineMatch);
      if (activeOnlineMatch.status === 'playing' || activeOnlineMatch.status === 'completed') $('#onlineModal').classList.remove('open');
      if ($('#onlineModal').classList.contains('open')) loadOnlineLobby();
    } catch (e) { say('#onlineError', e.message); }
  }
  function animateOnlineKick(event) {
    const directionX = (d) => d === 'left' ? '34%' : d === 'right' ? '66%' : '50%';
    const directionY = (d) => d === 'center' ? '22%' : '15%';
    if (onlineFieldResetTimer) clearTimeout(onlineFieldResetTimer);
    const ball = $('#shotBall'), keeper = $('#keeper'), striker = $('#striker');
    ball.className = 'shot-ball fly'; ball.style.left = directionX(event.shot_direction); ball.style.top = directionY(event.shot_direction);
    keeper.style.left = directionX(event.save_direction); keeper.style.top = '22%';
    striker.style.left = directionX(event.shot_direction);
    $('#callout span').textContent = event.scored ? 'GOAL!' : 'SAVED!'; $('#callout').classList.add('show');
    onlineFieldResetTimer = setTimeout(() => {
      $('#callout').classList.remove('show');
      ball.className = 'shot-ball'; ball.style.left = '50%'; ball.style.top = '72%';
      keeper.style.left = '50%'; keeper.style.top = '39%'; striker.style.left = '50%';
    }, 1050);
  }
  function renderRoomState(room) {
    if (!room || !roomIdentity || !activeRoomMeta) return;
    const isHost = activeRoomMeta.side === 'host';
    const mySide = isHost ? 'host' : 'guest', otherSide = isHost ? 'guest' : 'host';
    const myName = isHost ? room.host_name : room.guest_name, otherName = isHost ? room.guest_name : room.host_name;
    const myScore = isHost ? room.score_host : room.score_guest, otherScore = isHost ? room.score_guest : room.score_host;
    const myId = roomIdentity.user.id, otherId = isHost ? room.guest_id : room.host_id;
    $('#rankPill').textContent = 'FRIENDLY ROOM'; $('#opponentLabel').textContent = 'Opponent';
    $('#playerNameDisplay').textContent = (myName || 'Guest').toUpperCase(); $('#opponentName').textContent = (otherName || 'OPEN SLOT').toUpperCase();
    $('#score').textContent = `${myScore} — ${otherScore}`;
    const historyRows = room.score_history || [];
    const makeDots = (side) => {
      const played = historyRows.filter((event) => event.shooter_side === side);
      return Array.from({ length: Math.max(5, played.length) }, (_, i) => `<i class="dot ${played[i] ? (played[i].scored ? 'scored' : 'miss') : ''}"></i>`).join('');
    };
    $('#youDots').innerHTML = makeDots(mySide); $('#oppDots').innerHTML = makeDots(otherSide);
    const pairRound = Math.floor(room.kick_no / 2) + 1;
    $('#roundLabel').textContent = room.kick_no < 10 ? `ROUND ${Math.min(5, pairRound)} OF 5` : `SUDDEN DEATH · ${Math.floor((room.kick_no - 10) / 2) + 1}`;
    $('#timer').hidden = room.status !== 'playing'; $('#kickButton').hidden = true; $('#tipCard').hidden = true; $('#resultPanel').hidden = true;
    $('#history').replaceChildren(...historyRows.slice(-8).map((event) => {
      const badge = document.createElement('span'); badge.className = 'round-badge';
      const shooterName = event.shooter_side === 'host' ? room.host_name : room.guest_name;
      badge.textContent = `${shooterName}: ${event.scored ? 'GOAL' : 'SAVED'}`; return badge;
    }));
    if (room.status === 'completed') {
      $('#timer').hidden = true;
      const tied = !room.winner_id, won = room.winner_id === myId;
      $('#resultEmoji').textContent = tied ? '🤝' : won ? '🏆' : '🧤';
      $('#resultTitle').textContent = tied ? 'Level after sudden death' : won ? 'Ice cold. You win.' : 'So close.';
      $('#resultText').textContent = `${room.host_name} ${room.score_host} — ${room.score_guest} ${room.guest_name} · friendly room, not ranked`;
      $('#resultPanel').hidden = false; $('#choices').hidden = true; $('#rematchButton').hidden = false; $('#rematchButton').textContent = 'Create another room';
      window.penaltyMindsetOnlineRematch = () => { activeRoomMeta = activeRoomData = null; roomMatchStarted = false; try { localStorage.removeItem('pm-active-room'); } catch {} $('#onlineModal').classList.add('open'); createRoom(); };
      return;
    }
    const shooterSide = room.kick_no % 2 === 0 ? 'host' : 'guest', isShooter = shooterSide === mySide;
    $('#turnLabel').textContent = isShooter ? 'Your kick' : `${otherName || 'Your opponent'} is shooting`;
    $('#promptTitle').textContent = isShooter ? 'Pick your corner' : 'Read the striker';
    $('#promptText').textContent = isShooter ? 'Your opponent is setting their dive.' : 'Where do you think they’ll shoot?';
    $('#choices').setAttribute('aria-label', isShooter ? 'Choose your shot direction' : 'Choose your dive direction');
    const submitted = isHost ? room.pending_host : room.pending_guest;
    $('#choices').hidden = submitted;
    $('#turnHint').textContent = submitted ? 'Your choice is locked. Waiting for the other player…' : isShooter ? 'Tap a direction to take the shot.' : 'Tap where to dive.';
    startRoomClock(room);
  }
  function startRoomClock(room) {
    const turnKey = `${room.id}:${room.kick_no}`;
    if (roomTimeoutKey !== turnKey) roomTimeoutKey = '';
    if (!roomClockTimer) roomClockTimer = setInterval(() => {
      if (!activeRoomData || activeRoomData.status !== 'playing' || !activeRoomMeta || roomTimeoutBusy) return;
      const currentKey = `${activeRoomData.id}:${activeRoomData.kick_no}`;
      const startedAt = Date.parse(activeRoomData.turn_started_at || activeRoomData.updated_at);
      const remaining = Math.max(0, 10 - Math.floor((Date.now() - startedAt) / 1000));
      $('#timer').textContent = String(remaining).padStart(2, '0');
      if (remaining === 0 && roomTimeoutKey !== currentKey) {
        roomTimeoutKey = currentKey; roomTimeoutBusy = true;
        $('#turnHint').textContent = 'Time’s up. Resolving the turn…';
        roomRequest('/rest/v1/rpc/expire_penalty_room_turn', {
          method: 'POST', body: JSON.stringify({ p_room_id: activeRoomData.id })
        }).then(refreshActiveRoom).catch((e) => say('#onlineError', e.message)).finally(() => { roomTimeoutBusy = false; });
      }
    }, 250);
  }
  async function renderOnlineState(match) {
    if (!match || !user) return;
    const version = ++onlineRenderVersion;
    const meFirst = user.id === match.inviter_id, myScore = meFirst ? match.score_inviter : match.score_invitee, otherScore = meFirst ? match.score_invitee : match.score_inviter;
    const myId = user.id, otherId = meFirst ? match.invitee_id : match.inviter_id;
    $('#rankPill').textContent = 'ONLINE MATCH'; $('#opponentLabel').textContent = 'Friend';
    $('#opponentName').textContent = (activeOpponent?.display_name || 'FRIEND').toUpperCase(); $('#playerNameDisplay').textContent = profile.display_name.toUpperCase();
    $('#score').textContent = `${myScore} — ${otherScore}`;
    const historyRows = match.score_history || [];
    const makeDots = (id) => {
      const played = historyRows.filter((h) => h.shooter_id === id);
      return Array.from({ length: Math.max(5, played.length) }, (_, i) => `<i class="dot ${played[i] ? (played[i].scored ? 'scored' : 'miss') : ''}"></i>`).join('');
    };
    $('#youDots').innerHTML = makeDots(myId); $('#oppDots').innerHTML = makeDots(otherId);
    const pairRound = Math.floor(match.kick_no / 2) + 1;
    $('#roundLabel').textContent = match.kick_no < 10 ? `ROUND ${Math.min(5, pairRound)} OF 5` : `SUDDEN DEATH · ${Math.floor((match.kick_no - 10) / 2) + 1}`;
    $('#timer').hidden = true; $('#kickButton').hidden = true; $('#tipCard').hidden = true; $('#resultPanel').hidden = true;
    if (match.status === 'invited') {
      $('#turnLabel').textContent = 'Challenge sent'; $('#promptTitle').textContent = 'Waiting for your friend'; $('#promptText').textContent = 'They can accept from their online invites.';
      $('#turnHint').textContent = 'We’ll start as soon as they join.'; $('#choices').hidden = true; return;
    }
    if (match.status === 'declined') {
      $('#resultEmoji').textContent = '🤝'; $('#resultTitle').textContent = 'Invite declined'; $('#resultText').textContent = `${activeOpponent?.display_name || 'Your friend'} can accept a new challenge any time.`;
      $('#resultPanel').hidden = false; $('#choices').hidden = true; $('#rematchButton').hidden = true; return;
    }
    if (match.status === 'completed') {
      const tied = !match.winner_id; const won = match.winner_id === myId;
      $('#resultEmoji').textContent = tied ? '🤝' : won ? '🏆' : '🧤'; $('#resultTitle').textContent = tied ? 'Level after sudden death' : won ? 'Ice cold. You win.' : 'So close.';
      $('#resultText').textContent = `${profile.display_name} ${myScore} — ${otherScore} ${activeOpponent?.display_name || 'Friend'} · saved to the online leaderboard`;
      $('#resultPanel').hidden = false; $('#choices').hidden = true; $('#rematchButton').hidden = false; $('#rematchButton').textContent = 'Rematch friend';
      window.penaltyMindsetOnlineRematch = () => createOnlineInvite(otherId); return;
    }
    const shooterId = match.kick_no % 2 === 0 ? match.inviter_id : match.invitee_id, isShooter = shooterId === myId;
    $('#turnLabel').textContent = isShooter ? 'Your kick' : `${activeOpponent?.display_name || 'Friend'} is shooting`;
    $('#promptTitle').textContent = isShooter ? 'Pick your corner' : 'Read the striker';
    $('#promptText').textContent = isShooter ? 'Your friend is setting their dive.' : 'Where do you think they’ll shoot?';
    $('#choices').setAttribute('aria-label', isShooter ? 'Choose your shot direction' : 'Choose your dive direction');
    const ownMoves = await rest('penalty_online_moves', `select=kick_no&match_id=eq.${match.id}&kick_no=eq.${match.kick_no}&player_id=eq.${myId}&limit=1`);
    if (version !== onlineRenderVersion) return;
    const submitted = ownMoves.length > 0;
    $('#choices').hidden = submitted;
    $('#turnHint').textContent = submitted ? 'Your choice is locked. Waiting for your friend…' : isShooter ? 'Tap a direction to take the shot.' : 'Tap where to dive.';
  }
  async function submitRoomChoice(direction) {
    const room = activeRoomData;
    if (!room || room.status !== 'playing' || !direction || !roomIdentity || roomSubmitting) return;
    roomSubmitting = true;
    const isHost = activeRoomMeta.side === 'host';
    const side = isHost ? 'host' : 'guest';
    const shooterSide = room.kick_no % 2 === 0 ? 'host' : 'guest';
    const role = side === shooterSide ? 'shooter' : 'keeper';
    if (onlineFieldResetTimer) { clearTimeout(onlineFieldResetTimer); onlineFieldResetTimer = null; }
    $('#choices').hidden = true; $('#turnHint').textContent = 'Sending your choice…';
    try {
      await roomRequest('/rest/v1/penalty_room_moves', {
        method: 'POST', headers: { Prefer: 'return=minimal' },
        body: JSON.stringify({ room_id: room.id, kick_no: room.kick_no, player_id: roomIdentity.user.id, player_side: side, role, direction })
      });
      await refreshActiveRoom();
      if (activeRoomData?.status === 'playing' && activeRoomData.kick_no === room.kick_no) $('#turnHint').textContent = 'Your choice is locked. Waiting for the other player…';
    } catch (e) { say('#onlineError', e.message); $('#turnHint').textContent = `Could not send that choice: ${e.message}`; $('#choices').hidden = false; }
    finally { roomSubmitting = false; }
  }
  window.penaltyMindsetLeaveOnlineRoom = async () => {
    if (!activeRoomMeta) return false;
    const roomId = activeRoomMeta.id;
    try {
      await roomRequest('/rest/v1/rpc/leave_penalty_room', {
        method: 'POST', body: JSON.stringify({ p_room_id: roomId })
      });
      activeRoomMeta = activeRoomData = null;
      try { localStorage.removeItem('pm-active-room'); } catch {}
      stopRoomPolling();
      return true;
    } catch (e) {
      say('#onlineError', e.message);
      return false;
    }
  };
  window.penaltyMindsetRenderOnlineTurn = () => { if (activeRoomData) renderRoomState(activeRoomData); else if (activeOnlineMatch) renderOnlineState(activeOnlineMatch); };
  window.penaltyMindsetSubmitOnlineChoice = async (direction) => {
    if (activeRoomData) return submitRoomChoice(direction);
    const m = activeOnlineMatch;
    if (!m || m.status !== 'playing' || !direction || !user || onlineSubmitting) return;
    onlineSubmitting = true;
    const shooterId = m.kick_no % 2 === 0 ? m.inviter_id : m.invitee_id;
    const role = shooterId === user.id ? 'shooter' : 'keeper';
    $('#choices').hidden = true; $('#turnHint').textContent = 'Sending your choice…';
    try {
      await rest('penalty_online_moves', '', { method: 'POST', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ match_id: m.id, kick_no: m.kick_no, player_id: user.id, role, direction }) });
      await refreshOnlineMatch();
      if (activeOnlineMatch?.status === 'playing' && activeOnlineMatch.kick_no === m.kick_no) $('#turnHint').textContent = 'Your choice is locked. Waiting for your friend…';
    } catch (e) { say('#onlineError', e.message); $('#turnHint').textContent = 'Could not send that choice: ' + e.message; $('#choices').hidden = false; }
    finally { onlineSubmitting = false; }
  };
  $('#createRoomButton').addEventListener('click', createRoom);
  $('#joinRoomButton').addEventListener('click', joinRoom);
  $('#roomCodeInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') joinRoom(); });
  $('#roomCodeInput').addEventListener('input', () => { const input = $('#roomCodeInput'); input.value = input.value.toUpperCase().replace(/[^A-HJ-NP-Z2-9]/g, '').slice(0, 10); });
  $('#copyRoomButton').addEventListener('click', async () => {
    if (!activeRoomMeta) return;
    const link = roomInviteUrl(activeRoomMeta.code);
    try { await navigator.clipboard.writeText(link); $('#copyRoomButton').textContent = 'Link copied'; }
    catch { $('#roomShareHelp').textContent = `Copy this link: ${link}`; }
  });
  $('#friendButton').onclick = () => { $('#onlineError').textContent = ''; $('#onlineModal').classList.add('open'); loadOnlineLobby(); };
  $('#friendsButton').addEventListener('click', () => {
    if (!user || !profile) { $('#onlineModal').classList.add('open'); $('#onlineError').textContent = ''; loadOnlineLobby(); return; }
    $('#socialModal').classList.remove('open'); $('#onlineModal').classList.add('open'); $('#onlineError').textContent = ''; loadOnlineLobby();
  });
  $('#localPassButton').addEventListener('click', () => { $('#onlineModal').classList.remove('open'); $('#friendModal').classList.add('open'); });
  $('#accountSignout').addEventListener('click', async () => {
    try { if (session?.access_token) await fetch(`${PROJECT_URL}/auth/v1/logout`, { method: 'POST', headers: { apikey: PUBLIC_KEY, Authorization: `Bearer ${session.access_token}` } }); } catch {}
    if (realtimeChannel && realtimeClient) { await realtimeClient.removeChannel(realtimeChannel); realtimeChannel = null; }
    activeOnlineId = null; activeOnlineMatch = activeOpponent = null;
    storeSession(null); user = profile = null; friends = []; $('#socialModal').classList.remove('open'); $('#onlineModal').classList.remove('open'); updateAccountUi();
  });

  function addLeaderControls() {
    const host = $('#leaderRows');
    if ($('#rankMode')) return;
    const tabs = document.createElement('div'); tabs.className = 'account-tabs'; tabs.id = 'rankMode';
    tabs.innerHTML = '<button class="btn btn-primary" data-rank="all">Global</button><button class="btn btn-secondary" data-rank="friends">Friends</button>';
    host.before(tabs);
    tabs.addEventListener('click', (e) => { const b = e.target.closest('[data-rank]'); if (b) loadLeaderboard(b.dataset.rank); });
  }
  async function loadLeaderboard(mode = 'all') {
    const host = $('#leaderRows');
    if (!user || !profile) { host.textContent = 'Sign in to see the ranked leaderboard.'; return; }
    host.innerHTML = '<p class="rank-summary">Loading the table…</p>';
    try {
      let ids = null;
      if (mode === 'friends') {
        await loadFriends();
        ids = [user.id, ...friends.filter((f) => f.status === 'accepted').map((f) => f.requester_id === user.id ? f.recipient_id : f.requester_id)];
      }
      const query = `select=user_id,username,display_name,matches_played,wins,goals_scored,saves&order=wins.desc,matches_played.desc&limit=25${ids ? `&user_id=in.(${ids.join(',')})` : ''}`;
      const rows = await rest('penalty_online_leaderboard', query);
      host.replaceChildren();
      if (!rows.length) { host.textContent = mode === 'friends' ? 'No matches among your friends yet.' : 'No ranked matches yet. Play a solo shootout to get on the board.'; return; }
      rows.forEach((p, i) => {
        const row = document.createElement('div'); row.className = 'leader-row';
        row.innerHTML = `<em>${i + 1}</em><div><strong>${escape(p.display_name)}</strong><small>@${escape(p.username)} · ${p.matches_played} matches</small></div><b>${p.wins}W</b>`;
        host.append(row);
      });
    } catch (e) { host.textContent = 'Leaderboard unavailable: ' + e.message; }
  }
  $('#leaderButton').onclick = () => {
    $('#leaderModal').classList.add('open'); addLeaderControls(); loadLeaderboard('all');
  };
  document.querySelectorAll('[data-close]').forEach((b) => b.addEventListener('click', () => $('#' + b.dataset.close).classList.remove('open')));
  document.querySelectorAll('.modal-backdrop').forEach((m) => m.addEventListener('click', (e) => { if (e.target === m && m.id !== 'profileModal') m.classList.remove('open'); }));
  document.addEventListener('visibilitychange', () => { if (!document.hidden) { if (activeOnlineId) refreshOnlineMatch(); if (activeRoomMeta) refreshActiveRoom(); if ($('#onlineModal').classList.contains('open')) loadOnlineLobby(); } });
  setAuthMode('signin');
  loadAccount();
  const roomFromLink = new URLSearchParams(location.search).get('room');
  if (roomFromLink) { $('#roomCodeInput').value = roomFromLink.toUpperCase().replace(/[^A-HJ-NP-Z2-9]/g, '').slice(0, 10); $('#onlineModal').classList.add('open'); }
  try {
    const savedRoom = JSON.parse(localStorage.getItem('pm-active-room') || 'null');
    if (savedRoom?.id && savedRoom?.code && savedRoom?.playerId && (!roomFromLink || roomFromLink.toUpperCase() === savedRoom.code)) {
      activeRoomMeta = savedRoom;
      if (savedRoom.side === 'host') showRoomShare(savedRoom);
      startRoomPolling();
    }
  } catch {}
})();

