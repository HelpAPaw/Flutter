import 'package:adaptive_components/adaptive_components.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class SignalDetailsScreen extends StatefulWidget {
  const SignalDetailsScreen({super.key, required this.signalId});

  final String signalId;

  @override
  State<StatefulWidget> createState() => _SignalDetailsState();
}

class _SignalDetailsState extends State<SignalDetailsScreen> {
  Stream<DocumentSnapshot>? _signalStream;

  @override
  Widget build(BuildContext context) {
    _signalStream ??= FirebaseFirestore.instance.collection('signals').doc(widget.signalId).snapshots();
    Map<String, dynamic> data;

    return StreamBuilder(stream: _signalStream, builder: (BuildContext context, AsyncSnapshot<DocumentSnapshot> snapshot) {
      if (snapshot.hasError) {
        //TODO
        return const Text('Something went wrong');
      } else if (snapshot.connectionState == ConnectionState.waiting) {
        //TODO
        return const Text("Loading");
      } else {
        data = snapshot.data!.data() as Map<String, dynamic>;
      }

      return Scaffold(
        body: AdaptiveContainer(
          child: Text(data['title'])
        ),
      );
    });
  }
}