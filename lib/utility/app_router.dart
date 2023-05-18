import 'package:flutter/material.dart';
import 'package:help_a_paw/src/pages/login.dart';

import '../presentation/home_screen/home_screen.dart';
import '../src/pages/register.dart';
import 'app_router_routes.dart';


// example to use the app router :  Navigator.of(context).pushNamed(AppRoutes.homeScreen);
class AppRouter {


  Route? onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute(builder: (context) {

      // add new case with the name of your route and the screen you will navigate to

      return Builder(
        builder: (BuildContext context) {
          switch (settings.name) {

            case AppRoutes.homeScreen:
              return const HomeScreen(title: 'Help a Paw',);


            case AppRoutes.registerRoute:
              return const RegisterPage();

              case AppRoutes.loginRoute:
              return const LoginPage();


              // in case the named route provided in not available
            default:
              return const Scaffold(
                body: Center(
                  child: Text(
                    'Check Named Route',
                    style: TextStyle(fontSize: 30, color: Colors.black),
                  ),
                ),
              );
          }
        },
      );
    });
  }
}