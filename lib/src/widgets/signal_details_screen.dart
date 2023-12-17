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
  final TextEditingController _newCommentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    _signalStream ??= FirebaseFirestore.instance.collection('signals').doc(widget.signalId).snapshots();
    Map<String, dynamic> signalData;

    return StreamBuilder(stream: _signalStream, builder: (BuildContext context, AsyncSnapshot<DocumentSnapshot> snapshot) {
      if (snapshot.hasError) {
        //TODO
        return const Text('Something went wrong');
      } else if (snapshot.connectionState == ConnectionState.waiting) {
        //TODO
        return const CircularProgressIndicator();
      } else {
        signalData = snapshot.data!.data() as Map<String, dynamic>;
        if (reporterName.isEmpty) {
          DocumentReference reporterRef = signalData['reporter'];
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
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      controller: _scrollController,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: <Widget>[
                          const Icon(Icons.adb),
                          // Image.asset('assets/logo.png'),
                          Text(signalData['title'], style: const TextStyle(fontSize: 30), textAlign: TextAlign.center,),
                          Text(signalData['description'], style: const TextStyle(fontSize: 20), textAlign: TextAlign.center,),
                          Text("Signal type: ${_getSignalType(signalData["type"])}"),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(DateFormat.yMd().add_jm().format(signalData['createdAt'].toDate())),
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
                                icon: const Icon(Icons.directions),
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
                                label: Text(signalData['contactPhone']),
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
                            itemHeight: 64,
                            isExpanded: true,
                            value: signalData['status'],
                              items: [
                                DropdownMenuItem(
                                  value: 0,
                                  child: Row(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Image.asset('assets/icons/pin_red.png'),
                                      ),
                                      SizedBox.fromSize(size: const Size(8, 8)),
                                      const Text('Help needed'),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 1,
                                  child: Row(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Image.asset('assets/icons/pin_orange.png'),
                                      ),
                                      SizedBox.fromSize(size: const Size(8, 8)),
                                      const Text('Somebody on the way'),
                                    ],
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 2,
                                  child: Row(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Image.asset('assets/icons/pin_green.png'),
                                      ),
                                      SizedBox.fromSize(size: const Size(8, 8)),
                                      const Text('Solved'),
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
                                stream: FirebaseFirestore.instance.collection('signals').doc(widget.signalId).collection('comments')
                                  .orderBy('createdAt').snapshots(),
                                builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
                                  if (snapshot.hasError) {
                                    return Text(snapshot.error!.toString(), style: const TextStyle(color: Colors.red),);
                                  } else if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const CircularProgressIndicator();
                                  } else {
                                    var comments = snapshot.data!.docs;

                                    return ListView.builder(
                                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 80),
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
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
                    //add an element fixed at the bottom of the screen for entering new comments
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.grey,
                            width: 1,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.grey,
                              blurRadius: 5.0,
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _newCommentController,
                                  textCapitalization: TextCapitalization.sentences,
                                  decoration: const InputDecoration(
                                    hintText: 'Enter your comment',
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.send),
                                onPressed: _addComment
                              ),
                            ],
                          ),
                        ),
                      ),
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

  Future<void> _addComment() async {
    await FirebaseFirestore.instance.collection('signals').doc(widget.signalId).collection('comments').add({
      'text': _newCommentController.text,
      'createdAt': DateTime.now(),
      //TODO: update author field
      'author': FirebaseFirestore.instance.collection('users').doc('milen-marinov'),
    });
    _newCommentController.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
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