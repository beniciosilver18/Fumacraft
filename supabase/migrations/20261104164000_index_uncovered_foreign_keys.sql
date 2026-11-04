-- Cover foreign keys flagged by Supabase Performance Advisor.
create index if not exists cust_push_order_id_idx on public.cust_push(order_id);
create index if not exists events_product_id_idx on public.events(product_id);
create index if not exists payments_store_id_idx on public.payments(store_id);
create index if not exists push_subs_store_id_idx on public.push_subs(store_id);
create index if not exists stores_referred_by_idx on public.stores(referred_by);
