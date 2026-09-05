/// How long an uploaded file may be cached.
///
/// Every path this app writes to storage is built from the owner's id and a
/// microsecond timestamp, and every upload passes `upsert: false`. A URL
/// therefore names one file for as long as that file exists: the bytes behind
/// it never change, and changing a picture writes a new path and updates the
/// column that points at it.
///
/// That makes the content immutable in the only sense caching cares about,
/// which is worth saying out loud because the default says otherwise.
/// Supabase sends `cache-control: max-age=3600` unless told not to — one hour,
/// after which the CDN goes back to the origin and the phone downloads the
/// picture again. For a file that cannot have changed, that is a year of
/// re-downloading the same avatar twenty-four times a day, billed as egress at
/// one end and as mobile data at the other.
///
/// A year is the longest value `max-age` is meant to carry. `immutable` is not
/// included because Supabase takes a number of seconds here rather than a
/// header, but the effect that matters — the phone not asking again — is the
/// same.
///
/// The one thing this must never be applied to is a path that gets overwritten
/// in place. There is no such path in this app; if one is added, it needs its
/// own short value rather than this.
class StorageCache {
  const StorageCache._();

  /// One year, in seconds, as the string `FileOptions` wants.
  static const String immutable = '31536000';
}
