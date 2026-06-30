// Non-web stub used on mobile/desktop, where dart:html is unavailable.
// Storage is kept in memory for the session (the calendar-sync toggle still
// works during the run). File download is a no-op for now; on mobile this
// would typically use share_plus or write to the Downloads folder.
final Map<String, String> _memoryStorage = <String, String>{};

String? platformStorageGet(String key) => _memoryStorage[key];

void platformStorageSet(String key, String value) =>
    _memoryStorage[key] = value;

void platformDownloadText(String filename, String mime, String content) {
  // No-op on non-web. TODO: implement with share_plus / path_provider.
}

// ── PWA-installation: ikke relevant i den native app ──────────────────────────
bool platformIsWeb() => false;
bool platformIsStandalone() => true; // native app = "installeret", vis aldrig banner
String platformOS() => 'other';
bool platformCanInstallPrompt() => false;
void platformTriggerInstall() {}
double platformSafeAreaBottom() => 0.0; // native håndteres af MediaQuery/SafeArea

// OneSignal Web SDK-broen findes kun på web; native bruger onesignal_flutter
// direkte i NotificationService, så her er de blot no-ops.
Future<String?> platformOneSignalPromptAndGetId(String externalId) async => null;
void platformOneSignalIdentify(String externalId) {}
