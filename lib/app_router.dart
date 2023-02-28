import 'package:flutter/material.dart';
import 'app_router_routes_names.dart';
import 'main.dart';


// app router that was giving by flutter that will make
// dependency injection, sending arguments, and making global changes in the future much easier
// to add new screen just add the case name in app_router_routes_names.dart and make the case return the screen

// using example:  Navigator.of(context).pushNamed(homePage);

class AppRouter {

  Route? onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute(builder: (context){

      switch (settings.name) {

        case homePage:
          return const MyHomePage(title: 'Help a paw',);

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
    });
  }
}