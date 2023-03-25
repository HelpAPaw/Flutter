import 'package:flutter/material.dart';
import 'package:help_a_paw/src/pages/home.dart';
import 'package:help_a_paw/src/pages/login.dart';
import 'package:help_a_paw/src/pages/register.dart';
import 'package:help_a_paw/src/pages/splash.dart';
import 'package:help_a_paw/src/styles/theme.dart';
import './src/services/constants.dart' as global;

class App extends StatefulWidget {
  const App({super.key});

  @override
  AppState createState() => AppState();
}

class AppState extends State<App> {

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(context) {
    return MaterialApp(
      home: const SplashScreen(),
      theme: appTheme(context),
      debugShowCheckedModeBanner: false,
      routes: {
        global.homeRoute: (context) => const HomePage(title: 'Help a Paw'),
        global.loginRoute: (context) => const LoginPage(),
        global.registerRoute: (context) => const RegisterPage(),
      },
    );
  }
}
