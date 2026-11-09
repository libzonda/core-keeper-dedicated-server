import 'package:flutter/foundation.dart';

class RestartStateController extends ChangeNotifier {
  static final instance = RestartStateController._();
  RestartStateController._();

  bool _isRestartRequired = false;
  bool get isRestartRequired => _isRestartRequired;

  bool _isRestarting = false;
  bool get isRestarting => _isRestarting;

  void markRestartRequired() {
    if (!_isRestartRequired) {
      _isRestartRequired = true;
      notifyListeners();
    }
  }

  void syncStatus({required bool restartRequired, required bool isRunning}) {
    if (!isRunning) {
      if (_isRestartRequired) {
        _isRestartRequired = false;
        notifyListeners();
      }
      return;
    }

    if (restartRequired && !_isRestartRequired) {
      _isRestartRequired = true;
      notifyListeners();
    }
  }

  void setRestarting(bool value) {
    if (_isRestarting != value) {
      _isRestarting = value;
      notifyListeners();
    }
  }

  void dismiss() {
    if (_isRestartRequired) {
      _isRestartRequired = false;
      notifyListeners();
    }
  }
}

