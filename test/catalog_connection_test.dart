import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/cycani/catalog_connection.dart';
import 'package:kazumi/features/cycani/catalog_http.dart';

void main() {
  test(
    'address fallback connects to healthy node and rotates fresh DNS on retry',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = <Socket>[];
      final listener = server.listen(accepted.add);
      final attempts = <String>[];
      var lookups = 0;
      final connector = CatalogConnection(
        stagger: const Duration(milliseconds: 10),
        lookup: (_) async {
          lookups++;
          return [InternetAddress('127.0.0.2'), InternetAddress.loopbackIPv4];
        },
        connect: (address, port) {
          attempts.add(address.address);
          return Socket.startConnect(address, port);
        },
      );
      try {
        final uri = Uri.parse('http://fixture.invalid:${server.port}');
        for (var i = 0; i < 2; i++) {
          final task = await connector.call(uri, null, null);
          final socket = await task.socket;
          expect(socket.remoteAddress.address, '127.0.0.1');
          socket.destroy();
        }
        expect(lookups, 2);
        expect(attempts.take(3), ['127.0.0.2', '127.0.0.1', '127.0.0.1']);
      } finally {
        for (final socket in accepted) {
          socket.destroy();
        }
        await listener.cancel();
        await server.close();
      }
    },
  );
  test('cancellation during DNS completes without late connection', () async {
    final dns = Completer<List<InternetAddress>>();
    var calls = 0;
    final connector = CatalogConnection(
      lookup: (_) => dns.future,
      connect: (address, port) {
        calls++;
        return Socket.startConnect(address, port);
      },
    );
    final task = await connector.call(
      Uri.parse('https://fixture.invalid'),
      null,
      null,
    );
    final assertion = expectLater(task.socket, throwsA(isA<SocketException>()));
    task.cancel();
    await assertion;
    dns.complete([InternetAddress.loopbackIPv4]);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);
  });
  test('all DNS and connect work is bounded by one deadline', () async {
    final connector = CatalogConnection(
      timeout: const Duration(milliseconds: 20),
      lookup: (_) => Completer<List<InternetAddress>>().future,
    );
    final task = await connector.call(
      Uri.parse('https://fixture.invalid'),
      null,
      null,
    );
    await expectLater(task.socket, throwsA(isA<SocketException>()));
  });
  test(
    'site clients reject cross-origin before sending account headers',
    () async {
      final dio = CatalogHttp.client('https://first.invalid', {
        'Authorization': 'fixture',
      });
      await expectLater(
        dio.get('https://second.invalid/private'),
        throwsA(predicate((e) => '$e'.contains('Cross-origin'))),
      );
      dio.close(force: true);
    },
  );
}
