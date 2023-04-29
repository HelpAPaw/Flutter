import 'package:flutter/material.dart';

import '../presentation/home_screen/home_screen.dart';
import 'app_router_routes.dart';


class AppRouter {


  Route? onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute(builder: (context) {


      return Builder(
        builder: (BuildContext context) {
          switch (settings.name) {

            case AppRoutes.homeScreen:
              return const HomeScreen(title: 'Help',);


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