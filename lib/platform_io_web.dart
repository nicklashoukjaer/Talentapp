// Web implementation backed by dart:html. Only compiled on web.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;

String? platformStorageGet(String key) => html.window.localStorage[key];

void platformStorageSet(String key, String value) =>
    html.window.localStorage[key] = value;

/// Triggers a browser download of [content] as a file named [filename].
void platformDownloadText(String filename, String mime, String content) {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = filename
    ..click();
  html.Url.revokeObjectUrl(url);
}

// ── PWA-installation (kun web) ────────────────────────────────────────────────
bool platformIsWeb() => true;

/// True hvis appen allerede kører som installeret PWA (standalone).
bool platformIsStandalone() {
  try {
    if (html.window.matchMedia('(display-mode: standalone)').matches) return true;
  } catch (_) {}
  try {
    final nav = js.context['navigator'];
    if (nav != null && nav['standalone'] == true) return true; // iOS Safari
  } catch (_) {}
  return false;
}

/// 'ios' | 'android' | 'other' ud fra user agent.
String platformOS() {
  final ua = html.window.navigator.userAgent.toLowerCase();
  if (ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod')) {
    return 'ios';
  }
  if (ua.contains('android')) return 'android';
  return 'other';
}

/// Android Chrome: er der et fanget 'beforeinstallprompt'-event klar?
bool platformCanInstallPrompt() {
  try {
    return js.context['_deferredPrompt'] != null;
  } catch (_) {
    return false;
  }
}

/// Trigger den native Android-installationsdialog (via index.html-hook).
void platformTriggerInstall() {
  try {
    js.context.callMethod('triggerInstall');
  } catch (_) {}
}

/// iPhonens safe-area-inset-bottom i px (målt i index.html). 0 hvis ingen.
double platformSafeAreaBottom() {
  try {
    final v = js.context['__safeAreaInsetBottom'];
    if (v is num) return v.toDouble();
  } catch (_) {}
  return 0.0;
}

// ── OneSignal Web SDK-bro (kun web) ───────────────────────────────────────────
/// Logger brugeren ind hos OneSignal med [externalId], viser browserens
/// push-tilladelses-prompt og returnerer subscription-id'et (eller null hvis
/// brugeren afviser / det ikke kunne hentes).
///
/// Knytter brugeren til OneSignal (external_id) uden prompt. JS-helper i
/// web/index.html.
void platformOneSignalIdentify(String externalId) {
  try {
    js.context.callMethod('osIdentify', [externalId]);
  } catch (_) {}
}

/// JS-hjælperne (osStartPrompt + osPushResult) er defineret i web/index.html.
/// Vi starter prompten og poller resultatet, så vi slipper for at vente på en
/// JS-Promise (holder os til samme dart:js-mønster som resten af filen).
Future<String?> platformOneSignalPromptAndGetId(String externalId) async {
  try {
    js.context.callMethod('osStartPrompt', [externalId]);
    // Vent op til ~90s: brugeren skal nå at trykke "Tillad" i overlayet OG
    // svare på iOS' egen native popup, før id'et registreres. Terminér ved
    // 'done' (svar afgivet) eller 'blocked' (browseren har blokeret).
    for (var i = 0; i < 180; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final res = js.context['osPushResult'];
      final status = res == null ? null : res['status'];
      if (status == 'done' || status == 'blocked') {
        final id = res['id'];
        return (id is String && id.isNotEmpty) ? id : null;
      }
    }
  } catch (_) {}
  return null;
}
