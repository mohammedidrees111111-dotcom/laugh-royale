import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class L {
  final Locale locale;

  L(this.locale);

  static L of(BuildContext context) {
    final l = Localizations.of<L>(context, L);
    return l ?? L(const Locale('en'));
  }

  static const LocalizationsDelegate<L> delegate = _LDelegate();

  String get appTitle => _localized('Laugh Royale', '\u0644\u0648\u0641 \u0631\u0648\u064a\u0644');
  String get welcome => _localized('Welcome!', '!\u0623\u0647\u0644\u0627\u064b \u0648\u0633\u0647\u0644\u0627\u064b');
  String get signIn => _localized('Sign In', '\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644');
  String get signUp => _localized('Sign Up', '\u0625\u0646\u0634\u0627\u0621 \u062d\u0633\u0627\u0628');
  String get guestMode => _localized('Continue as Guest', '\u0627\u0644\u062f\u062e\u0648\u0644 \u0643\u0636\u064a\u0641');
  String get email => _localized('Email', '\u0627\u0644\u0628\u0631\u064a\u062f \u0627\u0644\u0625\u0644\u0643\u062a\u0631\u0648\u0646\u064a');
  String get password => _localized('Password', '\u0643\u0644\u0645\u0629 \u0627\u0644\u0645\u0631\u0648\u0631');
  String get name => _localized('Name', '\u0627\u0644\u0627\u0633\u0645');
  String get selectCountry => _localized('Select Your Country', '\u0627\u062e\u062a\u0631 \u062f\u0648\u0644\u062a\u0643');
  String get home => _localized('Home', '\u0627\u0644\u0631\u0626\u064a\u0633\u064a\u0629');
  String get feed => _localized('Feed', '\u0627\u0644\u0645\u0646\u0634\u0648\u0631\u0627\u062a');
  String get create => _localized('Create', '\u0625\u0646\u0634\u0627\u0621');
  String get settings => _localized('Settings', '\u0627\u0644\u0625\u0639\u062f\u0627\u062f\u0627\u062a');
  String get lobby => _localized('Lobby', '\u0627\u0644\u0644\u0648\u0628\u064a');
  String get shop => _localized('Shop', '\u0627\u0644\u0645\u062a\u062c\u0631');
  String get playRandom => _localized('Random Match', '\u0645\u0628\u0627\u0631\u0627\u0629 \u0639\u0634\u0648\u0627\u0626\u064a\u0629');
  String get privateRoom => _localized('Private Room', '\u063a\u0631\u0641\u0629 \u062e\u0627\u0635\u0629');
  String get createRoom => _localized('Create Room', '\u0625\u0646\u0634\u0627\u0621 \u063a\u0631\u0641\u0629');
  String get joinRoom => _localized('Join Room', '\u0627\u0644\u0627\u0646\u0636\u0645\u0627\u0645 \u0644\u063a\u0631\u0641\u0629');
  String get roomCode => _localized('Room Code', '\u0631\u0645\u0632 \u0627\u0644\u063a\u0631\u0641\u0629');
  String get enterCode => _localized('Enter Room Code', '\u0623\u062f\u062e\u0644 \u0631\u0645\u0632 \u0627\u0644\u063a\u0631\u0641\u0629');
  String get searching => _localized('Searching for opponent...', '...\u062c\u0627\u0631\u064a \u0627\u0644\u0628\u062d\u062b \u0639\u0646 \u0645\u0646\u0627\u0641\u0633');
  String get opponentFound => _localized('Opponent Found!', '!\u062a\u0645 \u0625\u064a\u062c\u0627\u062f \u0645\u0646\u0627\u0641\u0633');
  String get ready => _localized('Ready?', '?\u0645\u0633\u062a\u0639\u062f');
  String get startGame => _localized('Start Game', '\u0627\u0628\u062f\u0623 \u0627\u0644\u0644\u0639\u0628\u0629');
  String get lookAtCamera => _localized('Look at the camera', '\u0627\u0646\u0638\u0631 \u0625\u0644\u0649 \u0627\u0644\u0643\u0627\u0645\u064a\u0631\u0627');
  String get dontLaugh => _localized('DON\'T LAUGH!', '!\u0644\u0627 \u062a\u0636\u062d\u0643');
  String get youLaughed => _localized('YOU LAUGHED!', '!\u0623\u0646\u062a \u0636\u062d\u0643\u062a');
  String get youLost => _localized('You Lost!', '!\u0644\u0642\u062f \u062e\u0633\u0631\u062a');
  String get youWin => _localized('You Win!', '!\u0644\u0642\u062f \u0641\u0632\u062a');
  String get playAgain => _localized('Play Again', '\u0627\u0644\u0639\u0628 \u0645\u062c\u062f\u062f\u0627\u064b');
  String get backToLobby => _localized('Back to Lobby', '\u0627\u0644\u0639\u0648\u062f\u0629 \u0644\u0644\u0648\u0628\u064a');
  String get smileDetected => _localized('Smile Detected!', '!\u062a\u0645 \u0627\u0643\u062a\u0634\u0627\u0641 \u0627\u0628\u062a\u0633\u0627\u0645\u0629');
  String get loading => _localized('Loading...', '...\u062c\u0627\u0631\u064a \u0627\u0644\u062a\u062d\u0645\u064a\u0644');
  String get retry => _localized('Retry', '\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u0645\u062d\u0627\u0648\u0644\u0629');
  String get cancel => _localized('Cancel', '\u0625\u0644\u063a\u0627\u0621');
  String get submit => _localized('Submit', '\u0625\u0631\u0633\u0627\u0644');
  String get or => _localized('or', '\u0623\u0648');
  String get signOut => _localized('Sign Out', '\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062e\u0631\u0648\u062c');
  String get version => _localized('Version', '\u0627\u0644\u0625\u0635\u062f\u0627\u0631');
  String get termsOfService => _localized('Terms of Service', '\u0634\u0631\u0648\u0637 \u0627\u0644\u062e\u062f\u0645\u0629');
  String get privacyPolicy => _localized('Privacy Policy', '\u0633\u064a\u0627\u0633\u0629 \u0627\u0644\u062e\u0635\u0648\u0635\u064a\u0629');
  String get about => _localized('About', '\u062d\u0648\u0644');
  String get profile => _localized('Profile', '\u0627\u0644\u0645\u0644\u0641 \u0627\u0644\u0634\u062e\u0635\u064a');
  String get notifications => _localized('Notifications', '\u0627\u0644\u0625\u0634\u0639\u0627\u0631\u0627\u062a');
  String get darkMode => _localized('Dark Mode', '\u0627\u0644\u0648\u0636\u0639 \u0627\u0644\u062f\u0627\u0643\u0646');
  String get payNow => _localized('Pay Now', '\u0627\u062f\u0641\u0639 \u0627\u0644\u0622\u0646');

  String _localized(String en, String ar) {
    if (locale.languageCode == 'ar') return ar;
    return en;
  }
}

class _LDelegate extends LocalizationsDelegate<L> {
  const _LDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'ar'].contains(locale.languageCode);

  @override
  Future<L> load(Locale locale) async => L(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<L> old) => true;
}
