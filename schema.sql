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
