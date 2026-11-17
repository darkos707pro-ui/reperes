-- =====================================================================
-- Repères · Forum d'entraide entre élèves
-- À coller tel quel dans Supabase : SQL Editor > New query > Run.
-- Le script peut être relancé : il ne supprime aucune donnée.
--
-- Principes de sécurité
--  * Les tables ne sont jamais accessibles directement depuis le site
--    (RLS activée, aucune politique) : tout passe par les fonctions forum_*
--    et mod_*, qui vérifient chaque règle côté serveur.
--  * Lecture libre ; écriture seulement avec un code de lycée valide.
--  * Pseudonymes, pas de messages privés, pas de coordonnées dans les messages.
--  * 3 signalements de personnes différentes masquent un message en attendant
--    la décision d'un modérateur.
-- =====================================================================

-- ---------- Tables ----------------------------------------------------
create table if not exists forum_codes (
  code        text primary key,
  lycee       text not null check (char_length(lycee) between 2 and 120),
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists forum_profiles (
  user_id     uuid primary key,
  pseudo      text not null check (char_length(pseudo) between 3 and 20),
  role        text not null default 'lyceen' check (role in ('lyceen','etudiant')),
  code        text not null references forum_codes(code),
  banned      boolean not null default false,
  ban_reason  text,
  created_at  timestamptz not null default now()
);
create unique index if not exists forum_profiles_pseudo_uniq on forum_profiles (lower(pseudo));

create table if not exists forum_moderators (
  user_id     uuid primary key,
  label       text not null default 'Modération'
);

create table if not exists forum_topics (
  id          bigint generated always as identity primary key,
  salon       text not null,
  title       text not null check (char_length(title) between 5 and 120),
  body        text not null check (char_length(body) between 2 and 2000),
  author      uuid not null references forum_profiles(user_id),
  hidden      boolean not null default false,
  created_at  timestamptz not null default now(),
  last_at     timestamptz not null default now()
);
create index if not exists forum_topics_salon_idx on forum_topics (salon, last_at desc);

create table if not exists forum_replies (
  id          bigint generated always as identity primary key,
  topic_id    bigint not null references forum_topics(id) on delete cascade,
  body        text not null check (char_length(body) between 2 and 2000),
  author      uuid not null references forum_profiles(user_id),
  hidden      boolean not null default false,
  created_at  timestamptz not null default now()
);
create index if not exists forum_replies_topic_idx on forum_replies (topic_id, created_at);

create table if not exists forum_helpful (
  reply_id    bigint not null references forum_replies(id) on delete cascade,
  user_id     uuid not null references forum_profiles(user_id),
  primary key (reply_id, user_id)
);

create table if not exists forum_reports (
  id          bigint generated always as identity primary key,
  kind        text not null check (kind in ('topic','reply')),
  item_id     bigint not null,
  reporter    uuid not null references forum_profiles(user_id),
  reason      text not null check (char_length(reason) between 2 and 300),
  resolved    boolean not null default false,
  created_at  timestamptz not null default now(),
  unique (kind, item_id, reporter)
);

alter table forum_codes      enable row level security;
alter table forum_profiles   enable row level security;
alter table forum_moderators enable row level security;
alter table forum_topics     enable row level security;
alter table forum_replies    enable row level security;
alter table forum_helpful    enable row level security;
alter table forum_reports    enable row level security;

-- ---------- Outils internes -------------------------------------------
create or replace function forum_salons() returns text[] language sql immutable as $$
  select array['general','voie','dossier','courtes','longues','jpo','resultats','moral','etudiants']
$$;

create or replace function forum_is_mod() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from forum_moderators where user_id = auth.uid())
$$;

-- Refuse les coordonnées, les réseaux sociaux et les liens hors sites publics d'orientation.
create or replace function forum_check_text(t text) returns void
language plpgsql immutable as $$
declare
  low text := lower(t);
  url text;
begin
  if low ~ '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}' then
    raise exception 'Pas d''adresse e-mail dans les messages : pour ta sécurité, on reste sur le forum.' using errcode = 'P0001';
  end if;
  if regexp_replace(low, '[\s.\-]', '', 'g') ~ '(\+33|0033|0)[1-9][0-9]{8}' then
    raise exception 'Pas de numéro de téléphone dans les messages : pour ta sécurité, on reste sur le forum.' using errcode = 'P0001';
  end if;
  if low ~ '\m(snap(chat)?|insta(gram)?|whats ?app|telegram|discord|tiktok)\M' then
    raise exception 'Pas de réseaux sociaux ni de messageries privées : pour ta sécurité, on reste sur le forum.' using errcode = 'P0001';
  end if;
  for url in select (regexp_matches(low, '(https?://[^\s/]+|www\.[^\s/]+)', 'g'))[1] loop
    if url !~ '(\.gouv\.fr|onisep\.fr|parcoursup\.fr|monprojetsup\.fr|lescrous\.fr|etudiant\.gouv\.fr|service-civique\.gouv\.fr|filsantejeunes\.com|darkos707pro-ui\.github\.io)$' then
      raise exception 'Seuls les liens vers des sites publics d''orientation sont acceptés (parcoursup.fr, onisep.fr, .gouv.fr…).' using errcode = 'P0001';
    end if;
  end loop;
  if low ~ '\m(connard|connasse|salope|pute|encul[eé]|ntm|fdp|tg|ta gueule|batard|bâtard|pd|gogol|mongol)\M' then
    raise exception 'Ce message contient une insulte. Reformule-le : ici, on s''entraide.' using errcode = 'P0001';
  end if;
