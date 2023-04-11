import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:help_a_paw/src/pages/home.dart';
import 'package:help_a_paw/src/pages/login.dart';
import '../controllers/user_controller.dart';
import '../services/constants.dart' as global;

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    Future.delayed(const Duration(seconds: 2), () async {
      bool isLoggedIn = await UserController().isUserLoggedIn;
      Navigator.of(context).push(
        MaterialPageRoute(
            builder: (context) => isLoggedIn ? const HomePage(title: 'Help a Paw') : const LoginPage(),
            settings: RouteSettings(name: isLoggedIn ? global.homeRoute : global.loginRoute)),
      );
       // Remove all the screens from the stack until the first screen (SplashScreen)
      Navigator.of(context).popUntil((route) => route.isFirst);
    });

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const <Widget>[
            Image(
              image: AssetImage("assets/images/logo.jpg"),
              height: 100,
            ),
            SizedBox(
              height: 12,
            ),
            Text(
              "Help a Paw",
              style: TextStyle(
                  fontSize: 20,
                  color: Colors.orange,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
