import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";
Deno.serve(async (req) => {
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: sec } = await db.from("app_secrets").select("name,value"); const m: Record<string,string> = {}; for (const r of sec || []) m[r.name] = r.value;
  if (req.headers.get("x-hook") !== m.PUSH_HOOK_SECRET) return new Response("no", { status: 403 });
  const { order_id } = await req.json();
  const { data: o } = await db.from("orders").select("*, stores(name,currency)").eq("id", order_id).single(); if (!o) return new Response("none");
  webpush.setVapidDetails("mailto:beniciosilver18@gmail.com", m.VAPID_PUBLIC, m.VAPID_PRIVATE);
  const total = Number(o.total).toLocaleString("pt-PT", { minimumFractionDigits: 2 }) + " " + (o.stores?.currency || "");
  const payload = JSON.stringify({ title: "🛍️ Novo pedido " + o.code, body: (o.customer || "Cliente") + " · " + total, url: "/painel?pedido=" + o.code });
  const { data: subs } = await db.from("push_subs").select("*").eq("store_id", o.store_id);
  let sent = 0;
  for (const s of subs || []) {
    try { await webpush.sendNotification(s.sub, payload, { TTL: 86400, urgency: "high" }); sent++; }
    catch (e: any) { if (e?.statusCode === 404 || e?.statusCode === 410) await db.from("push_subs").delete().eq("endpoint", s.endpoint); }
  }
  return new Response(JSON.stringify({ sent }));
});
