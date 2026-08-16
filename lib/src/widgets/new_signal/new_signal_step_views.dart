import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../l10n/app_localizations.dart';
import '../../models/animal_type.dart';
import '../../models/help_tag.dart';
import '../../models/new_signal_step.dart';
import '../../models/signal.dart';
import '../../models/signal_urgency.dart';
import '../../viewmodels/map_view_model.dart';
import '../help_tag_selector.dart';
import '../section_header.dart';
import '../urgency_picker.dart';

/// Shared layout for a wizard page: the question, an optional supporting line,
/// then the control.
///
/// Every step goes through this so the headline sits in the same place on all
/// of them — a wizard whose title jumps around between steps reads as several
/// screens rather than one flow.
class NewSignalStepBody extends StatelessWidget {
  const NewSignalStepBody({
    super.key,
    required this.step,
    required this.child,
    this.hintOverride,
  });

  final NewSignalStep step;
  final Widget child;

  /// Replaces [NewSignalStep.hint] where the text needs a runtime value.
  final String? hintOverride;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hint = hintOverride ?? step.hint(l10n);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        // Stretch so each step's control gets the full width to lay itself out
        // in — chip Wraps, form fields and review rows all want it, and the
        // text is left-aligned by default regardless.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            step.question(l10n),
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(
              hint,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey.shade700),
            ),
          ],
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}

// ============================================================
// Step 2 — Photo
// ============================================================

/// Optional photo. Second in the flow because it is *perishable*: the reporter
/// is standing in front of the animal now, and it primes the description they
/// write on the next step.
class NewSignalPhotoStep extends ConsumerStatefulWidget {
  const NewSignalPhotoStep({super.key});

  @override
  ConsumerState<NewSignalPhotoStep> createState() => _NewSignalPhotoStepState();
}

class _NewSignalPhotoStepState extends ConsumerState<NewSignalPhotoStep> {
  final _imagePicker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final image = ref.watch(
      mapViewModelProvider.select((s) => s.formState.selectedImage),
    );

