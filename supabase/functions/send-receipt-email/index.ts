// Supabase Edge Function: sends a receipt email via Resend.
// Triggered by a Database Webhook on INSERT into `mail_requests`
// (see lib/db/mail_request_repository.dart — written when a customer
// taps "Kirim ke Email" on their receipt screen).
//
// Setup (one-time, in the Supabase dashboard):
//   1. Sign up at resend.com (free), verify a sender/domain, grab an API key.
//   2. Edge Functions > Secrets > add RESEND_API_KEY.
//   3. Deploy this function: `supabase functions deploy send-receipt-email`
//   4. Database > Webhooks > Create webhook:
//        table: mail_requests, event: INSERT, target: this Edge Function.

import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const payload = await req.json();
  const record = payload.record as {
    id: string;
    to_email: string;
    order_id: string;
  };

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  try {
    const { data: order, error } = await supabase
      .from("orders")
      .select()
      .eq("id", record.order_id)
      .single();
    if (error || !order) throw new Error("Order not found");

    const lines = (order.items as Array<{ productName: string; quantity: number; price: number }>)
      .map((i) => `  ${i.productName} x${i.quantity} - Rp${i.price * i.quantity}`);

    const body = [
      `Struk Pembayaran - Pesanan #${record.order_id.slice(0, 6).toUpperCase()}`,
      "",
      ...lines,
      "",
      `Total: Rp${order.total}`,
      `Metode Bayar: ${order.payment_method ?? "QRIS"}`,
      "",
      "Terima kasih!",
    ].join("\n");

    const resendKey = Deno.env.get("RESEND_API_KEY")!;
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "Kaata POS <onboarding@resend.dev>",
        to: record.to_email,
        subject: "Struk Pembayaran Kamu",
        text: body,
      }),
    });
    if (!res.ok) throw new Error(await res.text());

    await supabase.from("mail_requests").update({ status: "sent" }).eq("id", record.id);
  } catch (e) {
    await supabase
      .from("mail_requests")
      .update({ status: "failed", error: String(e) })
      .eq("id", record.id);
  }

  return new Response("ok");
});
