import 'package:bulkr/data/image_uploader.dart';
import 'package:bulkr/models/group.dart';
import 'package:bulkr/models/meal.dart';
import 'package:bulkr/models/post.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every picture uploaded before thumbnails existed has a null `thumb_url`,
/// and always will — going back to generate them would mean downloading the
/// whole bucket. So the fallback is not an edge case, it is most of the data,
/// and a card that renders nothing for an older meal is the failure mode.
void main() {
  group('Meal.smallImageUrl', () {
    test('prefers the thumbnail', () {
      final Meal meal = Meal.fromRow({
        'id': 'm1',
        'title': 'Chicken and rice',
        'image_url': 'https://cdn/full.jpg',
        'thumb_url': 'https://cdn/full_t.jpg',
      });

      expect(meal.smallImageUrl, 'https://cdn/full_t.jpg');
    });

    test('falls back to the full size when there is no thumbnail', () {
      final Meal meal = Meal.fromRow({
        'id': 'm1',
        'title': 'Chicken and rice',
        'image_url': 'https://cdn/full.jpg',
      });

      expect(meal.smallImageUrl, 'https://cdn/full.jpg');
    });

    test('stays null for a meal with no photo at all', () {
      final Meal meal = Meal.fromRow({'id': 'm1', 'title': 'Toast'});
      expect(meal.smallImageUrl, isNull);
    });
  });

  group('Group.smallImageUrl', () {
    test('falls back to the full size', () {
      final Group group = Group.fromRow({
        'id': 'g1',
        'name': 'Bulk club',
        'image_url': 'https://cdn/g.jpg',
      });

      expect(group.smallImageUrl, 'https://cdn/g.jpg');
    });
  });

  group('Post image thumbnails', () {
    // Per image, not per post: one old photo must not cost the new one its
    // thumbnail.
    test('each photo falls back on its own', () {
      final Post post = Post.fromRow({
        'id': 'p1',
        'user_id': 'u1',
        'content': 'before and after',
        'post_images': [
          {'url': 'https://cdn/a.jpg', 'position': 0},
          {
            'url': 'https://cdn/b.jpg',
            'thumb_url': 'https://cdn/b_t.jpg',
            'position': 1,
          },
        ],
      });

      expect(post.imageUrls, ['https://cdn/a.jpg', 'https://cdn/b.jpg']);
      expect(post.imageThumbUrls, ['https://cdn/a.jpg', 'https://cdn/b_t.jpg']);
    });

    // The order is the author's, and a before/after read backwards is wrong.
    test('thumbnails keep the same order as the photos', () {
      final Post post = Post.fromRow({
        'id': 'p1',
        'user_id': 'u1',
        'content': 'x',
        'post_images': [
          {'url': 'https://cdn/b.jpg', 'thumb_url': 'https://cdn/b_t.jpg', 'position': 1},
          {'url': 'https://cdn/a.jpg', 'thumb_url': 'https://cdn/a_t.jpg', 'position': 0},
        ],
      });

      expect(post.imageUrls, ['https://cdn/a.jpg', 'https://cdn/b.jpg']);
      expect(post.imageThumbUrls, ['https://cdn/a_t.jpg', 'https://cdn/b_t.jpg']);
    });

    test('an empty thumb_url counts as none', () {
      final Post post = Post.fromRow({
        'id': 'p1',
        'user_id': 'u1',
        'content': 'x',
        'post_images': [
          {'url': 'https://cdn/a.jpg', 'thumb_url': '', 'position': 0},
        ],
      });

      expect(post.imageThumbUrls, ['https://cdn/a.jpg']);
    });
  });

  group('ImageUploader.storagePathFor', () {
    test('reads the object path out of a public URL', () {
      expect(
        ImageUploader.storagePathFor(
          'https://x.supabase.co/storage/v1/object/public/meal-images/u1/12.jpg',
          bucket: 'meal-images',
        ),
        'u1/12.jpg',
      );
    });

    test('ignores a URL from another bucket', () {
      expect(
        ImageUploader.storagePathFor(
          'https://x.supabase.co/storage/v1/object/public/post-images/u1/12.jpg',
          bucket: 'meal-images',
        ),
        isNull,
      );
    });

    // A picture hosted anywhere else is not ours to delete.
    test('ignores a URL that is not storage at all', () {
      expect(
        ImageUploader.storagePathFor('https://example.com/x.jpg',
            bucket: 'meal-images'),
        isNull,
      );
    });

    test('ignores null and empty', () {
      expect(ImageUploader.storagePathFor(null, bucket: 'meal-images'), isNull);
      expect(ImageUploader.storagePathFor('', bucket: 'meal-images'), isNull);
    });

    test('drops a query string', () {
      expect(
        ImageUploader.storagePathFor(
          'https://x.supabase.co/storage/v1/object/public/avatars/u1/9.jpg?t=1',
          bucket: 'avatars',
        ),
        'u1/9.jpg',
      );
    });
  });
}
