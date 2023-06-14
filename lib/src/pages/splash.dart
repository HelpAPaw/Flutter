import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:help_a_paw/utility/app_router_routes.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    Future.delayed(const Duration(seconds: 2), () async {
      // bool isLoggedIn = await UserValidation().checkUserLogin();

      Navigator.of(context).pushNamed(AppRoutes.homeScreen);
    });

    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
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
