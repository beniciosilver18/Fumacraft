-- Include phone and signup name in the root/admin user directory for phone-first accounts.
DROP FUNCTION IF EXISTS public.admin_list_users();
CREATE FUNCTION public.admin_list_users()
RETURNS TABLE(
  id uuid,
  email text,
  phone text,
  full_name text,
  created_at timestamptz,
  last_sign_in_at timestamptz,
  stores_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'auth'
AS $function$
begin
  if not public.admin_has_permission('users.view') then raise exception 'forbidden'; end if;
  return query
  select
    u.id,
    u.email::text,
    u.phone::text,
    coalesce(nullif(u.raw_user_meta_data->>'full_name',''),nullif(u.raw_user_meta_data->>'name',''))::text,
    u.created_at,
    u.last_sign_in_at,
    (select count(*) from public.stores s where s.owner=u.id)
  from auth.users u
  order by u.created_at desc
  limit 500;
end;
$function$;
REVOKE ALL ON FUNCTION public.admin_list_users() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_users() TO authenticated;
