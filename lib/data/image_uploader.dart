import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/image_resize.dart';
import '../core/storage_cache.dart';
import 'moderation_service.dart';


/// A picture in the two sizes the app shows it at.
@immutable
class UploadedImage {
  const UploadedImage({required this.url, this.thumbUrl});

  /// The full-size file. Always present — it is the picture.
  final String url;

  /// The ~640px copy, or null when there is none: a photo already small
  /// enough to be its own thumbnail, or one the resizer could not read.
  final String? thumbUrl;
}

/// Puts pictures in a bucket, in both sizes.
///
/// One of these rather than a private `_uploadImage` on each of the three
/// repositories that upload. They had grown the same method three times —
/// same path shape, same content-type switch — and adding a second rendition
/// to each of them would have been the third and fourth copy of that too.
///
/// The path is `<owner-id>/<microseconds>.<ext>`, which is what the storage
/// policies scope writes to: a folder named after the uploader. A thumbnail
/// sits beside its original as `<microseconds>_t.jpg`, inside the same folder,
/// so the same policy covers it with no change.
class ImageUploader {
  ImageUploader({
    required SupabaseClient client,
    required this.bucket,
    ModerationService? moderation,
  })  : _client = client,
        _moderation = moderation ?? ModerationService(client: client);

  final SupabaseClient _client;

  /// Who decides whether a picture may be uploaded. Injectable so the
  /// repositories that own an uploader can be tested without a network.
  final ModerationService _moderation;

  /// Which bucket to write to — `meal-images`, `post-images`, `avatars`.
  final String bucket;

  /// Uploads [bytes], and a small copy of it when one is worth making.
  ///
  /// The thumbnail is best-effort by design: it is generated, uploaded and
  /// recorded only if all three work, and any failure returns an
  /// [UploadedImage] with a null `thumbUrl`. Callers store that null and read
  /// through a `smallImageUrl` getter that falls back to the full size — which
  /// is exactly how the app behaved before thumbnails existed, so the failure
  /// mode is "no saving", never "no picture".
  Future<UploadedImage> upload({
    required String ownerId,
    required Uint8List bytes,
    required String extension,
    String? name,
  }) async {
    // Before anything is written. Every image in the app arrives here — post
    // photos, meal photos, avatars, group pictures — so this is the one place
    // the check has to exist, and putting it before `_put` means an explicit
    // image never reaches a public URL at all.
    //
    // This used to be `ImageSafety.refuseIfExplicit`, an on-device model that
    // worked on neither platform: on iOS it scored a full nude below a topless
    // photo, and on Android the model it wanted 404s so it never ran. It now
    // asks the server, which holds the credentials, a far better model, and a
    // policy that can change without an app release.
    //
    // Same exception on refusal, which is why nothing downstream changed.
    await _moderation.refuseIfExplicit(bytes);

    final String stem =
        name ?? '${DateTime.now().toUtc().microsecondsSinceEpoch}';
    final String path = '$ownerId/$stem.$extension';

    await _put(path, bytes, _contentTypeFor(extension));
    final String url = _client.storage.from(bucket).getPublicUrl(path);

    return UploadedImage(
      url: url,
      thumbUrl: await _uploadThumbnail(
        ownerId: ownerId,
        stem: stem,
        bytes: bytes,
      ),
    );
  }

  /// Makes and stores the small copy, or returns null and says why.
  ///
  /// Always JPEG regardless of what the original was: the resizer encodes JPEG,
  /// and a thumbnail has no transparency worth keeping.
  Future<String?> _uploadThumbnail({
    required String ownerId,
    required String stem,
    required Uint8List bytes,
  }) async {
    try {
      final Uint8List? small = await ImageResize.thumbnail(bytes);
      if (small == null) return null;

      final String path = '$ownerId/${stem}_t.jpg';
      await _put(path, small, 'image/jpeg');

      return _client.storage.from(bucket).getPublicUrl(path);
    } catch (error) {
      debugPrint('Bulkr: thumbnail not stored — $error');
      return null;
    }
  }

  Future<void> _put(String path, Uint8List bytes, String contentType) {
    return _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: false,
            // The path is unique and never rewritten, so the file behind this
            // URL cannot change — see StorageCache.
            cacheControl: StorageCache.immutable,
          ),
        );
  }

  /// Best-effort removal of files nothing points at any more.
  ///
  /// Takes public URLs and skips whatever it cannot turn into a path. Never
  /// throws: an orphaned file costs a fraction of a cent, and failing a save
  /// because a *previous* picture would not delete is the wrong trade.
  Future<void> remove(Iterable<String?> publicUrls) async {
    final List<String> paths = <String>[];
    for (final String? url in publicUrls) {
      final String? path = storagePathFor(url, bucket: bucket);
      if (path != null) paths.add(path);
    }

    if (paths.isEmpty) return;

    try {
      await _client.storage.from(bucket).remove(paths);
    } catch (error) {
      debugPrint('Bulkr: old image not removed — $error');
    }
  }

  /// The object path inside [bucket] that a public URL points at.
  ///
  /// Null for an empty URL, and for one that belongs to a different bucket or
  /// a different host entirely — an image hosted somewhere else is not ours to
  /// delete.
  static String? storagePathFor(String? publicUrl, {required String bucket}) {
    if (publicUrl == null || publicUrl.isEmpty) return null;

    final String marker = '/public/$bucket/';
    final int start = publicUrl.indexOf(marker);
    if (start < 0) return null;

    // Query strings appear on signed and transformed URLs, never on the object
    // path itself.
    final String path = publicUrl
        .substring(start + marker.length)
        .split('?')
        .first;
    return path.isEmpty ? null : Uri.decodeComponent(path);
  }

  static String _contentTypeFor(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }
}
