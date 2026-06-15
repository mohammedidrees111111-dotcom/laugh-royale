import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/error_handler.dart';

void main() {
  ErrorHandler.initialize();
  WidgetsFlutterBinding.ensureInitialized();

  runZonedGuarded(
    () {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]).then((_) {});

      runApp(const LaughRoyaleApp());
    },
    (error, stack) {
      ErrorHandler.logZoneError(error, stack);
    },
  );
}
