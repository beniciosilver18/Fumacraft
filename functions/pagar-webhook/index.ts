import { createClient } from "npm:@supabase/supabase-js@2";

const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map(x => x.toString(16).padStart(2, "0")).join("");
Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("ok");
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: ws } = await db.from("app_secrets").select("value").eq("name","PAGAR_WEBHOOK_SECRET").single(); const WH = ws!.value;
  const raw = await req.text();
  const eid = req.headers.get("Pagar-Event-Id"); if (!eid) return new Response("no id", { status: 400 });
  const parts = Object.fromEntries((req.headers.get("Pagar-Signature") || "").split(",").map(p => p.trim().split("=")));
  const ts = parts.t, got = parts.v1;
  if (!/^\d+$/.test(ts || "") || !/^[a-f0-9]{64}$/.test(got || "")) return new Response("bad sig", { status: 401 });
  if (Math.abs(Date.now() / 1000 - Number(ts)) > 300) return new Response("old", { status: 401 });
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(WH), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const exp = hex(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(ts + "." + raw)));
  let diff = exp.length ^ got.length; for (let i = 0; i < exp.length; i++) diff |= exp.charCodeAt(i) ^ (got.charCodeAt(i) || 0);
  if (diff) return new Response("bad sig", { status: 401 });
  const ev = JSON.parse(raw); const type = ev.type || ev.event;
  const pay = ev.data?.payment || ev.payment || ev.data || {};
  if (pay.reference) {
    if (type === "payment.succeeded" || pay.status === "PAID") await db.rpc("apply_payment", { ref: pay.reference });
    else if (type === "payment.failed") await db.from("payments").update({ status: pay.status || "FAILED" }).eq("reference", pay.reference).neq("status", "PAID");
  }
  return new Response("ok");
});
