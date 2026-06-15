import 'package:flutter/material.dart';
import '../../l10n/localization.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import 'register_screen.dart';
import '../../app.dart' show MainShell;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please fill all fields');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final ok = await AuthService.signInWithEmail(email, pass);
    if (!mounted) return;
    if (ok) {
      await _navigateToMain();
    } else {
      setState(() { _loading = false; _error = 'Login failed. Try signing up.'; });
    }
  }

  Future<void> _guestLogin() async {
    await AuthService.signInAsGuest();
    if (!mounted) return;
    await _navigateToMain();
  }

  Future<void> _navigateToMain() async {
    // Check if country is set, if not go to country select
    final country = await AuthService.getSavedCountry();
    if (!mounted) return;
    if (country == null) {
      Navigator.of(context).pushReplacementNamed('/country');
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => MainShell()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Icon(Icons.emoji_emotions, size: 56, color: Color(0xFF6C63FF)),
                ),
                const SizedBox(height: 24),
                Text(l.appTitle, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('The Ultimate Laugh Challenge', style: TextStyle(color: Colors.white54, fontSize: 14)),
                const SizedBox(height: 40),

                // Email
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: l.email,
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),

                // Password
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l.password,
                    prefixIcon: const Icon(Icons.lock_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onSubmitted: (_) => _signIn(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ],
                const SizedBox(height: 24),

                // Sign In Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _loading ? null : _signIn,
                    child: _loading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(l.signIn, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 12),

                // Sign Up Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _loading ? null : () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen()));
                    },
                    child: Text(l.signUp, style: const TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 24),

                // Divider
                Row(children: [
                  const Expanded(child: Divider()),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(l.or, style: const TextStyle(color: Colors.white38))),
                  const Expanded(child: Divider()),
                ]),
                const SizedBox(height: 24),

                // Guest Mode
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _guestLogin,
                    icon: const Icon(Icons.person_outline),
                    label: Text(l.guestMode, style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
