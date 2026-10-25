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
