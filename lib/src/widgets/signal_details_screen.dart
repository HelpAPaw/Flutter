import 'dart:async';
import 'dart:io';

import 'package:adaptive_components/adaptive_components.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../utils/nav_extensions.dart';
import 'escape_leading.dart';
import 'level_badge.dart';

import '../models/signal_event.dart';
import '../models/signal.dart';
import '../models/signal_doc_state.dart';
import '../models/signal_status.dart';
import '../models/animal_type.dart';
import '../models/help_tag.dart';
import '../models/signal_urgency.dart';
import 'update_note_dialog.dart';
import 'urgency_picker.dart';
import '../services/app_preferences_service.dart';
import '../services/public_profile_service.dart';

class SignalDetailsScreen extends StatefulWidget {
  const SignalDetailsScreen({super.key, required this.signalId});

  final String signalId;

  @override
  State<StatefulWidget> createState() => _SignalDetailsState();
}

class _SignalDetailsState extends State<SignalDetailsScreen> {
  // Not final: a snapshot listener terminates on error, so recovering from a
  // failed read means replacing the stream, not just rebuilding.
  late Stream<DocumentSnapshot> _signalStream;

  // The signal history is read from TWO collections and merged — see
  // [SignalHistoryEntry.fromDocument] for why both stay in play.
  //
  // Explicit subscriptions rather than two StreamBuilders because the two lists
  // have to be sorted into one thread before anything can be rendered, and
  // rather than a merge package because that would be a new dependency for two
  // small objects.
  //
  // State and errors are tracked PER SOURCE, and the history only gives up once
  // every source has failed. One shared error slot meant a denied `events` read
  // blanked the comments too — the state every device is in until the rules
  // carrying the `events` block are deployed, and the state any single future
  // rules mistake would recreate. Half a history beats none.
  final _comments = _HistorySource('comments');
  final _events = _HistorySource('events');
  late final List<_HistorySource> _historySources = [_comments, _events];

  /// Which rows the history list is showing. Client-side over data already in
  /// memory — both listeners stay subscribed either way.
  SignalHistoryFilter _historyFilter = SignalHistoryFilter.all;
  // Memoized public-name lookups, keyed by uid so each name is resolved once
  // per screen rather than once per rebuild — the comment list would otherwise
  // re-read publicProfiles for every row every time this screen rebuilds.
  final Map<String, Future<String?>> _nameFutures = {};
  // uids whose lookup has already been given a second chance — see _nameFor.
  final Set<String> _nameRetried = {};
  final TextEditingController _newCommentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploadingPhoto = false;

  /// Guards a status or urgency write. Without it a double-tap posts two
  /// timeline entries and (on an urgency escalation) two pushes to every
  /// subscriber.
  bool _isApplyingLevelChange = false;
  final PageController _photoPageController = PageController();
  int _currentPhotoPage = 0;
  bool _hasNavigatedAway = false;
  // Whether this screen ever rendered the signal. Distinguishes "deleted while
  // you were reading it" from "was already gone when you opened it", which want
  // opposite treatments — see the missing-document branch in build().
  bool _signalWasLoaded = false;
  // Set once we have waited long enough for the server to say anything at all.
  // See SignalDocState.
  bool _serverUnreachable = false;
  Timer? _serverConfirmationTimer;

  /// How long to sit on the spinner before treating the device as offline and
  /// saying so, rather than spinning forever. Generous, because a
  /// congested-but-working connection reaching this point would be told its
  /// network is broken when it is only slow.
  static const _serverConfirmationTimeout = Duration(seconds: 20);

  // Note: every field above is memoized per signal. Navigating signal->signal
  // must therefore build a fresh State rather than reuse this one — the route
  // gives this screen a ValueKey on the signal id (see main.dart) so the
  // framework disposes and rebuilds instead of swapping `widget` underneath us.

