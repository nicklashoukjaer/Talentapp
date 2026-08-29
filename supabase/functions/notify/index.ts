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
// Automatisk til rådighed i Supabase Edge Functions — ingen ekstra secrets.
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const ONESIGNAL_URL = "https://api.onesignal.com/notifications";
const APP_URL = "https://de-talentlose.vercel.app";

// Holdene en begivenhed/afstemning gælder. Samme regel som i appen:
// group_ids (flere hold) med fallback til group_id. Tom = klub-bred.
function groupIdsOf(rec: Record<string, unknown>): string[] {
  const arr = rec.group_ids;
  if (Array.isArray(arr) && arr.length > 0) return arr.map(String);
  const single = rec.group_id;
  return single ? [String(single)] : [];
}

async function restGet(path: string): Promise<Record<string, unknown>[]> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    headers: {
      "apikey": SERVICE_ROLE_KEY,
      "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
    },
  });
  if (!res.ok) {
    console.error("Supabase-opslag fejlede", res.status, await res.text());
    return [];
  }
  return await res.json();
}

/// Hvem skal have besked om noget der hører til [groupIds]?
/// Medlemmerne af de hold (trænere inkluderet — de er på holdet) plus alle
/// admins, som følger hele klubben. Tom liste = ingen at sende til.
async function recipientsForGroups(groupIds: string[]): Promise<string[]> {
  const inList = encodeURIComponent(
    `(${groupIds.map((g) => `"${g}"`).join(",")})`,
  );
  const [members, admins] = await Promise.all([
    restGet(`group_members?group_id=in.${inList}&select=user_id`),
    restGet(`profiles?rolle=eq.admin&select=id`),
  ]);
  const ids = new Set<string>();
  for (const m of members) if (m.user_id) ids.add(String(m.user_id));
  for (const a of admins) if (a.id) ids.add(String(a.id));
  return [...ids];
}

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

/// Modtager-feltet til OneSignal for en begivenhed/afstemning.
/// Uden hold: hele klubben (som hidtil). Med hold: kun holdets medlemmer plus
/// admins. null = ingen at sende til, så vi springer kaldet over.
async function audienceFor(
  rec: Record<string, unknown>,
  udelad = "",
): Promise<Record<string, unknown> | null> {
  const groupIds = groupIdsOf(rec);
  if (groupIds.length === 0) {
    // Klub-bredt. Kan vi ikke udelade én person af et segment, sender vi til
    // alle — det er stadig bedre end ingen besked.
    if (!udelad) return { included_segments: ["Total Subscriptions"] };
    const alle = await restGet(`profiles?select=id`);
    const ids = alle
      .map((p) => String(p.id))
      .filter((id) => id && id !== udelad);
    if (ids.length === 0) return null;
    return { include_aliases: { external_id: ids } };
  }
  const ids = (await recipientsForGroups(groupIds)).filter((id) =>
    id !== udelad
  );
  if (ids.length === 0) return null;
  return { include_aliases: { external_id: ids } };
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
      const target = await audienceFor(rec);
      if (!target) return new Response("no recipients", { status: 200 });
      result = await sendPush({
        ...target,
        headings: { en: "Ny begivenhed 🎾", da: "Ny begivenhed 🎾" },
        contents: { en: `${titel}${when}`, da: `${titel}${when}` },
      });
      break;
    }
    case "trainings_aendret": {
      // Ændret begivenhed. Teksten er lavet i databasen, så push og klokke
      // siger nøjagtig det samme.
      const titel = (rec.titel as string) ?? "Begivenhed";
      const hvad = (rec._aendringer as string) ?? "Der er sket en ændring";
      const target = await audienceFor(rec, String(rec._af ?? ""));
      if (!target) return new Response("no recipients", { status: 200 });
      result = await sendPush({
        ...target,
        headings: { en: "Ændret 🔁", da: "Ændret 🔁" },
        contents: { en: `${titel} — ${hvad}`, da: `${titel} — ${hvad}` },
      });
      break;
    }
    case "polls": {
      const titel = (rec.titel as string) ?? "Ny afstemning";
      const target = await audienceFor(rec);
      if (!target) return new Response("no recipients", { status: 200 });
      result = await sendPush({
        ...target,
        headings: { en: "Ny afstemning 🗳️", da: "Ny afstemning 🗳️" },
        contents: { en: titel, da: titel },
      });
      break;
    }
    case "boedeforslag": {
      // Navngiven modtagerliste (staff) frem for et hold — derfor ikke
      // audienceFor() her.
      const ids = ((rec._modtagere as unknown[]) ?? []).map(String).filter(
        Boolean,
      );
      if (ids.length === 0) return new Response("no recipients", { status: 200 });
      const titel = (rec.titel as string) ?? "Bødeforslag";
      const af = (rec._af as string) ?? "";
      result = await sendPush({
        include_aliases: { external_id: ids },
        headings: { en: "Nyt bødeforslag ⚖️", da: "Nyt bødeforslag ⚖️" },
        contents: {
          en: af ? `${titel} — foreslået af ${af}` : titel,
          da: af ? `${titel} — foreslået af ${af}` : titel,
        },
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
