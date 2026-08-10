// ─────────────────────────────────────────────────────────────────────────────
// Edge Function: calendar-feed
//
// Leverer et iCalendar-feed (.ics) som medlemmerne kan abonnere på fra Google
// Kalender, Apple Kalender osv. URL'en er `?token=<bruger-id>` og bygges i
// appen under Profil → Kalender-synkronisering.
//
// Feedet er PERSONLIGT: det indeholder kun begivenheder brugeren faktisk må se.
//   • Hold: kun brugerens egne hold + klub-brede begivenheder uden hold.
//     Samme regel som Oversigten (group_ids med fallback til group_id).
//     Undtagelse: profiles.kalender_alle_hold = true → hele klubbens program,
//     hele sæsonen (også endnu ikke udgivne). Flaget gælder KUN her; det giver
//     ingen adgang til noget i appen.
//   • Synlighed: begivenheder med synlig_fra i fremtiden udelades — undtagen
//     for staff (admin/træner), der også ser dem i appen.
//
// Funktionen kører med service_role og omgår dermed RLS, så filtreringen SKAL
// ske her. Bliver den lempet, lækker hele klubbens kalender til alle.
//
// Deploy: via Management API (POST /v1/projects/<ref>/functions/deploy?slug=
// calendar-feed) eller `supabase functions deploy calendar-feed`.
// ─────────────────────────────────────────────────────────────────────────────

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ADDRESS_UNSET = "Ikke angivet";
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function escapeICS(s: string): string {
  return s
    .replace(/\\/g, "\\\\")
    .replace(/,/g, "\\,")
    .replace(/;/g, "\\;")
    .replace(/\n/g, "\\n");
}

function fmtICSDate(iso: string): string {
  const d = new Date(iso);
  const two = (n: number) => n.toString().padStart(2, "0");
  return `${d.getUTCFullYear()}${two(d.getUTCMonth() + 1)}${
    two(d.getUTCDate())
  }T${two(d.getUTCHours())}${two(d.getUTCMinutes())}${two(d.getUTCSeconds())}Z`;
}

/// Holdene en begivenhed gælder — samme regel som `_trainingGroupIds` i appen.
/// Tom liste = klub-bred (alle må se den).
function groupIdsOf(t: Record<string, unknown>): string[] {
  const arr = t.group_ids;
  if (Array.isArray(arr) && arr.length > 0) return arr.map(String);
  const single = t.group_id;
  return single ? [String(single)] : [];
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const token = url.searchParams.get("token");
  if (!token || !UUID_PATTERN.test(token)) {
    return new Response("Invalid or missing token", { status: 400 });
  }

  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: profile } = await sb
    .from("profiles")
    .select("id, navn, rolle, kalender_alle_hold")
    .eq("id", token)
    .single();
  if (!profile) {
    return new Response("User not found", { status: 404 });
  }
  const isStaff = profile.rolle === "admin" || profile.rolle === "træner";
  const allTeams = profile.kalender_alle_hold === true;

  // Brugerens hold — afgør hvad de må se i feedet.
  const { data: memberships } = await sb
    .from("group_members")
    .select("group_id")
    .eq("user_id", profile.id);
  const myGroups = new Set(
    (memberships ?? []).map((m: Record<string, unknown>) => String(m.group_id)),
  );

  const since = new Date(Date.now() - 30 * 86400000).toISOString();
  const { data: trainings } = await sb
    .from("trainings")
    .select(
      "id, titel, beskrivelse, start_tid, slut_tid, adresse, group_id, group_ids, synlig_fra",
    )
    .gte("start_tid", since)
    .order("start_tid");

  const now = Date.now();
  const mine = (trainings ?? []).filter((t: Record<string, unknown>) => {
    // Undtagelsen: hele klubbens program, hele sæsonen — uanset hold og uanset
    // om begivenheden er udgivet endnu. Bruges til at følge planlægningen i en
    // ekstern kalender.
    if (allTeams) return true;
    // Endnu ikke udgivet → kun staff ser den, præcis som i appen.
    const sf = t.synlig_fra as string | null;
    if (!isStaff && sf && new Date(sf).getTime() > now) return false;
    // Klub-bred (uden hold) er for alle; ellers skal mindst ét hold være mit.
    const gids = groupIdsOf(t);
    if (gids.length === 0) return true;
    return gids.some((g) => myGroups.has(g));
  });

  const dtstamp = fmtICSDate(new Date().toISOString());
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//De talentlose Hjorring//Padel//DA",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "X-WR-CALNAME:De talentløse Hjørring",
    "X-WR-CALDESC:Holdets træninger, kampe og events",
    "REFRESH-INTERVAL;VALUE=DURATION:PT1H",
    "X-PUBLISHED-TTL:PT1H",
  ];
  for (const t of mine) {
    lines.push("BEGIN:VEVENT");
    lines.push(`UID:${t.id}@padel.dln.dk`);
    lines.push(`DTSTAMP:${dtstamp}`);
    lines.push(`DTSTART:${fmtICSDate(t.start_tid as string)}`);
    lines.push(`DTEND:${fmtICSDate(t.slut_tid as string)}`);
    lines.push(`SUMMARY:${escapeICS(t.titel as string)}`);
    if (t.beskrivelse) {
      lines.push(`DESCRIPTION:${escapeICS(t.beskrivelse as string)}`);
    }
    if (t.adresse && t.adresse !== ADDRESS_UNSET) {
      lines.push(`LOCATION:${escapeICS(t.adresse as string)}`);
    }
    lines.push("END:VEVENT");
  }
  lines.push("END:VCALENDAR");

  return new Response(lines.join("\r\n"), {
    headers: {
      "Content-Type": "text/calendar; charset=utf-8",
      // Feedet er personligt — må ikke caches i fælles proxyer.
      "Cache-Control": "private, max-age=3600",
      "Access-Control-Allow-Origin": "*",
    },
  });
});
