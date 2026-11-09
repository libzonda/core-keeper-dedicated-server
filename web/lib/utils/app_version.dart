import 'package:flutter/foundation.dart';

const String defaultAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'v0.1.1');

class AppVersion {
  static final ValueNotifier<String> notifier = ValueNotifier<String>(defaultAppVersion);

  static String get current => notifier.value;

  static void update(String newVersion) {
    if (newVersion.isNotEmpty && notifier.value != newVersion) {
      notifier.value = newVersion;
    }
  }
}

