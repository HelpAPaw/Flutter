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
  /// Replaced on every [_reload] — see there.
  late UserActivityService _service;

  /// [SignalWithId] for the two signal lists, [AuthoredComment] for comments.
  List<Object> _items = const [];
  DocumentSnapshot? _cursor;
  bool _hasMore = false;

  /// Whether a first load has ever finished — see `UserProfilePage._loaded`.
  bool _loaded = false;
  bool _loadingMore = false;
  bool _failed = false;

  /// Bumped by every [_reload], so a "Load more" still in flight when the
  /// list is refreshed is dropped instead of appended to the new first page —
  /// its cursor belongs to the list that was just thrown away.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<ActivityPage<Object>> _fetch(DocumentSnapshot? after) =>
      switch (widget.kind) {
        UserActivityKind.signals => _service.signals(after: after),
        UserActivityKind.helping => _service.helping(),
        UserActivityKind.comments => _service.comments(after: after),
      };

  Future<void> _reload() async {
    final generation = ++_generation;
    // A fresh service, so a refresh re-reads the parent signals too rather
    // than trusting a cache that may still hold one since removed.
    _service = UserActivityService(
      collection: AppPreferencesService().signalsCollectionName,
      uid: widget.uid,
    );
    try {
      final page = await _fetch(null);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = page.items;
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _failed = false;
        _loaded = true;
        _loadingMore = false;
      });
    } catch (error, stack) {
      reportError(error, stack, where: 'userActivity.${widget.kind.name}');
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _loaded = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetch(_cursor);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = [..._items, ...page.items];
        _cursor = page.cursor;
        _hasMore = page.hasMore;
      });
    } catch (error, stack) {
      reportError(error, stack, where: 'userActivity.${widget.kind.name}.more');
      if (!mounted || generation != _generation) return;
      // The rows already on screen are still good, so a failed page is a
      // message and a button that still works, not an error screen.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).activityCouldNotLoad),
      ));
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingMore = false);
      }
    }
  }

  /// Everything about the screen that depends on which list it is.
  ///
  /// [note] is why the list can be shorter than the number that opened it —
  /// none for "Helping now", whose list and count are the same query.
  ({String title, IconData emptyIcon, String emptyTitle, String? note})
      _copy(AppLocalizations l10n) => switch (widget.kind) {
            UserActivityKind.signals => (
                title: l10n.signals,
                emptyIcon: Icons.pin_drop_outlined,
                emptyTitle: l10n.noSignalsYet,
                note: l10n.activityRemovedSignalsNote,
              ),
            UserActivityKind.helping => (
                title: l10n.helpingNow,
                emptyIcon: Icons.volunteer_activism_outlined,
                emptyTitle: l10n.activityNothingHelpingNow,
                note: null,
              ),
            UserActivityKind.comments => (
                title: l10n.comments,
                emptyIcon: Icons.comment_outlined,
                emptyTitle: l10n.activityNoCommentsYet,
                note: l10n.activityRemovedCommentsNote,
              ),
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
        title: AppBarTitle(_copy(l10n).title),
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

    final copy = _copy(l10n);
    final note = copy.note;

    if (_items.isEmpty && !_hasMore) {
      return scrollable(StatusView.empty(
        icon: copy.emptyIcon,
        title: copy.emptyTitle,
        hint: note,
      ));
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
        onTap: () => context.push(
            Routes.signalDetails(comment.signal.id, commentId: comment.id)),
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
