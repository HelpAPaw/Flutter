import 'package:flutter/material.dart';

Future dialogWithMessageAndCustomButton(
        BuildContext ctx, String title, String message, String rightBtnMessage,
        {required String leftBtnMessage}) =>
    showDialog(
      barrierDismissible: false,
      context: ctx,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              TextButton(
                child: Text(
                  leftBtnMessage,
                  style: const TextStyle(color: Colors.orange),
                ),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              ),
              const SizedBox(
                width: 50,
              ),
              TextButton(
                child: Text(
                  rightBtnMessage,
                  style: const TextStyle(color: Colors.orange),
                ),
                onPressed: () {
                  Navigator.of(context).pop(true);
                },
              )
            ],
          )
        ],
      ),
    );

Future dialogWithContentYesNo(
        {required BuildContext ctx, required String content}) =>
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        content: Text(content),
        actions: <Widget>[
          TextButton(
            style: ButtonStyle(
                backgroundColor:
                    MaterialStateProperty.all<Color>(Colors.orange)),
            child: const Text(
              'Yes',
            ),
            onPressed: () async {
              Navigator.of(context).pop(true);
            },
          ),
          TextButton(
            style: ButtonStyle(
                backgroundColor:
                    MaterialStateProperty.all<Color>(Colors.orange)),
            child: const Text('No'),
            onPressed: () {
              Navigator.of(context).pop(false);
            },
          ),
        ],
      ),
    );
