/// Shared mutation guard. A disposed page never receives completion callbacks.
Future<void> runCatalogAction({
  required bool busy,
  required bool Function() active,
  required void Function(bool) setBusy,
  required Future<void> Function() action,
  required void Function(Object) onError,
  void Function()? onSuccess,
}) async {
  if (busy || !active()) return;
  setBusy(true);
  try {
    await action();
    if (active()) onSuccess?.call();
  } catch (error) {
    if (active()) onError(error);
  } finally {
    if (active()) setBusy(false);
  }
}
