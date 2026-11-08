import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cyanmoon_acg/features/cycani/catalog_action.dart';
import 'package:cyanmoon_acg/services/network/image_acceleration.dart';
import 'package:cyanmoon_acg/services/network/image_file_service.dart';
import 'package:cyanmoon_acg/services/network/image_file_response.dart';

void main() {
  test('image body idle timeout releases transport exactly once', () async {
    final stream = StreamController<List<int>>();
    var releases = 0;
    final response = await createImageFileResponse(
      http.StreamedResponse(stream.stream, 200),
      contentLength: null,
      idleTimeout: const Duration(milliseconds: 10),
      onComplete: () => releases++,
    );
    await expectLater(
      response.content.drain<void>(),
      throwsA(isA<TimeoutException>()),
    );
    expect(releases, 1);
    await stream.close();
  });
  test(
    'timed-out direct image requests cannot exhaust the global queue',
    () async {
      final service = ImageFileService(
        modeOverride: ImageAcceleration.direct,
        directTimeout: const Duration(milliseconds: 10),
        clientFactory: () =>
            MockClient((_) => Completer<http.Response>().future),
      );
      try {
        await Future.wait([
          for (var i = 0; i < 7; i++)
            expectLater(
              service.get('https://public.test/$i.jpg'),
              throwsA(isA<TimeoutException>()),
            ),
        ]);
      } finally {
        service.close();
      }
    },
  );
  test(
    'busy mutations are skipped and disposed pages have no callbacks',
    () async {
      final complete = Completer<void>();
      var active = true;
      var busy = false;
      var errors = 0;
      var calls = 0;
      final action = runCatalogAction(
        busy: busy,
        active: () => active,
        setBusy: (v) => busy = v,
        action: () {
          calls++;
          return complete.future;
        },
        onError: (_) => errors++,
      );
      await runCatalogAction(
        busy: busy,
        active: () => active,
        setBusy: (v) => busy = v,
        action: () async {
          calls++;
        },
        onError: (_) => errors++,
      );
      expect(calls, 1);
      active = false;
      complete.completeError(StateError('late'));
      await action;
      expect(errors, 0);
    },
  );
  test('failed mutations release busy and expose one error', () async {
    var busy = false, errors = 0;
    await runCatalogAction(
      busy: busy,
      active: () => true,
      setBusy: (v) => busy = v,
      action: () async => throw StateError('failure'),
      onError: (_) => errors++,
    );
    expect(busy, isFalse);
    expect(errors, 1);
  });
}
