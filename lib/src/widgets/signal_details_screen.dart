import 'dart:io';

import 'package:adaptive_components/adaptive_components.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/repositories/repository_provider.dart';
import 'package:help_a_paw/src/services/share_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/routes.dart';
import '../services/navigation_service.dart';

import '../models/signal.dart';
import '../models/signal_status.dart';
import '../services/app_preferences_service.dart';
import '../services/public_profile_service.dart';

class SignalDetailsScreen extends StatefulWidget {
  const SignalDetailsScreen({super.key, required this.signalId});

  final String signalId;

  @override
  State<StatefulWidget> createState() => _SignalDetailsState();
}

class _SignalDetailsState extends State<SignalDetailsScreen> {
  Stream<DocumentSnapshot>? _signalStream;
  // Memoized reporter-name lookup, keyed by reporter uid so it is resolved
  // once per signal rather than on every rebuild.
  String? _reporterId;
  Future<String?>? _reporterNameFuture;
  final TextEditingController _newCommentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploadingPhoto = false;
  final PageController _photoPageController = PageController();
  int _currentPhotoPage = 0;
  bool _hasNavigatedAway = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    _signalStream ??= FirebaseFirestore.instance.collection(AppPreferencesService().signalsCollectionName).doc(widget.signalId).snapshots();
    Signal signal;

