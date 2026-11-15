// LA Belle LB · new inquiry → admin alert + confirmation to the sender (Resend).
// Called by the database trigger with {"id": "<inquiry id>"}. Sends at most once per inquiry (mailed_at).
// Secrets: RESEND_API_KEY (required), MAIL_FROM (optional), NOTIFY_TO (optional).
import { createClient } from "npm:@supabase/supabase-js@2";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const KEY = Deno.env.get("RESEND_API_KEY");
const FROM = Deno.env.get("MAIL_FROM") ?? "LA Belle LB <ceo@labellelb.com>";
const TO = Deno.env.get("NOTIFY_TO") ?? "labellelb0415@gmail.com";
const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

async function send(to: string, subject: string, html: string, replyTo?: string) {
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: FROM, to: [to], subject, html, ...(replyTo ? { reply_to: replyTo } : {}) }),
  });
  if (!r.ok) throw new Error(`resend ${r.status} ${await r.text()}`);
}

const wrap = (body: string) => `<div style="font-family:Helvetica,Arial,'Noto Sans KR',sans-serif;background:#f3f2ee;padding:28px"><div style="max-width:560px;margin:auto;background:#fbfaf7;border:1px solid #dddbd2;border-radius:14px;padding:28px;color:#24252a;font-size:14px;line-height:1.65"><div style="font-weight:700;font-size:16px;margin-bottom:16px">LA Belle LB</div>${body}<p style="margin-top:24px;color:#6c6b64;font-size:12px">라벨르엘비 주식회사 · labellelb.com</p></div></div>`;

Deno.serve(async (req) => {
  const { id } = await req.json().catch(() => ({}));
  if (!id || typeof id !== "string") return new Response("bad request", { status: 400 });
  if (!KEY) return new Response("mail not configured");
  // claim the row so a repeated call never sends twice
  const { data: rows } = await sb.from("labelle_inquiries").update({ mailed_at: new Date().toISOString() })
    .eq("id", id).is("mailed_at", null).gt("created_at", new Date(Date.now() - 3600_000).toISOString()).select("*");
  const q = rows?.[0];
  if (!q) return new Response("skip");
  const brand = q.form === "brand", ko = !q.lang || q.lang === "ko";
  const kind = brand ? "브랜드 입점·해외 유통 제휴" : "비즈니스 협업";
  const rowsHtml = [["구분", kind], ["유형", q.category], ["회사/브랜드", q.company], ["담당자", q.name], ["이메일", q.email], ["연락처", q.phone],
    ["관심 국가", q.target_countries], ["제품 카테고리", q.product_category], ["링크", q.website], ["첨부", (q.attachments ?? []).length + "개"], ["언어", q.lang]]
    .filter(([, v]) => v).map(([k, v]) => `<tr><td style="color:#6c6b64;padding:4px 14px 4px 0;white-space:nowrap">${k}</td><td style="padding:4px 0">${esc(v)}</td></tr>`).join("");
  const out: string[] = [];
  try {
    await send(TO, `[라벨르엘비] 새 ${kind} 문의 · ${q.company}`, wrap(`<p><b>새 문의가 접수되었습니다.</b></p><table style="border-collapse:collapse;font-size:14px">${rowsHtml}</table>${q.message ? `<div style="white-space:pre-wrap;background:#f3f2ee;border-radius:8px;padding:12px;margin-top:14px">${esc(q.message)}</div>` : ""}<p style="margin-top:18px">labellelb.com → 관리자 → 문의 관리에서 확인하세요.</p>`), q.email);
    out.push("admin");
  } catch (e) { out.push("admin-fail " + e); }
  try {
    const subj = ko ? "[라벨르엘비] 문의가 정상적으로 접수되었습니다" : "[LA Belle LB] We have received your inquiry";
    const body = ko
      ? `<p>${esc(q.name || q.company)}님, 안녕하세요.</p><p>라벨르엘비에 <b>${kind}</b> 문의를 보내 주셔서 감사합니다. 문의가 정상적으로 접수되었으며, 담당자가 검토한 뒤 보통 2영업일 안에 이 메일 주소로 회신드립니다.</p><p style="color:#6c6b64">접수 내용: ${esc(q.category)} · ${esc(q.company)}</p><p>이 메일은 발신 전용이 아니며, 답장으로 추가 자료를 보내 주셔도 됩니다.</p>`
      : `<p>Hello ${esc(q.name || q.company)},</p><p>Thank you for your <b>${brand ? "brand listing & global distribution" : "business partnership"}</b> inquiry to La Belle LB. We have received it, and our team usually replies to this address within two business days.</p><p style="color:#6c6b64">Received: ${esc(q.company)}</p><p>You can reply to this email to send us more information.</p>`;
    await send(q.email, subj, wrap(body), TO);
    out.push("confirm");
  } catch (e) { out.push("confirm-fail " + e); }
  return new Response(out.join(", "));
});
