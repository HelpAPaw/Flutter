import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/src/models/signal_event.dart';
import 'package:help_a_paw/src/models/signal.dart';
import 'package:help_a_paw/src/models/signal_urgency.dart';
import 'package:help_a_paw/src/services/app_preferences_service.dart';
import 'package:help_a_paw/src/services/case_ownership_service.dart';
import 'package:help_a_paw/src/models/help_tag.dart';
import 'package:help_a_paw/src/widgets/help_tag_selector.dart';
import 'package:help_a_paw/src/widgets/level_badge.dart';
import 'package:help_a_paw/src/widgets/section_header.dart';
import 'package:help_a_paw/src/widgets/update_note_dialog.dart';
import 'package:help_a_paw/src/widgets/urgency_picker.dart';
import 'app_bar_title.dart';

class EditSignalScreen extends StatefulWidget {
  const EditSignalScreen({
    super.key,
    required this.signalId,
  });

  final String signalId;

  @override
  State<EditSignalScreen> createState() => _EditSignalScreenState();
}

class _EditSignalScreenState extends State<EditSignalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _phoneController = TextEditingController();
  int _urgency = SignalUrgency.amber.code;

  List<String> _helpTags = const [];
  String? _animalType;

  /// Urgency as loaded, so a save can tell whether it actually changed and
  /// record a timeline entry to match the details screen.
  int _originalUrgency = SignalUrgency.amber.code;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSignal();
  }

  Future<void> _loadSignal() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(AppPreferencesService().signalsCollectionName)
          .doc(widget.signalId)
          .get();

      if (!mounted) return;

      if (doc.exists) {
        final signal = Signal.fromJson(doc.data()!);
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null || signal.reporter.id != currentUser.uid) {
          if (mounted) context.pop();
          return;
        }
        _titleController.text = signal.title;
        _descriptionController.text = signal.description;
        _phoneController.text = signal.contactPhone;
        _urgency = signal.urgency;
        _originalUrgency = signal.urgency;
        // Signals created before tags existed load with none. The picker then
        // requires a choice before saving, which quietly migrates them as their
        // reporters edit — no backfill needed.
        _helpTags = List.of(signal.helpNeededTags);
        _animalType = signal.animalType;
      } else {
        if (mounted) context.pop();
        return;
      }

      setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).somethingWentWrong),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveSignal() async {
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context);

    // The pickers are not form fields, so they are validated by hand.
    if (_helpTags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseSelectHelpTag)),
      );
      return;
    }
    if (_animalType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseSelectAnimalType)),
      );
      return;
    }

    final urgencyChanged = _urgency != _originalUrgency;

    // Spec §4.6: an urgency change carries an update note wherever it is made.
    // Asked before the save starts, so cancelling leaves the form as it is and
    // nothing is written — the same protocol as the details screen, which is
    // the point: two ways to escalate a signal must not produce two different
    // kinds of history.
    String? note;
    if (urgencyChanged) {
      final urgency = SignalUrgency.fromCode(_urgency);
      note = await showUpdateNoteDialog(
        context,
        headline: l10n.updateNoteChangingTo(urgency.label(l10n)),
        badge: urgencyBadge(urgency),
      );
      // Backing out of the note abandons the whole save, including the title,
      // description, phone and tag edits made alongside it. That is the right
      // call — a half-applied save is worse — but it has to be SAID: the dialog
      // is titled "What changed?", so Cancel reads as "cancel the note", and
      // without this the Save button would simply un-press and every edit would
      // be gone with no explanation.
      if (note == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.nothingWasSaved)),
          );
        }
        return;
      }
      if (!mounted) return;
    }

    setState(() => _isSaving = true);

    final signalRef = FirebaseFirestore.instance
        .collection(AppPreferencesService().signalsCollectionName)
        .doc(widget.signalId);
    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser!.uid);

    // One batch so an urgency change and the timeline entry describing it land
    // together — a failed second write would leave a push sent with no history
    // to explain it — and so the whole save costs one round trip.
    final batch = FirebaseFirestore.instance.batch();
    batch.update(signalRef, {
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim(),
      'contactPhone': _phoneController.text.trim(),
      'urgency': _urgency,
      'helpNeededTags': _helpTags,
      'animalType': _animalType,
      // Changing urgency here fires the same update notification as the
      // details screen, so the actor has to be recorded — otherwise a stale
      // lastUpdatedBy from an earlier status change decides who gets skipped.
      // The same helper the details screen uses, which also carries the holder's
      // proof of life: this screen is a coordination write like any other, and
      // omitting the stamp let a reporter actively re-triaging their own case
      // fall into the stale-holder path anyway.
      ...CaseOwnershipService.coordinationStamp(userRef),
    });

    // Same timeline entry the details screen writes. Without it, escalating
    // to Red from this screen would push every subscriber while the signal
    // history showed nothing changed — and the spec's Red-Alert-misuse
    // handling has nothing to review.
    if (urgencyChanged) {
      batch.set(
        signalRef.collection('events').doc(),
        // Built by the same encoder the details screen uses, so the two writers
        // cannot drift on field names — the spec's standing warning that these
        // must stay in step is now a shared function rather than a comment.
        SignalEventType.urgencyChange.eventData(
          oldValue: _originalUrgency,
          newValue: _urgency,
          // Non-null under the same `urgencyChanged` guard that produced it:
          // the block above returns when the dialog is cancelled.
          note: note!,
          actor: userRef,
        ),
      );
    }

    try {
      await batch.commit();
      _originalUrgency = _urgency;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.signalUpdatedSuccessfully),
          backgroundColor: Colors.green,
        ),
      );
      context.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.failedToUpdateSignal),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(l10n.editSignal),
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2
                    ),
                  )
                : const Icon(Icons.check),
            onPressed: _isSaving ? null : _saveSignal,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: l10n.title,
                        border: const OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return l10n.pleaseEnterTitle;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: InputDecoration(
                        labelText: l10n.description,
                        border: const OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 4,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return l10n.pleaseEnterDescription;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        labelText: l10n.contactPhone,
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),
                    SectionHeader(l10n.urgency),
                    // Only the reporter can reach this screen at all
                    // (_loadSignal pops otherwise), so no extra gate is needed
                    // for the reporter-only urgency rule here.
                    UrgencyPicker(
                      value: _urgency,
                      enabled: !_isSaving,
                      onChanged: (value) => setState(() => _urgency = value),
                    ),
                    const SizedBox(height: 16),
                    SectionHeader(l10n.animalType),
                    const SizedBox(height: 8),
                    AnimalTypeSelector(
                      selected: [if (_animalType != null) _animalType!],
                      singleSelect: true,
                      semanticPrefix: 'editAnimalType',
                      onToggle: (code) => setState(() => _animalType = code),
                    ),
                    const SizedBox(height: 16),
                    SectionHeader(l10n.helpNeeded),
                    const SizedBox(height: 8),
                    HelpTagSelector(
                      selected: _helpTags,
                      maxSelection: HelpTag.maxPerSignal,
                      semanticPrefix: 'editHelpTag',
                      onToggle: (code) => setState(() {
                        _helpTags = toggledCode(
                          _helpTags,
                          code,
                          max: HelpTag.maxPerSignal,
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