    return NewSignalStepBody(
      step: NewSignalStep.photo,
      child: image == null
          ? Semantics(
              identifier: 'newSignal.addPhoto',
              button: true,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: Text(l10n.newSignalAddPhoto),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(120),
                  foregroundColor: Colors.orange.shade800,
                  side: BorderSide(color: Colors.orange.shade200, width: 2),
                ),
                onPressed: _showImageSourceBottomSheet,
              ),
            )
          : _buildImagePreview(context, image),
    );
  }

  Widget _buildImagePreview(BuildContext context, XFile image) {
    final l10n = AppLocalizations.of(context);
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: Image.file(
            File(image.path),
            height: 240,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Semantics(
            identifier: 'newSignal.removePhoto',
            label: l10n.removePhoto,
            button: true,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
              onPressed: () =>
                  ref.read(mapViewModelProvider.notifier).clearFormImage(),
            ),
          ),
        ),
      ],
    );
  }

  void _showImageSourceBottomSheet() {
    final l10n = AppLocalizations.of(context);
    final hasImage =
        ref.read(mapViewModelProvider).formState.selectedImage != null;

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
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.orange),
                title: Text(l10n.chooseFromGallery),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              if (hasImage)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: Text(l10n.removePhoto),
                  onTap: () {
                    Navigator.pop(context);
                    ref.read(mapViewModelProvider.notifier).clearFormImage();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final l10n = AppLocalizations.of(context);
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (image != null) {
        ref.read(mapViewModelProvider.notifier).setFormImage(image);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(source == ImageSource.camera
              ? l10n.errorAccessingCamera(e.toString())
              : l10n.errorAccessingGallery(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// ============================================================
// Step 3 — Details
// ============================================================

/// The only step that needs a keyboard, which is why title, description and
/// phone are together rather than spread over three pages: the keyboard opens
/// and closes once across the whole wizard.
class NewSignalDetailsStep extends ConsumerStatefulWidget {
  const NewSignalDetailsStep({super.key});

  @override
  ConsumerState<NewSignalDetailsStep> createState() =>
      _NewSignalDetailsStepState();
}

class _NewSignalDetailsStepState extends ConsumerState<NewSignalDetailsStep> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    // Seeded from state rather than starting blank: only the visible step is
    // mounted, so leaving and returning to this page rebuilds it from scratch
    // and the reporter would otherwise find their text gone.
    final formState = ref.read(mapViewModelProvider).formState;
    _titleController = TextEditingController(text: formState.title);
    _descriptionController =
        TextEditingController(text: formState.description);
    _phoneController = TextEditingController(text: formState.phoneNumber);
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
    final notifier = ref.read(mapViewModelProvider.notifier);

    return NewSignalStepBody(
      step: NewSignalStep.details,
      child: Form(
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              identifier: 'newSignal.title',
              child: TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: l10n.title,
                  border: const OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                // Mirrors the Firestore rules' create bounds, so an over-long
                // title is capped as it's typed instead of failing the write
                // with an opaque PERMISSION_DENIED.
                inputFormatters: [LengthLimitingTextInputFormatter(300)],
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? l10n.pleaseEnterTitle
                    : null,
                onChanged: notifier.updateFormTitle,
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              identifier: 'newSignal.description',
              child: TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: l10n.description,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                inputFormatters: [LengthLimitingTextInputFormatter(10000)],
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? l10n.pleaseEnterDescription
                    : null,
                onChanged: notifier.updateFormDescription,
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              identifier: 'newSignal.phone',
              child: TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: l10n.contactPhone,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                onChanged: notifier.updateFormPhoneNumber,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Step 4 — Animal
// ============================================================

/// The easiest classification — three chips, purely perceptual — so it opens
/// the run of tap-only questions.
class NewSignalAnimalStep extends ConsumerWidget {
  const NewSignalAnimalStep({super.key, required this.onAnswered});

  final VoidCallback onAnswered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animalType = ref.watch(
      mapViewModelProvider.select((s) => s.formState.animalType),
    );

    return NewSignalStepBody(
      step: NewSignalStep.animal,
      child: AnimalTypeSelector(
        selected: [if (animalType != null) animalType],
        singleSelect: true,
        semanticPrefix: 'wizardAnimalType',
        onToggle: (code) {
          ref.read(mapViewModelProvider.notifier).setFormAnimalType(code);
          onAnswered();
        },
      ),
    );
  }
}

// ============================================================
// Step 5 — Signal type
// ============================================================

/// The coarse category. Localized here — the old inline form rendered the raw
/// English `Signal.signalTypes` constants, so Bulgarian reporters picked their
/// category out of an English list.
class NewSignalTypeStep extends ConsumerWidget {
  const NewSignalTypeStep({super.key, required this.onAnswered});

  final VoidCallback onAnswered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(
      mapViewModelProvider.select((s) => s.formState.signalType),
    );
    final names = Signal.getLocalizedSignalTypes(context);

    void select(int index) {
      ref.read(mapViewModelProvider.notifier).setFormSignalType(index);
      onAnswered();
    }

    return NewSignalStepBody(
      step: NewSignalStep.signalType,
      child: RadioGroup<int>(
        groupValue: selected,
        onChanged: (value) {
          if (value != null) select(value);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < names.length; index++)
              Semantics(
                identifier: 'wizardSignalType.$index',
                selected: index == selected,
                button: true,
                child: InkWell(
                  onTap: () => select(index),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Radio<int>(value: index),
                        Expanded(child: Text(names[index])),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Step 6 — Urgency
// ============================================================

/// Late in the flow on purpose: asked cold it invites a reflexive "Red,
/// obviously", asked after the reporter has had to describe the case it is
/// calibrated. This is also the first place the per-level descriptions fit —
/// the old inline form passed `showDescriptions: false` for space, hiding the
/// guidance on the one field with real consequences.
class NewSignalUrgencyStep extends ConsumerWidget {
  const NewSignalUrgencyStep({super.key, required this.onAnswered});

  final VoidCallback onAnswered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formState = ref.watch(
      mapViewModelProvider.select((s) => s.formState),
    );

    return NewSignalStepBody(
      step: NewSignalStep.urgency,
      // UrgencyPicker owns the Red Alert confirmation and only calls onChanged
      // once it has been accepted, so advancing from here can never skip past
      // a dialog the reporter declined.
      child: UrgencyPicker(
        value: formState.urgency,
        enabled: !formState.isSubmitting,
        onChanged: (urgency) {
          ref.read(mapViewModelProvider.notifier).setFormUrgency(urgency);
          onAnswered();
        },
      ),
    );
  }
}

// ============================================================
// Step 7 — Help needed
// ============================================================

/// The most derived question, and the last one asked: it decides who gets
/// notified. It follows urgency because "what does this case need" is not
/// answerable until "how bad is it" is settled.
class NewSignalHelpTagsStep extends ConsumerWidget {
  const NewSignalHelpTagsStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final helpTags = ref.watch(
      mapViewModelProvider.select((s) => s.formState.helpTags),
    );

    return NewSignalStepBody(
      step: NewSignalStep.helpTags,
      hintOverride: l10n.newSignalHintHelp(HelpTag.maxPerSignal),
      // Multi-select, so no auto-advance: there is no way to tell a first
      // choice from a half-finished one.
      child: HelpTagSelector(
        selected: helpTags,
        maxSelection: HelpTag.maxPerSignal,
        semanticPrefix: 'wizardHelpTag',
        onToggle: (code) =>
            ref.read(mapViewModelProvider.notifier).toggleFormHelpTag(code),
      ),
    );
  }
}

// ============================================================
// Step 8 — Review
// ============================================================

/// Every answer on one screen, each with a way back to the step that set it.
class NewSignalReviewStep extends ConsumerWidget {
  const NewSignalReviewStep({
    super.key,
    required this.onChangeLocation,
  });

  /// The location lives on the map, not in the wizard, so revising it means
  /// leaving this route entirely — the wizard page owns that trip.
  final VoidCallback onChangeLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formState = ref.watch(
      mapViewModelProvider.select((s) => s.formState),
    );
    final notifier = ref.read(mapViewModelProvider.notifier);

    final urgency = formState.urgency;
    final animalType = formState.animalType;

    return NewSignalStepBody(
      step: NewSignalStep.review,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (formState.selectedImage != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(formState.selectedImage!.path),
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
          ],
          _ReviewRow(
            field: 'location',
            label: l10n.newSignalStepLocation,
            value: formState.isLocationUnset
                ? l10n.newSignalNotProvided
                : '${l10n.newSignalPinPlaced} '
                    '(${formState.latitude!.toStringAsFixed(5)}, '
                    '${formState.longitude!.toStringAsFixed(5)})',
            onChange: onChangeLocation,
          ),
          if (formState.selectedImage == null)
            _ReviewRow(
              field: 'photo',
              label: l10n.newSignalStepPhoto,
              value: l10n.newSignalNoPhoto,
              onChange: () => notifier.goToStep(NewSignalStep.photo),
            ),
          _ReviewRow(
            field: 'title',
            label: l10n.title,
            value: formState.title,
            onChange: () => notifier.goToStep(NewSignalStep.details),
          ),
          _ReviewRow(
            field: 'description',
            label: l10n.description,
            value: formState.description,
            onChange: () => notifier.goToStep(NewSignalStep.details),
          ),
          _ReviewRow(
            field: 'phone',
            label: l10n.contactPhone,
            value: formState.phoneNumber.trim().isEmpty
                ? l10n.newSignalNotProvided
                : formState.phoneNumber,
            onChange: () => notifier.goToStep(NewSignalStep.details),
          ),
          _ReviewRow(
            field: 'animal',
            label: l10n.animalType,
            value: animalType == null
                ? l10n.newSignalNotProvided
                : (AnimalType.fromCode(animalType)?.label(l10n) ?? animalType),
            onChange: () => notifier.goToStep(NewSignalStep.animal),
          ),
          _ReviewRow(
            field: 'signalType',
            label: l10n.signalType,
            value: Signal.getLocalizedSignalTypeName(
              context,
              formState.signalType,
            ),
            onChange: () => notifier.goToStep(NewSignalStep.signalType),
          ),
          _ReviewRow(
            field: 'urgency',
            label: l10n.urgency,
            value: urgency == null
                ? l10n.newSignalNotProvided
                : SignalUrgency.fromCode(urgency).label(l10n),
            onChange: () => notifier.goToStep(NewSignalStep.urgency),
          ),
          _ReviewRow(
            field: 'helpTags',
            label: l10n.helpNeeded,
            value: formState.helpTags.isEmpty
                ? l10n.newSignalNotProvided
                : HelpTag.fromCodes(formState.helpTags)
                    .map((tag) => tag.label(l10n))
                    .join(', '),
            onChange: () => notifier.goToStep(NewSignalStep.helpTags),
          ),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.field,
    required this.label,
    required this.value,
    required this.onChange,
  });

  /// Stable identifier for the Change button. Deliberately not derived from
  /// [label], which is localized — an automation identifier that changes with
  /// the device language is no identifier at all.
  final String field;

  final String label;
  final String value;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(label),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            identifier: 'newSignalReviewChange.$field',
            button: true,
            child: TextButton(onPressed: onChange, child: Text(l10n.change)),
          ),
        ],
      ),
    );
  }
}
