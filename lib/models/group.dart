import 'package:equatable/equatable.dart';

/// A `public.groups` row plus this user's relationship to it.
///
/// Same shape as [Person] and [Post]: the flags a card needs — am I in it, do
/// I own it — do not live on the row, and the repository resolves them once so
/// no widget has to join anything in its head.
class Group extends Equatable {
  const Group({
    required this.id,
    required this.name,
    this.description,
    this.imageUrl,
    required this.ownerId,
    this.isPrivate = false,
    required this.createdAt,
    this.memberCount = 0,
    this.postCount = 0,
    this.isMember = false,
    this.isOwner = false,
  });

  final String id;
  final String name;
  final String? description;
  final String? imageUrl;
  final String ownerId;

  /// Invisible to non-members, posts included.
  ///
  /// A public group is the opposite of open: anyone can read it, only members
  /// can post to it. "Private" here means the room is hidden, not that the
  /// door is locked.
  final bool isPrivate;

  final DateTime createdAt;

  /// Aggregates, not stored columns — same trade as follower counts, and for
  /// the same reasons: they cannot drift and nobody can inflate their own.
  final int memberCount;
  final int postCount;

  final bool isMember;

  /// This user owns it, so they can delete it and remove members. Implies
  /// [isMember] — the owner is inserted as a member by a trigger, so a group
  /// where this is true and that is false means the trigger did not run.
  final bool isOwner;

  /// Whether this user may post into it. Membership, not ownership — the
  /// insert policy on `posts` checks the same thing.
  bool get canPost => isMember;

  /// Whether to offer joining. An owner cannot leave their own group, so they
  /// get neither button.
  bool get canJoin => !isMember;

  bool get canLeave => isMember && !isOwner;

  Group copyWith({
    String? name,
    String? description,
    String? imageUrl,
    bool? isPrivate,
    int? memberCount,
    int? postCount,
    bool? isMember,
    bool? isOwner,
  }) {
    return Group(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      ownerId: ownerId,
      isPrivate: isPrivate ?? this.isPrivate,
      createdAt: createdAt,
      memberCount: memberCount ?? this.memberCount,
      postCount: postCount ?? this.postCount,
      isMember: isMember ?? this.isMember,
      isOwner: isOwner ?? this.isOwner,
    );
  }

  /// Reads a `groups` row, with the count aggregates when they were asked for.
  factory Group.fromRow(
    Map<String, dynamic> row, {
    String? currentUserId,
    bool isMember = false,
  }) {
    final String ownerId = '${row['owner_id']}';
    final bool isOwner = currentUserId != null && ownerId == currentUserId;

    return Group(
      id: '${row['id']}',
      name: '${row['name'] ?? ''}',
      description: row['description'] as String?,
      imageUrl: row['image_url'] as String?,
      ownerId: ownerId,
      isPrivate: row['is_private'] == true,
      createdAt: DateTime.tryParse('${row['created_at']}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      memberCount: _aggregate(row['group_members']),
      postCount: _aggregate(row['posts']),
      // An owner is always a member — the trigger sees to it — so this does
      // not depend on the membership lookup having succeeded.
      isMember: isMember || isOwner,
      isOwner: isOwner,
    );
  }

  /// The number out of a PostgREST `(count)` embed.
  ///
  /// Arrives as `[{"count": 3}]` — a list, because the relationship is
  /// to-many — and as an empty list when there is nothing to count rather than
  /// as a zero.
  static int _aggregate(Object? embedded) {
    if (embedded is List) {
      if (embedded.isEmpty) return 0;
      final Object? first = embedded.first;
      if (first is Map<String, dynamic>) return _asInt(first['count']);
      return 0;
    }
    if (embedded is Map<String, dynamic>) return _asInt(embedded['count']);
    return 0;
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        imageUrl,
        ownerId,
        isPrivate,
        memberCount,
        postCount,
        isMember,
        isOwner,
      ];
}

/// A group being created, before it becomes a `groups` row.
///
/// Pure and immutable, like the other drafts, so the rules about when it can
/// be saved are arithmetic testable without a widget or a network.
class GroupDraft extends Equatable {
  const GroupDraft({
    this.name = '',
    this.description = '',
    this.isPrivate = false,
    this.imagePath,
  });

  final String name;
  final String description;
  final bool isPrivate;

  /// Local path of the picked photo, before it is uploaded.
  final String? imagePath;

  /// Bounds matching the CHECK constraints on `groups`, so the form refuses
  /// what the database would.
  static const int minNameLength = 2;
  static const int maxNameLength = 60;
  static const int maxDescriptionLength = 500;

  String get trimmedName => name.trim();
  String get trimmedDescription => description.trim();

  bool get hasImage => imagePath != null;

  bool get isNameValid =>
      trimmedName.length >= minNameLength &&
      trimmedName.length <= maxNameLength;

  bool get isDescriptionValid =>
      trimmedDescription.length <= maxDescriptionLength;

  bool get canSubmit => isNameValid && isDescriptionValid;

  GroupDraft copyWith({
    String? name,
    String? description,
    bool? isPrivate,
    String? imagePath,
    bool clearImage = false,
  }) {
    return GroupDraft(
      name: name ?? this.name,
      description: description ?? this.description,
      isPrivate: isPrivate ?? this.isPrivate,
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
    );
  }

  /// The `groups` column values for this draft.
  ///
  /// `owner_id` is supplied by the repository from the session rather than
  /// living here: a draft that carried its own owner could be saved under
  /// somebody else's name.
  Map<String, dynamic> toRowValues({
    required String ownerId,
    String? imageUrl,
  }) {
    return {
      'owner_id': ownerId,
      'name': trimmedName,
      'description': trimmedDescription.isEmpty ? null : trimmedDescription,
      'is_private': isPrivate,
      'image_url': imageUrl,
    };
  }

  @override
  List<Object?> get props => [name, description, isPrivate, imagePath];
}
