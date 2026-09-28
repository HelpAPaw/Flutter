import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';

import '../config/routes.dart';
import '../repositories/signal_repository.dart';
import '../services/app_preferences_service.dart';
import '../services/user_activity_service.dart';
import '../utils/error_text.dart';
import '../utils/nav_extensions.dart';
import 'app_bar_title.dart';
import 'escape_leading.dart';
import 'page_width.dart';
import 'signal_list_tile.dart';
import 'status_view.dart';

/// The list behind one of a profile's numbers: the signals someone reported,
/// the ones they are helping with now, or the comments they wrote.
///
/// The same screen for your own profile and for anybody else's — every query
/// in [UserActivityService] is one any signed-in session may already run, so
/// there is nothing here that needs to know whose list it is.
class UserActivityPage extends StatefulWidget {
  const UserActivityPage({super.key, required this.uid, required this.kind});

  final String uid;
  final UserActivityKind kind;

  @override
  State<UserActivityPage> createState() => _UserActivityPageState();
}

class _UserActivityPageState extends State<UserActivityPage> {
  late UserActivityService _service = _newService();

  /// [SignalWithId] for the two signal lists, [AuthoredComment] for comments.
  List<Object> _items = const [];
  DocumentSnapshot? _cursor;
  bool _hasMore = false;

  /// Whether a first load has ever finished — see `UserProfilePage._loaded`.
  bool _loaded = false;
  bool _loadingMore = false;
  bool _failed = false;

  UserActivityService _newService() => UserActivityService(
        collection: AppPreferencesService().signalsCollectionName,
        uid: widget.uid,
      );

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<({List<Object> items, DocumentSnapshot? cursor, bool hasMore})>
      _fetch(DocumentSnapshot? after) async {
    switch (widget.kind) {
      case UserActivityKind.signals:
        final page = await _service.signals(after: after);
        return (items: page.items, cursor: page.cursor, hasMore: page.hasMore);
      case UserActivityKind.helping:
        return (items: await _service.helping(), cursor: null, hasMore: false);
      case UserActivityKind.comments:
        final page = await _service.comments(after: after);
        return (items: page.items, cursor: page.cursor, hasMore: page.hasMore);
    }
  }

  Future<void> _reload() async {
    // A fresh service, so a refresh re-reads the parent signals too rather
    // than trusting a cache that may still hold one since removed.
    _service = _newService();
    try {
      final page = await _fetch(null);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _failed = false;
        _loaded = true;
      });
    } catch (error, stack) {
      reportError(error, stack, where: 'userActivity.${widget.kind.name}');
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loaded = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetch(_cursor);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _cursor = page.cursor;
        _hasMore = page.hasMore;
      });
    } catch (error, stack) {
      reportError(error, stack, where: 'userActivity.${widget.kind.name}.more');
      if (!mounted) return;
      // The rows already on screen are still good, so a failed page is a
      // message and a button that still works, not an error screen.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).activityCouldNotLoad),
      ));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _title(AppLocalizations l10n) => switch (widget.kind) {
        UserActivityKind.signals => l10n.signals,
        UserActivityKind.helping => l10n.helpingNow,
        UserActivityKind.comments => l10n.comments,
      };

  /// Why the list can be shorter than the number that opened it. None for
  /// "Helping now": that list and its count are the same query.
  String? _gapNote(AppLocalizations l10n) => switch (widget.kind) {
        UserActivityKind.signals => l10n.activityRemovedSignalsNote,
        UserActivityKind.helping => null,
        UserActivityKind.comments => l10n.activityRemovedCommentsNote,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: escapeLeading(
          context,
          label: l10n.back,
          onLeave: () => context.popOrHome(),
        ),
        title: AppBarTitle(_title(l10n)),
      ),
      body: PageWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: _body(context, l10n),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    // Every state is a scrollable, so pull-to-refresh works from all of them —
    // including the error and empty states, which are where it is wanted most.
    Widget scrollable(Widget child) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [child],
        );

    if (!_loaded) {
      return scrollable(const Padding(
        padding: EdgeInsets.only(top: 64),
        child: Center(child: CircularProgressIndicator()),
      ));
    }

    if (_failed) {
      return scrollable(StatusView.error(
        title: l10n.activityCouldNotLoad,
        hint: l10n.couldNotLoadSignalsHint,
        onRetry: () {
          setState(() => _loaded = false);
          _reload();
        },
      ));
    }

    final note = _gapNote(l10n);

    if (_items.isEmpty && !_hasMore) {
      return scrollable(switch (widget.kind) {
        UserActivityKind.signals => StatusView.empty(
            icon: Icons.pin_drop_outlined,
            title: l10n.noSignalsYet,
            hint: note,
          ),
        UserActivityKind.helping => StatusView.empty(
            icon: Icons.volunteer_activism_outlined,
            title: l10n.activityNothingHelpingNow,
          ),
        UserActivityKind.comments => StatusView.empty(
            icon: Icons.comment_outlined,
            title: l10n.activityNoCommentsYet,
            hint: note,
          ),
      });
    }

    // One trailing slot: "Load more" while there is more, the note once the
    // end is reached — that is the moment the reader can compare the two.
    final trailing = _hasMore || note != null;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _items.length + (trailing ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return _hasMore ? _loadMoreButton(l10n) : _noteText(context, note!);
        }
        final item = _items[index];
        return switch (item) {
          SignalWithId entry => SignalListTile(
              signal: entry.signal,
              onTap: () => context.push(Routes.signalDetails(entry.id)),
            ),
          AuthoredComment comment => _CommentTile(comment: comment),
          _ => const SizedBox.shrink(),
        };
      },
    );
  }

  Widget _loadMoreButton(AppLocalizations l10n) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _loadingMore
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  onPressed: _loadMore,
                  child: Text(l10n.loadMore),
                ),
        ),
      );

  Widget _noteText(BuildContext context, String note) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Text(
        note,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// One comment, with the signal it was written on underneath. Opens the
/// signal — the comment only makes sense in its thread.
class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final AuthoredComment comment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final createdAt = comment.createdAt;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: () => context.push(Routes.signalDetails(comment.signal.id)),
        title: Text(
          comment.text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Icon(comment.signal.signal.primaryTag.icon,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  comment.signal.signal.displayTitle(l10n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                createdAt != null
                    ? SignalListTile.formatDate(context, createdAt)
                    : l10n.unknownDate,
                style: muted,
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
