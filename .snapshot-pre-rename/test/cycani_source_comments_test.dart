import 'package:kazumi/features/cycani/cycani_source_comments.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kazumi/features/cycani/cycani_source_accounts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'signed-out comment writes require the matching source account',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = SourceAccounts();
      for (final giri in [false, true]) {
        await expectLater(api.postComment(giri, 123, 'test'), throwsStateError);
      }
      await expectLater(
        api.updateXifanProfile(displayName: 'test'),
        throwsStateError,
      );
    },
  );

  test(
    'live external comments keep their original site and pagination fields',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = SourceAccounts();
      final x = await api.readComments(false, 3432, sort: 'most_liked');
      final g = await api.readComments(true, 27203);
      expect(x['items'], isA<List>());
      expect(x, contains('next_cursor'));
      expect(g['rows'], isA<List>());
      expect(g, contains('total'));
    },
    skip: Platform.environment['CYCANI_COMMENTS_LIVE'] != '1',
  );
  test(
    'disk comments keep only public fields including nested Giri replies',
    () {
      final x = publicSourceComment({
        'id': 3,
        'is_mine': true,
        'my_reaction': 'like',
        'like_count': 2,
        'author': {'name': 'name', 'account_id': 'private'},
      }, giri: false);
      expect(x, {
        'id': 3,
        'like_count': 2,
        'author': {'name': 'name'},
      });
      final g = publicSourceComment({
        'comment_id': 9,
        'user_id': 23,
        'chile_list': [
          {'comment_id': 10, 'comment_content': 'reply', 'user_id': 24},
        ],
      }, giri: true);
      expect(g, {
        'comment_id': 9,
        'chile_list': [
          {'comment_id': 10, 'comment_content': 'reply'},
        ],
      });
      expect(sourceCommentDate(0), isEmpty);
      expect(sourceCommentDate('2026-11-03T12:30:00'), '2026-11-03 12:30');
    },
  );
}
