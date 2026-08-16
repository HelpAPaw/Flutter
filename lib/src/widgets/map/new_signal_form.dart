import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/help_tag.dart';
import '../../viewmodels/map_view_model.dart';
import '../help_tag_selector.dart';
import '../urgency_picker.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';

/// Form widget for creating a new signal
class NewSignalForm extends ConsumerStatefulWidget {
  final VoidCallback? onSubmitSuccess;
  final void Function(String errorKey)? onSubmitError;
  final Future<(double latitude, double longitude)> Function() getMapCenter;

  const NewSignalForm({
    super.key,
    this.onSubmitSuccess,
    this.onSubmitError,
    required this.getMapCenter,
  });

  @override
  ConsumerState<NewSignalForm> createState() => _NewSignalFormState();
}

class _NewSignalFormState extends ConsumerState<NewSignalForm> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _phoneNumberController = TextEditingController();
  final _imagePicker = ImagePicker();

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _phoneNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formState = ref.watch(
      mapViewModelProvider.select((state) => state.formState),
    );

    return Builder(
      builder: (BuildContext context) {
        final mediaQuery = MediaQuery.maybeOf(context);
        if (mediaQuery == null) {
          return const SafeArea(child: SizedBox.shrink());
        }

        final keyboardHeight = mediaQuery.viewInsets.bottom;
        final screenHeight = mediaQuery.size.height;
        final safeAreaTop = mediaQuery.padding.top;

        final availableHeight =
            screenHeight - safeAreaTop - keyboardHeight - 16 - 150;
        final formMaxHeight = availableHeight.clamp(200.0, 400.0);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              constraints: BoxConstraints(maxHeight: formMaxHeight),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(color: Colors.grey, width: 1.0),
              ),
              child: Row(
                children: [
                  Semantics(
                    label: l10n.uploadPhoto,
                    button: true,
                    enabled: true,
                    child: IconButton(
                      icon: const Icon(Icons.camera_alt),
                      onPressed: _showImageSourceBottomSheet,
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          TextField(
                            controller: _titleController,
                            decoration: InputDecoration(
                              labelText: l10n.title,
                            ),
                            textCapitalization: TextCapitalization.sentences,
                            // Mirrors the Firestore rules' create bounds, so an
                            // over-long title is capped as it's typed instead of
                            // failing the write with an opaque PERMISSION_DENIED.
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(300),
                            ],
                            onChanged: (value) {
                              ref
                                  .read(mapViewModelProvider.notifier)
                                  .updateFormTitle(value);
                            },
                          ),
                          TextField(
                            controller: _descriptionController,
                            decoration: InputDecoration(
                              labelText: l10n.description,
                            ),
                            textCapitalization: TextCapitalization.sentences,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(10000),
                            ],
                            onChanged: (value) {
                              ref
                                  .read(mapViewModelProvider.notifier)
                                  .updateFormDescription(value);
                            },
                          ),
                          TextField(
                            controller: _phoneNumberController,
                            decoration: InputDecoration(
                              labelText: l10n.phoneNumber,
                            ),
                            keyboardType: TextInputType.phone,
                            onChanged: (value) {
                              ref
                                  .read(mapViewModelProvider.notifier)
                                  .updateFormPhoneNumber(value);
                            },
                          ),
                          const SizedBox(height: 8),
                          _buildSectionLabel(l10n.urgency),
                          UrgencyPicker(
                            value: formState.urgency,
                            // The form is a short scrollable strip, so the
                            // per-level guidance would push everything else out
                            // of reach. The details/edit screens show it.
                            showDescriptions: false,
                            enabled: !formState.isSubmitting,
                            onChanged: (urgency) => ref
                                .read(mapViewModelProvider.notifier)
                                .setFormUrgency(urgency),
                          ),
                          const SizedBox(height: 8),
                          _buildSectionLabel(l10n.animalType),
                          AnimalTypeSelector(
                            selected: [
                              if (formState.animalType != null)
                                formState.animalType!,
                            ],
                            singleSelect: true,
                            onToggle: (code) => ref
                                .read(mapViewModelProvider.notifier)
                                .setFormAnimalType(code),
                          ),
                          const SizedBox(height: 8),
                          _buildSectionLabel(
                            l10n.helpNeeded,
                            // The cap is the reach limit as much as a priority
                            // limit, so say what it is instead of letting chips
                            // silently go dead at three.
                            hint: l10n.helpTagLimitReached(
                              HelpTag.maxPerSignal,
                            ),
                          ),
                          HelpTagSelector(
                            selected: formState.helpTags,
                            maxSelection: HelpTag.maxPerSignal,
                            onToggle: (code) => ref
                                .read(mapViewModelProvider.notifier)
                                .toggleFormHelpTag(code),
                          ),
                          if (formState.selectedImage != null)
                            _buildImagePreview(context, formState.selectedImage!),
                        ],
                      ),
                    ),
                  ),
                  Semantics(
                    label: l10n.submitSignal,
                    button: true,
                    enabled: !formState.isSubmitting,
                    child: IconButton(
                      icon: formState.isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.orange),
                              ),
                            )
                          : const Icon(Icons.send),
                      onPressed:
                          formState.isSubmitting ? null : _handleSubmit,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Left-aligned heading for one of the form's picker sections, with an
  /// optional grey hint beside it.
  Widget _buildSectionLabel(String text, {String? hint}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                hint,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImagePreview(BuildContext context, XFile image) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: Image.file(
              File(image.path),
              height: 150,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Semantics(
              label: AppLocalizations.of(context).removePhoto,
              button: true,
              enabled: true,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
                onPressed: () {
                  ref.read(mapViewModelProvider.notifier).clearFormImage();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showImageSourceBottomSheet() {
    final l10n = AppLocalizations.of(context);
    final formState = ref.read(mapViewModelProvider).formState;

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
                  _pickImageFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.orange),
                title: Text(l10n.chooseFromGallery),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageFromGallery();
                },
              ),
              if (formState.selectedImage != null)
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

  Future<void> _pickImageFromCamera() async {
    final l10n = AppLocalizations.of(context);
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (image != null) {
        ref.read(mapViewModelProvider.notifier).setFormImage(image);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorAccessingCamera(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickImageFromGallery() async {
    final l10n = AppLocalizations.of(context);
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (image != null) {
        ref.read(mapViewModelProvider.notifier).setFormImage(image);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.errorAccessingGallery(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleSubmit() async {
    final l10n = AppLocalizations.of(context);
    final (latitude, longitude) = await widget.getMapCenter();

    final (success, errorMessage) =
        await ref.read(mapViewModelProvider.notifier).submitSignal(
              latitude: latitude,
              longitude: longitude,
            );

    if (!mounted) return;

    if (!success) {
      FocusScope.of(context).unfocus();
    }

    if (success) {
      if (errorMessage == 'photo_upload_failed') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.signalCreatedPhotoFailed),
            backgroundColor: Colors.orange,
          ),
        );
      }
      _titleController.clear();
      _descriptionController.clear();
      _phoneNumberController.clear();
      widget.onSubmitSuccess?.call();
    } else {
      _showErrorSnackBar(errorMessage);
      widget.onSubmitError?.call(errorMessage ?? 'unknown');
    }
  }

  void _showErrorSnackBar(String? errorKey) {
    final l10n = AppLocalizations.of(context);

    String errorMessage;
    switch (errorKey) {
      case 'title_empty':
        errorMessage = l10n.pleaseEnterTitle;
        break;
      case 'description_empty':
        errorMessage = l10n.pleaseEnterDescription;
        break;
      case 'urgency_unset':
        errorMessage = l10n.pleaseSelectUrgency;
        break;
      case 'help_tags_empty':
        errorMessage = l10n.pleaseSelectHelpTag;
        break;
      case 'animal_type_unset':
        errorMessage = l10n.pleaseSelectAnimalType;
        break;
      case 'not_authenticated':
        errorMessage = l10n.authenticationError;
        break;
      case 'permission-denied':
        errorMessage = l10n.permissionDenied;
        break;
      case 'unauthenticated':
        errorMessage = l10n.authenticationError;
        break;
      case 'unavailable':
        errorMessage = l10n.serviceUnavailable;
        break;
      case 'network-request-failed':
        errorMessage = l10n.networkError;
        break;
      default:
        errorMessage = l10n.failedToCreateSignal;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(errorMessage),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
