// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';

/// A stand-in for a `users/{uid}` reference — a signal's `reporter`, its
/// `signalOwner`, an event's actor — which cannot be built without an
/// initialised Firebase app.
///
/// Give it an [id] when the code under test reads one or compares owners;
/// leave it out when the reference is only carried along. Every other member,
/// and [id] when none was given, throws rather than returning null, so an
/// unexpected read shows up as a test failure instead of silently rendering
/// nothing.
///
/// The suite's only implementation of `DocumentReference`, which is sealed:
/// one `subtype_of_sealed_class` suppression, and one place to fix if
/// cloud_firestore ever enforces the seal.
class FakeDocumentReference implements DocumentReference<Map<String, dynamic>> {
  FakeDocumentReference([this._id]);

  final String? _id;

  @override
  String get id => _id ?? super.noSuchMethod(Invocation.getter(#id));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
