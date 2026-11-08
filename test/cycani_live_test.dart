// Opt-in, read-only integration checks. No real token is part of this file.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/cycani/cycani_api.dart';
import 'package:kazumi/features/cycani/catalog_models.dart';

class ExternalSessionVault implements CycaniVault {
  ExternalSessionVault(this.file);
  final File file;
  @override
  Future<String?> read() => file.readAsString();
  @override
  Future<void> write(String? value) async {
    // Keep renewed credentials out of test output and out of the repository.
    if (value != null) {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(value);
      await tmp.rename(file.path);
    }
  }
}

void main() {
  final path = Platform.environment['CYCANI_LIVE_SESSION'];
  test(
    'real site catalogue, account reads, native API media resolver and 1KB MP4 range',
    () async {
      final api = CycaniApi(vault: ExternalSessionVault(File(path!)));
      await api.restore();
      final catalogue = await api.videos();
      expect(catalogList(catalogue), isNotEmpty);
      final results = await api.videos(keyword: '紫罗兰永恒花园');
      expect(catalogList(results).length, greaterThanOrEqualTo(3));
      final video = await api.detail(63);
      expect(video.bangumiId, 183878);
      final episodes = await api.episodes(video.id, video: video);
      expect(episodes.first.items.length, 13);
      expect(await api.recommendations(), isNotEmpty);
      expect(await api.zones(), isNotEmpty);
      final ranks = await api.ranks();
      expect(ranks, isNotEmpty);
      expect(await api.rankVideos(catalogInt(ranks.first['id'])), isNotEmpty);
      expect(await api.schedule(1), isNotEmpty);
      await api.profile();
      expect(api.loggedIn, true);
      expect(api.user, isNotEmpty);
      await api.favorites();
      await api.histories();
      await api.comments(63);
      final comments = await api.danmaku(52391);
      expect(comments, isNotEmpty);
      final media = await api.playUrl(52391);
      final uri = Uri.parse(media);
      expect(uri.scheme, 'https');
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      try {
        final request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
        request.headers.set(HttpHeaders.refererHeader, '${CycaniApi.origin}/');
        final response = await request.close();
        expect(response.statusCode, 206);
        if (response.statusCode != 206)
          throw StateError(
            'Server did not honor byte range; full download aborted',
          );
        final bytes = await response.fold<List<int>>(
          [],
          (all, chunk) => all..addAll(chunk),
        );
        expect(bytes.length, 1024);
        expect(String.fromCharCodes(bytes.take(64)), contains('ftyp'));
      } finally {
        client.close(force: true);
      }
    },
    skip: path == null
        ? 'Set CYCANI_LIVE_SESSION to an external private session JSON to enable.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
