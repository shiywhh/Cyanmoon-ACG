import 'dart:async';
import 'dart:io';
import 'catalog_lru.dart';

/// TCP-only address fallback. HttpClient retains the original hostname for TLS
/// certificate verification, SNI and Host; no HTTP write is replayed here.
class CatalogConnection {
  CatalogConnection({
    Future<List<InternetAddress>> Function(String)? lookup,
    Future<ConnectionTask<Socket>> Function(InternetAddress, int)? connect,
    this.timeout = const Duration(seconds: 4),
    this.stagger = const Duration(milliseconds: 250),
  }) : _lookup = lookup ?? InternetAddress.lookup,
       _connect = connect ?? Socket.startConnect;
  final Future<List<InternetAddress>> Function(String) _lookup;
  final Future<ConnectionTask<Socket>> Function(InternetAddress, int) _connect;
  final Duration timeout, stagger;
  final _offsets = CatalogLru<String, int>(capacity: 64);

  Future<ConnectionTask<Socket>> call(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) async {
    final host = proxyHost ?? uri.host, port = proxyPort ?? uri.port;
    final result = Completer<Socket>();
    final attempts = <ConnectionTask<Socket>>[];
    final scheduled = <Timer>[];
    ConnectionTask<Socket>? winner;
    late Timer deadline;
    void cleanup() {
      deadline.cancel();
      for (final timer in scheduled) {
        timer.cancel();
      }
      for (final task in attempts) {
        if (task != winner) task.cancel();
      }
    }

    void fail(Object error) {
      if (result.isCompleted) return;
      result.completeError(error);
      cleanup();
    }

    deadline = Timer(
      timeout,
      () => fail(
        SocketException(
          'Connection timed out',
          address: InternetAddress.tryParse(host),
          port: port,
        ),
      ),
    );
    Future<void> run() async {
      try {
        // Resolve afresh on each new connection/retry instead of pinning a failed node.
        final resolved = await _lookup(host);
        if (result.isCompleted) return;
        final addresses = <InternetAddress>[];
        final seen = <String>{};
        for (final address in resolved) {
          if (seen.add(address.address)) addresses.add(address);
        }
        if (addresses.isEmpty) throw SocketException('No addresses for $host');
        final offset = (_offsets[host] ?? 0) % addresses.length;
        _offsets[host] = offset + 1;
        final ordered = [
          ...addresses.skip(offset),
          ...addresses.take(offset),
        ].take(6).toList();
        var pending = ordered.length;
        Future<void> attempt(InternetAddress address) async {
          if (result.isCompleted) return;
          try {
            final task = await _connect(address, port);
            attempts.add(task);
            // Attach before cancellation: a canceled task completes with an error.
            final socketFuture = task.socket;
            if (result.isCompleted) task.cancel();
            final socket = await socketFuture;
            if (result.isCompleted) {
              socket.destroy();
              return;
            }
            winner = task;
            result.complete(socket);
            cleanup();
          } catch (error) {
            if (--pending == 0) fail(error);
          }
        }

        for (var i = 0; i < ordered.length; i++) {
          if (i == 0) {
            unawaited(attempt(ordered[i]));
          } else {
            final address = ordered[i];
            scheduled.add(
              Timer(stagger * i, () => unawaited(attempt(address))),
            );
          }
        }
      } catch (error) {
        fail(error);
      }
    }

    unawaited(run());
    return ConnectionTask.fromSocket(
      result.future,
      () => fail(const SocketException('Connection cancelled')),
    );
  }
}