  DocumentReference<Map<String, dynamic>> get _signalRef =>
      FirebaseFirestore.instance
          .collection(AppPreferencesService().signalsCollectionName)
          .doc(widget.signalId);

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    // includeMetadataChanges is what lets the screen tell "the server says this
    // is gone" from "only our cache thinks so": without it Firestore never
    // delivers the server confirmation for a document the cache already knows
    // is absent, because nothing but the metadata differs between the two
    // events — and the screen waits for it forever (R6-001).
    _signalStream = _signalRef.snapshots(includeMetadataChanges: true);
    _subscribeToHistory();
  }

  /// Replaces just the two history listeners, leaving `_signalStream` alone.
  ///
  /// Separate from [_subscribe] because the history has its own Retry, and
  /// reassigning the signal stream to serve it would put the whole screen back
  /// to `unknownYet` — a full-page spinner over the photos, description and
  /// comment box, and a detached `_scrollController` that drops the reader back
  /// at the top of a long signal. Reloading a sub-list must not cost the page.
  void _subscribeToHistory() {
    for (final source in _historySources) {
      source.reset();
      source.sub = _listenToHistory(source);
    }
  }

  /// One ordered listener on a history collection, decoded into the merged row
  /// type. Documents this build cannot read are dropped rather than thrown on —
  /// an unrecognised `type` means a newer client wrote it, and one row it cannot
  /// render must not take out the whole thread.
  StreamSubscription<QuerySnapshot> _listenToHistory(_HistorySource source) {
    return _signalRef
        .collection(source.collection)
        .orderBy('createdAt')
        .snapshots()
        .listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          source.entries = snapshot.docs
              .map((doc) => SignalHistoryEntry.fromDocument(doc.id, doc.data()))
              .whereType<SignalHistoryEntry>()
              .toList();
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => source.error = error);
      },
    );
  }

  /// Subscribes again after a failed read. Firestore ends a listener on error,
  /// so the error is permanent for that stream even once the cause has passed —
  /// an App Check or auth token that was not ready at cold launch, say. Both
  /// listeners are replaced: whatever killed one killed the other.
  void _restartListeners() {
    setState(() {
      _resetServerConfirmationWait();
      _subscribe();
    });
  }

  /// Leaves this screen the way the rest of the screen does: back if there is
  /// somewhere to go back to, otherwise to the map. A cold deep link makes this
  /// the first route in the stack, so there is nothing to pop.
  ///
  /// Claims the exit on the way out, so that a listener event arriving while
  /// the route animates away cannot leave a second time on top of this one.
  void _leaveScreen() {
    _hasNavigatedAway = true;
    context.popOrHome();
  }

  /// Whether this screen is the one the user is actually looking at. Popping
  /// pops whatever is topmost, so anything that leaves on its own initiative —
  /// rather than because the user pressed something here — has to check first.
  bool get _isForeground => ModalRoute.of(context)?.isCurrent ?? true;

  /// Drops the offline countdown once the server has answered, so that a later
  /// cache-only event (a signal deleted while you read it) starts a fresh wait
  /// instead of inheriting a stale verdict.
  void _resetServerConfirmationWait() {
    _serverConfirmationTimer?.cancel();
    _serverConfirmationTimer = null;
    _serverUnreachable = false;
  }

  /// This screen's app bar, in every state it can be in. The `leading` is what
  /// keeps a cold deep link from being a dead end — see [escapeLeading].
  AppBar _appBar(AppLocalizations l10n, {List<Widget>? actions}) {
    return AppBar(
      title: Text(l10n.signalDetails),
      backgroundColor: Colors.orange,
      foregroundColor: Colors.white,
      leading: escapeLeading(
        context,
        label: l10n.backToMap,
        onLeave: _leaveScreen,
      ),
      actions: actions,
    );
  }

  /// Shown until the server has told us whether the signal exists. Waiting is
  /// not a reason to be trapped, so this carries the app bar too.
  Widget _buildLoading() {
    return Scaffold(
      appBar: _appBar(AppLocalizations.of(context)),
      body: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
        ),
      ),
    );
  }

  /// Shown when the server says the signal is gone.
  Widget _buildNotFound() {
    final l10n = AppLocalizations.of(context);
    return _buildMessage(
      icon: Icons.search_off,
      title: l10n.signalNoLongerAvailable,
      hint: l10n.signalNoLongerAvailableHint,
    );
  }

  /// The frame shared by the dead ends this screen can land in: an app bar you
  /// can always leave from and a centred explanation.
  Widget _buildMessage({
    required IconData icon,
    required String title,
    String? hint,
    VoidCallback? onRetry,
  }) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: _appBar(l10n),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(fontSize: 20),
                textAlign: TextAlign.center,
              ),
              if (hint != null) ...[
                const SizedBox(height: 8),
                Text(
                  hint,
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _leaveScreen,
                child: Text(l10n.backToMap),
              ),
              if (onRetry != null)
                TextButton(onPressed: onRetry, child: Text(l10n.retry)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final dateFormat = DateFormat.yMd(locale).add_jm();

    return StreamBuilder(stream: _signalStream, builder: (BuildContext context, AsyncSnapshot<DocumentSnapshot> snapshot) {
      final docState = resolveSignalDocState(
        hasError: snapshot.hasError,
        isWaiting: snapshot.connectionState == ConnectionState.waiting,
        exists: snapshot.data?.exists ?? false,
        isFromCache: snapshot.data?.metadata.isFromCache ?? true,
        wasLoaded: _signalWasLoaded,
        serverUnreachable: _serverUnreachable,
      );

      // Rendering the spinner is what starts the clock that eventually turns an
      // unanswered listen into `unreachable`; anything else means the server has
      // spoken, so the clock goes away.
      if (docState == SignalDocState.unknownYet) {
        _serverConfirmationTimer ??= Timer(_serverConfirmationTimeout, () {
          if (mounted) setState(() => _serverUnreachable = true);
        });
      } else if (docState != SignalDocState.unreachable) {
        _resetServerConfirmationWait();
      }

      switch (docState) {
        case SignalDocState.failed:
          // A denied read (rules, App Check, or an id from the other collection
          // while test mode is on) must not leave a bare string on a blank
          // screen: arriving here by deep link, that is the only route.
          return _buildMessage(
            icon: Icons.error_outline,
            title: l10n.somethingWentWrong,
            // Unlike `unreachable`, this state cannot heal on its own: the
            // listener is finished, so retrying has to start a new one.
            onRetry: _restartListeners,
          );
        case SignalDocState.unknownYet:
          return _buildLoading();
        case SignalDocState.unreachable:
          return _buildMessage(
            icon: Icons.cloud_off,
            title: l10n.networkError,
            // The listener stays subscribed, so retrying only needs to put the
            // spinner back and start the clock again — a connection that comes
            // back on its own recovers without being asked.
            onRetry: () => setState(_resetServerConfirmationWait),
          );
        case SignalDocState.deletedWhileOpen:
          // Deleted while this screen was open (e.g. the author removed it
          // while another user was reading it). Pop back to the map instead of
          // rendering a blank view — but only while this is the screen in front
          // of the user. Popping pops whatever is topmost, so with the photo
          // gallery, the edit route or another signal pushed above, leaving now
          // would dismiss *that* and yank them out of something they are
          // reading. Sit on the not-found state until they come back (reading
          // `isCurrent` subscribes us to that, so returning rebuilds and takes
          // the branch below). Navigation can't happen during build, so defer
          // it to after the current frame.
          if (!_isForeground) return _buildNotFound();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _hasNavigatedAway) return;
            // Capture the (app-level) messenger before popping, since this
            // screen's element is torn down by the navigation.
            final messenger = ScaffoldMessenger.of(context);
            _leaveScreen();
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.signalNoLongerAvailable)),
            );
          });
          return _buildLoading();
        case SignalDocState.missing:
          // Already gone when the screen was opened — an inbox entry or a
          // shared link pointing at a since-deleted id. Auto-popping here would
          // push a screen that instantly dismisses itself, which reads as a
          // dead tap (R5-004). Show a real not-found state and let the user
          // leave deliberately.
          return _buildNotFound();
        case SignalDocState.present:
          break;
      }

      _signalWasLoaded = true;
      final signal = Signal.fromJson(snapshot.data!.data() as Map<String, dynamic>);
      final isAuthor = _isUserAuthor(signal);

      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            _leaveScreen();
          }
        },
        child: Scaffold(
          body: AdaptiveContainer(
            child: Scaffold(
              appBar: _appBar(l10n, actions: [
                if (isAuthor)
                  Semantics(
                    label: l10n.editSignal,
                    button: true,
                    enabled: true,
                    child: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => context.push(Routes.editSignal(widget.signalId)),
                    ),
                  ),
                if (isAuthor)
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
                          headline: signal.primaryTag.neededLabel(l10n),
                          description: signal.description,
                          latitude: geopoint?.latitude,
                          longitude: geopoint?.longitude,
                          sharePositionOrigin: origin,
                        );
                      },
                    );
                  }),
                ),
              ]),
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
                          if (signal.photoUrls.isNotEmpty || isAuthor)
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
                                        (isAuthor && signal.photoUrls.length < 5 ? 1 : 0),
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
                                              if (isAuthor)
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
                                        (isAuthor && signal.photoUrls.length < 5 ? 1 : 0)) >
                                    1)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: List.generate(
                                        signal.photoUrls.length +
                                            (isAuthor && signal.photoUrls.length < 5 ? 1 : 0),
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
                          // No type line: what the signal needs is shown as the
                          // help-tag chips below, which carry the same
                          // information with more precision.
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  dateFormat.format((signal.createdAt as Timestamp).toDate()),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                // Same helper the history rows use, so the
                                // "don't flash the fallback before the lookup
                                // lands" rule (R4-OBS-01) has one home rather
                                // than a copy here and a copy per row type.
                                child: _actorText(
                                  signal.reporter.id,
                                  (name) => name,
                                  fallback: l10n.unknown,
                                  textAlign: TextAlign.end,
                                  maxLines: 1,
                                ),
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
                          Text(' ${l10n.urgency}'),
                          // Urgency is reporter-only. The spec restricts it to
                          // the signal holder, a moderator or an admin; there are
                          // no moderator/admin roles yet, so the reporter is
                          // the whole of that set today. Firestore's
                          // `isStatusOnlyUpdate` enforces the same rule, so
                          // hiding this is UI courtesy, not the security
                          // boundary. Everyone else sees the level read-only.
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: isAuthor
                                ? UrgencyPicker(
                                    value: signal.urgency,
                                    enabled: !_isApplyingLevelChange,
                                    onChanged: (value) => _updateSignalUrgency(
                                      signal.urgency,
                                      value,
                                    ),
                                  )
                                : Align(
                                    alignment: Alignment.centerLeft,
                                    child: UrgencyChip(urgency: signal.urgency),
                                  ),
                          ),
                          // What the signal needs, read-only. Editing lives on the
                          // edit screen with the rest of the reporter's fields.
                          // Signals from before tags existed have none, so the
                          // whole block is omitted rather than showing an empty
                          // heading.
                          if (signal.helpNeededTags.isNotEmpty ||
                              signal.animalType != null) ...[
                            const SizedBox(height: 8),
                            // Only when there is actually a need to head. A
                            // signal with a species and no tags (legacy, or
                            // edited by an older build) would otherwise read
                            // "Help needed" above a lone Cat chip.
                            if (signal.helpNeededTags.isNotEmpty)
                              Text(' ${l10n.helpNeeded}'),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  if (AnimalType.fromCode(signal.animalType)
                                      case final species?)
                                    Chip(
                                      avatar: Icon(species.icon, size: 16),
                                      label: Text(species.label(l10n)),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  // Unknown codes are dropped: one means the
                                  // signal came from a newer build, and there is
                                  // no label for it here.
                                  for (final tag in HelpTag.fromCodes(
                                      signal.helpNeededTags))
                                    Chip(
                                      avatar: Icon(tag.icon, size: 16),
                                      label: Text(tag.label(l10n)),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(' ${l10n.status}'),
                          DropdownButton<int>(
                            itemHeight: 64,
                            isExpanded: true,
                            value: signal.status,
                              items: SignalStatus.values
                                  .map(
                                    (status) => DropdownMenuItem(
                                      value: status.code,
                                      child: Row(
                                        children: [
                                          // A coloured dot, not a map pin: the
                                          // pin is the urgency vocabulary now,
                                          // and reusing it here would re-imply
                                          // that pin colour tracks status.
                                          Padding(
                                            padding: const EdgeInsets.all(12.0),
                                            child: CircleAvatar(
                                              radius: 6,
                                              backgroundColor: status.color,
                                            ),
                                          ),
                                          SizedBox.fromSize(size: const Size(8, 8)),
                                          Text(status.label(l10n)),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                              // Disabled mid-write for the same reason as the
                              // urgency picker: a second selection before the
                              // first lands posts a duplicate timeline entry.
                              onChanged: _isApplyingLevelChange
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        _updateSignalStatus(
                                            signal.status, value);
                                      }
                                    },
                          ),
                          _buildSignalHistory(signal, dateFormat),
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
                                  // Matches the rules' 2000-char cap, so over-long
                                  // input is stopped at the keyboard rather than
                                  // failing the write. No counter — this is a
                                  // chat-style field, not a form.
                                  inputFormatters: [
                                    LengthLimitingTextInputFormatter(2000),
                                  ],
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

  /// One All/Events chip.
  ///
  /// Labelled for the same reason as every other control on this screen:
  /// element-based device automation finds a labelled control reliably, and
  /// coordinate-tapping a small chip does not (see CLAUDE.md).
  Widget _historyFilterChip(SignalHistoryFilter filter) {
    final l10n = AppLocalizations.of(context);
    final label = switch (filter) {
      SignalHistoryFilter.all => l10n.historyFilterAll,
      SignalHistoryFilter.events => l10n.historyFilterEvents,
    };
    final selected = _historyFilter == filter;

    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => _historyFilter = filter),
      ),
    );
  }

  /// A history read that failed, and the way back from it.
  ///
  /// Retries the history listeners only — see [_subscribeToHistory].
  Widget _historyNotice(String message) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
          Semantics(
            label: l10n.retry,
            button: true,
            child: TextButton(
              onPressed: () => setState(_subscribeToHistory),
              child: Text(l10n.retry),
            ),
          ),
        ],
      ),
    );
  }

  /// The signal timeline (master spec §4.6): what happened to this signal, and
  /// what people said about it, in one chronological thread.
  Widget _buildSignalHistory(Signal signal, DateFormat dateFormat) {
    final l10n = AppLocalizations.of(context);
    // Only when BOTH sources are unreadable. If one still works the history is
    // incomplete rather than unavailable, and showing the half we have beats
    // replacing the whole thread — which is what a device on rules that predate
    // the `events` block would otherwise see.
    //
    // This branch gets the SAME retry as the one-sided failure. Both listeners
    // failing is the *more* recoverable case, not the less: it is what a cold
    // launch looks like when the auth or App Check token was not ready in time,
    // and that passes on its own. Leaving it as a dead end — the state it was in
    // when only the one-sided path had a Retry — stranded exactly the users
    // whose problem a retry would have solved.
    if (_historySources.every((s) => s.error != null)) {
      return _historyNotice(l10n.somethingWentWrong);
    }
    // Likewise only while BOTH are still silent: rendering as soon as either
    // arrives means rows appear rather than a spinner sitting there, and the
    // two listeners are created together so the gap is a frame or two.
    if (_historySources.every((s) => s.isSilent)) {
      return const CircularProgressIndicator();
    }

    final entries = filterSignalHistory(
      mergeSignalHistory(
        created: SignalHistoryEntry.created(
          reporterId: signal.reporter.id,
          createdAt: SignalHistoryEntry.dateFrom(signal.createdAt),
        ),
        comments: _comments.entries ?? const [],
        events: _events.entries ?? const [],
      ),
      _historyFilter,
    );

    return Column(
      children: [
        Text(l10n.signalHistory),
        // Exactly one source failed. The list below is missing rows and would
        // otherwise look complete — the silent-failure shape this codebase
        // keeps getting bitten by. A Firestore listener ends on error and never
        // heals, so the retry is the only way back short of leaving the screen.
        if (_historySources.any((s) => s.error != null))
          _historyNotice(l10n.historyPartiallyUnavailable),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final filter in SignalHistoryFilter.values)
                _historyFilterChip(filter),
            ],
          ),
        ),
        ListView.builder(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 80),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: entries.length,
          itemBuilder: (context, index) =>
              _buildHistoryRow(entries[index], dateFormat),
        ),
      ],
    );
  }

  Widget _buildHistoryRow(SignalHistoryEntry entry, DateFormat dateFormat) =>
      switch (entry.kind) {
        SignalHistoryKind.created => _buildCreatedRow(entry, dateFormat),
        SignalHistoryKind.statusChange ||
        SignalHistoryKind.urgencyChange =>
          _buildEventRow(entry, dateFormat),
        SignalHistoryKind.comment => _buildCommentRow(entry, dateFormat),
      };

  /// The row every timeline opens with. Not stored — see
  /// [SignalHistoryEntry.created].
  Widget _buildCreatedRow(SignalHistoryEntry entry, DateFormat dateFormat) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: _historyCard(
        background: Colors.grey.shade100,
        border: Colors.grey.shade300,
        child: Row(
          children: [
            const Icon(Icons.flag_outlined, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: _actorText(
                entry.actorId,
                (name) => l10n.reportedThisSignal(name),
                fallback: l10n.someone,
              ),
            ),
          ],
        ),
      ),
      subtitle: _dateSubtitle(entry, dateFormat),
    );
  }

  /// A status or urgency change, with the update note that explains it.
  Widget _buildEventRow(SignalHistoryEntry entry, DateFormat dateFormat) {
    final l10n = AppLocalizations.of(context);
    final isUrgency = entry.kind == SignalHistoryKind.urgencyChange;
    final level = entry.level!;
    final note = entry.note;

    return ListTile(
      title: _historyCard(
        background: Colors.orange.shade50,
        border: Colors.orange.shade200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                isUrgency
                    ? urgencyBadge(SignalUrgency.fromCode(level))
                    : statusBadge(SignalStatus.fromCode(level)),
                const SizedBox(width: 8),
                Expanded(
                  child: _actorText(
                    entry.actorId,
                    (name) => isUrgency
                        ? l10n.changedUrgencyTo(
                            name,
                            SignalUrgency.fromCode(level).label(l10n),
                          )
                        : l10n.changedStatusTo(
                            name,
                            SignalStatus.fromCode(level).label(l10n),
                          ),
                    fallback: l10n.someone,
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
            // Absent on entries written before the note was mandatory. Those
            // are the legacy rows still living in `comments`, and they have to
            // keep rendering exactly as they always did.
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(note),
            ],
          ],
        ),
      ),
      subtitle: _dateSubtitle(entry, dateFormat),
    );
  }

  Widget _buildCommentRow(SignalHistoryEntry entry, DateFormat dateFormat) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: _historyCard(
        background: Colors.white,
        border: Colors.grey,
        child: Text(entry.text ?? ''),
      ),
      subtitle: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              _formatDate(entry, dateFormat) ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // The author name is user-supplied and capped at 100 chars, so it must
          // be allowed to shrink instead of overflowing the row.
          Flexible(
            child: _actorText(
              entry.actorId,
              (name) => name,
              fallback: l10n.unknown,
              textAlign: TextAlign.end,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  /// The bubble every history row sits in. One definition so the three rows
  /// cannot drift apart visually; they differ only in their two colours.
  Widget _historyCard({
    required Color background,
    required Color border,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 1),
      ),
      child: Padding(padding: const EdgeInsets.all(8.0), child: child),
    );
  }

  Widget? _dateSubtitle(SignalHistoryEntry entry, DateFormat dateFormat) {
    final text = _formatDate(entry, dateFormat);
    return text == null ? null : Text(text);
  }

  /// Null while a write is still in flight and has no timestamp yet — the row
  /// itself still renders, it just has no date to show.
  String? _formatDate(SignalHistoryEntry entry, DateFormat dateFormat) {
    final at = entry.createdAt;
    return at == null ? null : dateFormat.format(at);
  }

  /// Resolves [uid] to a display name through the per-screen memo and renders
  /// [sentence] around it.
  ///
  /// [maxLines] for the places the name shares a row with the date: it is
  /// user-supplied and capped at 100 chars, so it has to shrink rather than
  /// overflow.
  Widget _actorText(
    String uid,
    String Function(String name) sentence, {
    required String fallback,
    TextStyle? style,
    TextAlign? textAlign,
    int? maxLines,
  }) {
    return FutureBuilder<String?>(
      future: _nameFor(uid),
      builder: (context, snapshot) {
        // Nothing while the lookup is in flight. `snapshot.data` is null until
        // it completes, so rendering unconditionally paints the fallback first
        // and then flips to the real name — and since the created row now opens
        // every signal, that made "Unknown reported this signal" flash on every
        // open. On completion it always renders, falling back to [fallback].
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final name =
            (snapshot.data?.isNotEmpty ?? false) ? snapshot.data! : fallback;
        return Text(
          sentence(name),
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
        );
      },
    );
  }

  @override
  void dispose() {
    _serverConfirmationTimer?.cancel();
    for (final source in _historySources) {
      source.sub?.cancel();
    }
    _photoPageController.dispose();
    _scrollController.dispose();
    _newCommentController.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    // The rules reject an empty `text`, so a whitespace-only comment would come
    // back as an opaque PERMISSION_DENIED. Drop it here instead — sending blank
    // comments was never meaningful anyway.
    final text = _newCommentController.text.trim();
    if (text.isEmpty) return;

    try {
      await _signalRef.collection('comments').add({
        'text': text,
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

  /// Resolves (and memoizes) a public display name. The future is created once
  /// per uid so rebuilds — and the several comment rows a single author can
  /// own — reuse the in-flight/completed result instead of re-fetching.
  ///
  /// A lookup that *failed* is dropped from the memo once, so the next rebuild
  /// tries again: the usual cause is the auth window at cold launch, and
  /// keeping the failure would pin the reporter and every commenter to
  /// "Unknown" for as long as the screen lives. An account that simply has no
  /// name did not fail — that answer is final and stays memoized, which is what
  /// keeps the known "Unknown" population from being re-read every rebuild.
  Future<String?> _nameFor(String uid) {
    return _nameFutures[uid] ??= _resolveName(uid).onError((_, __) {
      // Only the first failure earns a retry; a read that is denied for good
      // would otherwise start a fresh attempt chain on every rebuild.
      if (_nameRetried.add(uid)) _nameFutures.remove(uid);
      return null;
    });
  }

  /// Reads a name from the world-readable public profile, retrying a failed
  /// read. The `publicProfiles` read is auth-gated, and right after a fresh
  /// (anonymous) sign-in the ID token may not be valid yet, so the first read
  /// can transiently be denied.
  ///
  /// Throws if every attempt failed, which is what tells [_nameFor] the null it
  /// is about to show is ignorance rather than an answer.
  Future<String?> _resolveName(String uid) async {
    const maxAttempts = 4;
    for (var attempt = 1; ; attempt++) {
      try {
        return await PublicProfileService.readName(uid);
      } catch (_) {
        if (attempt == maxAttempts || !mounted) rethrow;
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  bool _isUserAuthor(Signal signal) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;
    return signal.reporter.id == currentUser.uid;
  }

  Future<void> _updateSignalStatus(int oldStatus, int newStatus) async {
    final status = SignalStatus.fromCode(newStatus);
    await _applyLevelChange(
      eventType: SignalEventType.statusChange,
      oldValue: oldStatus,
      newValue: newStatus,
      levelLabel: status.label(AppLocalizations.of(context)),
      levelBadge: statusBadge(status),
      errorText: (l10n) => l10n.errorUpdatingStatus,
    );
  }

  /// Change the signal's urgency and record it on the timeline.
  ///
  /// The Red Alert confirmation has already been handled by [UrgencyPicker]
  /// before this is called.
  Future<void> _updateSignalUrgency(int oldUrgency, int newUrgency) async {
    final urgency = SignalUrgency.fromCode(newUrgency);
    await _applyLevelChange(
      eventType: SignalEventType.urgencyChange,
      oldValue: oldUrgency,
      newValue: newUrgency,
      levelLabel: urgency.label(AppLocalizations.of(context)),
      levelBadge: urgencyBadge(urgency),
      errorText: (l10n) => l10n.errorUpdatingUrgency,
    );
  }

  /// Moves a signal from one level to another — status or urgency — and records
  /// it on the signal timeline.
  ///
  /// One implementation for both because the protocol around them is identical
  /// and must stay so: gate on a real account, ask for the update note, write
  /// the field, append the matching event, subscribe the actor, report failure.
  ///
  /// Which field to write, and what to call the before/after values, comes from
  /// [SignalEventType] rather than from the caller — the read side already
  /// derives them from the type, and passing them in parallel let the two sides
  /// disagree.
  ///
  /// `lastUpdatedBy` is stamped for both. The rules only need it on the
  /// non-reporter status path, but `handleSignalUpdated` uses it to avoid
  /// notifying whoever made the change — so leaving it stale on an urgency
  /// write would silently mute a subscriber.
  Future<void> _applyLevelChange({
    required SignalEventType eventType,
    required int oldValue,
    required int newValue,
    required String levelLabel,
    required Widget levelBadge,
    required String Function(AppLocalizations) errorText,
  }) async {
    if (oldValue == newValue || _isApplyingLevelChange) return;

    if (!RepositoryProvider.instance.userRepository.canModifyData) {
      _showSignInDialog();
      return;
    }

    // Spec 4.6: every change carries a note saying what happened. Asked before
    // anything is written, so backing out of the dialog leaves the signal
    // exactly as it was — the dropdown and the picker both read their value
    // from the signal stream, so neither needs reverting.
    //
    // On the urgency path this runs AFTER UrgencyPicker's Red Alert
    // confirmation: confirm the intent first, then explain it.
    final note = await showUpdateNoteDialog(
      context,
      levelLabel: levelLabel,
      levelBadge: levelBadge,
    );
    if (note == null || !mounted) return;
    // Re-checked after the dialog, not just before it: writing the note can take
    // a while, and the guard's whole job is to stop a second change landing on
    // top of one already in flight.
    //
    // The `old*` value this event records is the one read when the dropdown was
    // opened, so a change made by someone else meanwhile leaves it stale. That
    // is cosmetic — nothing reads `old*`; the renderer, the rules and the push
    // all key off the new value — and fixing it properly means re-reading the
    // signal, a round trip to correct a field nobody consults.
    if (_isApplyingLevelChange) return;

    final user = FirebaseAuth.instance.currentUser!;
    final userRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);
    final signalRef = _signalRef;

    setState(() => _isApplyingLevelChange = true);

    // One batch, so the field change and the timeline entry it describes land
    // together or not at all. Written separately, a failed second write left a
    // notification sent with no history to explain it.
    final batch = FirebaseFirestore.instance.batch();
    batch.update(signalRef, {
      eventType.signalField: newValue,
      'lastUpdatedBy': userRef,
    });
    batch.set(
      signalRef.collection('events').doc(),
      eventType.eventData(
        oldValue: oldValue,
        newValue: newValue,
        note: note,
        actor: userRef,
      ),
    );

    try {
      // The subscription is independent and best-effort (it swallows its own
      // errors), so it overlaps the commit instead of adding a round trip.
      await Future.wait([batch.commit(), _subscribeToSignal(user.uid)]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorText(AppLocalizations.of(context)))),
        );
      }
    } finally {
      if (mounted) setState(() => _isApplyingLevelChange = false);
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
      final signalRef = _signalRef;

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

      // Batch-delete both history subcollections. `events` has to be included:
      // Firestore keeps subcollection documents when the parent document is
      // deleted, so anything missed here is orphaned with nothing left to reach
      // it by. This is also the only reason the rules let the reporter delete
      // events at all — see the known gap on that rule (HelpAPaw/Flutter#68).
      await _deleteHistory(signalRef);

      // Claim the exit before the delete, not after it: Firestore applies the
      // delete to the local cache immediately, so the still-live listener
      // reports the document missing while this method is parked on the await.
      // The "deleted while you were reading it" branch would then pop a route
      // of its own and replace the success message below with the *other*
      // user's "this signal is no longer available" (R6-002).
      _hasNavigatedAway = true;
      await signalRef.delete();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.signalDeletedSuccessfully),
          backgroundColor: Colors.green,
        ),
      );

      _leaveScreen();
    } catch (e) {
      // The signal is still there, so give the exit claim back.
      _hasNavigatedAway = false;
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

  /// Empties both history subcollections ahead of deleting the signal.
  ///
  /// The two reads are independent, so they run concurrently and their deletes
  /// share one batch: two round trips on a tap that shows no progress, instead
  /// of the four that reading and committing each collection in turn cost.
  ///
  /// One batch also makes the two deletes atomic — a signal cannot end up with
  /// its comments gone and its history intact. It is bounded by what a single
  /// signal accumulates, and a 500-document signal has never existed; if one
  /// ever does, this is where the chunking goes.
  Future<void> _deleteHistory(DocumentReference<Object?> signalRef) async {
    final snapshots = await Future.wait([
      signalRef.collection('comments').get(),
      signalRef.collection('events').get(),
    ]);

    final docs = [for (final snapshot in snapshots) ...snapshot.docs];
    if (docs.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
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

        await _signalRef.update({
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
      await _signalRef.update({
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
    // See FirebaseStorageRepository.uploadSignalImage: the rules require an
    // `image/*` content type, so declare it instead of relying on inference.
    final UploadTask uploadTask = storageRef.putFile(
      file,
      SettableMetadata(contentType: 'image/jpeg'),
    );
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

/// One collection feeding the merged history.
///
/// Exists so the two sources move as units instead of as six parallel fields:
/// every predicate on this screen asks the same question of both, and a third
/// source would otherwise mean three more fields and four more boolean arms.
class _HistorySource {
  _HistorySource(this.collection);

  /// Subcollection name under the signal document.
  final String collection;

  StreamSubscription<QuerySnapshot>? sub;

  /// Null means "nothing delivered yet", which is distinct from an empty list —
  /// an empty list is a real answer.
  List<SignalHistoryEntry>? entries;

  Object? error;

  /// Nothing has arrived and nothing has failed: still waiting.
  bool get isSilent => entries == null && error == null;

  void reset() {
    sub?.cancel();
    sub = null;
    entries = null;
    error = null;
  }
}
