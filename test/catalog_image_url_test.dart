import 'package:flutter_test/flutter_test.dart';
import 'package:cyanmoon_acg/services/network/catalog_image_url.dart';

void main() {
  test('public covers use Baidu and Xifan grid variant', () {
    final url = 'https://img2.xfmanga.top/r/1200/a.jpg';
    expect(
      CatalogImageUrl.thumbnail(url),
      'https://img2.xfmanga.top/r/600/a.jpg',
    );
    final proxy = CatalogImageUrl.proxy(Uri.parse(url))!;
    expect(proxy.host, 'gimg1.baidu.com');
    expect(
      Uri.decodeComponent(proxy.path),
      contains('img2.xfmanga.top/r/1200/a.jpg'),
    );
  });
  test(
    'private, signed, spoofed and non-image API hosts are never proxied',
    () {
      for (final url in [
        'https://img2.xfmanga.top/a.jpg?token=secret',
        'https://jpg.girigirilove.com/avatar/a.jpg',
        'https://jpg.girigirilove.com.evil.test/a.jpg',
        'https://u:p@jpg.girigirilove.com/a.jpg',
        'https://m3u8.girigirilove.com/api.php/test',
        'https://gimg1.baidu.com/gimg/app=2001&src=a',
      ]) {
        expect(CatalogImageUrl.proxy(Uri.parse(url)), isNull);
      }
      expect(
        CatalogImageUrl.proxy(
          Uri.parse('https://jpg.girigirilove.com/a.jpg'),
          headers: {'Authorization': 'secret'},
        ),
        isNull,
      );
    },
  );
  test('relative Giri cover is resolved against its image origin', () {
    expect(
      CatalogImageUrl.giriPublic('upload/vod/a.webp'),
      'https://jpg.girigirilove.com/upload/vod/a.webp',
    );
    expect(
      CatalogImageUrl.giriPublic('/upload/vod/a.webp'),
      'https://jpg.girigirilove.com/upload/vod/a.webp',
    );
    expect(
      CatalogImageUrl.giriPublic('https://other.test/a.jpg'),
      'https://other.test/a.jpg',
    );
  });
}
