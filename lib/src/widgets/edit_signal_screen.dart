import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/src/models/signal.dart';
import 'package:help_a_paw/src/services/app_preferences_service.dart';

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
  int _signalType = 0;
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
        _signalType = signal.signalType;
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
    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance
          .collection(AppPreferencesService().signalsCollectionName)
          .doc(widget.signalId)
          .update({
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'contactPhone': _phoneController.text.trim(),
        'signalType': _signalType,
      });

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
        title: Text(l10n.editSignal),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
                valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
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
                    DropdownButtonFormField<int>(
                      initialValue: _signalType,
                      decoration: InputDecoration(
                        labelText: l10n.signalType,
                        border: const OutlineInputBorder(),
                      ),
                      items: List.generate(
                        Signal.signalTypes.length,
                        (index) => DropdownMenuItem(
                          value: index,
                          child: Text(
                            Signal.getLocalizedSignalTypeName(context, index),
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _signalType = value);
                        }
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
                  ],
                ),
              ),
            ),
    );
  }
}
