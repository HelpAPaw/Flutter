// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import '../services/constants.dart' as global;

class UserController {
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  /* store user details in local*/
  void setUserPrefs(user) async {
    final SharedPreferences prefs = await _prefs;
    prefs.setBool(global.loggedIn, true);
    prefs.setString(global.displayName, user.displayName ?? '');
  }
}
