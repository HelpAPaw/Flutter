import 'dart:io';

/// Result of an image upload operation
class UploadResult {
  final String? downloadUrl;
  final bool success;
  final String? errorMessage;

  UploadResult({
    this.downloadUrl,
    required this.success,
    this.errorMessage,
  });

  factory UploadResult.success(String downloadUrl) {
    return UploadResult(downloadUrl: downloadUrl, success: true);
  }

  factory UploadResult.failure(String errorMessage) {
    return UploadResult(
      success: false,
      errorMessage: errorMessage,
    );
  }
}

/// Abstract interface for file storage operations
abstract class StorageRepository {
  /// Upload an image file for a signal
  /// Returns the download URL on success
  Future<UploadResult> uploadSignalImage({
    required String signalId,
    required File imageFile,
  });

  /// Delete an image from a signal
  Future<void> deleteSignalImage({
    required String signalId,
    required String imageUrl,
  });

  /// Get all image URLs for a signal
  Future<List<String>> getSignalImageUrls(String signalId);
}
