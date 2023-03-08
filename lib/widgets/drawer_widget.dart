import 'package:flutter/material.dart';

class MyDrawer extends StatelessWidget {
  final String userName;
  final String userImage;

  MyDrawer({Key? key, required this.userName, required this.userImage})
      : super(key: key);

  final List<String> items = [
    'Profile',
    'My Signals',
    'My Notifications',
    'FAQS',
    'Settings',
    'Feedback',
    'Privacy Policy',
    'About',
    'Share'
  ];

  @override
  Widget build(BuildContext context) {
    final widthSize = MediaQuery.of(context).size.width;
    final heightSize = MediaQuery.of(context).size.height;
    return SafeArea(
      child: Drawer(
        backgroundColor: Colors.orange,
        child: Column(
          children: [
            Container(
              color: Colors.white,
              height: heightSize * 0.25,
              width: widthSize,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: widthSize * 0.8,
                    height: heightSize * 0.17,
                    child: Image.asset(userImage),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    userName,
                    style: const TextStyle(fontSize: 18, color: Colors.orange),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (BuildContext context, int index) {
                  return ListTile(
                    title: Text(
                      items[index],
                      style: const TextStyle(fontSize: 18, color: Colors.white),
                    ),
                    onTap: () {
                      // Handle item tap here
                    },
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}
