-- Restrict administrative and maintenance SECURITY DEFINER RPCs.
-- Public storefront RPCs remain available to anonymous visitors.

revoke all on function public.admin_stores() from public, anon;
grant execute on function public.admin_stores() to authenticated;

revoke all on function public.purge_old_orders() from public, anon, authenticated;

-- Trigger functions are invoked by PostgreSQL triggers, not directly through the Data API.
revoke all on function public.notify_order() from public, anon, authenticated;
revoke all on function public.notify_status() from public, anon, authenticated;
revoke all on function public.notify_waiter() from public, anon, authenticated;
