import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_config.dart';
import 'config/theme.dart';
import 'l10n/localization.dart';
import 'screens/home_screen.dart';
import 'screens/feed_screen.dart';
import 'screens/create_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/lobby/lobby_screen.dart';
import 'screens/store/store_screen.dart';
import 'screens/onboarding/login_screen.dart';
import 'screens/onboarding/country_select_screen.dart';
import 'screens/onboarding/register_screen.dart';
import 'services/auth_service.dart';
import 'services/firebase_service.dart';
import 'services/error_handler.dart';
import 'widgets/error_fallback.dart';

class LaughRoyaleApp extends StatefulWidget {
  const LaughRoyaleApp({super.key});

  @override
  State<LaughRoyaleApp> createState() => _LaughRoyaleAppState();
}

class _LaughRoyaleAppState extends State<LaughRoyaleApp> {
  bool _initialized = false;
  bool _hasError = false;
  bool _firebaseOk = false;
  bool _isLoggedIn = false;
  Locale _locale = const Locale('en');

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lang = prefs.getString('language') ?? 'en';
      if (lang == 'ar') _locale = const Locale('ar');

      final fbOk = await FirebaseService.safeInitialize();
      debugPrint('APP: Firebase initialized → $fbOk');

      AppConfig.checkServerHealth(url: AppConfig.candidateWsUrls.first)
          .then((ok) => debugPrint('APP: Server warmup → ${ok ? "OK" : "sleeping"}'));

      _isLoggedIn = await AuthService.restoreSession();
    } catch (e, stack) {
      ErrorHandler.logError('App init', e, stack);
    }

    if (mounted) setState(() => _initialized = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return MaterialApp(
        locale: _locale,
        localizationsDelegates: const [L.delegate],
        supportedLocales: const [Locale('en'), Locale('ar')],
        home: Scaffold(
          body: ErrorFallbackWidget(
            message: 'Failed to start app. Please restart.',
            onRetry: () {
              setState(() => _hasError = false);
              _initializeApp();
            },
          ),
        ),
      );
    }

    if (!_initialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: _locale,
        localizationsDelegates: const [L.delegate],
        supportedLocales: const [Locale('en'), Locale('ar')],
        home: const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.emoji_emotions, size: 64, color: Color(0xFFFF6584)),
                SizedBox(height: 24),
                Text('Laugh Royale',
                    style: TextStyle(
                        color: Color(0xFFFF6584),
                        fontSize: 32,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 12),
                Text('REAL PLAYERS ONLY',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3)),
                SizedBox(height: 24),
                SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                        strokeWidth: 3, color: Color(0xFFFF6584))),
              ],
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'Laugh Royale',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      localizationsDelegates: const [L.delegate],
      supportedLocales: const [Locale('en'), Locale('ar')],
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: _isLoggedIn ? const MainShell() : const LoginScreen(),
      routes: {
        '/country': (ctx) => const CountrySelectScreen(),
      },
      builder: (context, child) {
        return child!;
      },
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  late final List<Widget> _screens = [
    const HomeScreen(),
    const FeedScreen(),
    const CreateScreen(),
    const LobbyScreen(),
    const StoreScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
  }

  void _showFirebaseAlert() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_amber, color: Colors.orange),
          SizedBox(width: 8),
          Text('Firebase Setup Required'),
        ]),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Real multiplayer needs Firebase. No bots!'),
              SizedBox(height: 16),
              Text('Follow these steps:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('1. Go to console.firebase.google.com'),
              Text('2. Create project "laugh-royale"'),
              Text('3. Add Android app: com.laughroyale.app'),
              Text('4. Enable Cloud Firestore'),
              Text('5. Download google-services.json'),
              Text('6. Replace: android/app/google-services.json'),
              SizedBox(height: 12),
              Text('Then rebuild the app.', style: TextStyle(color: Colors.greenAccent)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('I\'ll set it up later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Material(
      color: const Color(0xFF0F0F1A),
      child: Stack(
        children: [
          Positioned.fill(
            bottom: 56 + bottomInset,
            child: IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(height: 2, color: const Color(0xFF6C63FF)),
                Container(
                  height: 56,
                  color: const Color(0xFF0A0A14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _navItem(Icons.home, 'Home', 0),
                      _navItem(Icons.dynamic_feed, 'Feed', 1),
                      _navItem(Icons.add_circle, 'Create', 2),
                      _navItem(Icons.sports_esports, 'Play', 3),
                      _navItem(Icons.store, 'Shop', 4),
                      _navItem(Icons.settings, 'Settings', 5),
                    ],
                  ),
                ),
                SizedBox(height: bottomInset),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final selected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: selected ? const Color(0xFF6C63FF) : Colors.white54),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 9, fontWeight: selected ? FontWeight.bold : FontWeight.normal, color: selected ? const Color(0xFF6C63FF) : Colors.white54)),
          ],
        ),
      ),
    );
  }
}
