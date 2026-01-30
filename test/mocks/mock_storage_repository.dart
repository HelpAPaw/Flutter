import 'dart:io';

import 'package:help_a_paw/src/repositories/storage_repository.dart';

/// Mock implementation of StorageRepository for testing
class MockStorageRepository implements StorageRepository {
  /// Images uploaded during tests
  final List<({String signalId, String filePath})> uploadedImages = [];

  /// Images deleted during tests
  final List<({String signalId, String imageUrl})> deletedImages = [];

  /// Whether upload should succeed
  bool shouldUploadSucceed = true;

  /// Custom error message for failed uploads
  String uploadErrorMessage = 'Mock upload error';

  /// Counter for generating unique download URLs
  int _uploadCounter = 0;

  @override
  Future<UploadResult> uploadSignalImage({
    required String signalId,
    required File imageFile,
  }) async {
    uploadedImages.add((signalId: signalId, filePath: imageFile.path));

    if (shouldUploadSucceed) {
      _uploadCounter++;
      return UploadResult.success(
        'https://mock-storage.example.com/signals/$signalId/photo_$_uploadCounter.jpg',
      );
    } else {
      return UploadResult.failure(uploadErrorMessage);
    }
  }

  @override
  Future<void> deleteSignalImage({
    required String signalId,
    required String imageUrl,
  }) async {
    deletedImages.add((signalId: signalId, imageUrl: imageUrl));
  }

  @override
  Future<List<String>> getSignalImageUrls(String signalId) async {
    return uploadedImages
        .where((img) => img.signalId == signalId)
        .map((img) =>
            'https://mock-storage.example.com/signals/$signalId/${img.filePath}')
        .toList();
  }
}
