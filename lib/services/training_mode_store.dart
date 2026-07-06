import 'package:shared_preferences/shared_preferences.dart';

class TrainingModeStore {
  const TrainingModeStore();

  static const _enabledKey = 'yosy_group.cashier.training_mode_enabled';

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }
}
