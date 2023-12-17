import 'package:adaptive_components/adaptive_components.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class SignalDetailsScreen extends StatefulWidget {
  const SignalDetailsScreen({super.key, required this.signalId});

  final String signalId;

  @override
  State<StatefulWidget> createState() => _SignalDetailsState();
}

class _SignalDetailsState extends State<SignalDetailsScreen> {
  Stream<DocumentSnapshot>? _signalStream;
  String reporterName = '';

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
        return const CircularProgressIndicator();
      } else {
        data = snapshot.data!.data() as Map<String, dynamic>;
        if (reporterName.isEmpty) {
          DocumentReference reporterRef = data['reporter'];
          reporterRef.get().then((DocumentSnapshot reporterSnapshot) {
            if (reporterSnapshot.exists) {
              Map<String, dynamic> reporterData = reporterSnapshot.data() as Map<String, dynamic>;
              setState(() {
                reporterName = reporterData['name'];
              });
            }
          });
        }
      }

      return Scaffold(
        body: AdaptiveContainer(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Signal Details'),
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: () => {
                    context.go('/in_dev'),
                  },
                ),
              ],
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  //add spacing between children

                  mainAxisAlignment: MainAxisAlignment.start,
                  children: <Widget>[
                    const Icon(Icons.adb),
                    // Image.asset('assets/logo.png'),
                    Text(data['title'], style: const TextStyle(fontSize: 30), textAlign: TextAlign.center,),
                    Text(data['description'], style: const TextStyle(fontSize: 20), textAlign: TextAlign.center,),
                    Text("Signal type: ${_getSignalType(data["type"])}"),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(DateFormat.yMd().add_jm().format(data['createdAt'].toDate())),
                        //show user name from reporter field which is a reference to the users collection
                        Text(reporterName)
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: () => {
                            context.go('/in_dev'),
                          },
                          icon: const Icon(Icons.navigation),
                          label: const Text('Navigate Me'),
                          //TODO: extract button style
                          style: ButtonStyle(
                            foregroundColor: MaterialStateProperty.all<Color>(Colors.white),
                            backgroundColor: MaterialStateProperty.all<Color>(Colors.orange),
                          )
                        ),
                        TextButton.icon(
                          onPressed: () => {
                            context.go('/in_dev'),
                          },
                          icon: const Icon(Icons.phone),
                          label: Text(data['contactPhone']),
                          style: ButtonStyle(
                            foregroundColor: MaterialStateProperty.all<Color>(Colors.white),
                            backgroundColor: MaterialStateProperty.all<Color>(Colors.orange),
                          )
                        ),
                      ],
                    ),
                    //add section delimiter + label
                    const Text(' Status'),
                    DropdownButton(
                      // expand to fill width
                      isExpanded: true,
                      value: data['status'],
                        items: const [
                          DropdownMenuItem(
                            value: 0,
                            child: Row(
                              children: [
                                Icon(Icons.warning),
                                Text('Help needed'),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 1,
                            child: Row(
                              children: [
                                Icon(Icons.directions_run),
                                Text('Somebody on the way'),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 2,
                            child: Row(
                              children: [
                                Icon(Icons.done),
                                Text('Solved'),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (value) => {
                          //TODO: update signal status
                        },
                    ),
                    //Get nested Firebase collection called 'comments'
                    Column(
                      children: [
                        const Text('Comments'),
                        StreamBuilder(
                          stream: FirebaseFirestore.instance.collection('signals').doc(widget.signalId).collection('comments').snapshots(),
                          builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
                            if (snapshot.hasError) {
                              return Text(snapshot.error!.toString(), style: const TextStyle(color: Colors.red),);
                            } else if (snapshot.connectionState == ConnectionState.waiting) {
                              return const CircularProgressIndicator();
                            } else {
                              var comments = snapshot.data!.docs;
                              return ListView.builder(
                                shrinkWrap: true,
                                itemCount: comments.length,
                                itemBuilder: (BuildContext context, int index) {
                                  Map<String, dynamic> commentData = comments[index].data()! as Map<String, dynamic>;
                                  return ListTile(
                                    title: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.grey,
                                          width: 1,
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Text(commentData['text']),
                                      )
                                    ),
                                    subtitle: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(DateFormat.yMd().add_jm().format(commentData['createdAt'].toDate())),
                                        //Retrieve user name from author field
                                        FutureBuilder<DocumentSnapshot>(
                                          future: commentData['author'].get(),
                                          builder: (BuildContext context, AsyncSnapshot<DocumentSnapshot> snapshot) {
                                            if (snapshot.hasError) {
                                              return const Text('Unknown');
                                            } else if (snapshot.connectionState == ConnectionState.waiting) {
                                              return const Text('');
                                            } else {
                                              Map<String, dynamic>? authorData = snapshot.data?.data() as Map<String, dynamic>?;
                                              return Text(authorData?['name'] ?? 'Unknown');
                                            }
                                          }
                                        ),
                                      ],
                                    )
                                  );
                                },
                              );
                            }
                          }
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
        ),
      );
    });
  }

  //TODO: extract to separate file
  _getSignalType(int type) {
    switch(type) {
      case 0: return 'Emergency';
      case 1: return 'Lost or Found';
      case 2: return 'Blood donation';
      case 3: return 'Homeless';
      case 4: return 'Unneutered animals';
      case 5: return 'Wild animals';
      default: return 'Other';
    }
  }
}