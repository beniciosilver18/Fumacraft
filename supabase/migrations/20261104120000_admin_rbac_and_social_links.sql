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
