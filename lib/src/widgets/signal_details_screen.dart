import 'dart:io';

import 'package:adaptive_components/adaptive_components.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/services/share_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
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
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploadingPhoto = false;
  final PageController _photoPageController = PageController();
  int _currentPhotoPage = 0;

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
            context.pop();
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
                  onPressed: () {
                    final GeoPoint? geopoint = signal.location['geopoint'] as GeoPoint?;
                    ShareService.shareSignal(
                      signalId: widget.signalId,
                      signalType: Signal.getSignalTypeName(signal.signalType),
                      description: signal.description,
                      latitude: geopoint?.latitude,
                      longitude: geopoint?.longitude,
                    );
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
                          if (signal.photoUrls.isNotEmpty || _isUserAuthor(signal))
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: 250,
                                  child: PageView.builder(
                                    controller: _photoPageController,
                                    onPageChanged: (index) {
                                      setState(() {
                                        _currentPhotoPage = index;
                                      });
                                    },
                                    itemCount: signal.photoUrls.length +
                                        (_isUserAuthor(signal) && signal.photoUrls.length < 5 ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      // Show "Add Photo" page if this is the last index and user is author
                                      if (index >= signal.photoUrls.length) {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                          child: GestureDetector(
                                            onTap: _isUploadingPhoto ? null : _showImageSourceDialog,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.grey[200],
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: Colors.orange,
                                                  width: 2,
                                                  style: BorderStyle.solid,
                                                ),
                                              ),
                                              child: Center(
                                                child: _isUploadingPhoto
                                                    ? Column(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        children: [
                                                          const CircularProgressIndicator(
                                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                                                          ),
                                                          const SizedBox(height: 16),
                                                          Text(
                                                            'Uploading photo...',
                                                            style: TextStyle(
                                                              color: Colors.grey[600],
                                                              fontSize: 14,
                                                            ),
                                                          ),
                                                        ],
                                                      )
                                                    : Column(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        children: [
                                                          const Icon(
                                                            Icons.add_photo_alternate,
                                                            size: 48,
                                                            color: Colors.orange,
                                                          ),
                                                          const SizedBox(height: 8),
                                                          Text(
                                                            signal.photoUrls.isEmpty ? 'Add Photo' : 'Add Another Photo',
                                                            style: TextStyle(
                                                              color: Colors.grey[600],
                                                              fontSize: 16,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                          const SizedBox(height: 4),
                                                          Text(
                                                            '${signal.photoUrls.length}/5 photos',
                                                            style: TextStyle(
                                                              color: Colors.grey[500],
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }

                                      // Show photo
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                        child: GestureDetector(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => _FullScreenPhotoGallery(
                                                  photoUrls: signal.photoUrls,
                                                  initialIndex: index,
                                                ),
                                              ),
                                            );
                                          },
                                          child: Stack(
                                            children: [
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(12.0),
                                                child: CachedNetworkImage(
                                                  imageUrl: signal.photoUrls[index],
                                                  width: double.infinity,
                                                  fit: BoxFit.cover,
                                                  placeholder: (context, url) => Container(
                                                    color: Colors.grey[200],
                                                    child: const Center(
                                                      child: CircularProgressIndicator(),
                                                    ),
                                                  ),
                                                  errorWidget: (context, url, error) => Container(
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
                                                  ),
                                                ),
                                              ),
                                              if (_isUserAuthor(signal))
                                                Positioned(
                                                  top: 8,
                                                  right: 8,
                                                  child: IconButton(
                                                    icon: const Icon(Icons.delete, color: Colors.white),
                                                    style: IconButton.styleFrom(
                                                      backgroundColor: Colors.red,
                                                    ),
                                                    onPressed: () => _deletePhoto(signal.photoUrls[index]),
                                                  ),
                                                ),
                                              Positioned(
                                                bottom: 8,
                                                right: 8,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black54,
                                                    borderRadius: BorderRadius.circular(20),
                                                  ),
                                                  child: Text(
                                                    '${index + 1}/${signal.photoUrls.length}',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                // Page indicator dots
                                if ((signal.photoUrls.length +
                                        (_isUserAuthor(signal) && signal.photoUrls.length < 5 ? 1 : 0)) >
                                    1)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: List.generate(
                                        signal.photoUrls.length +
                                            (_isUserAuthor(signal) && signal.photoUrls.length < 5 ? 1 : 0),
                                        (index) => Container(
                                          margin: const EdgeInsets.symmetric(horizontal: 4.0),
                                          width: 8.0,
                                          height: 8.0,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: _currentPhotoPage == index
                                                ? Colors.orange
                                                : Colors.grey[400],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                              ],
                            ),
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
                                  // Use geo URI with query parameter - allows user to choose navigation app
                                  GeoPoint location = signal.location['geopoint'];
                                  Uri url = Uri.parse(
                                    'geo:${location.latitude},${location.longitude}?q=${location.latitude},${location.longitude}(${Uri.encodeComponent(signal.title)})'
                                  );
                                  if (await canLaunchUrl(url)) {
                                    launchUrl(url);
                                  } else {
                                    // Fallback to Google Maps web URL if geo: scheme not supported
                                    final fallbackUri = Uri.parse(
                                      'https://www.google.com/maps/dir/?api=1&destination=${location.latitude},${location.longitude}'
                                    );
                                    if (await canLaunchUrl(fallbackUri)) {
                                      await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
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
                              onChanged: (value) {
                                if (value != null) {
                                  _updateSignalStatus(signal.status, value);
                                }
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
                                        final bool isStatusChange = commentData['type'] == 'status_change';

                                        if (isStatusChange) {
                                          // Status change entry
                                          return ListTile(
                                            title: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade50,
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: Colors.orange.shade200,
                                                  width: 1,
                                                ),
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.all(8.0),
                                                child: Row(
                                                  children: [
                                                    Image.asset(
                                                      _getStatusIcon(commentData['newStatus']),
                                                      width: 24,
                                                      height: 24,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: FutureBuilder<DocumentSnapshot>(
                                                        future: commentData['author'].get(),
                                                        builder: (BuildContext context, AsyncSnapshot<DocumentSnapshot> snapshot) {
                                                          String authorName = 'Someone';
                                                          if (snapshot.hasData && snapshot.data?.data() != null) {
                                                            Map<String, dynamic> authorData = snapshot.data!.data() as Map<String, dynamic>;
                                                            authorName = authorData['name'] ?? 'Someone';
                                                          }
                                                          return Text(
                                                            '$authorName changed the status to ${_getStatusName(commentData['newStatus'])}',
                                                            style: const TextStyle(fontStyle: FontStyle.italic),
                                                          );
                                                        },
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            subtitle: Text(
                                              DateFormat.yMd().add_jm().format(commentData['createdAt'].toDate()),
                                            ),
                                          );
                                        }

                                        // Regular comment
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

  @override
  void dispose() {
    _photoPageController.dispose();
    _scrollController.dispose();
    _newCommentController.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance.collection('signals').doc(widget.signalId).collection('comments').add({
      'text': _newCommentController.text,
      'createdAt': DateTime.now(),
      'author': FirebaseFirestore.instance.collection('users').doc(userId),
    });

    // Subscribe user to this signal for update notifications
    await _subscribeToSignal(userId);

    _newCommentController.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// Subscribe the user to receive notifications about this signal's updates
  Future<void> _subscribeToSignal(String userId) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).set(
        {
          'signalSubscriptions': FieldValue.arrayUnion([widget.signalId]),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Error subscribing to signal: $e');
    }
  }

  bool _isUserAuthor(Signal signal) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;

    // Compare the user UID with the reporter's document ID
    return signal.reporter.id == currentUser.uid;
  }

  String _getStatusName(int status) {
    switch (status) {
      case 0:
        return 'Help needed';
      case 1:
        return 'Somebody on the way';
      case 2:
        return 'Solved';
      default:
        return 'Unknown';
    }
  }

  String _getStatusIcon(int status) {
    switch (status) {
      case 0:
        return 'assets/icons/pin_red.png';
      case 1:
        return 'assets/icons/pin_orange.png';
      case 2:
        return 'assets/icons/pin_green.png';
      default:
        return 'assets/icons/pin_red.png';
    }
  }

  Future<void> _updateSignalStatus(int oldStatus, int newStatus) async {
    if (oldStatus == newStatus) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSignInDialog();
      return;
    }

    final signalRef = FirebaseFirestore.instance.collection('signals').doc(widget.signalId);

    // Update signal status and track who made the update (for notification filtering)
    await signalRef.update({
      'status': newStatus,
      'lastUpdatedBy': FirebaseFirestore.instance.collection('users').doc(user.uid),
    });

    // Add status change comment
    await signalRef.collection('comments').add({
      'type': 'status_change',
      'oldStatus': oldStatus,
      'newStatus': newStatus,
      'createdAt': DateTime.now(),
      'author': FirebaseFirestore.instance.collection('users').doc(user.uid),
    });

    // Subscribe user to this signal for update notifications
    await _subscribeToSignal(user.uid);
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.orange),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.orange),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() => _isUploadingPhoto = true);

      try {
        final photoUrl = await _uploadImageToStorage(image);

        // Add photo URL to photoUrls array
        await FirebaseFirestore.instance
            .collection('signals')
            .doc(widget.signalId)
            .update({
          'photoUrls': FieldValue.arrayUnion([photoUrl])
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Photo added successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to upload photo: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isUploadingPhoto = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accessing ${source == ImageSource.camera ? "camera" : "gallery"}: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deletePhoto(String photoUrl) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Photo'),
        content: const Text('Are you sure you want to delete this photo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Remove from Firestore array
      await FirebaseFirestore.instance
          .collection('signals')
          .doc(widget.signalId)
          .update({
        'photoUrls': FieldValue.arrayRemove([photoUrl])
      });

      // Delete from Storage
      try {
        final ref = FirebaseStorage.instanceFor(
                bucket: 'gs://help-a-paw-dev.appspot.com')
            .refFromURL(photoUrl);
        await ref.delete();
      } catch (e) {
        // Storage deletion failed, but Firestore update succeeded
        // This is acceptable - orphaned files can be cleaned up later
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete photo: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String> _uploadImageToStorage(XFile image) async {
    final String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';

    final storage = FirebaseStorage.instanceFor(bucket: 'gs://help-a-paw-dev.appspot.com');
    final Reference storageRef = storage
        .ref()
        .child('signals')
        .child(widget.signalId)
        .child('photos')
        .child(fileName);

    final File file = File(image.path);
    final UploadTask uploadTask = storageRef.putFile(file);
    final TaskSnapshot snapshot = await uploadTask;
    final String downloadUrl = await snapshot.ref.getDownloadURL();

    return downloadUrl;
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

class _FullScreenPhotoGallery extends StatefulWidget {
  final List<String> photoUrls;
  final int initialIndex;

  const _FullScreenPhotoGallery({
    required this.photoUrls,
    required this.initialIndex,
  });

  @override
  State<_FullScreenPhotoGallery> createState() => _FullScreenPhotoGalleryState();
}

class _FullScreenPhotoGalleryState extends State<_FullScreenPhotoGallery> {
  late int _currentIndex;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            pageController: _pageController,
            itemCount: widget.photoUrls.length,
            builder: (context, index) {
              return PhotoViewGalleryPageOptions(
                imageProvider: CachedNetworkImageProvider(widget.photoUrls[index]),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
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
              );
            },
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
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
          // Photo counter
          if (widget.photoUrls.length > 1)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_currentIndex + 1} of ${widget.photoUrls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}