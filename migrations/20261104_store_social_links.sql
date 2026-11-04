-- Optional public social profiles and community invite link for each store.
alter table public.stores
  add column if not exists social_links jsonb not null default '{}'::jsonb;
