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
              if (leftBtnMessage != null)
                TextButton(
                  child: Text(
                    leftBtnMessage,
                    style: const TextStyle(color: Colors.orange),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                ),
              if (leftBtnMessage != null)
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