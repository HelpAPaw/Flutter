import 'package:adaptive_components/adaptive_components.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/signal.dart';

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
    Signal signal;

    return StreamBuilder(stream: _signalStream, builder: (BuildContext context, AsyncSnapshot<DocumentSnapshot> snapshot) {
      if (snapshot.hasError) {
        //TODO
        return const Text('Something went wrong');
      } else if (snapshot.connectionState == ConnectionState.waiting) {
        //TODO
        return const CircularProgressIndicator();
      } else {
        final signalData = snapshot.data!.data() as Map<String, dynamic>;
        signal = Signal.fromJson(signalData);
        if (reporterName.isEmpty) {
          signal.reporter.get().then((DocumentSnapshot reporterSnapshot) {
            if (reporterSnapshot.exists) {
              Map<String, dynamic> reporterData = reporterSnapshot.data() as Map<String, dynamic>;
              setState(() {
                reporterName = reporterData['name'];
              });
            }
          });
        }
      }

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            context.go('/home');
          }
        },
        child: Scaffold(
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
                    context.push('/in_dev'),
                  },
                ),
              ],
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SingleChildScrollView(
                      controller: _scrollController,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: <Widget>[
                          if (signal.photoUrl != null && signal.photoUrl!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => _FullScreenPhotoViewer(
                                        photoUrl: signal.photoUrl!,
                                      ),
                                    ),
                                  );
                                },
                                child: Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12.0),
                                      child: Image.network(
                                        signal.photoUrl!,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return SizedBox(
                                            height: 200,
                                            child: Center(
                                              child: CircularProgressIndicator(
                                                value: loadingProgress.expectedTotalBytes != null
                                                    ? loadingProgress.cumulativeBytesLoaded /
                                                        loadingProgress.expectedTotalBytes!
                                                    : null,
                                              ),
                                            ),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            height: 200,
                                            color: Colors.grey[200],
                                            child: const Center(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.broken_image, size: 48, color: Colors.grey),
                                                  SizedBox(height: 8),
                                                  Text('Failed to load image', style: TextStyle(color: Colors.grey)),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: const Icon(
                                          Icons.zoom_in,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            const Icon(Icons.adb),
                          Text(signal.title, style: const TextStyle(fontSize: 30), textAlign: TextAlign.center,),
                          Text(signal.description, style: const TextStyle(fontSize: 20), textAlign: TextAlign.center,),
                          Text("Signal type: ${Signal.getSignalTypeName(signal.signalType)}"),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(DateFormat.yMd().add_jm().format((signal.createdAt as Timestamp).toDate())),
                              //show user name from reporter field which is a reference to the users collection
                              Text(reporterName)
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton.icon(
                                onPressed: () async {
                                  // Open navigation app with signal location
                                  GeoPoint location = signal.location['geopoint'];
                                  Uri url = Uri.parse('geo:${location.latitude},${location.longitude}');
                                  if (await canLaunchUrl(url)) {
                                    launchUrl(url);
                                  } else {
                                    // Show alert to the user
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Cannot navigate to signal location, please try to do so manually.'),
                                        ),
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.directions),
                                label: const Text('Navigate Me'),
                                //TODO: extract button style
                                style: ButtonStyle(
                                  foregroundColor: WidgetStateProperty.all<Color>(Colors.white),
                                  backgroundColor: WidgetStateProperty.all<Color>(Colors.orange),
                                )
                              ),
                              TextButton.icon(
                                onPressed: () async {
                                  Uri phoneUri = Uri(scheme: 'tel', path: signal.contactPhone);
                                  if (await canLaunchUrl(phoneUri)) {
                                    launchUrl(phoneUri);
                                  } else {
                                    // Show an alert to the user
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Cannot call ${signal.contactPhone}, please try to connect manually.'),
                                        ),
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.phone),
                                label: Text(signal.contactPhone),
                                style: ButtonStyle(
                                  foregroundColor: WidgetStateProperty.all<Color>(Colors.white),
                                  backgroundColor: WidgetStateProperty.all<Color>(Colors.orange),
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
                            value: signal.status,
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
                                onPressed: () {
                                  // Check if user is authenticated
                                  if (FirebaseAuth.instance.currentUser == null) {
                                    _showSignInDialog();
                                  } else {
                                    _addComment();
                                  }
                                }
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
        ),
      );
    });
  }

  Future<void> _addComment() async {
    await FirebaseFirestore.instance.collection('signals').doc(widget.signalId).collection('comments').add({
      'text': _newCommentController.text,
      'createdAt': DateTime.now(),
      'author': FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid),
    });
    _newCommentController.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _showSignInDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Sign in required'),
          content: const Text('You need to sign in to comment'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/sign_in');
              },
              child: const Text('Sign In'),
            ),
          ],
        );
      },
    );
  }
}

class _FullScreenPhotoViewer extends StatelessWidget {
  final String photoUrl;

  const _FullScreenPhotoViewer({required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PhotoView(
            imageProvider: NetworkImage(photoUrl),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3,
            backgroundDecoration: const BoxDecoration(
              color: Colors.black,
            ),
            loadingBuilder: (context, event) {
              return Center(
                child: CircularProgressIndicator(
                  value: event == null
                      ? 0
                      : event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1),
                  color: Colors.white,
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, size: 64, color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Failed to load image',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}