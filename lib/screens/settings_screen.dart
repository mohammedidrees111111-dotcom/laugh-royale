import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/localization.dart';
import '../services/auth_service.dart';
import '../services/error_handler.dart';
import '../services/language_service.dart';
import '../config/theme.dart';
import 'onboarding/login_screen.dart';
import 'onboarding/register_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifications = true;
  bool _darkMode = true;
  Map<String, int> _stats = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPreferences();
    });
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _notifications = prefs.getBool('notifications') ?? true;
        _darkMode = prefs.getBool('darkMode') ?? true;
        _stats = {
          'wins': prefs.getInt('wins') ?? 0,
          'losses': prefs.getInt('losses') ?? 0,
          'total': prefs.getInt('totalGames') ?? 0,
        };
      });
    } catch (e, stack) {
      ErrorHandler.logError('Settings load', e, stack);
    }
  }

  Future<void> _savePreference(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign Out')),
        ],
      ),
    );
    if (confirm == true) {
      await AuthService.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  void _switchLanguage() async {
    await LanguageService.switchLanguage();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final theme = Theme.of(context);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _sectionHeader(l.profile),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
                  child: Text(AuthService.displayName[0].toUpperCase(),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(AuthService.displayName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Text(AuthService.isGuest ? 'Guest Mode' : 'Signed In', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                  ]),
                ),
                if (AuthService.isSignedIn)
                  TextButton(onPressed: _signOut, child: Text(l.signOut, style: const TextStyle(color: Colors.redAccent))),
              ]),
            ),
          ),
          if (AuthService.isGuest) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen()))
                          .then((_) => setState(() {}));
                    },
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text('Sign Up'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C63FF)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen()))
                          .then((_) => setState(() {}));
                    },
                    icon: const Icon(Icons.login, size: 18),
                    label: const Text('Log In'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                  ),
                ),
              ]),
            ),
          ],

          _sectionHeader('Game Stats'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _statItem('\ud83c\udfc6', _stats['wins'] ?? 0, 'Wins', Colors.amber),
                _statItem('\ud83d\ude22', _stats['losses'] ?? 0, 'Losses', Colors.redAccent),
                _statItem('\ud83c\udfae', _stats['total'] ?? 0, 'Total', const Color(0xFF6C63FF)),
                _statItem('\ud83d\udcb0', 1250, 'Gems', const Color(0xFF00D9FF)),
              ]),
            ),
          ),

          _sectionHeader('Preferences'),
          _switchTile(Icons.notifications_outlined, l.notifications, 'Get notified about challenges', _notifications, (v) {
            setState(() => _notifications = v);
            _savePreference('notifications', v);
          }),
          _switchTile(Icons.dark_mode, l.darkMode, 'Enable dark theme', _darkMode, (v) {
            setState(() => _darkMode = v);
            _savePreference('darkMode', v);
            AppTheme.darkModeNotifier.value = v;
          }),
          _switchTile(Icons.language, 'Language', isArabic ? '\u0627\u0644\u0639\u0631\u0628\u064a\u0629 (Arabic)' : 'English', isArabic, (_) => _switchLanguage()),

          _sectionHeader(l.about),
          _infoTile(Icons.info_outline, l.version, '1.0.0 (build 1)'),
          _infoTile(Icons.description_outlined, l.termsOfService, '', () => _showTerms()),
          _infoTile(Icons.shield_outlined, l.privacyPolicy, '', () => _showPrivacy()),
          _infoTile(Icons.verified_user, 'Secure Payments', 'Processed via PayPal'),

          const SizedBox(height: 40),
          Center(child: Text('Laugh Royale v1.0.0', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12))),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showTerms() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terms of Service'),
        content: const SingleChildScrollView(
          child: Text('By using Laugh Royale, you agree to play fair, not use cheats, and respect other players. '
              'All payments are processed securely via PayPal.\n\n'
              'We reserve the right to suspend accounts for violating community guidelines.'),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  void _showPrivacy() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Privacy Policy'),
        content: const SingleChildScrollView(
          child: Text('Laugh Royale collects minimal data: your email, game stats, and country for matchmaking. '
              'Camera data is processed on-device only and never uploaded.\n\n'
              'Payment data is handled entirely by PayPal. We never store your financial information.'),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
    );
  }

  Widget _statItem(String emoji, int value, String label, Color color) {
    return Column(children: [
      Text(emoji, style: const TextStyle(fontSize: 28)),
      const SizedBox(height: 4),
      Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
    ]);
  }

  Widget _switchTile(IconData icon, String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SwitchListTile(
        secondary: Icon(icon, color: Colors.white70),
        title: Text(title, style: const TextStyle(fontSize: 15)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.white54)),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _infoTile(IconData icon, String title, String subtitle, [VoidCallback? onTap]) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: Colors.white70),
        title: Text(title, style: const TextStyle(fontSize: 15)),
        subtitle: subtitle.isNotEmpty ? Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.white54)) : null,
        trailing: onTap != null ? const Icon(Icons.chevron_right, color: Colors.white24) : null,
        onTap: onTap,
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
