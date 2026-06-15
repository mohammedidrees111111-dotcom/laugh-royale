import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'error_handler.dart';

class AuthService {
  AuthService._();

  static final _uuid = const Uuid();
  static String? _currentUserId;
  static String? _currentEmail;
  static String? _currentName;
  static String? _currentCountry;
  static bool _isGuest = true;

  static final Map<String, _UserRecord> _users = {};

  static String? get currentUserId => _currentUserId;
  static String? get currentEmail => _currentEmail;
  static String get displayName => _currentName ?? 'Guest';
  static String? get country => _currentCountry;
  static bool get isSignedIn => _currentUserId != null;
  static bool get isGuest => _isGuest;

  static Future<bool> signInWithEmail(String email, String password) async {
    try {
      if (_users.containsKey(email)) {
        final user = _users[email]!;
        if (user.password == password) {
          _currentUserId = user.id;
          _currentEmail = email;
          _currentName = user.name;
          _currentCountry = user.country;
          _isGuest = false;
          await _saveSession();
          return true;
        }
        return false;
      }
      final prefs = await SharedPreferences.getInstance();
      final storedId = prefs.getString('user_${email}_id');
      if (storedId != null) {
        final storedPass = prefs.getString('user_${email}_pass') ?? '';
        if (storedPass == password) {
          _currentUserId = storedId;
          _currentEmail = email;
          _currentName = prefs.getString('user_${email}_name') ?? email.split('@').first;
          _currentCountry = prefs.getString('country');
          _isGuest = false;
          _users[email] = _UserRecord(id: storedId, email: email, password: password, name: _currentName!, country: _currentCountry);
          await _saveSession();
          return true;
        }
      }
      return false;
    } catch (e, s) {
      ErrorHandler.logError('Sign in', e, s);
      return false;
    }
  }

  static Future<bool> signUpWithEmail(String email, String password, String name) async {
    try {
      if (_users.containsKey(email)) return false;
      final id = _uuid.v4();
      _users[email] = _UserRecord(id: id, email: email, password: password, name: name, country: _currentCountry);
      _currentUserId = id;
      _currentEmail = email;
      _currentName = name;
      _isGuest = false;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_${email}_id', id);
      await prefs.setString('user_${email}_pass', password);
      await prefs.setString('user_${email}_name', name);
      await _saveSession();
      return true;
    } catch (e, s) {
      ErrorHandler.logError('Sign up', e, s);
      return false;
    }
  }

  static Future<void> signInAsGuest() async {
    _currentUserId = 'guest_${_uuid.v4().substring(0, 8)}';
    _currentEmail = null;
    _currentName = 'Guest';
    _isGuest = true;
    await _saveSession();
  }

  static Future<void> setCountry(String code, String countryName) async {
    _currentCountry = countryName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('country', countryName);
    await prefs.setString('countryCode', code);
  }

  static Future<String?> getSavedCountry() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('country');
  }

  static Future<void> signOut() async {
    _currentUserId = null;
    _currentEmail = null;
    _currentName = null;
    _isGuest = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    await prefs.remove('email');
    await prefs.remove('name');
    await prefs.remove('isGuest');
  }

  static Future<bool> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString('userId');
      if (id != null) {
        _currentUserId = id;
        _currentEmail = prefs.getString('email');
        _currentName = prefs.getString('name') ?? 'Guest';
        _currentCountry = prefs.getString('country');
        _isGuest = prefs.getBool('isGuest') ?? true;
        return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<void> _saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentUserId != null) {
      await prefs.setString('userId', _currentUserId!);
      await prefs.setString('name', _currentName ?? 'Guest');
      await prefs.setBool('isGuest', _isGuest);
      if (_currentEmail != null) await prefs.setString('email', _currentEmail!);
    }
  }
}

class _UserRecord {
  final String id;
  final String email;
  final String password;
  final String name;
  final String? country;

  _UserRecord({required this.id, required this.email, required this.password, required this.name, this.country});
}
