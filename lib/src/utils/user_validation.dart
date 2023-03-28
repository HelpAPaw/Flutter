import 'package:shared_preferences/shared_preferences.dart';
import '../services/constants.dart' as global;

class UserValidation {
  /* Validation for name field */
  String? validateName(value) {
    if (value.isEmpty) return 'Name cannot be blank';
    if (value.length < 3) {
      return 'Name must be more than 2 character';
    } else {
      return null;
    }
  }

  /* Validation for email field */
  String? validateEmail(value) {
    if (value.isEmpty) return 'Email cannot be blank';
    RegExp regex = RegExp(
        r'^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$');
    if (!regex.hasMatch(value!)) {
      return 'Enter Valid Email';
    } else {
      return null;
    }
  }

  /* Validation for password field */
  String? validatePassword(value) {
    if (value.isEmpty) return 'Password cannot be blank';
    if (value.length < 6) {
      return 'Password must be more than 6 character';
    } else {
      return null;
    }
  }

  /* Check user loggedin or not */
  checkUserLogin() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    dynamic isLoggedIn = prefs.getBool(global.loggedIn);
    return isLoggedIn ?? false;
  }
}