    return StreamBuilder(stream: _signalStream, builder: (BuildContext context, AsyncSnapshot<DocumentSnapshot> snapshot) {
      if (snapshot.hasError) {
        return Text(l10n.somethingWentWrong);
      } else if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.orange))),
        );
      } else if (!(snapshot.data?.exists ?? false)) {
        // The signal was deleted while this screen was open (e.g. the author
        // removed it while another user was reading it). Pop back to the map
        // instead of rendering a blank view. Navigation can't happen during
        // build, so defer it to after the current frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _hasNavigatedAway) return;
          _hasNavigatedAway = true;
          // Capture the (app-level) messenger before popping, since this
          // screen's element is torn down by the navigation.
          final messenger = ScaffoldMessenger.of(context);
          if (Navigator.of(context).canPop()) {
            context.pop();
          } else {
            context.go(Routes.home);
          }
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.signalNoLongerAvailable)),
          );
        });
        return const Scaffold(
          body: Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.orange))),
        );
      } else {
        final signalData = snapshot.data!.data() as Map<String, dynamic>;
        signal = Signal.fromJson(signalData);
      }

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go(Routes.home);
            }
          }
        },
        child: Scaffold(
          body: AdaptiveContainer(
            child: Scaffold(
              appBar: AppBar(
              title: Text(l10n.signalDetails),
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              actions: [
                if (_isUserAuthor(signal))
                  Semantics(
                    label: l10n.editSignal,
                    button: true,
                    enabled: true,
                    child: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => context.push(Routes.editSignal(widget.signalId)),
                    ),
                  ),
                if (_isUserAuthor(signal))
                  Semantics(
                    label: l10n.deleteSignal,
                    button: true,
                    enabled: true,
                    child: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _confirmDeleteSignal(),
                    ),
                  ),
                Semantics(
                  label: l10n.shareSignal,
                  button: true,
                  enabled: true,
                  child: Builder(builder: (context) {
                    return IconButton(
                      icon: const Icon(Icons.share),
                      onPressed: () {
                        final box = context.findRenderObject() as RenderBox?;
                        final origin = box != null
                            ? box.localToGlobal(Offset.zero) & box.size
                            : null;
                        final GeoPoint? geopoint = signal.location['geopoint'] as GeoPoint?;
                        ShareService.shareSignal(
                          signalId: widget.signalId,
                          signalType: Signal.getLocalizedSignalTypeName(context, signal.signalType),
                          description: signal.description,
                          latitude: geopoint?.latitude,
                          longitude: geopoint?.longitude,
                          sharePositionOrigin: origin,
                        );
                      },
                    );
                  }),
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
                                                            l10n.uploadingPhoto,
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
                                                            signal.photoUrls.isEmpty ? l10n.addPhoto : l10n.addAnotherPhoto,
                                                            style: TextStyle(
                                                              color: Colors.grey[600],
                                                              fontSize: 16,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                          const SizedBox(height: 4),
                                                          Text(
                                                            l10n.photosCount(signal.photoUrls.length, 5),
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
                                                    child: Center(
                                                      child: Column(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        children: [
                                                          const Icon(Icons.broken_image, size: 48, color: Colors.grey),
                                                          const SizedBox(height: 8),
                                                          Text(l10n.failedToLoadImage, style: const TextStyle(color: Colors.grey)),
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
                                                  child: Semantics(
                                                    label: l10n.deletePhoto,
                                                    button: true,
                                                    enabled: true,
                                                    child: IconButton(
                                                      icon: const Icon(Icons.delete, color: Colors.white),
                                                      style: IconButton.styleFrom(
                                                        backgroundColor: Colors.red,
                                                      ),
                                                      onPressed: () => _deletePhoto(signal.photoUrls[index]),
                                                    ),
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
                          Text(l10n.signalTypeLabel(Signal.getLocalizedSignalTypeName(context, signal.signalType))),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(DateFormat.yMd(locale).add_jm().format((signal.createdAt as Timestamp).toDate())),
                              FutureBuilder<String?>(
                                future: _reporterNameFor(signal.reporter.id),
                                builder: (context, snapshot) {
                                  // While the (auth-gated) lookup is still in
                                  // flight, show nothing rather than flashing a
                                  // fallback. Once it completes, always show a
                                  // name — falling back to "Unknown" so a failed
                                  // or empty lookup never renders blank.
                                  if (snapshot.connectionState != ConnectionState.done) {
                                    return const SizedBox.shrink();
                                  }
                                  final name = snapshot.data;
                                  return Text((name != null && name.isNotEmpty) ? name : l10n.unknown);
                                },
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton.icon(
                                onPressed: () async {
                                  GeoPoint location = signal.location['geopoint'];
                                  final coords = Coords(location.latitude, location.longitude);
                                  await NavigationService.navigateTo(
                                    context: context,
                                    coords: coords,
                                    destinationTitle: signal.title,
                                  );
                                },
                                icon: const Icon(Icons.directions),
                                label: Text(l10n.navigateMe),
                                style: ButtonStyle(
                                  foregroundColor: WidgetStateProperty.all<Color>(Colors.white),
                                  backgroundColor: WidgetStateProperty.all<Color>(Colors.orange),
                                )
                              ),
                              if (signal.contactPhone.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () async {
                                    Uri phoneUri = Uri(scheme: 'tel', path: signal.contactPhone);
                                    if (await canLaunchUrl(phoneUri)) {
                                      launchUrl(phoneUri);
                                    } else {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(l10n.cannotCall(signal.contactPhone)),
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
                          Text(' ${l10n.status}'),
                          DropdownButton(
                            itemHeight: 64,
                            isExpanded: true,
                            value: signal.status,
                              items: SignalStatus.values
                                  .map(
                                    (status) => DropdownMenuItem(
                                      value: status.code,
                                      child: Row(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.all(12.0),
                                            child: Image.asset(status.pinAsset),
                                          ),
                                          SizedBox.fromSize(size: const Size(8, 8)),
                                          Text(status.label(l10n)),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  _updateSignalStatus(signal.status, value);
                                }
                              },
                          ),
                          Column(
                            children: [
                              Text(l10n.comments),
                              StreamBuilder(
                                stream: FirebaseFirestore.instance.collection(AppPreferencesService().signalsCollectionName).doc(widget.signalId).collection('comments')
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
                                                      child: FutureBuilder<String?>(
                                                        future: PublicProfileService.getName(
                                                            (commentData['author'] as DocumentReference).id),
                                                        builder: (context, snapshot) {
                                                          final authorName = (snapshot.data?.isNotEmpty ?? false)
                                                              ? snapshot.data!
                                                              : l10n.someone;
                                                          return Text(
                                                            l10n.changedStatusTo(
                                                              authorName,
                                                              _getStatusName(context, commentData['newStatus']),
                                                            ),
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
                                              DateFormat.yMd(locale).add_jm().format(commentData['createdAt'].toDate()),
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
                                              Text(DateFormat.yMd(locale).add_jm().format(commentData['createdAt'].toDate())),
                                              FutureBuilder<String?>(
                                                future: PublicProfileService.getName(
                                                    (commentData['author'] as DocumentReference).id),
                                                builder: (context, snapshot) {
                                                  return Text((snapshot.data?.isNotEmpty ?? false)
                                                      ? snapshot.data!
                                                      : l10n.unknown);
                                                },
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
                                  decoration: InputDecoration(
                                    hintText: l10n.enterYourComment,
                                  ),
                                ),
                              ),
                              Semantics(
                                label: l10n.sendComment,
                                button: true,
                                enabled: true,
                                child: IconButton(
                                  icon: const Icon(Icons.send),
                                  onPressed: () {
                                    if (!RepositoryProvider.instance.userRepository.canModifyData) {
                                      _showSignInDialog();
                                    } else {
                                      _addComment();
                                    }
                                  }
                                ),
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

    try {
      await FirebaseFirestore.instance.collection(AppPreferencesService().signalsCollectionName).doc(widget.signalId).collection('comments').add({
        'text': _newCommentController.text,
        'createdAt': DateTime.now(),
        'author': FirebaseFirestore.instance.collection('users').doc(userId),
      });

      await _subscribeToSignal(userId);

      _newCommentController.clear();
      FocusManager.instance.primaryFocus?.unfocus();
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).errorAddingComment)),
        );
      }
    }
  }

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

  /// Resolves (and memoizes) the reporter's public display name. The future is
  /// created once per reporter uid so rebuilds reuse the in-flight/completed
  /// result instead of re-fetching.
  Future<String?> _reporterNameFor(String reporterId) {
    if (_reporterId != reporterId) {
      _reporterId = reporterId;
      _reporterNameFuture = _resolveReporterName(reporterId);
    }
    return _reporterNameFuture!;
  }

  /// Reads the reporter's name from the world-readable public profile, with a
  /// short retry. The `publicProfiles` read is auth-gated, and right after a
  /// fresh (anonymous) sign-in the ID token may not be valid yet, so the first
  /// read can transiently return null; retrying lets the name resolve without
  /// the user having to reopen the screen.
  Future<String?> _resolveReporterName(String reporterId) async {
    const maxAttempts = 4;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final name = await PublicProfileService.getName(reporterId);
      if (name != null && name.isNotEmpty) return name;
      if (attempt == maxAttempts - 1 || !mounted) return null;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return null;
  }

  bool _isUserAuthor(Signal signal) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;
    return signal.reporter.id == currentUser.uid;
  }

  String _getStatusName(BuildContext context, int status) =>
      SignalStatus.fromCode(status).label(AppLocalizations.of(context));

  String _getStatusIcon(int status) => SignalStatus.fromCode(status).pinAsset;

  Future<void> _updateSignalStatus(int oldStatus, int newStatus) async {
    if (oldStatus == newStatus) return;

    if (!RepositoryProvider.instance.userRepository.canModifyData) {
      _showSignInDialog();
      return;
    }

    final user = FirebaseAuth.instance.currentUser!;
    final signalRef = FirebaseFirestore.instance.collection(AppPreferencesService().signalsCollectionName).doc(widget.signalId);

    try {
      await signalRef.update({
        'status': newStatus,
        'lastUpdatedBy': FirebaseFirestore.instance.collection('users').doc(user.uid),
      });

      await signalRef.collection('comments').add({
        'type': 'status_change',
        'oldStatus': oldStatus,
        'newStatus': newStatus,
        'createdAt': DateTime.now(),
        'author': FirebaseFirestore.instance.collection('users').doc(user.uid),
      });

      await _subscribeToSignal(user.uid);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).errorUpdatingStatus)),
        );
      }
    }
  }

  Future<void> _confirmDeleteSignal() async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteSignal),
        content: Text(l10n.confirmDeleteSignal),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      final signalRef = FirebaseFirestore.instance
          .collection(AppPreferencesService().signalsCollectionName)
          .doc(widget.signalId);

      // Read signal data to get photo URLs before deletion
      final signalDoc = await signalRef.get();
      if (signalDoc.exists) {
        final signal = Signal.fromJson(signalDoc.data()!);

        // Delete photos from Storage (best-effort)
        for (final photoUrl in signal.photoUrls) {
          try {
            final ref = FirebaseStorage.instanceFor(
                    bucket: 'gs://help-a-paw-dev.appspot.com')
                .refFromURL(photoUrl);
            await ref.delete();
          } catch (_) {
            // Storage deletion failed, continue with the rest
          }
        }
      }

      // Batch-delete subcollection comments
      final comments = await signalRef.collection('comments').get();
      if (comments.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in comments.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      // Delete the signal document
      await signalRef.delete();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.signalDeletedSuccessfully),
          backgroundColor: Colors.green,
        ),
      );

      if (Navigator.of(context).canPop()) {
        context.pop();
      } else {
        context.go(Routes.home);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.failedToDeleteSignal),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showImageSourceDialog() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.orange),
                title: Text(l10n.takePhoto),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.orange),
                title: Text(l10n.chooseFromGallery),
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
    final l10n = AppLocalizations.of(context);
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

        await FirebaseFirestore.instance
            .collection(AppPreferencesService().signalsCollectionName)
            .doc(widget.signalId)
            .update({
          'photoUrls': FieldValue.arrayUnion([photoUrl])
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.photoAddedSuccessfully),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.failedToUploadPhoto(e.toString())),
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
        final errorMessage = source == ImageSource.camera
            ? l10n.errorAccessingCamera(e.toString())
            : l10n.errorAccessingGallery(e.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deletePhoto(String photoUrl) async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deletePhoto),
        content: Text(l10n.confirmDeletePhoto),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection(AppPreferencesService().signalsCollectionName)
          .doc(widget.signalId)
          .update({
        'photoUrls': FieldValue.arrayRemove([photoUrl])
      });

      try {
        final ref = FirebaseStorage.instanceFor(
                bucket: 'gs://help-a-paw-dev.appspot.com')
            .refFromURL(photoUrl);
        await ref.delete();
      } catch (e) {
        // Storage deletion failed, but Firestore update succeeded
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.photoDeletedSuccessfully),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.failedToDeletePhoto(e.toString())),
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
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(l10n.signInRequired),
          content: Text(l10n.signInToComment),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push(Routes.signIn);
              },
              child: Text(l10n.signIn),
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
    final l10n = AppLocalizations.of(context);
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
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.broken_image, size: 64, color: Colors.white),
                        const SizedBox(height: 16),
                        Text(
                          l10n.failedToLoadImage,
                          style: const TextStyle(color: Colors.white),
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
                  Semantics(
                    label: l10n.closePhotoViewer,
                    button: true,
                    enabled: true,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 30),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
                    l10n.photoOf(_currentIndex + 1, widget.photoUrls.length),
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
