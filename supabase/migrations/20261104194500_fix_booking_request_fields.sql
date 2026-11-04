-- Preserve both the requested booking time and the customer's notes in their intended order fields.
CREATE OR REPLACE FUNCTION public.create_order(
  sid uuid, its jsonb, cname text, cmode text, caddr text, cnote text,
  ccoupon text DEFAULT NULL::text, cvisitor text DEFAULT NULL::text, ctable text DEFAULT NULL::text
)
RETURNS TABLE(code text, items jsonb, subtotal numeric, fee numeric, total numeric, discount numeric, coupon text, tok uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare st stores; c text; lines jsonb := '[]'; sub numeric := 0; f numeric := 0;
d numeric := 0; cc text := null; r record; i int := 0; tb text := null; tk uuid;
begin
 select * into st from stores where id=sid;
 if not found then raise exception 'store'; end if;
 if st.is_public is not true then raise exception 'not_public'; end if;
 if not public.store_is_open(st) then raise exception 'closed'; end if;
 if cmode not in ('entrega','levantamento','mesa','marcacao') then raise exception 'invalid_mode'; end if;
 if cmode='entrega' and st.delivery is not true then raise exception 'delivery_disabled'; end if;
 if cmode='levantamento' and st.pickup is not true then raise exception 'pickup_disabled'; end if;
 if cmode='marcacao' and (st.delivery is true or st.pickup is true) then raise exception 'booking_only'; end if;
 if cmode='mesa' then
   if not st.dine_in then raise exception 'no_dine_in'; end if;
   tb := nullif(left(trim(coalesce(ctable,'')),10),'');
   if tb is null then raise exception 'table'; end if;
 end if;
 for r in
   select p.id,p.name,p.price,(x->>'qty')::int q
   from jsonb_array_elements(its) x
   join products p on p.id=(x->>'id')::uuid and p.store_id=sid and p.active
 loop
   if r.q<1 or r.q>999 then continue; end if;
   lines := lines || jsonb_build_object('name',r.name,'qty',r.q,'price',r.price);
   sub := sub + r.price*r.q;
 end loop;
 if jsonb_array_length(lines)=0 then raise exception 'empty'; end if;
 if cmode='entrega' then f := coalesce(st.delivery_fee,0); end if;
 if coalesce(trim(ccoupon),'')<>'' then
   d := public.coupon_discount(sid, ccoupon, sub);
   if d is null then raise exception 'coupon'; end if;
   cc := upper(trim(ccoupon));
 end if;
 loop
   c := (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',(1+floor(random()*32))::int,1),'') from generate_series(1,6));
   exit when not exists(select 1 from orders o where o.code=c);
   i:=i+1; exit when i>20;
 end loop;
 insert into orders(store_id,code,items,subtotal,fee,total,customer,mode,address,note,discount,coupon,table_no)
 values(sid,c,lines,sub,f,sub-d+f,left(cname,80),cmode,
   case when cmode in ('entrega','marcacao') then left(caddr,300) end,
   left(cnote,300),d,cc,tb)
 returning orders.token into tk;
 insert into events(store_id,type,visitor)
 values(sid,'order',nullif(left(coalesce(cvisitor,''),40),''));
 return query select c,lines,sub,f,sub-d+f,d,cc,tk;
end
$function$;
