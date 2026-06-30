// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

/// Resultat af [NotificationService.requestPermissionAndSaveToken].
enum PushResult {
  /// Token blev hentet og gemt i Supabase.
  saved,

  /// Brugeren afviste prompten (eller intet id kunne hentes).
  denied,

  /// Intet rigtigt OneSignal App ID er indsat endnu (placeholder).
  notConfigured,

  /// Ingen bruger er logget ind.
  noUser,

  /// Uventet fejl (fx netværk/Supabase).
  error,
}

// ─────────────────────────────────────────────────────────────────────────────
// NotificationService — push-notifikationer via OneSignal.
//
// VIGTIGT — to platforme, to veje:
//   • Native (Android/iOS): bruger onesignal_flutter-pakken direkte herunder.
//   • Web/PWA (jeres Vercel-deploy): onesignal_flutter virker IKKE på web, så
//     web-push kører via OneSignal Web SDK indlæst i web/index.html. Denne
//     service kalder så blot JS-broen i platform_io_web.dart.
//
// App ID'et skal stå to steder med samme værdi: _appId herunder OG appId i
// web/index.html. (Worker-filen henter SDK'et fra CDN og har intet ID.)
// ─────────────────────────────────────────────────────────────────────────────
class NotificationService {
  NotificationService._();

  /// OneSignal App ID — find det i OneSignal-dashboardet:
  /// Settings → Keys & IDs → "OneSignal App ID".
  static const String _appId = 'b404a88c-5684-4650-bff4-a72d84892a00';

  /// True når et rigtigt App ID er indsat (undgår crash/no-op under udvikling).
  static bool get isConfigured => _appId != 'DIT-ONESIGNAL-APP-ID';

  static bool _initialized = false;

  /// Kald én gang ved app-start (efter Supabase.initialize, i main()).
  static Future<void> init() async {
    if (_initialized || !isConfigured) return;
    _initialized = true;

    if (platformIsWeb()) {
      // Web-push initialiseres i web/index.html (OneSignal Web SDK) ved
      // sideindlæsning — der er intet at gøre her.
      return;
    }

    OneSignal.Debug.setLogLevel(OSLogLevel.warn);
    OneSignal.initialize(_appId);
  }

  /// Knytter den loggede bruger til OneSignal som `external_id` — UDEN at vise
  /// nogen prompt. Kaldes når man er logget ind, så vi senere kan sende
  /// målrettet push (fx bøder) til netop denne bruger via deres Supabase-id.
  /// Selve "vil du tillade?"-spørgsmålet håndteres af OneSignals slide-prompt
  /// (eller knappen i Profil) — vi spørger aldrig automatisk her.
  static Future<void> identify(String userId) async {
    if (!isConfigured) return;
    try {
      if (platformIsWeb()) {
        platformOneSignalIdentify(userId);
      } else {
        OneSignal.login(userId);
      }
    } catch (e) {
      debugPrint('NotificationService: identify fejlede: $e');
    }
  }

  /// Prompter brugeren for push-tilladelse og gemmer — hvis de siger ja —
  /// deres OneSignal subscription-id i Supabase 'profiles.onesignal_id', så
  /// backenden ved hvilken telefon/browser der hører til hvilken bruger.
  ///
  /// Kaldes "fire-and-forget" i baggrunden når en bruger er logget ind (så de
  /// bliver spurgt på et naturligt tidspunkt) — og fra "Aktivér
  /// notifikationer"-knappen i Profil-fanen, hvor returværdien bruges til at
  /// vise feedback. Fejler aldrig hårdt: push er "nice to have" og må aldrig
  /// vælte UI'et.
  static Future<PushResult> requestPermissionAndSaveToken() async {
    if (!isConfigured) return PushResult.notConfigured;
    final user = supabase.auth.currentUser;
    if (user == null) return PushResult.noUser;

    try {
      String? subId;

      if (platformIsWeb()) {
        // Web: JS-broen logger ind, viser prompten og venter på subscription-id.
        subId = await platformOneSignalPromptAndGetId(user.id);
      } else {
        // Native: knyt OneSignal-bruger til vores Supabase-bruger-id…
        OneSignal.login(user.id);
        // …vis system-prompten (true = fallback hvis tidligere afvist)…
        final accepted = await OneSignal.Notifications.requestPermission(true);
        if (!accepted) return PushResult.denied;
        // …id'et er ikke altid klar straks efter ja; prøv et par gange.
        for (var i = 0; i < 6; i++) {
          subId = OneSignal.User.pushSubscription.id;
          if (subId != null && subId.isNotEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }
      }

      if (subId == null || subId.isEmpty) return PushResult.denied;

      await supabase
          .from('profiles')
          .update({'onesignal_id': subId})
          .eq('id', user.id);
      return PushResult.saved;
    } catch (e) {
      debugPrint('NotificationService: push-token kunne ikke gemmes: $e');
      return PushResult.error;
    }
  }
}
