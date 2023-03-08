import 'package:flutter/material.dart';

class MyDrawer extends StatefulWidget {
  final String userName;
  final String userImage;

  const MyDrawer({super.key, required this.userName, required this.userImage});

  @override
  MyDrawerState createState() => MyDrawerState();
}

class MyDrawerState extends State<MyDrawer> {
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
    var widthSize = MediaQuery.of(context).size.width;
    var heightSize = MediaQuery.of(context).size.height;
    return SafeArea(
      child: Drawer(
        backgroundColor: Colors.orange,
        child: Column(
          children: [
            Container(
              color: Colors.white,
              height: heightSize * 0.25,
              width: widthSize * 1,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Container(
                    alignment: Alignment.center,
                    width: widthSize * 0.8,
                    height: heightSize * 0.17,
                    child: Image.asset(widget.userImage),
                  ),
                  Text(
                    widget.userName,
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