end $$;

-- Profil de l'appelant, s'il peut écrire ; sinon erreur explicite.
create or replace function forum_writer() returns forum_profiles
language plpgsql stable security definer set search_path = public as $$
declare p forum_profiles;
begin
  if auth.uid() is null then raise exception 'Session absente : recharge la page.' using errcode = 'P0001'; end if;
  select * into p from forum_profiles where user_id = auth.uid();
  if not found then raise exception 'Rejoins le forum avec le code de ton lycée pour écrire.' using errcode = 'P0001'; end if;
  if p.banned then raise exception 'Ton compte ne peut plus écrire sur le forum.' using errcode = 'P0001'; end if;
  if not exists (select 1 from forum_codes where code = p.code and active) then
    raise exception 'Le code de ton lycée a été désactivé. Demande le nouveau code à ton professeur.' using errcode = 'P0001';
  end if;
  return p;
end $$;

-- 1 message toutes les 20 secondes, 30 par jour.
create or replace function forum_rate_limit(uid uuid) returns void
language plpgsql stable security definer set search_path = public as $$
declare last timestamptz; n int;
begin
  select max(c), count(*) filter (where c > now() - interval '1 day') into last, n from (
    select created_at c from forum_topics where author = uid and created_at > now() - interval '1 day'
    union all
    select created_at from forum_replies where author = uid and created_at > now() - interval '1 day') x;
  if last is not null and last > now() - interval '20 seconds' then
    raise exception 'Doucement : attends quelques secondes avant de publier à nouveau.' using errcode = 'P0001';
  end if;
  if n >= 30 then raise exception 'Limite de 30 messages par jour atteinte. Reviens demain !' using errcode = 'P0001'; end if;
end $$;

-- ---------- Fonctions publiques (élèves) -------------------------------
create or replace function forum_me() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'pseudo', p.pseudo, 'role', p.role, 'lycee', c.lycee, 'banned', p.banned,
    'code_active', c.active, 'is_mod', forum_is_mod())
  from forum_profiles p join forum_codes c using (code) where p.user_id = auth.uid()
  union all
  select json_build_object('pseudo', null, 'is_mod', true)
  where forum_is_mod() and not exists (select 1 from forum_profiles where user_id = auth.uid())
  limit 1
$$;

create or replace function forum_join(p_code text, p_pseudo text, p_role text) returns json
language plpgsql security definer set search_path = public as $$
declare c forum_codes; ps text := btrim(p_pseudo);
begin
  if auth.uid() is null then raise exception 'Session absente : recharge la page.' using errcode = 'P0001'; end if;
  if exists (select 1 from forum_profiles where user_id = auth.uid()) then return forum_me(); end if;
  select * into c from forum_codes where code = upper(btrim(p_code)) and active;
  if not found then raise exception 'Code inconnu ou désactivé. Vérifie-le auprès de ton professeur.' using errcode = 'P0001'; end if;
  if ps !~ '^[A-Za-z0-9À-ÖØ-öø-ÿ_.-]{3,20}$' then
    raise exception 'Pseudo : 3 à 20 caractères, lettres, chiffres, point, tiret ou souligné, sans espace.' using errcode = 'P0001';
  end if;
  perform forum_check_text(ps);
  if lower(ps) ~ '(modo|moderat|admin|prof|repere)' then
    raise exception 'Ce pseudo est réservé. Choisis-en un autre.' using errcode = 'P0001';
  end if;
  if exists (select 1 from forum_profiles where lower(pseudo) = lower(ps)) then
    raise exception 'Ce pseudo est déjà pris.' using errcode = 'P0001';
  end if;
  insert into forum_profiles(user_id, pseudo, role, code)
  values (auth.uid(), ps, case when p_role = 'etudiant' then 'etudiant' else 'lyceen' end, c.code);
  return forum_me();
end $$;

