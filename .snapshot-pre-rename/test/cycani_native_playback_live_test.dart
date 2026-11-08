import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:kazumi/features/cycani/cycani_api.dart';
import 'cycani_live_test.dart' show ExternalSessionVault;

void main() {
  final session = Platform.environment['CYCANI_LIVE_SESSION'];
  final library = Platform.environment['CYCANI_MPV_LIBRARY'];
  test('native MediaKit loads site MP4, plays silently and seeks', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null; // Opt-in real network, not the widget-test mock.
    MediaKit.ensureInitialized(libmpv: library);
    final api = CycaniApi(vault: ExternalSessionVault(File(session!)));
    await api.restore();
    final url = await api.playUrl(52391);
    final player = Player();
    try {
      final native = player.platform as NativePlayer;
      await native.setProperty('ao', 'null');
      await native.setProperty('vo', 'null');
      await player.setVolume(0);
      await player.open(Media(url, httpHeaders: {'Referer': '${CycaniApi.origin}/'}), play: false);
      final duration = player.state.duration > Duration.zero ? player.state.duration
          : await player.stream.duration.firstWhere((v) => v > Duration.zero).timeout(const Duration(seconds: 45));
      expect(duration.inSeconds, greaterThan(60));
      await player.play();
      await player.stream.position.firstWhere((v) => v.inMilliseconds >= 1000).timeout(const Duration(seconds: 30));
      final seeked = player.stream.position.firstWhere((v) => v.inSeconds >= 29).timeout(const Duration(seconds: 30));
      await player.seek(const Duration(seconds: 30));
      await seeked;
      await player.pause();
      expect(player.state.position.inSeconds, greaterThanOrEqualTo(29));
    } finally {
      await player.dispose();
    }
  }, skip: session == null || library == null || !Platform.isWindows
      ? 'Opt-in: set external CYCANI_LIVE_SESSION and CYCANI_MPV_LIBRARY.' : false,
    timeout: const Timeout(Duration(minutes: 2)));
}
