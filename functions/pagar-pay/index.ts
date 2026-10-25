import { createClient } from "npm:@supabase/supabase-js@2";
const API = Deno.env.get("PAGAR_API_BASE_URL") || "https://api.pagar.co.mz/api/v1";
let KEY = "", SIG = "";
async function secrets(db: any) { const { data } = await db.from("app_secrets").select("name,value"); const m: Record<string,string> = {}; for (const r of data || []) m[r.name] = r.value; return m; }

const PRICE = 640, DAYS = 30;
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const j = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map(x => x.toString(16).padStart(2, "0")).join("");
async function hmac(key: string, msg: string) { const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]); return hex(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(msg))); }
async function pget(path: string) { const r = await fetch(API + path, { headers: { Authorization: "Bearer " + KEY } }); return { ok: r.ok, status: r.status, data: await r.json().catch(() => ({})) }; }
async function ppost(path: string, body: unknown, idem: string) {
  const ts = Date.now().toString(), nonce = crypto.randomUUID().replace(/-/g, ""), raw = JSON.stringify(body);
  const bh = hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(raw)));
  const sig = await hmac(SIG, [ts, nonce, "POST", new URL(API + path).pathname, bh].join("\n"));
  const r = await fetch(API + path, { method: "POST", headers: { Authorization: "Bearer " + KEY, "Content-Type": "application/json", "Idempotency-Key": idem, "X-Pagar-Timestamp": ts, "X-Pagar-Nonce": nonce, "X-Pagar-Signature": "v1=" + sig }, body: raw });
  return { ok: r.ok, status: r.status, data: await r.json().catch(() => ({})) };
}
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  if (!KEY) { const m = await secrets(db); KEY = m.PAGAR_API_KEY; SIG = m.PAGAR_SIGNING_SECRET; }
  const jwt = (req.headers.get("Authorization") || "").replace("Bearer ", "");
  const { data: u } = await db.auth.getUser(jwt); if (!u?.user) return j({ error: "login" }, 401);
  const { data: st } = await db.from("stores").select("id").eq("owner", u.user.id).maybeSingle(); if (!st) return j({ error: "no_store" }, 404);
  const b = await req.json().catch(() => ({}));
  if (b.action === "status") {
    const { data: p } = await db.from("payments").select("*").eq("reference", b.reference).eq("store_id", st.id).maybeSingle();
    if (!p) return j({ error: "not_found" }, 404);
    if (p.status === "PAID") return j({ status: "PAID" });
    const r = await pget("/payments/by-reference/" + encodeURIComponent(p.reference));
    const pay = r.data?.payment; const s = pay?.status || p.status;
    if (s === "PAID") await db.rpc("apply_payment", { ref: p.reference }); else await db.from("payments").update({ status: s }).eq("reference", p.reference);
    return j({ status: s, message: pay?.safeMessage || null, retryAllowed: pay?.retryAllowed });
  }
  const method = b.method === "EMOLA" ? "EMOLA" : "MPESA"; const phone = String(b.phone || "").replace(/\D/g, "").replace(/^258/, "");
  if (!/^8[2-7]\d{7}$/.test(phone)) return j({ error: "Número inválido. Use 9 dígitos, ex.: 84XXXXXXX" }, 400);
  const ref = "fc-" + st.id.slice(0, 8) + "-" + Date.now();
  await db.from("payments").insert({ reference: ref, store_id: st.id, amount: PRICE, method, days: DAYS });
  const r = await ppost("/payments", { reference: ref, title: "Fumacraft Plano Loja 30 dias", description: "Assinatura mensal da loja", amountMzn: PRICE, method, payerPhone: phone }, "pay:" + ref);
  if (!r.ok) { await db.from("payments").update({ status: "FAILED" }).eq("reference", ref); return j({ error: r.data?.message || "Pagar recusou o pedido", code: r.data?.error }, 400); }
  const p = r.data.payment; await db.from("payments").update({ pagar_id: p?.id, status: p?.status === "PAID" ? "PROCESSING" : (p?.status || "PROCESSING") }).eq("reference", ref);
  if (p?.status === "PAID") await db.rpc("apply_payment", { ref });
  return j({ reference: ref, status: p?.status });
});