create or replace function forum_salon_counts() returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_object_agg(salon, json_build_object('topics', n, 'unanswered', u)), '{}'::json) from (
    select t.salon, count(*) n,
           count(*) filter (where not exists (select 1 from forum_replies r where r.topic_id = t.id and not r.hidden)) u
    from forum_topics t where not t.hidden group by t.salon) x
$$;

create or replace function forum_topics(p_salon text, p_unanswered boolean default false, p_before timestamptz default null, p_limit int default 30)
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(x order by x.last_at desc), '[]'::json) from (
    select t.id, t.salon, t.title, left(t.body, 180) as excerpt, p.pseudo, p.role, t.created_at, t.last_at,
           (select count(*) from forum_replies r where r.topic_id = t.id and not r.hidden) as replies,
           (t.author = auth.uid()) as mine
    from forum_topics t join forum_profiles p on p.user_id = t.author
    where not t.hidden and (p_salon is null or t.salon = p_salon)
      and (p_before is null or t.last_at < p_before)
      and (not p_unanswered or not exists (select 1 from forum_replies r where r.topic_id = t.id and not r.hidden))
    order by t.last_at desc
    limit least(greatest(p_limit, 1), 50)) x
$$;

create or replace function forum_topic(p_id bigint) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'id', t.id, 'salon', t.salon, 'title', t.title, 'body', t.body, 'pseudo', p.pseudo, 'role', p.role,
    'created_at', t.created_at, 'mine', t.author = auth.uid(),
    'replies', coalesce((select json_agg(json_build_object(
        'id', r.id, 'body', r.body, 'pseudo', rp.pseudo, 'role', rp.role, 'created_at', r.created_at,
        'mine', r.author = auth.uid(),
        'helpful', (select count(*) from forum_helpful h where h.reply_id = r.id),
        'i_helpful', exists (select 1 from forum_helpful h where h.reply_id = r.id and h.user_id = auth.uid()))
      order by r.created_at)
      from forum_replies r join forum_profiles rp on rp.user_id = r.author
      where r.topic_id = t.id and not r.hidden), '[]'::json))
  from forum_topics t join forum_profiles p on p.user_id = t.author
  where t.id = p_id and not t.hidden
$$;

create or replace function forum_post_topic(p_salon text, p_title text, p_body text) returns bigint
language plpgsql security definer set search_path = public as $$
declare me forum_profiles := forum_writer(); new_id bigint;
begin
  if not (p_salon = any (forum_salons())) then raise exception 'Salon inconnu.' using errcode = 'P0001'; end if;
  perform forum_rate_limit(me.user_id);
  perform forum_check_text(p_title); perform forum_check_text(p_body);
  insert into forum_topics(salon, title, body, author) values (p_salon, btrim(p_title), btrim(p_body), me.user_id)
  returning id into new_id;
  return new_id;
end $$;

create or replace function forum_post_reply(p_topic bigint, p_body text) returns bigint
language plpgsql security definer set search_path = public as $$
declare me forum_profiles := forum_writer(); new_id bigint;
begin
  if not exists (select 1 from forum_topics where id = p_topic and not hidden) then
    raise exception 'Ce sujet n''existe plus.' using errcode = 'P0001';
  end if;
  perform forum_rate_limit(me.user_id);
  perform forum_check_text(p_body);
  insert into forum_replies(topic_id, body, author) values (p_topic, btrim(p_body), me.user_id) returning id into new_id;
  update forum_topics set last_at = now() where id = p_topic;
  return new_id;
end $$;

create or replace function forum_toggle_helpful(p_reply bigint) returns boolean
language plpgsql security definer set search_path = public as $$
declare me forum_profiles := forum_writer();
begin
  if exists (select 1 from forum_replies where id = p_reply and author = me.user_id) then
    raise exception 'Tu ne peux pas marquer ta propre réponse comme utile.' using errcode = 'P0001';
  end if;
  delete from forum_helpful where reply_id = p_reply and user_id = me.user_id;
  if found then return false; end if;
  insert into forum_helpful(reply_id, user_id) values (p_reply, me.user_id);
  return true;
end $$;

