import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/model/home_route_model.dart';

class HomeRouteDrawer extends StatefulWidget {
  const HomeRouteDrawer({super.key});

  // Home Route Navigation Drawer State
  @override
  State<HomeRouteDrawer> createState() => _HomeRouteDrawerState();
}

class _HomeRouteDrawerState extends State<HomeRouteDrawer> {
  int _homeRouteTile = 0;

  // Home Route Navigation Drawer Widgets
  @override
  Widget build(BuildContext context) {
    return HomeRouteModel(
      homeRouteTileAspect: _homeRouteTile,
      child: Drawer(
        elevation: 6,
        semanticLabel: 'Navigation Drawer',
        child: ListView(
          children: <Widget>[
            DrawerHeader(
              child: Image.asset('lib/assets/icon/pet/3d_paw_64.png'),
            ),
            ListTile(
              enableFeedback: true,
              leading: Image.asset('lib/assets/icon/log_in.png'),
              onTap: () => {
                context.go('/sign_in'),
                setState(() {
                  _homeRouteTile = 0;
                }),
              },
              selected: _homeRouteTile == 0,
              title: const Text(
                'Sign In',
                softWrap: true,
              ),
            ),
            ListTile(
              enableFeedback: true,
              leading: Image.asset('lib/assets/icon/people_paw.png'),
              onTap: () => {
                context.go('/in_dev'),
                setState(() {
                  _homeRouteTile = 1;
                }),
              },
              selected: _homeRouteTile == 1,
              title: const Text(
                'Profile',
                softWrap: true,
              ),
            ),
            ListTile(
              enableFeedback: true,
              leading: Image.asset('lib/assets/icon/webdev.png'),
              onTap: () => {
                context.go('/paw_browser'),
                setState(() {
                  _homeRouteTile = 2;
                }),
              },
              selected: _homeRouteTile == 2,
              title: const Text(
                'Our Site',
                softWrap: true,
              ),
            ),
            ListTile(
              enableFeedback: true,
              leading: Image.asset('lib/assets/icon/settings.png'),
              onTap: () => {
                context.go('/in_dev'),
                setState(() {
                  _homeRouteTile = 3;
                }),
              },
              selected: _homeRouteTile == 3,
              title: const Text(
                'Settings',
                softWrap: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
