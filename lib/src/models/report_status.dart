/// Lifecycle of a report (master spec §18).
///
/// [code] is the value persisted in `reports/{id}.status`. It is a **stable,
/// opaque identifier** — never rename or reuse one.
///
/// **This one is guarded, unlike the action names, because it is a query
/// filter.** The moderation queue lists reports `where('status', isEqualTo:
/// open)`. If the client's spelling and the server's terminal spellings ever
/// disagree, nothing errors: either handled reports never leave the queue, or
/// filed reports never enter it, and the first anyone knows is a moderator
/// asking why a report they resolved keeps coming back. Compare the eight
/// action names, whose drift fails loudly with `invalid-argument` and which
/// therefore need no enum.
///
/// The server copy is `OUTCOMES` in `functions/src/moderation.ts` (the two
/// terminal states only — `open` is client-written and server-read). Guarded by
/// `test/report_status_vocabulary_guard_test.dart`.
enum ReportStatus {
  /// Awaiting a moderator. The only status a client may write.
  open(code: 'open'),

  /// A moderator acted on the content.
  actioned(code: 'actioned'),

  /// A moderator judged the report not to need action.
  dismissed(code: 'dismissed');

  const ReportStatus({required this.code});

  /// Stable identifier persisted in Firestore. Never change or reuse.
  final String code;

  /// Whether this is a terminal state, i.e. one only the server may write.
  bool get isTerminal => this != ReportStatus.open;

  static ReportStatus? fromCode(String? code) {
    if (code == null) return null;
    for (final status in values) {
      if (status.code == code) return status;
    }
    return null;
  }
}
