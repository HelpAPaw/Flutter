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
import 'case_holder_block.dart';
import 'help_tag_picker_sheet.dart';
import 'report_dialog.dart';
import 'update_note_dialog.dart';
import 'urgency_picker.dart';
import '../models/moderation_target.dart';
import '../models/removed_signal.dart';
import '../models/report_reason.dart';
import '../services/app_preferences_service.dart';
import '../services/callable_client.dart';
import '../services/case_ownership_service.dart';
import '../services/moderation_service.dart';
import '../services/signal_removal_service.dart';
import 'moderation_action_sheet.dart';
import 'section_header.dart';
import '../services/public_profile_service.dart';
import 'app_bar_title.dart';
import 'status_view.dart';

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

  /// Removing, and the two dialogs in front of it. See [_confirmRemoveSignal].
  final _removalService = SignalRemovalService();

  /// Whether a removal is in flight.
  ///
  /// The removal is a network round trip now, not a local cache write, so the
  /// button stays on screen and tappable for as long as it takes. Without this
  /// a second tap fires a second call — which fails `not-found` because the
  /// first one succeeded, and whose `catch` hands back the exit claim the first
  /// one took. The listener's `deletedWhileOpen` branch then pops a route of
  /// its own and replaces the success message with "no longer available",
  /// which is R6-002 arriving by a different door.
  bool _isRemoving = false;

  /// Whether the viewer holds the moderator role.
  ///
  /// A plain field fed by one subscription rather than a `StreamBuilder`,
  /// because two very different surfaces need the answer — the app-bar shield
  /// and every comment row — and wrapping each of a long comment list's rows in
  /// its own builder to ask the same question is a lot of machinery for a bool.
  ///
  /// Safe to hold in State here, unlike in `HomeRouteDrawer`, whose State is
  /// created and disposed on every drawer open. `ModerationService` fans a
  /// single process-lifetime listener out to its subscribers, so this costs no
  /// extra read.
  ///
  /// A **UI affordance only** — the real check is in the `moderateAction`
  /// callable, so a stale `true` costs nothing worse than a button that returns
  /// `permission-denied`.
  bool _isModerator = false;
  StreamSubscription<bool>? _roleSub;

  /// Which rows the history list is showing. Client-side over data already in
  /// memory — both listeners stay subscribed either way.
  SignalHistoryFilter _historyFilter = SignalHistoryFilter.all;
  // Memoized public-name lookups, keyed by uid so each name is resolved once
  // per screen rather than once per rebuild — the comment list would otherwise
  // re-read publicProfiles for every row every time this screen rebuilds.
  final Map<String, Future<String?>> _nameFutures = {};
  // uids whose lookup has already been given a second chance — see _nameFor.
  final Set<String> _nameRetried = {};
  // Memoized name PAIRS, for rows whose sentence names two people. Keyed on both
  // uids because `FutureBuilder` compares by identity — see _namePairFor.
  final Map<String, Future<List<String?>>> _namePairFutures = {};
  final TextEditingController _newCommentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploadingPhoto = false;

  /// Guards a status or urgency write. Without it a double-tap posts two
  /// timeline entries and (on an urgency escalation) two pushes to every
  /// subscriber.
  ///
  /// Also guards every **ownership** change, deliberately sharing one flag
  /// rather than adding a second: a claim can carry a status change with it, so
  /// two separate guards would let one tap through each of them and produce the
  /// double write neither was meant to allow.
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

  /// The signed-in user's `users/{uid}` document, as a reference.
  ///
  /// Beside [_signalRef] because the two are always used together: every
  /// coordination write names the signal and stamps the actor.
  DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid);

  DocumentReference<Map<String, dynamic>> get _signalRef =>
      FirebaseFirestore.instance
          .collection(AppPreferencesService().signalsCollectionName)
          .doc(widget.signalId);

  @override
  void initState() {
    super.initState();
    _subscribe();
    _roleSub = ModerationService.instance.watchIsModerator().listen((value) {
      if (mounted && value != _isModerator) {
        setState(() => _isModerator = value);
      }
    });
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
      title: AppBarTitle(l10n.signalDetails),
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
      // The shape of this block is now shared with My Signals and the inbox
      // (see StatusView); what stays local is the way out, because this screen
      // is the one a cold deep link can strand you on.
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: onRetry != null
                ? StatusView.error(
                    icon: icon,
                    title: title,
                    hint: hint,
                    onRetry: onRetry,
                  )
                : StatusView.empty(icon: icon, title: title, hint: hint),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 32),
            child: ElevatedButton(
              onPressed: _leaveScreen,
              child: Text(l10n.backToMap),
            ),
          ),
        ],
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
      // Master spec §4.5: the case holder coordinates the case. The reporter
      // keeps their own powers whether or not they still hold it — they own the
      // photos, the description and the phone number, and §5.2 names "the
      // original poster/case holder" as one set. `firestore.rules` draws the
      // same line with `isSignalReporter() || isCaseHolderUpdate()`; this is
      // which controls to draw, not the security boundary.
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final canCoordinate = signal.canCoordinate(uid);

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
                    label: l10n.removeSignal,
                    button: true,
                    enabled: !_isRemoving,
                    child: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: _isRemoving
                          ? null
                          : () => _confirmRemoveSignal(signal),
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
                // Report (master spec §18.1). Only for other people's signals —
                // the author has edit and delete, and "report my own signal" is
                // a support request, not a moderation one.
                //
                // This is the affordance `faqReportInappropriateAnswer` has been
                // pointing users at since before it existed.
                if (!isAuthor)
                  Semantics(
                    label: l10n.reportSignal,
                    button: true,
                    enabled: true,
                    child: IconButton(
                      icon: const Icon(Icons.flag_outlined),
                      onPressed: () => showReportDialog(
                        context,
                        target: ReportTarget.signal(
                          signalId: widget.signalId,
                          collection:
                              AppPreferencesService().signalsCollectionName,
                          reportedUserId: signal.reporter.id,
                        ),
                      ),
                    ),
                  ),
                // Act on your own judgement (master spec §18.3). Until this
                // existed a moderator could only touch content somebody had
                // already *reported* — the action sheet's only entry point was
                // the report queue — so a problem post found while browsing had
                // to be reported first, by the moderator, to themselves.
                //
                // Beside the report flag rather than replacing it: reporting
                // and moderating are different acts, and a moderator may well
                // want the report on record for whoever holds the queue.
                //
                // Not for your own signal. That is enforced server-side (see
                // `loadSignal` in functions/src/moderation.ts); hiding the icon
                // just means nobody meets the error.
                if (!isAuthor && _isModerator)
                  Semantics(
                    label: l10n.moderationActionsLabel,
                    button: true,
                    enabled: true,
                    child: IconButton(
                      icon: const Icon(Icons.shield_outlined),
                      onPressed: () => _openSignalModeration(signal),
                    ),
                  ),
              ]),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    // A Column, not a Stack. The composer used to be
                    // Positioned(bottom: 0) over the same scroll view, with no
                    // bottom padding underneath it, so it permanently hid the
                    // last ~90px of the page — and more at larger text sizes,
                    // where it swallowed the whole "Red — immediate critical
                    // help" option. Making it a sibling means the overlap
                    // cannot come back, and no padding constant has to track
                    // the composer's height.
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: <Widget>[
                            // A moderator's warning label (§18.3). Above the
                            // photos on purpose: the whole point of "possible
                            // duplicate" or "disputed" is to be read *before* the
                            // content it qualifies, not after scrolling past it.
                            _moderationLabelBanner(signal, l10n),
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
                                                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: Theme.of(context).colorScheme.primary,
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
                                                            ),
                                                            const SizedBox(height: 16),
                                                            Text(
                                                              l10n.uploadingPhoto,
                                                              style: TextStyle(
                                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                                fontSize: 14,
                                                              ),
                                                            ),
                                                          ],
                                                        )
                                                      : Column(
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          children: [
                                                            Icon(
                                                              Icons.add_photo_alternate,
                                                              size: 48,
                                                              color: Theme.of(context).colorScheme.primary,
                                                            ),
                                                            const SizedBox(height: 8),
                                                            Text(
                                                              signal.photoUrls.isEmpty ? l10n.addPhoto : l10n.addAnotherPhoto,
                                                              style: TextStyle(
                                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                                fontSize: 16,
                                                                fontWeight: FontWeight.bold,
                                                              ),
                                                            ),
                                                            const SizedBox(height: 4),
                                                            Text(
                                                              l10n.photosCount(signal.photoUrls.length, 5),
                                                              style: TextStyle(
                                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                                                      child: const Center(
                                                        child: CircularProgressIndicator(),
                                                      ),
                                                    ),
                                                    errorWidget: (context, url, error) => Container(
                                                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                                                      child: Center(
                                                        child: Column(
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          children: [
                                                            Icon(Icons.broken_image, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                                            const SizedBox(height: 8),
                                                            Text(l10n.failedToLoadImage,
                                                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                                                        icon: const Icon(Icons.delete, color: Colors.white),  // theme-independent: over a photo
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
                                                        color: Colors.white,  // theme-independent: over a photo
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
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .outline,
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
                                  // Colours come from elevatedButtonTheme.
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
                                    // Colours come from elevatedButtonTheme.
                                  ),
                              ],
                            ),
                            Text(' ${l10n.urgency}'),
                            // Master spec §5.2 restricts marking a case Red to
                            // "the original poster/case holder, a moderator or an
                            // admin". Until case ownership existed the reporter
                            // was the whole of that set by default; now the case
                            // holder is in it too, which is the spec being
                            // implemented rather than the rule being relaxed.
                            //
                            // A moderator does NOT reach it here: they use the
                            // shield in the app bar, which routes through the
                            // `moderateAction` callable so the correction is
                            // audited and carries a note (§5.3).
                            //
                            // `isCaseHolderUpdate` enforces the same line, so
                            // hiding this picker is UI courtesy, not the security
                            // boundary. Everyone else sees the level read-only.
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: canCoordinate
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
                            // What the signal needs. Master spec §4.2: "as needs
                            // are resolved, the case holder removes/completes tags
                            // and the next priority becomes active" — so the
                            // holder edits these here, rather than through the
                            // edit screen, which carries the reporter's own
                            // account of what they saw and stays theirs.
                            //
                            // Signals from before tags existed have none, so the
                            // block is omitted rather than showing an empty
                            // heading — but a coordinator still needs a way to add
                            // the first one, which is why the edit affordance is
                            // not inside the `if`.
                            if (signal.helpNeededTags.isNotEmpty ||
                                signal.animalType != null ||
                                canCoordinate) ...[
                              const SizedBox(height: 8),
                              // Only when there is actually a need to head. A
                              // signal with a species and no tags (legacy, or
                              // edited by an older build) would otherwise read
                              // "Help needed" above a lone Cat chip.
                              if (signal.helpNeededTags.isNotEmpty ||
                                  canCoordinate)
                                Row(
                                  children: [
                                    Text(' ${l10n.helpNeeded}'),
                                    const Spacer(),
                                    if (canCoordinate)
                                      TextButton.icon(
                                        icon: const Icon(Icons.edit, size: 16),
                                        label: Text(l10n.change),
                                        onPressed: _isApplyingLevelChange
                                            ? null
                                            : () => _editHelpTags(signal),
                                      ),
                                  ],
                                ),
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
                            // Who is responsible, immediately above the control
                            // that responsibility gates. The holder is *who*, the
                            // status is *how far along*, and putting them next to
                            // each other is what makes "take responsibility, then
                            // move it" read as one idea rather than two.
                            CaseHolderBlock(
                              signal: signal,
                              signalId: widget.signalId,
                              uid: uid,
                              busy: _isApplyingLevelChange,
                              runGuarded: _runGuarded,
                              nameOf: _nameWidget,
                              onClaim: _claimCase,
                              onSignInRequired: _showSignInDialog,
                            ),
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
                                            // A neutral glyph, not a map pin and
                                            // not a coloured dot: colour is the
                                            // urgency vocabulary, and status
                                            // borrowing it put two traffic
                                            // lights with opposite meanings on
                                            // the same screen.
                                            Padding(
                                              padding: const EdgeInsets.all(12.0),
                                              child: Icon(status.icon, size: 20),
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
                                              signal, signal.status, value);
                                        }
                                      },
                            ),
                            _buildSignalHistory(signal, dateFormat),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.shadow
                                .withAlpha(40),
                            blurRadius: 5.0,
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        // A moderator has locked comments (§18.3). The
                        // composer is replaced rather than merely disabled:
                        // a greyed-out field invites people to keep tapping
                        // it, while a sentence explains what happened. The
                        // rules deny the write regardless — this is the
                        // courtesy, not the enforcement.
                        child: signal.commentsLocked
                            ? Row(
                                children: [
                                  Icon(Icons.lock_outline,
                                      size: 20,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      l10n.moderationCommentsLocked,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Row(
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
          itemBuilder: (context, index) => _buildHistoryRow(
            entries[index],
            dateFormat,
            // Computed once for the whole list rather than per row. A moderator
            // may not act on comments under their OWN signal — deleting the
            // comment criticising your case is the conflict of interest the
            // server's `requireNotOwnContent` refuses — so on your own signal
            // the rows behave exactly as they do for everybody else.
            canModerateComments: _isModerator && !_isUserAuthor(signal),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryRow(
    SignalHistoryEntry entry,
    DateFormat dateFormat, {
    required bool canModerateComments,
  }) =>
      switch (entry.kind) {
        SignalHistoryKind.created => _buildCreatedRow(entry, dateFormat),
        SignalHistoryKind.statusChange ||
        SignalHistoryKind.urgencyChange =>
          _buildEventRow(entry, dateFormat),
        SignalHistoryKind.ownershipTransfer =>
          _buildOwnershipRow(entry, dateFormat),
        SignalHistoryKind.comment => _buildCommentRow(
            entry,
            dateFormat,
            canModerateComments: canModerateComments,
          ),
      };

  /// "Ownership history is visible in the case timeline" (master spec §4.5).
  ///
  /// Three sentences from one event, told apart by who the actor and the new
  /// holder are — which is the whole reason the event stores both rather than
  /// just the new one:
  ///
  ///  * no new holder → the holder stepped down;
  ///  * the actor IS the new holder → they took the case on themselves;
  ///  * otherwise → the previous holder handed it to someone.
  ///
  /// The previous holder stays visible because the row above it in the thread is
  /// theirs — the spec's "previous case holders remain visible" is satisfied by
  /// the timeline being a thread, with no per-row restatement.
  Widget _buildOwnershipRow(SignalHistoryEntry entry, DateFormat dateFormat) {
    final l10n = AppLocalizations.of(context);
    final holderId = entry.holderId;

    final Widget sentence;
    if (holderId == null) {
      sentence = _actorText(
        entry.actorId,
        (name) => l10n.releasedCase(name),
        fallback: l10n.someone,
      );
    } else if (holderId == entry.actorId) {
      sentence = _actorText(
        entry.actorId,
        (name) => l10n.tookResponsibility(name),
        fallback: l10n.someone,
      );
    } else {
      // Two names in one sentence, which is the one case `_actorText` cannot
      // serve — it resolves a single uid. Memoized as a *pair*, not just built
      // from two memoized halves: `FutureBuilder` compares futures by identity,
      // so a fresh `Future.wait` each build restarts it at `waiting` and the
      // sentence collapses to zero height for a frame. This screen rebuilds on
      // every signal, comment and event snapshot, so that was every row
      // flickering on each one.
      sentence = FutureBuilder<List<String?>>(
        future: _namePairFor(entry.actorId, holderId),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox.shrink();
          }
          final names = snapshot.data ?? const [null, null];
          final actorName =
              (names[0]?.isNotEmpty ?? false) ? names[0]! : l10n.someone;
          // Same fallback as the actor above — one sentence should not mix
          // "Someone" and "Unknown" for two people in the same position.
          final holderName =
              (names[1]?.isNotEmpty ?? false) ? names[1]! : l10n.someone;
          return Text(l10n.handedCaseTo(actorName, holderName));
        },
      );
    }

    return ListTile(
      title: _historyCard(
        // The same blue the case-holder block uses, so a transfer reads as
        // belonging to that part of the screen rather than to the orange
        // status/urgency events.
        background: Colors.blue.shade50,
        border: Colors.blue.shade200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  holderId == null
                      ? Icons.person_off_outlined
                      : Icons.volunteer_activism,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(child: sentence),
              ],
            ),
            if (entry.note case final note? when note.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(note),
            ],
          ],
        ),
      ),
      // The same subtitle slot every other history row uses, so the timeline's
      // dates stay in one column and `_formatDate` remains the single place a
      // change to date presentation has to be made.
      subtitle: _dateSubtitle(entry, dateFormat),
    );
  }

  /// The row every timeline opens with. Not stored — see
  /// [SignalHistoryEntry.created].
  Widget _buildCreatedRow(SignalHistoryEntry entry, DateFormat dateFormat) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: _historyCard(
        background: Theme.of(context).colorScheme.surfaceContainer,
        border: Theme.of(context).colorScheme.outline,
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
        background: Theme.of(context).colorScheme.primaryContainer,
        border: Theme.of(context).colorScheme.primary,
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

  /// Opens the moderator action sheet for this signal.
  ///
  /// The parsed [signal] is handed over so the sheet does not re-read a
  /// document this screen is already displaying — it needs `commentsLocked` and
  /// the label to point its toggles the right way.
  Future<void> _openSignalModeration(Signal signal) async {
    final outcome = await showModerationActionSheet(
      context,
      target: ModerationTarget.signal(
        signalId: widget.signalId,
        collection: AppPreferencesService().signalsCollectionName,
      ),
      signal: signal,
    );
    if (!mounted) return;
    // Hiding moves the document out of `signals` entirely, so the stream behind
    // this screen has just gone empty. Leaving is not cosmetic: the empty
    // branch in build() would otherwise tell the moderator the signal was
    // *deleted*, which is both wrong and the opposite of the reversible thing
    // they just did. `_leaveScreen` also handles the cold-deep-link case, where
    // there is nothing to pop back to.
    if (outcome == ModerationOutcome.targetRemoved) _leaveScreen();
  }

  /// What a long-press on someone else's comment offers a moderator.
  ///
  /// A chooser rather than going straight to one or the other, because both
  /// remain meaningful: reporting puts the comment in the queue for whoever is
  /// on duty, while deleting is the moderator acting now. Ordinary users never
  /// see this — for them the long-press goes straight to the report dialog, as
  /// it always has.
  Future<void> _showCommentModeratorMenu(SignalHistoryEntry entry) async {
    final l10n = AppLocalizations.of(context);
    final collection = AppPreferencesService().signalsCollectionName;

    final moderate = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SectionHeader(l10n.moderationCommentChooserTitle),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(l10n.reportComment),
              onTap: () => Navigator.of(context).pop(false),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.moderationDeleteComment),
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
    if (!mounted || moderate == null) return;

    if (moderate) {
      // Through the same sheet as everything else, so the mandatory note and
      // the audit entry cannot be skipped just because this route is shorter.
      await showModerationActionSheet(
        context,
        target: ModerationTarget.comment(
          commentId: entry.id,
          signalId: widget.signalId,
          collection: collection,
        ),
      );
    } else {
      await showReportDialog(
        context,
        target: ReportTarget.comment(
          commentId: entry.id,
          signalId: widget.signalId,
          collection: collection,
          reportedUserId: entry.actorId,
        ),
      );
    }
  }

  Widget _buildCommentRow(
    SignalHistoryEntry entry,
    DateFormat dateFormat, {
    required bool canModerateComments,
  }) {
    final l10n = AppLocalizations.of(context);
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    // Reporting your own comment is meaningless; deleting it is what you want,
    // and that is the reporter's cascade or a moderator's job.
    final canReport = currentUid != null && entry.actorId != currentUid;
    return ListTile(
      // Long-press rather than a per-row menu button: a comment list with a
      // trailing overflow icon on every row reads as an admin tool, and the
      // rows are already dense. Long-press is the platform gesture for "more
      // about this item" and costs no layout.
      //
      // A moderator gets a chooser here instead of going straight to the report
      // dialog, which is how they act on a comment without waiting for somebody
      // to report it first. The gesture is deliberately the same one — adding a
      // visible moderator control per row would turn the list into the admin
      // tool the comment above rules out.
      onLongPress: !canReport
          ? null
          : canModerateComments
              ? () => _showCommentModeratorMenu(entry)
              : () => showReportDialog(
                    context,
                    target: ReportTarget.comment(
                      commentId: entry.id,
                      signalId: widget.signalId,
                      collection:
                          AppPreferencesService().signalsCollectionName,
                      reportedUserId: entry.actorId,
                    ),
                  ),
      title: _historyCard(
        background: Theme.of(context).colorScheme.surface,
        border: Theme.of(context).colorScheme.outline,
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

  /// The moderator's warning label, or nothing when there isn't one.
  ///
  /// An unrecognised code renders as nothing rather than as raw text — see
  /// [ModerationLabel.fromCode] for why that is the right failure.
  Widget _moderationLabelBanner(Signal signal, AppLocalizations l10n) {
    final text = signal.moderationLabel?.label(l10n);
    if (text == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade700),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 20, color: Colors.amber.shade900),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.amber.shade900,
                fontWeight: FontWeight.w600,
              ),
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
    _roleSub?.cancel();
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

  /// Both names for a row that names two people, as one stable future.
  ///
  /// Composed from [_nameFor], so the underlying reads stay memoized per uid and
  /// shared with every other row; this memo exists only so the *combined* future
  /// keeps its identity across rebuilds.
  Future<List<String?>> _namePairFor(String first, String second) =>
      _namePairFutures['$first|$second'] ??=
          Future.wait([_nameFor(first), _nameFor(second)]);

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

  /// Move the signal's status, taking responsibility for it first if needed.
  ///
  /// **Claim-to-act** (master spec §4.5, "the current case holder can update
  /// status"). Before case ownership, any signed-in user could move any
  /// stranger's signal to Resolved with nothing recording that they had taken
  /// it on. Now a bystander who wants to move a case is asked to take it on —
  /// one confirmation, one note, one write. The status dropdown stays visible
  /// and enabled for everyone, because hiding it would leave a volunteer with no
  /// way to discover that taking the case on is what unlocks it.
  Future<void> _updateSignalStatus(
      Signal signal, int oldStatus, int newStatus) async {
    final status = SignalStatus.fromCode(newStatus);

    if (!signal.canCoordinate(FirebaseAuth.instance.currentUser?.uid)) {
      await _claimCase(newStatus: newStatus);
      return;
    }

    await _applyLevelChange(
      eventType: SignalEventType.statusChange,
      oldValue: oldStatus,
      newValue: newStatus,
      levelLabel: status.label(AppLocalizations.of(context)),
      levelBadge: statusBadge(status),
      errorText: (l10n) => l10n.errorUpdatingStatus,
    );
  }

  // -------------------------------------------------------------------------
  // Case ownership (master spec §4.5). Every one of these goes through the
  // `caseOwnership` callable — the client cannot write `caseHolder`, by rule.
  // -------------------------------------------------------------------------

  /// Take responsibility for a case, optionally moving its status in the same
  /// The flag's whole job is to stop a second change landing on top of one
  /// already in flight, and it is deliberately **one flag for every path** — a
  /// claim can carry a status change, so separate guards would let one tap
  /// through each of them. Owning the `setState`/`finally` pair here means a new
  /// path cannot half-implement it; a missed `if (mounted)` in the `finally`
  /// leaves every control on this screen permanently disabled, which is a bug
  /// this file has been fixed for before.
  Future<void> _runGuarded(Future<void> Function() body) async {
    if (_isApplyingLevelChange) return;
    setState(() => _isApplyingLevelChange = true);
    try {
      await body();
    } finally {
      if (mounted) setState(() => _isApplyingLevelChange = false);
    }
  }

  /// Change what the case needs (master spec §4.2).
  ///
  /// An ordinary field write on the holder branch, not an ownership change — it
  /// travels through `isCaseHolderUpdate()` like a status change does, and needs
  /// no callable.
  Future<void> _editHelpTags(Signal signal) async {
    final selected = await showHelpTagPicker(
      context,
      initial: HelpTag.fromCodes(signal.helpNeededTags),
    );
    if (selected == null || !mounted || _isApplyingLevelChange) return;

    await _runGuarded(() async {
      try {
        await _signalRef.update({
          'helpNeededTags': selected.map((t) => t.code).toList(),
          // The shared stamp, so this write cannot forget the holder's proof of
          // life the way the edit screen once did.
          ...CaseOwnershipService.coordinationStamp(_userRef),
        });
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).errorUpdatingStatus),
          ),
        );
      }
    });
  }

  /// Take responsibility for a case, optionally moving its status with it.
  ///
  /// Lives here rather than in [CaseHolderBlock] because the **status dropdown**
  /// shares it: choosing a status you are not entitled to set offers to claim
  /// first, and that has to be the same flow as pressing the button in the
  /// block, or the two ways of taking a case on write different history.
  ///
  /// [newStatus] arrives from the dropdown on that path. The server applies both
  /// in one batch, which is what lets one note explain both and stops a failed
  /// second write leaving someone owning a case they only meant to update.
  Future<void> _claimCase({int? newStatus}) async {
    final l10n = AppLocalizations.of(context);
    final note = await askOwnershipNote(
      context,
      title: l10n.takeoverConfirmTitle,
      body: l10n.takeoverConfirmBody,
      confirmLabel: l10n.takeoverConfirmAction,
      // The claim-with-status path changes two things at once and the note
      // explains both, so the headline has to name both — naming only the
      // ownership change left the status the user picked unmentioned anywhere.
      noteHeadline: newStatus == null
          ? l10n.updateNoteTakingCase
          : l10n.updateNoteTakingCaseAndChangingTo(
              SignalStatus.fromCode(newStatus).label(l10n),
            ),
      busy: _isApplyingLevelChange,
      onSignInRequired: _showSignInDialog,
      canModifyData: RepositoryProvider.instance.userRepository.canModifyData,
    );
    if (note == null || !mounted) return;

    await runOwnershipChange(
      context,
      _runGuarded,
      () => CaseOwnershipService.instance.claim(
        signalId: widget.signalId,
        note: note,
        newStatus: newStatus,
      ),
    );
  }

  /// [CaseHolderBlock]'s name renderer, adapting [_actorText] so the block
  /// shares this screen's memoized `publicProfiles` cache rather than starting
  /// a second one.
  Widget _nameWidget(
    String uid, {
    required String fallback,
    TextStyle? style,
    int? maxLines,
  }) =>
      _actorText(
        uid,
        (name) => name,
        fallback: fallback,
        style: style,
        maxLines: maxLines,
      );

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
    required LevelEventType eventType,
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
      headline: AppLocalizations.of(context).updateNoteChangingTo(levelLabel),
      badge: levelBadge,
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
      // `lastUpdatedBy` plus the holder's proof of life, from the one helper
      // that defines what a coordination write carries — see its doc comment for
      // what each is load-bearing for.
      ...CaseOwnershipService.coordinationStamp(userRef),
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

  /// Take a signal down — the author's own "delete", made recoverable (#68).
  ///
  /// Two dialogs, and the first one exists because of what people were actually
  /// using Delete for. A reporter whose animal has been helped reaches for
  /// Delete rather than Resolved: the case is finished, so the post feels like
  /// clutter. That silently threw away the outcome other people could have
  /// learned from, and — until statistics moved off the live collection — the
  /// credit for having reported it. So an OPEN case is asked the question
  /// first, with Resolved as the primary action; an already-resolved one goes
  /// straight to the removal confirmation and is not nagged.
  ///
  /// The removal itself is one call to `signalRemoval`. Everything the old
  /// client-side cascade did — the photos, the three subcollections, the
  /// document — now happens server-side, which is what lets the rules stop
  /// granting the reporter deletes on `comments`, `events` and
  /// `takeoverRequests`. See `SignalRemovalService`.
  Future<void> _confirmRemoveSignal(Signal signal) async {
    final l10n = AppLocalizations.of(context);

    if (SignalStatus.fromCode(signal.status).isOpen) {
      final choice = await showDialog<_RemoveChoice>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.removeSignalCaseOpenTitle),
          content: Text(l10n.removeSignalCaseOpenBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _RemoveChoice.remove),
              child: Text(l10n.removeAnyway),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, _RemoveChoice.resolve),
              child: Text(l10n.markAsResolved),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == _RemoveChoice.resolve) {
        // Reuses the ordinary status path, so this asks for the same mandatory
        // update note and offers claim-to-act exactly as the dropdown does.
        // Resolving from here must not produce a different kind of history
        // from resolving the normal way.
        await _updateSignalStatus(
          signal,
          signal.status,
          SignalStatus.resolved.code,
        );
        return;
      }
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.removeSignal),
        content: Text(l10n.confirmRemoveSignal(RemovedSignal.retentionDays)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.remove),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    // Re-checked after the dialogs, not just on the button: the taps that open
    // them are cheap, and two dialogs is plenty of time for a first removal to
    // still be in flight behind them.
    if (_isRemoving) return;
    setState(() => _isRemoving = true);

    // Claim the exit before the call, not after it (R6-002). The reason has
    // changed but not gone away: the local cache no longer applies a delete
    // instantly — the server does the write — but the still-live listener does
    // report the document missing the moment that lands, and the "deleted while
    // you were reading it" branch would then pop a route of its own and replace
    // the message below with the *other* user's "no longer available".
    _hasNavigatedAway = true;
    try {
      await _removalService.remove(widget.signalId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.signalRemovedSuccessfully),
          backgroundColor: Colors.green,
        ),
      );
      _leaveScreen();
    } catch (e) {
      // Still there, so give the exit claim back.
      _hasNavigatedAway = false;
      if (!mounted) return;
      // `failed-precondition` is the one refusal worth explaining: the signal
      // has an open report against it, so withdrawing it would take the
      // evidence out from under the moderator looking at it. Anything else is
      // a generic failure the user can only retry.
      final message = e is CallableException && e.code == 'failed-precondition'
          ? l10n.signalUnderReview
          : l10n.failedToRemoveSignal;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } finally {
      // Irrelevant on success — the screen is gone — and load-bearing on
      // failure: without it the button stays disabled for good and the user
      // cannot retry. The `mounted` check is the one this file has been fixed
      // for before; missing it leaves the control permanently dead.
      if (mounted) setState(() => _isRemoving = false);
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
                leading: Icon(Icons.camera_alt, color: Theme.of(context).colorScheme.primary),
                title: Text(l10n.takePhoto),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: Theme.of(context).colorScheme.primary),
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
      backgroundColor: Colors.black,  // theme-independent: fullscreen photo viewer
      body: Stack(
        children: [
          PhotoViewGallery.builder(  // theme-independent: fullscreen photo viewer
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
                        const Icon(Icons.broken_image, size: 64, color: Colors.white),  // theme-independent: fullscreen photo viewer
                        const SizedBox(height: 16),
                        Text(
                          l10n.failedToLoadImage,  // theme-independent: fullscreen photo viewer
                          style: const TextStyle(color: Colors.white),  // theme-independent: fullscreen photo viewer
                        ),
                      ],
                    ),  // theme-independent: fullscreen photo viewer
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
              color: Colors.black,  // theme-independent: fullscreen photo viewer
            ),
            loadingBuilder: (context, event) {
              return Center(  // theme-independent: fullscreen photo viewer
                child: CircularProgressIndicator(
                  value: event == null
                      ? 0
                      : event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1),
                  color: Colors.white,  // theme-independent: fullscreen photo viewer
                ),
              );
            },  // theme-independent: fullscreen photo viewer
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
                      icon: const Icon(Icons.close, color: Colors.white, size: 30),  // theme-independent: fullscreen photo viewer
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),  // theme-independent: fullscreen photo viewer
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
                      color: Colors.white,  // theme-independent: fullscreen photo viewer
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),  // theme-independent: fullscreen photo viewer
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
/// What the resolve-first dialog came back with.
///
/// An enum rather than a nullable bool because there are genuinely three
/// answers — mark it Resolved, remove it anyway, and dismissed — and `null`
/// already carries the third. See [_SignalDetailsScreenState._confirmRemoveSignal].
enum _RemoveChoice { resolve, remove }

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
