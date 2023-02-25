import 'package:shared_preferences/shared_preferences.dart';
import '../services/constants.dart' as global;

class UserController {
  late SharedPreferences _prefs;

  Future<bool> get isUserLoggedIn async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isLoggedIn = prefs.getBool(global.loggedIn) ?? false;
    return isLoggedIn ? true : false;
  }

  void setUserPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _prefs.setBool(global.loggedIn, true);
  }
}
