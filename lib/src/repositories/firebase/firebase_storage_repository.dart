import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

import '../storage_repository.dart';

/// Firebase Storage implementation of StorageRepository
class FirebaseStorageRepository implements StorageRepository {
  final FirebaseStorage _storage;

  FirebaseStorageRepository({FirebaseStorage? storage})
      : _storage = storage ??
            FirebaseStorage.instanceFor(
                bucket: 'gs://help-a-paw-dev.appspot.com');

  @override
  Future<UploadResult> uploadSignalImage({
    required String signalId,
    required File imageFile,
  }) async {
    try {
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';

      final Reference storageRef = _storage
          .ref()
          .child('signals')
          .child(signalId)
          .child('photos')
          .child(fileName);

      // Declared rather than left to the platform's MIME inference: the
      // Storage rules require an `image/*` content type, and the picker always
      // re-encodes to JPEG (it is given an imageQuality).
      final UploadTask uploadTask = storageRef.putFile(
        imageFile,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      return UploadResult.success(downloadUrl);
    } on FirebaseException catch (e) {
      return UploadResult.failure(e.message ?? 'Failed to upload image');
    } catch (e) {
      return UploadResult.failure('Unexpected error: $e');
    }
  }

  @override
  Future<void> deleteSignalImage({
    required String signalId,
    required String imageUrl,
  }) async {
    try {
      final ref = _storage.refFromURL(imageUrl);
      await ref.delete();
    } catch (e) {
      // Silently fail if image doesn't exist
    }
  }

  @override
  Future<List<String>> getSignalImageUrls(String signalId) async {
    try {
      final ListResult result = await _storage
          .ref()
          .child('signals')
          .child(signalId)
          .child('photos')
          .listAll();

      final urls = await Future.wait(
        result.items.map((ref) => ref.getDownloadURL()),
      );
      return urls;
    } catch (e) {
      return [];
    }
  }
}
