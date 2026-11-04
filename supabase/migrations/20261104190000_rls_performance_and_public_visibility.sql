-- Optimise auth.uid() evaluation and prevent unpublished stores/products leaking through public reads.
DO $$
DECLARE
  pol record;
  role_list text;
  statement text;
BEGIN
  FOR pol IN
    SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
    FROM pg_policies
    WHERE schemaname = 'public'
      AND (coalesce(qual, '') || coalesce(with_check, '')) LIKE '%auth.uid()%'
  LOOP
    SELECT string_agg(
      CASE WHEN r = 'public' THEN 'PUBLIC' ELSE format('%I', r) END,
      ', '
    )
    INTO role_list
    FROM unnest(pol.roles) AS x(r);

    EXECUTE format('DROP POLICY %I ON %I.%I',
      pol.policyname, pol.schemaname, pol.tablename);

    statement := format(
      'CREATE POLICY %I ON %I.%I AS %s FOR %s TO %s',
      pol.policyname, pol.schemaname, pol.tablename,
      lower(pol.permissive), pol.cmd, role_list
    );

    IF pol.qual IS NOT NULL THEN
      statement := statement || ' USING (' ||
        regexp_replace(pol.qual, 'auth[.]uid[(][)]', '(select auth.uid())', 'g') || ')';
    END IF;

    IF pol.with_check IS NOT NULL THEN
      statement := statement || ' WITH CHECK (' ||
        regexp_replace(pol.with_check, 'auth[.]uid[(][)]', '(select auth.uid())', 'g') || ')';
    END IF;

    EXECUTE statement;
  END LOOP;
END $$;

-- A store can be read publicly only when published; its owner retains access when private.
DROP POLICY IF EXISTS stores_read ON public.stores;
CREATE POLICY stores_read ON public.stores
  FOR SELECT TO PUBLIC
  USING (is_public IS TRUE OR owner = (select auth.uid()));

-- Only active products in published stores are public. Owners can still manage/view all their products.
DROP POLICY IF EXISTS products_read ON public.products;
CREATE POLICY products_read ON public.products
  FOR SELECT TO PUBLIC
  USING (
    EXISTS (
      SELECT 1
      FROM public.stores s
      WHERE s.id = products.store_id
        AND (
          (s.is_public IS TRUE AND products.active IS TRUE)
          OR s.owner = (select auth.uid())
        )
    )
  );

-- Separate write policies avoid a second permissive SELECT policy on products.
DROP POLICY IF EXISTS products_write ON public.products;
DROP POLICY IF EXISTS products_insert ON public.products;
DROP POLICY IF EXISTS products_update ON public.products;
DROP POLICY IF EXISTS products_delete ON public.products;

CREATE POLICY products_insert ON public.products
  FOR INSERT TO PUBLIC
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.stores s
      WHERE s.id = products.store_id AND s.owner = (select auth.uid()))
  );

CREATE POLICY products_update ON public.products
  FOR UPDATE TO PUBLIC
  USING (
    EXISTS (SELECT 1 FROM public.stores s
      WHERE s.id = products.store_id AND s.owner = (select auth.uid()))
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.stores s
      WHERE s.id = products.store_id AND s.owner = (select auth.uid()))
  );

CREATE POLICY products_delete ON public.products
  FOR DELETE TO PUBLIC
  USING (
    EXISTS (SELECT 1 FROM public.stores s
      WHERE s.id = products.store_id AND s.owner = (select auth.uid()))
  );
