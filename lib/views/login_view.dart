// Auto-split (del af biblioteket padel_app)
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
part of '../main.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isSignup = false;
  bool _loading  = false;

  final _formKey      = GlobalKey<FormState>();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _navnCtrl     = TextEditingController();
  final _clubCodeCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _navnCtrl.dispose();
    _clubCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      if (_isSignup) {
        final res = await supabase.auth.signUp(
          email:    _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          data:     {'navn': _navnCtrl.text.trim()},
        );
        if (!mounted) return;
        if (res.session == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Profil oprettet — tjek din mail for bekræftelseslink.'),
          ));
          setState(() => _isSignup = false);
        }
      } else {
        await supabase.auth.signInWithPassword(
          email:    _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      }
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Uventet fejl: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  /// Terracotta install-banner i bunden af login — kun på web når appen IKKE
  /// allerede kører som installeret PWA (standalone). Returnerer null ellers.
  Widget? _buildInstallBanner(BuildContext context) {
    if (!platformIsWeb() || platformIsStandalone()) return null;
    final os = platformOS();
    if (os != 'ios' && os != 'android') return null;
    final isIos = os == 'ios';
    return Material(
      color: _neon,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Row(
            children: [
              Icon(isIos ? Icons.ios_share : Icons.install_mobile,
                  color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isIos
                      ? "Installér appen på iPhone: Tryk på de 3 prikker i "
                          "Safari ➔ Vælg 'Del' ➔ Rul ned og tryk 'Se mere' ➔ "
                          "Vælg 'Føj til hjemmeskærm' 🎾"
                      : 'Føj De Talentløse til din startskærm 🎾',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      height: 1.3),
                ),
              ),
              if (!isIos) ...[
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: platformTriggerInstall,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _neon,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Installér'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      bottomNavigationBar: _buildInstallBanner(context),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.sports_tennis, size: 64, color: theme.colorScheme.primary),
                      const SizedBox(height: 12),
                      Text('DE TALENTLØSE',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                              letterSpacing: 2)),
                      const SizedBox(height: 2),
                      Text('HJØRRING',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              letterSpacing: 6)),
                      const SizedBox(height: 6),
                      Text('THE CLAY COURT',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: _textSecondary,
                              letterSpacing: 4,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 24),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Log ind')),
                          ButtonSegment(value: true,  label: Text('Opret profil')),
                        ],
                        selected: {_isSignup},
                        onSelectionChanged: (s) => setState(() => _isSignup = s.first),
                      ),
                      const SizedBox(height: 24),
                      if (_isSignup) ...[
                        TextFormField(
                          controller: _navnCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Navn',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Indtast dit navn' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _clubCodeCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Klubkode',
                            prefixIcon: Icon(Icons.vpn_key_outlined),
                            helperText: 'Få koden af en træner',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Indtast klubkode';
                            }
                            if (v.trim() != clubCode) return 'Forkert klubkode';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'E-mail',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Indtast email';
                          if (!v.contains('@'))               return 'Ugyldig email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: 'Adgangskode',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Indtast adgangskode';
                          if (v.length < 6)           return 'Mindst 6 tegn';
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(_isSignup ? 'Opret profil' : 'Log ind'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HomeShell — NavigationRail (5 destinations) + Ctrl+K + command registry
// ─────────────────────────────────────────────────────────────────────────────

