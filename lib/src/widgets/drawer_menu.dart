import 'package:flutter/material.dart';
import 'package:help_a_paw/src/pages/login.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../showdialogs/message.dart';
import '../utils/firebase_auth.dart';
import '../utils/user_validation.dart';

class DrawerMenu extends StatefulWidget {
  const DrawerMenu({super.key});

  @override
  DrawerMenuState createState() => DrawerMenuState();
}

class DrawerMenuState extends State<DrawerMenu> {
  TextStyle listTitleStyle = const TextStyle(
    color: Colors.white,
  );
  String loginOrLogout = 'Log in';
  UserValidation userValidation = UserValidation();
  FirebaseAuthentication auth = FirebaseAuthentication();

  //send feedback
  final String emailTo = "help.a.paw@outlook.com";

  void sendEmail(String email) => launch("mailto:$email");

  @override
  void initState() {
    super.initState();
    checkUserLogin();
  }

  @override
  void dispose() {
    super.dispose();
  }

  checkUserLogin() async {
    bool login = await userValidation.checkUserLogin();
    setState(() {
      loginOrLogout = login ? 'Log out' : 'Log in';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        color: Colors.orange,
        child: ListView(
          children: <Widget>[
            DrawerHeader(
              padding: const EdgeInsets.all(0),
              child: Container(
                color: Colors.white,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const <Widget>[
                      Image(
                        image: AssetImage(
                          "assets/images/logo.jpg",
                        ),
                        height: 80,
                      ),
                      SizedBox(
                        height: 12,
                      ),
                      Text(
                        "Help a Paw",
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 20,
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
            ListTile(
              title: Text(
                loginOrLogout,
                style: listTitleStyle,
              ),
              onTap: () async {
                if (loginOrLogout == 'Log out') {
                  bool response = await dialogWithContentYesNo(
                      ctx: context, content: "Do you really want to log out?");
                  response = response;
                  if (response) {
                    auth.logOut().then((value) async {
                      SharedPreferences prefs =
                          await SharedPreferences.getInstance();
                      prefs.setBool('isLoggedIn', false);
                      // ignore: use_build_context_synchronously
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (BuildContext context) =>
                                  const LoginPage()));
                    });
                  }
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (BuildContext context) => const LoginPage(),
                    ),
                  );
                }
              },
            ),
            ListTile(
              title: Text(
                "FAQs",
                style: listTitleStyle,
              ),
              onTap: () {},
            ),
            ListTile(
              title: Text(
                "Settings",
                style: listTitleStyle,
              ),
              onTap: () {},
            ),
            ListTile(
              title: Text(
                "Feedback",
                style: listTitleStyle,
              ),
              onTap: () {
                sendEmail(emailTo);
              },
            ),
            ListTile(
              title: Text(
                "Privacy Policy",
                style: listTitleStyle,
              ),
              onTap: () {},
            ),
            ListTile(
              title: Text(
                "About",
                style: listTitleStyle,
              ),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}
