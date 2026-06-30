// ─────────────────────────────────────────────────────────────────────────────
// Edge Function: notify
//
// Sender push-notifikationer via OneSignal når der oprettes en ny række i
// trainings / polls / fines. Kaldes af en database-trigger (pg_net) på INSERT —
// se supabase/migrations/*_notify_push.sql.
//
// Krævede secrets (sæt med `supabase secrets set ...`):
//   ONESIGNAL_APP_ID        = b404a88c-5684-4650-bff4-a72d84892a00
//   ONESIGNAL_REST_API_KEY  = <REST API Key fra OneSignal → Settings → Keys & IDs>
//   NOTIFY_WEBHOOK_SECRET   = <vilkårlig hemmelig streng, samme som i SQL'en>
//
// Deploy:  supabase functions deploy notify --no-verify-jwt
// (--no-verify-jwt fordi databasen kalder os; vi beskytter i stedet med
//  x-webhook-secret-headeren herunder.)
// ─────────────────────────────────────────────────────────────────────────────

const ONESIGNAL_APP_ID = Deno.env.get("ONESIGNAL_APP_ID") ?? "";
const ONESIGNAL_REST_API_KEY = Deno.env.get("ONESIGNAL_REST_API_KEY") ?? "";
const WEBHOOK_SECRET = Deno.env.get("NOTIFY_WEBHOOK_SECRET") ?? "";

const ONESIGNAL_URL = "https://api.onesignal.com/notifications";
const APP_URL = "https://de-talentlose.vercel.app";

// Pænt dansk dato/tid i Europe/Copenhagen, fx "tor. 25. jun. 18:30".
function daDateTime(iso: string): string {
  try {
    return new Date(iso).toLocaleString("da-DK", {
      weekday: "short",
      day: "numeric",
      month: "short",
      hour: "2-digit",
      minute: "2-digit",
      timeZone: "Europe/Copenhagen",
    });
  } catch {
    return "";
  }
}

async function sendPush(extra: Record<string, unknown>) {
  const res = await fetch(ONESIGNAL_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Key ${ONESIGNAL_REST_API_KEY}`,
    },
    body: JSON.stringify({
      app_id: ONESIGNAL_APP_ID,
      target_channel: "push",
      url: APP_URL,
      ...extra,
    }),
  });
  const text = await res.text();
  if (!res.ok) console.error("OneSignal-fejl", res.status, text);
  return { ok: res.ok, status: res.status, body: text };
}

Deno.serve(async (req) => {
  // Simpel beskyttelse: kun kald med vores hemmelige header accepteres.
  if (req.headers.get("x-webhook-secret") !== WEBHOOK_SECRET) {
    return new Response("forbidden", { status: 401 });
  }

  let payload: { table?: string; record?: Record<string, unknown> };
  try {
    payload = await req.json();
  } catch {
    return new Response("bad json", { status: 400 });
  }

  const table = payload.table ?? "";
  const rec = payload.record ?? {};

  let result;
  switch (table) {
    case "trainings": {
      const titel = (rec.titel as string) ?? "Ny begivenhed";
      const when = rec.start_tid ? ` — ${daDateTime(rec.start_tid as string)}` : "";
      result = await sendPush({
        included_segments: ["Subscribed Users"],
        headings: { en: "Ny begivenhed 🎾", da: "Ny begivenhed 🎾" },
        contents: { en: `${titel}${when}`, da: `${titel}${when}` },
      });
      break;
    }
    case "polls": {
      const titel = (rec.titel as string) ?? "Ny afstemning";
      result = await sendPush({
        included_segments: ["Subscribed Users"],
        headings: { en: "Ny afstemning 🗳️", da: "Ny afstemning 🗳️" },
        contents: { en: titel, da: titel },
      });
      break;
    }
    case "fines": {
      const userId = rec.user_id ? String(rec.user_id) : "";
      if (!userId) return new Response("no user_id", { status: 200 });
      const titel = (rec.titel as string) ?? "Bøde";
      const kr = typeof rec.belob_oere === "number"
        ? ` (${(rec.belob_oere as number) / 100} kr.)`
        : "";
      result = await sendPush({
        include_aliases: { external_id: [userId] },
        headings: { en: "Du har fået en bøde ⚖️", da: "Du har fået en bøde ⚖️" },
        contents: { en: `${titel}${kr}`, da: `${titel}${kr}` },
      });
      break;
    }
    default:
      return new Response("ignored", { status: 200 });
  }

  return new Response(JSON.stringify(result), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
