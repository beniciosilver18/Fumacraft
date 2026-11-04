-- Fumacraft schema (Supabase)
create extension if not exists pgcrypto;

create table if not exists public.stores (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null unique references auth.users(id) on delete cascade,
  slug text not null unique check (slug ~ '^[a-z0-9-]{3,40}$'),
  name text not null,
  whatsapp text not null,
  currency text not null default 'BRL',
  description text default '',
  logo_url text default '',
  cover_url text default '',
  social_links jsonb not null default '{}'::jsonb,
  delivery boolean default true,
  pickup boolean default true,
  delivery_fee numeric default 0,
  plan text not null default 'trial',          -- trial | active | canceled
  trial_started timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null,
  price numeric not null default 0,
  description text default '',
  photo_url text default '',
  category text default '',
  active boolean not null default true,
  sort int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists products_store_idx on public.products(store_id);

alter table public.stores enable row level security;
alter table public.products enable row level security;

drop policy if exists stores_read on public.stores;
create policy stores_read on public.stores for select using (true);
drop policy if exists stores_ins on public.stores;
create policy stores_ins on public.stores for insert with check (auth.uid() = owner);
drop policy if exists stores_upd on public.stores;
create policy stores_upd on public.stores for update using (auth.uid() = owner) with check (auth.uid() = owner and plan = (select s.plan from public.stores s where s.id = stores.id));
drop policy if exists stores_del on public.stores;
create policy stores_del on public.stores for delete using (auth.uid() = owner);

drop policy if exists products_read on public.products;
create policy products_read on public.products for select using (active or exists (select 1 from public.stores s where s.id = store_id and s.owner = auth.uid()));
drop policy if exists products_write on public.products;
create policy products_write on public.products for all
  using (exists (select 1 from public.stores s where s.id = store_id and s.owner = auth.uid()))
  with check (exists (select 1 from public.stores s where s.id = store_id and s.owner = auth.uid()));

-- Storage bucket for images (public read, owners write in their own folder)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('images','images', true, 3145728, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

drop policy if exists img_read on storage.objects;
create policy img_read on storage.objects for select using (bucket_id = 'images');
drop policy if exists img_ins on storage.objects;
create policy img_ins on storage.objects for insert to authenticated with check (bucket_id = 'images' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists img_upd on storage.objects;
create policy img_upd on storage.objects for update to authenticated using (bucket_id = 'images' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists img_del on storage.objects;
create policy img_del on storage.objects for delete to authenticated using (bucket_id = 'images' and (storage.foldername(name))[1] = auth.uid()::text);
create or replace function public.is_admin() returns boolean language sql stable as $$ select coalesce(auth.jwt()->>'email','') = 'beniciosilver18@gmail.com' $$;
create or replace function public.admin_stores() returns table(id uuid, slug text, name text, whatsapp text, currency text, plan text, trial_started timestamptz, created_at timestamptz, email text, products bigint)
language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  return query select s.id,s.slug,s.name,s.whatsapp,s.currency,s.plan,s.trial_started,s.created_at,u.email::text,(select count(*) from products p where p.store_id=s.id)
  from stores s join auth.users u on u.id=s.owner order by s.created_at desc;
end $$;
create or replace function public.admin_set_plan(sid uuid, p text) returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if p not in ('trial','active','canceled') then raise exception 'bad plan'; end if;
  update stores set plan=p where id=sid;
end $$;
create or replace function public.admin_users_count() returns bigint language plpgsql security definer set search_path=public as $$
begin if not public.is_admin() then raise exception 'forbidden'; end if; return (select count(*) from auth.users); end $$;
revoke all on function public.admin_stores() from anon; revoke all on function public.admin_set_plan(uuid,text) from anon; revoke all on function public.admin_users_count() from anon;
alter table public.stores add column if not exists paid_until timestamptz;
drop function if exists public.admin_stores();
create or replace function public.admin_stores() returns table(id uuid, slug text, name text, whatsapp text, currency text, plan text, trial_started timestamptz, paid_until timestamptz, created_at timestamptz, email text, products bigint)
language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  return query select s.id,s.slug,s.name,s.whatsapp,s.currency,s.plan,s.trial_started,s.paid_until,s.created_at,u.email::text,(select count(*) from products p where p.store_id=s.id)
  from stores s join auth.users u on u.id=s.owner order by s.created_at desc;
end $$;
create or replace function public.admin_add_days(sid uuid, d int) returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  update stores set plan=case when d>0 then 'active' else 'trial' end,
    paid_until=case when d>0 then greatest(coalesce(paid_until,now()),now()) + make_interval(days=>d) else null end where id=sid;
end $$;
revoke all on function public.admin_stores() from anon; revoke all on function public.admin_add_days(uuid,int) from anon;
-- prevent owners from changing paid_until
drop policy if exists stores_upd on public.stores;
create policy stores_upd on public.stores for update using (auth.uid() = owner) with check (auth.uid() = owner and plan = (select s.plan from public.stores s where s.id = stores.id) and paid_until is not distinct from (select s.paid_until from public.stores s where s.id = stores.id));
create table if not exists public.orders(
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.stores(id) on delete cascade,
 code text not null, items jsonb not null, subtotal numeric not null, fee numeric not null default 0, total numeric not null,
 customer text, mode text, address text, note text, status text not null default 'novo',
 created_at timestamptz not null default now(), unique(store_id,code));
alter table public.orders enable row level security;
drop policy if exists orders_owner on public.orders;
create policy orders_owner on public.orders for select using (exists(select 1 from public.stores s where s.id=store_id and s.owner=auth.uid()));
drop policy if exists orders_owner_upd on public.orders;
create policy orders_owner_upd on public.orders for update using (exists(select 1 from public.stores s where s.id=store_id and s.owner=auth.uid()));
create or replace function public.create_order(sid uuid, its jsonb, cname text, cmode text, caddr text, cnote text)
returns table(code text, items jsonb, subtotal numeric, fee numeric, total numeric) language plpgsql security definer set search_path=public as $$
declare st stores; c text; lines jsonb := '[]'; sub numeric := 0; f numeric := 0; r record; i int := 0;
begin
 select * into st from stores where id=sid; if not found then raise exception 'store'; end if;
 for r in select p.id,p.name,p.price,(x->>'qty')::int q from jsonb_array_elements(its) x join products p on p.id=(x->>'id')::uuid and p.store_id=sid and p.active loop
   if r.q<1 or r.q>999 then continue; end if;
   lines := lines || jsonb_build_object('name',r.name,'qty',r.q,'price',r.price); sub := sub + r.price*r.q; end loop;
 if jsonb_array_length(lines)=0 then raise exception 'empty'; end if;
 if cmode='entrega' then f := coalesce(st.delivery_fee,0); end if;
 loop c := (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',(1+floor(random()*32))::int,1),'') from generate_series(1,6));
   exit when not exists(select 1 from orders o where o.store_id=sid and o.code=c); i:=i+1; exit when i>20; end loop;
 insert into orders(store_id,code,items,subtotal,fee,total,customer,mode,address,note) values(sid,c,lines,sub,f,sub+f,left(cname,80),cmode,left(caddr,300),left(cnote,300));
 return query select c,lines,sub,f,sub+f;
end $$;
grant execute on function public.create_order(uuid,jsonb,text,text,text,text) to anon, authenticated;
create table if not exists public.payments(
 reference text primary key, store_id uuid not null references public.stores(id) on delete cascade,
 pagar_id text, amount int not null, method text, status text not null default 'PENDING', days int not null default 30,
 created_at timestamptz default now(), paid_at timestamptz);
alter table public.payments enable row level security;
drop policy if exists pay_owner on public.payments;
create policy pay_owner on public.payments for select using (exists(select 1 from public.stores s where s.id=store_id and s.owner=auth.uid()));
create or replace function public.apply_payment(ref text) returns boolean language plpgsql security definer set search_path=public as $$
declare p payments;
begin
 update payments set status='PAID', paid_at=now() where reference=ref and status<>'PAID' returning * into p;
 if not found then return false; end if;
 update stores set plan='active', paid_until=greatest(coalesce(paid_until,now()),now())+make_interval(days=>p.days) where id=p.store_id;
 return true;
end $$;
revoke all on function public.apply_payment(text) from public, anon, authenticated;
create table if not exists public.app_secrets(name text primary key, value text not null, updated_at timestamptz default now());
alter table public.app_secrets enable row level security;
revoke all on public.app_secrets from anon, authenticated;
create extension if not exists pg_net;
create table if not exists public.push_subs(endpoint text primary key, store_id uuid not null references public.stores(id) on delete cascade, sub jsonb not null, created_at timestamptz default now());
alter table public.push_subs enable row level security;
drop policy if exists push_owner on public.push_subs;
create policy push_owner on public.push_subs for all using (exists(select 1 from public.stores s where s.id=store_id and s.owner=auth.uid())) with check (exists(select 1 from public.stores s where s.id=store_id and s.owner=auth.uid()));
insert into public.app_secrets(name,value) values ('VAPID_PUBLIC','BC_EbstDYvF7mykSqgfC6m_RgJ9wDz_LFDIU4RFExzXgunIdL-OsQU_aJIqydzupTfs5c-L7otAsKfJ80nyJX18'),('VAPID_PRIVATE','<VAPID_PRIVATE>'),('PUSH_HOOK_SECRET','<HOOK>') on conflict (name) do update set value=excluded.value;
create or replace function public.notify_order() returns trigger language plpgsql security definer set search_path=public, extensions as $$
begin
  perform net.http_post(url:='https://hqjmkdfbwdtxgifkenew.supabase.co/functions/v1/push-order',
    body:=jsonb_build_object('order_id',new.id),
    headers:=jsonb_build_object('Content-Type','application/json','x-hook',(select value from app_secrets where name='PUSH_HOOK_SECRET')));
  return new;
end $$;
drop trigger if exists orders_push on public.orders;
create trigger orders_push after insert on public.orders for each row execute function public.notify_order();
alter table public.stores add column if not exists order_retention_days int not null default 0;
drop policy if exists orders_owner_del on public.orders;
create policy orders_owner_del on public.orders for delete using (exists(select 1 from public.stores s where s.id=store_id and s.owner=auth.uid()));
create or replace function public.admin_delete_store(sid uuid) returns void language plpgsql security definer set search_path=public as $$
begin if not public.is_admin() then raise exception 'forbidden'; end if; delete from public.stores where id=sid; end $$;
create or replace function public.admin_delete_user(sid uuid) returns void language plpgsql security definer set search_path=public, auth as $$
declare uid uuid; begin if not public.is_admin() then raise exception 'forbidden'; end if;
 select owner into uid from public.stores where id=sid; if uid is null then raise exception 'not found'; end if;
 if (select email from auth.users where id=uid)='beniciosilver18@gmail.com' then raise exception 'Não pode apagar a conta admin'; end if;
 delete from auth.users where id=uid; end $$;
create or replace function public.admin_delete_orders(sid uuid, older_days int) returns int language plpgsql security definer set search_path=public as $$
declare n int; begin if not public.is_admin() then raise exception 'forbidden'; end if;
 delete from public.orders where store_id=sid and created_at < now() - make_interval(days=>older_days); get diagnostics n=row_count; return n; end $$;
revoke all on function public.admin_delete_store(uuid) from anon; revoke all on function public.admin_delete_user(uuid) from anon; revoke all on function public.admin_delete_orders(uuid,int) from anon;
create or replace function public.purge_old_orders() returns void language sql security definer set search_path=public as $$
 delete from public.orders o using public.stores s where s.id=o.store_id and s.order_retention_days>0 and o.status='entregue' and o.created_at < now() - make_interval(days=>s.order_retention_days); $$;
revoke all on function public.purge_old_orders() from anon, authenticated;
create extension if not exists pg_cron;
select cron.schedule('purge-old-orders','15 1 * * *','select public.purge_old_orders()');


-- Latest store-profile and admin RBAC migration
-- Fumacraft: public store social links and role-based administration.
-- Apply this migration to the Fumacraft Supabase project before using the new admin features.

alter table public.stores
  add column if not exists social_links jsonb not null default '{}'::jsonb;

alter table public.stores
  drop constraint if exists stores_social_links_object;
alter table public.stores
  add constraint stores_social_links_object
  check (jsonb_typeof(social_links) = 'object');

create table if not exists public.admin_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','support','moderator','finance')),
  permissions jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint admin_members_permissions_object check (jsonb_typeof(permissions) = 'object')
);

alter table public.admin_members enable row level security;
revoke all on public.admin_members from anon, authenticated;

create or replace function public.admin_is_root()
returns boolean
language sql stable security definer
set search_path = pg_catalog, auth
as $$
  select lower(coalesce(auth.jwt()->>'email','')) = 'beniciosilver18@gmail.com';
$$;

create or replace function public.admin_has_permission(p_permission text)
returns boolean
language sql stable security definer
set search_path = pg_catalog, public, auth
as $$
  select public.admin_is_root()
    or coalesce((
      select (m.permissions -> p_permission) = 'true'::jsonb
      from public.admin_members m
      where m.user_id = (select auth.uid())
    ), false);
$$;

create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = pg_catalog, public, auth
as $$
  select public.admin_has_permission('dashboard.view');
$$;

create or replace function public.admin_my_permissions()
returns jsonb
language sql stable security definer
set search_path = pg_catalog, public, auth
as $$
  select jsonb_build_object(
    'dashboard.view', public.admin_has_permission('dashboard.view'),
    'stores.view', public.admin_has_permission('stores.view'),
    'stores.manage', public.admin_has_permission('stores.manage'),
    'users.view', public.admin_has_permission('users.view'),
    'orders.view', public.admin_has_permission('orders.view'),
    'orders.manage', public.admin_has_permission('orders.manage'),
    'products.manage', public.admin_has_permission('products.manage'),
    'billing.view', public.admin_has_permission('billing.view'),
    'billing.manage', public.admin_has_permission('billing.manage')
  );
$$;

drop function if exists public.admin_stores();
create function public.admin_stores()
returns table(
  id uuid, slug text, name text, whatsapp text, currency text, plan text,
  trial_started timestamptz, paid_until timestamptz, created_at timestamptz,
  email text, products bigint
)
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not public.admin_has_permission('stores.view') then raise exception 'forbidden'; end if;
  return query
  select s.id,s.slug,s.name,s.whatsapp,s.currency,s.plan,s.trial_started,s.paid_until,
         s.created_at,u.email::text,
         (select count(*) from public.products p where p.store_id=s.id)
  from public.stores s
  join auth.users u on u.id=s.owner
  order by s.created_at desc;
end;
$$;

create or replace function public.admin_users_count()
returns bigint
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not public.admin_has_permission('dashboard.view') then raise exception 'forbidden'; end if;
  return (select count(*) from auth.users);
end;
$$;

create or replace function public.admin_list_users()
returns table(id uuid, email text, created_at timestamptz, last_sign_in_at timestamptz, stores_count bigint)
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not public.admin_has_permission('users.view') then raise exception 'forbidden'; end if;
  return query
  select u.id,u.email::text,u.created_at,u.last_sign_in_at,
         (select count(*) from public.stores s where s.owner=u.id)
  from auth.users u
  order by u.created_at desc
  limit 500;
end;
$$;

create or replace function public.admin_list_orders()
returns table(
  id uuid, store_id uuid, store_name text, store_slug text, code text,
  customer text, status text, total numeric, currency text, created_at timestamptz
)
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not public.admin_has_permission('orders.view') then raise exception 'forbidden'; end if;
  return query
  select o.id,o.store_id,s.name::text,s.slug::text,o.code::text,o.customer::text,
         o.status::text,o.total,s.currency::text,o.created_at
  from public.orders o
  join public.stores s on s.id=o.store_id
  order by o.created_at desc
  limit 500;
end;
$$;

create or replace function public.admin_list_admin_members()
returns table(email text, role text, permissions jsonb, created_at timestamptz)
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not public.admin_is_root() then raise exception 'forbidden'; end if;
  return query
  select u.email::text,m.role,m.permissions,m.created_at
  from public.admin_members m
  join auth.users u on u.id=m.user_id
  order by m.created_at desc;
end;
$$;

create or replace function public.admin_save_admin_member(
  p_email text, p_role text, p_permissions jsonb default '{}'::jsonb
)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
declare target_id uuid;
begin
  if not public.admin_is_root() then raise exception 'forbidden'; end if;
  if p_role not in ('admin','support','moderator','finance') then raise exception 'invalid role'; end if;
  if jsonb_typeof(coalesce(p_permissions,'{}'::jsonb)) <> 'object' then raise exception 'invalid permissions'; end if;
  if exists (
    select 1 from jsonb_each(coalesce(p_permissions,'{}'::jsonb)) e
    where e.key not in ('dashboard.view','stores.view','stores.manage','users.view','orders.view','orders.manage','products.manage','billing.view','billing.manage')
       or jsonb_typeof(e.value) <> 'boolean'
  ) then raise exception 'invalid permission key or value'; end if;
  select u.id into target_id from auth.users u where lower(u.email)=lower(trim(p_email));
  if target_id is null then raise exception 'account not found; the person must create an account first'; end if;
  if lower(trim(p_email))='beniciosilver18@gmail.com' then raise exception 'root administrator cannot be changed here'; end if;
  insert into public.admin_members(user_id,role,permissions)
  values(target_id,p_role,coalesce(p_permissions,'{}'::jsonb))
  on conflict(user_id) do update set role=excluded.role,permissions=excluded.permissions,updated_at=now();
end;
$$;

create or replace function public.admin_remove_admin_member(p_email text)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not public.admin_is_root() then raise exception 'forbidden'; end if;
  delete from public.admin_members m
  using auth.users u
  where u.id=m.user_id and lower(u.email)=lower(trim(p_email))
    and lower(u.email)<>'beniciosilver18@gmail.com';
end;
$$;

create or replace function public.admin_update_order_status(p_order_id uuid, p_status text)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not public.admin_has_permission('orders.manage') then raise exception 'forbidden'; end if;
  if p_status not in ('novo','pronto','entregue') then raise exception 'invalid status'; end if;
  update public.orders set status=p_status where id=p_order_id;
  if not found then raise exception 'order not found'; end if;
end;
$$;

create or replace function public.admin_delete_user_by_id(p_user_id uuid)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not public.admin_is_root() then raise exception 'forbidden'; end if;
  if exists(select 1 from auth.users u where u.id=p_user_id and lower(u.email)='beniciosilver18@gmail.com') then
    raise exception 'root administrator cannot be deleted';
  end if;
  delete from auth.users where id=p_user_id;
  if not found then raise exception 'user not found'; end if;
end;
$$;

create or replace function public.admin_delete_store(sid uuid)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not public.admin_has_permission('stores.manage') then raise exception 'forbidden'; end if;
  delete from public.stores where id=sid;
end;
$$;

create or replace function public.admin_delete_orders(sid uuid, older_days int)
returns int
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
declare n int;
begin
  if not public.admin_has_permission('orders.manage') then raise exception 'forbidden'; end if;
  if older_days < 0 then raise exception 'invalid days'; end if;
  delete from public.orders
  where store_id=sid and (older_days=0 or created_at < now()-make_interval(days=>older_days));
  get diagnostics n=row_count;
  return n;
end;
$$;

create or replace function public.admin_delete_user(sid uuid)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
declare target_id uuid;
begin
  if not public.admin_is_root() then raise exception 'forbidden'; end if;
  select owner into target_id from public.stores where id=sid;
  if target_id is null then raise exception 'not found'; end if;
  if exists(select 1 from auth.users where id=target_id and lower(email)='beniciosilver18@gmail.com') then
    raise exception 'root administrator cannot be deleted';
  end if;
  delete from auth.users where id=target_id;
end;
$$;

create or replace function public.admin_add_days(sid uuid, d int)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not public.admin_has_permission('billing.manage') then raise exception 'forbidden'; end if;
  if d < 1 or d > 3650 then raise exception 'invalid days'; end if;
  update public.stores
  set plan='active',paid_until=greatest(coalesce(paid_until,now()),now())+make_interval(days=>d)
  where id=sid;
end;
$$;

create or replace function public.admin_set_plan(sid uuid, p text)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not public.admin_has_permission('billing.manage') then raise exception 'forbidden'; end if;
  if p not in ('trial','active','canceled') then raise exception 'bad plan'; end if;
  update public.stores set plan=p where id=sid;
end;
$$;

-- RPC functions are only callable by authenticated users; each function checks its own permission.
revoke all on function public.admin_is_root() from public, anon, authenticated;
revoke all on function public.admin_has_permission(text) from public, anon, authenticated;
revoke all on function public.is_admin() from public, anon, authenticated;
revoke all on function public.admin_my_permissions() from public, anon;
revoke all on function public.admin_stores() from public, anon;
revoke all on function public.admin_users_count() from public, anon;
revoke all on function public.admin_list_users() from public, anon;
revoke all on function public.admin_list_orders() from public, anon;
revoke all on function public.admin_list_admin_members() from public, anon;
revoke all on function public.admin_save_admin_member(text,text,jsonb) from public, anon;
revoke all on function public.admin_remove_admin_member(text) from public, anon;
revoke all on function public.admin_update_order_status(uuid,text) from public, anon;
revoke all on function public.admin_delete_user_by_id(uuid) from public, anon;
revoke all on function public.admin_delete_store(uuid) from public, anon;
revoke all on function public.admin_delete_orders(uuid,int) from public, anon;
revoke all on function public.admin_delete_user(uuid) from public, anon;
revoke all on function public.admin_add_days(uuid,int) from public, anon;
revoke all on function public.admin_set_plan(uuid,text) from public, anon;

grant execute on function public.admin_my_permissions() to authenticated;
grant execute on function public.admin_stores() to authenticated;
grant execute on function public.admin_users_count() to authenticated;
grant execute on function public.admin_list_users() to authenticated;
grant execute on function public.admin_list_orders() to authenticated;
grant execute on function public.admin_list_admin_members() to authenticated;
grant execute on function public.admin_save_admin_member(text,text,jsonb) to authenticated;
grant execute on function public.admin_remove_admin_member(text) to authenticated;
grant execute on function public.admin_update_order_status(uuid,text) to authenticated;
grant execute on function public.admin_delete_user_by_id(uuid) to authenticated;
grant execute on function public.admin_delete_store(uuid) to authenticated;
grant execute on function public.admin_delete_orders(uuid,int) to authenticated;
grant execute on function public.admin_delete_user(uuid) to authenticated;
grant execute on function public.admin_add_days(uuid,int) to authenticated;
grant execute on function public.admin_set_plan(uuid,text) to authenticated;


-- Latest moderation extensions from the versioned migration.
-- Additional moderation controls: temporarily hide a public storefront without deleting it.
alter table public.stores
  add column if not exists is_public boolean not null default true;

drop function if exists public.admin_stores();
create function public.admin_stores()
returns table(
  id uuid, slug text, name text, whatsapp text, currency text, plan text,
  trial_started timestamptz, paid_until timestamptz, created_at timestamptz,
  is_public boolean, email text, products bigint
)
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not public.admin_has_permission('stores.view') then raise exception 'forbidden'; end if;
  return query
  select s.id,s.slug,s.name,s.whatsapp,s.currency,s.plan,s.trial_started,s.paid_until,
         s.created_at,s.is_public,u.email::text,
         (select count(*) from public.products p where p.store_id=s.id)
  from public.stores s
  join auth.users u on u.id=s.owner
  order by s.created_at desc;
end;
$$;

create or replace function public.admin_set_store_visibility(p_store_id uuid, p_is_public boolean)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not public.admin_has_permission('stores.manage') then raise exception 'forbidden'; end if;
  update public.stores set is_public=p_is_public where id=p_store_id;
  if not found then raise exception 'store not found'; end if;
end;
$$;

create or replace function public.admin_list_products()
returns table(
  id uuid, store_id uuid, store_name text, store_slug text,
  name text, price numeric, currency text, active boolean, created_at timestamptz
)
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not public.admin_has_permission('products.manage') then raise exception 'forbidden'; end if;
  return query
  select p.id,p.store_id,s.name::text,s.slug::text,p.name::text,p.price,
         s.currency::text,p.active,p.created_at
  from public.products p
  join public.stores s on s.id=p.store_id
  order by p.created_at desc
  limit 500;
end;
$$;

create or replace function public.admin_update_product_visibility(p_product_id uuid, p_active boolean)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not public.admin_has_permission('products.manage') then raise exception 'forbidden'; end if;
  update public.products set active=p_active where id=p_product_id;
  if not found then raise exception 'product not found'; end if;
end;
$$;

create or replace function public.admin_delete_product(p_product_id uuid)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
begin
  if not public.admin_has_permission('products.manage') then raise exception 'forbidden'; end if;
  delete from public.products where id=p_product_id;
  if not found then raise exception 'product not found'; end if;
end;
$$;

revoke all on function public.admin_set_store_visibility(uuid,boolean) from public, anon;
revoke all on function public.admin_list_products() from public, anon;
revoke all on function public.admin_update_product_visibility(uuid,boolean) from public, anon;
revoke all on function public.admin_delete_product(uuid) from public, anon;
grant execute on function public.admin_set_store_visibility(uuid,boolean) to authenticated;
grant execute on function public.admin_list_products() to authenticated;
grant execute on function public.admin_update_product_visibility(uuid,boolean) to authenticated;
grant execute on function public.admin_delete_product(uuid) to authenticated;
