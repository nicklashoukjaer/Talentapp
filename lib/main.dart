// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'platform_io.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

part 'core/theme.dart';
part 'core/utils.dart';
part 'services/supabase_service.dart';
part 'services/cache_service.dart';
part 'services/config_service.dart';
part 'services/calendar_service.dart';
part 'services/notification_service.dart';
part 'models/feed_models.dart';
part 'models/models.dart';
part 'views/login_view.dart';
part 'views/home_shell.dart';
part 'views/oversigt_view.dart';
part 'views/profile_view.dart';
part 'views/traeninger_view.dart';
part 'views/afstemninger_view.dart';
part 'views/bodekasse_view.dart';
part 'views/dashboard_view.dart';
part 'views/polls_view.dart';
part 'views/common_fields_view.dart';
part 'views/board_view.dart';

const _supabaseUrl     = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

// ─────────────────────────────────────────────────────────────────────────────
// MobilePay Box-ID/-link styres nu af ADMINS via databasen (Dashboard).
// Se ClubConfig + mobilePayLinkFor() i services/config_service.dart.
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Klubkode — kræves for at oprette en ny bruger. Skift den her når den ændres.
// ─────────────────────────────────────────────────────────────────────────────
String clubCode = 'Talentloes2026';

const _addressUnspecified = 'Ikke angivet';
const _defaultMaxParticipants = 4;

// Sættes i main() FØR Supabase.initialize, som ellers rydder URL-fragmentet.
// Fortæller AuthGate at appen blev åbnet via et nulstil-kodeord-link.
bool pendingPasswordRecovery = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fang recovery-linket før SDK'et behandler og rydder URL'en.
  pendingPasswordRecovery = Uri.base.fragment.contains('type=recovery');
  if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
    runApp(const _MissingEnvApp());
    return;
  }
  await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
  // Opsæt OneSignal (native). Web/PWA-push initieres i web/index.html.
  await NotificationService.init();
  runApp(const PadelApp());
}


class PadelApp extends StatelessWidget {
  const PadelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'De talentløse Hjørring',
      debugShowCheckedModeBanner: false,
      theme: _buildClayCourt(),
      home: const AuthGate(),
    );
  }
}


class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _sub;
  bool _recovery = false;

  @override
  void initState() {
    super.initState();
    // Åbnet via et nulstil-kodeord-link? (fanget i main() før URL'en blev ryddet)
    if (pendingPasswordRecovery ||
        Uri.base.fragment.contains('type=recovery')) {
      _recovery = true;
    }
    // Fanger også hændelsen når SDK'et behandler recovery-linket efter opstart.
    _sub = supabase.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery && mounted) {
        setState(() => _recovery = true);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_recovery) {
      return ResetPasswordScreen(onDone: () => setState(() => _recovery = false));
    }
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, _) {
        final session = supabase.auth.currentSession;
        return session == null ? const AuthScreen() : const HomeShell();
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Login / Signup
// ─────────────────────────────────────────────────────────────────────────────

