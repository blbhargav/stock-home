import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

/// Handles grocery item image uploads to Firebase Storage.
///
/// Layout: households/{householdId}/groceries/{imageId}.jpg
class StorageService {
  StorageService({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  Reference _imageRef(String householdId, String imageId) {
    return _storage
        .ref()
        .child('households')
        .child(householdId)
        .child('groceries')
        .child('$imageId.jpg');
  }

  /// Uploads [file] for the household and returns its download URL.
  /// [imageId] uniquely identifies the image (e.g. a timestamp or item id).
  /// [onProgress] reports 0.0–1.0 upload progress.
  Future<String> uploadImage({
    required String householdId,
    required String imageId,
    required File file,
    void Function(double progress)? onProgress,
  }) async {
    final ref = _imageRef(householdId, imageId);
    final task = ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));

    StreamSubscription<TaskSnapshot>? progressSub;
    if (onProgress != null) {
      progressSub = task.snapshotEvents.listen((snapshot) {
        final total = snapshot.totalBytes;
        if (total > 0) {
          onProgress(snapshot.bytesTransferred / total);
        }
      });
    }

    try {
      final snapshot = await task;
      return await snapshot.ref.getDownloadURL();
    } finally {
      // Always release the progress listener, including on error/cancel.
      await progressSub?.cancel();
    }
  }

  /// Deletes an image by its download URL. Safe to call even if already gone.
  Future<void> deleteByUrl(String url) async {
    try {
      await _storage.refFromURL(url).delete();
    } catch (_) {
      // Already deleted or invalid URL — ignore.
    }
  }
}