create or replace function forum_report(p_kind text, p_id bigint, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare me forum_profiles := forum_writer(); n int;
begin
  if p_kind not in ('topic','reply') then raise exception 'Signalement invalide.' using errcode = 'P0001'; end if;
  if (select count(*) from forum_reports where reporter = me.user_id and created_at > now() - interval '1 day') >= 20 then
    raise exception 'Trop de signalements aujourd''hui.' using errcode = 'P0001';
  end if;
  if (p_kind = 'topic' and not exists (select 1 from forum_topics where id = p_id))
     or (p_kind = 'reply' and not exists (select 1 from forum_replies where id = p_id)) then
    raise exception 'Message introuvable.' using errcode = 'P0001';
  end if;
  insert into forum_reports(kind, item_id, reporter, reason) values (p_kind, p_id, me.user_id, left(btrim(p_reason), 300))
  on conflict (kind, item_id, reporter) do nothing;
  select count(*) into n from forum_reports where kind = p_kind and item_id = p_id and not resolved;
  if n >= 3 then
    if p_kind = 'topic' then update forum_topics set hidden = true where id = p_id;
    else update forum_replies set hidden = true where id = p_id; end if;
  end if;
end $$;

-- Supprimer son propre message (masqué, conservé pour la modération).
create or replace function forum_delete_mine(p_kind text, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_kind = 'topic' then update forum_topics set hidden = true where id = p_id and author = auth.uid();
  elsif p_kind = 'reply' then update forum_replies set hidden = true where id = p_id and author = auth.uid();
  end if;
  if not found then raise exception 'Message introuvable.' using errcode = 'P0001'; end if;
end $$;

-- ---------- Fonctions de modération ------------------------------------
create or replace function mod_require() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not forum_is_mod() then raise exception 'Réservé aux modérateurs.' using errcode = '42501'; end if;
end $$;

create or replace function mod_queue() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  perform mod_require();
  return (select coalesce(json_agg(q order by q.last_report desc), '[]'::json) from (
    select r.kind, r.item_id, count(*) as reports, max(r.created_at) as last_report,
           string_agg(distinct r.reason, ' · ') as reasons,
           coalesce(t.title, tr.title) as topic_title, coalesce(t.body, rp.body) as body,
           coalesce(t.hidden, rp.hidden) as hidden, coalesce(t.id, rp.topic_id) as topic_id,
           p.pseudo, p.user_id as author, p.banned, c.lycee
    from forum_reports r
    left join forum_topics t on r.kind = 'topic' and t.id = r.item_id
    left join forum_replies rp on r.kind = 'reply' and rp.id = r.item_id
    left join forum_topics tr on tr.id = rp.topic_id
    left join forum_profiles p on p.user_id = coalesce(t.author, rp.author)
    left join forum_codes c on c.code = p.code
    where not r.resolved
    group by r.kind, r.item_id, t.title, tr.title, t.body, rp.body, t.hidden, rp.hidden, t.id, rp.topic_id, p.pseudo, p.user_id, p.banned, c.lycee) q);
end $$;

create or replace function mod_resolve(p_kind text, p_id bigint, p_hide boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform mod_require();
  if p_kind = 'topic' then update forum_topics set hidden = p_hide where id = p_id;
  else update forum_replies set hidden = p_hide where id = p_id; end if;
  update forum_reports set resolved = true where kind = p_kind and item_id = p_id;
end $$;

create or replace function mod_hide(p_kind text, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform mod_require();
  if p_kind = 'topic' then update forum_topics set hidden = true where id = p_id;
  else update forum_replies set hidden = true where id = p_id; end if;
end $$;

create or replace function mod_ban(p_user uuid, p_banned boolean, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform mod_require();
  update forum_profiles set banned = p_banned, ban_reason = case when p_banned then p_reason end where user_id = p_user;
  if p_banned then
    update forum_topics set hidden = true where author = p_user;
    update forum_replies set hidden = true where author = p_user;
  end if;
end $$;

create or replace function mod_codes() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  perform mod_require();
  return (select coalesce(json_agg(json_build_object('code', c.code, 'lycee', c.lycee, 'active', c.active,
    'members', (select count(*) from forum_profiles p where p.code = c.code)) order by c.created_at desc), '[]'::json)
    from forum_codes c);
end $$;

create or replace function mod_create_code(p_lycee text) returns text
language plpgsql security definer set search_path = public as $$
declare k text;
begin
  perform mod_require();
  loop
    k := (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + (get_byte(b, i) % 32), 1), '')
          from (select decode(replace(gen_random_uuid()::text, '-', ''), 'hex') b) x, generate_series(0, 7) i);
    exit when not exists (select 1 from forum_codes where code = k);
  end loop;
  insert into forum_codes(code, lycee) values (k, btrim(p_lycee));
  return k;
end $$;

create or replace function mod_set_code(p_code text, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform mod_require();
  update forum_codes set active = p_active where code = p_code;
end $$;

-- ---------- Droits ----------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function
  forum_me(), forum_salon_counts(), forum_topics(text, boolean, timestamptz, int), forum_topic(bigint)
  to anon, authenticated;
grant execute on function
  forum_join(text, text, text), forum_post_topic(text, text, text), forum_post_reply(bigint, text),
  forum_toggle_helpful(bigint), forum_report(text, bigint, text), forum_delete_mine(text, bigint),
  mod_queue(), mod_resolve(text, bigint, boolean), mod_hide(text, bigint), mod_ban(uuid, boolean, text),
  mod_codes(), mod_create_code(text), mod_set_code(text, boolean)
  to authenticated;
