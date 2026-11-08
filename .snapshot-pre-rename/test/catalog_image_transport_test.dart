import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kazumi/services/network/image_acceleration.dart';
import 'package:kazumi/services/network/image_file_service.dart';

void main() {
  test(
    'Baidu bad body falls back to original image without origin headers leakage',
    () async {
      final hosts = <String>[];
      final service = ImageFileService(
        modeOverride: ImageAcceleration.baidu,
        clientFactory: () => MockClient((r) async {
          hosts.add(r.url.host);
          if (r.url.host == 'gimg1.baidu.com') {
            expect(r.headers.containsKey('referer'), isFalse);
            return http.Response(
              'not an image',
              200,
              headers: {'content-type': 'image/jpeg'},
            );
          }
          expect(r.headers['referer'], 'https://next.xifanacg.com/');
          return http.Response.bytes(
            [255, 216, 255, 0],
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );
      final response = await service.get(
        'https://img2.xfmanga.top/r/600/a.jpg',
        headers: {'referer': 'https://next.xifanacg.com/'},
      );
      expect(await response.content.expand((x) => x).toList(), [
        255,
        216,
        255,
        0,
      ]);
      expect(hosts, ['gimg1.baidu.com', 'img2.xfmanga.top']);
      service.close();
    },
  );
  test('credentialed images never leave original host', () async {
    final service = ImageFileService(
      modeOverride: ImageAcceleration.baidu,
      clientFactory: () => MockClient((r) async {
        expect(r.url.host, 'jpg.girigirilove.com');
        expect(r.headers['authorization'], 'Bearer local-test');
        return http.Response.bytes([255, 216, 255, 0], 200);
      }),
    );
    final response = await service.get(
      'https://jpg.girigirilove.com/a.jpg',
      headers: {'authorization': 'Bearer local-test'},
    );
    await response.content.drain<void>();
    service.close();
  });
  test(
    'HTTP 200 tiny GIF proxy placeholder is rejected and fetched directly',
    () async {
      final hosts = <String>[];
      final service = ImageFileService(
        modeOverride: ImageAcceleration.baidu,
        clientFactory: () => MockClient((r) async {
          hosts.add(r.url.host);
          if (r.url.host == 'gimg1.baidu.com')
            return http.Response.bytes(
              [71, 73, 70, 56, 57, 97, 4, 0, 8, 0, ...List.filled(42, 0)],
              200,
              headers: {'content-type': 'image/gif'},
            );
          return http.Response.bytes(
            [255, 216, 255, ...List.filled(160, 0)],
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }),
      );
      final response = await service.get('https://jpg.girigirilove.com/a.jpg');
      await response.content.drain<void>();
      expect(hosts, ['gimg1.baidu.com', 'jpg.girigirilove.com']);
      service.close();
    },
  );
}
