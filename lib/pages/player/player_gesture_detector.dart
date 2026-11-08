import 'package:flutter/widgets.dart';

class PlayerGestureDetector extends StatefulWidget {
  const PlayerGestureDetector({
    super.key,
    required this.onSeekStart,
    required this.onSeekUpdate,
    required this.onSeekEnd,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
    this.onVerticalDragCancel,
  });

  final VoidCallback onSeekStart;
  final void Function(double delta, bool cancelPending) onSeekUpdate;
  final void Function(bool cancelled) onSeekEnd;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;
  final GestureDragCancelCallback? onVerticalDragCancel;

  @override
  State<PlayerGestureDetector> createState() => _PlayerGestureDetectorState();
}

class _PlayerGestureDetectorState extends State<PlayerGestureDetector> {
  bool? _cancelPending;
  final Set<int> _downPointers = {};
  int? _lastDownPointer;
  int? _seekPointer;

  void _endSeek({bool cancelled = false}) {
    final cancelPending = _cancelPending;
    if (cancelPending == null) return;
    _cancelPending = null;
    _seekPointer = null;
    widget.onSeekEnd(cancelled || cancelPending);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isAtEdge(Offset position) =>
            position.dx <= 0 ||
            position.dy <= 0 ||
            position.dx >= constraints.maxWidth ||
            position.dy >= constraints.maxHeight;

        return Listener(
          behavior: HitTestBehavior.translucent,
          // Flutter reports pointer cancellation as onEnd for accepted drags.
          onPointerDown: (event) {
            _downPointers.add(event.pointer);
            _lastDownPointer = event.pointer;
          },
          onPointerUp: (event) => _downPointers.remove(event.pointer),
          onPointerCancel: (event) {
            _downPointers.remove(event.pointer);
            // 仅当被取消的是发起 seek 的那根指针时才结束 seek；
            // 第二根手指被系统/手势抢占取消不应误结束进行中的横向 seek。
            if (_seekPointer == null || _seekPointer == event.pointer) {
              _endSeek(cancelled: true);
            }
          },
          child: GestureDetector(
            onHorizontalDragStart: (details) {
              _cancelPending = isAtEdge(details.localPosition);
              // 发起 seek 的指针取最近按下且仍存活的指针（拖拽回调不携带 pointer id）。
              final candidate = _lastDownPointer;
              _seekPointer =
                  candidate != null && _downPointers.contains(candidate)
                      ? candidate
                      : null;
              widget.onSeekStart();
            },
            onHorizontalDragUpdate: (details) {
              final wasCancelPending = _cancelPending;
              if (wasCancelPending == null) return;
              final cancelPending = isAtEdge(details.localPosition);
              final delta =
                  cancelPending || wasCancelPending ? 0.0 : details.delta.dx;
              _cancelPending = cancelPending;
              widget.onSeekUpdate(delta, cancelPending);
            },
            onHorizontalDragEnd: (_) => _endSeek(),
            onVerticalDragUpdate: widget.onVerticalDragUpdate,
            onVerticalDragEnd: widget.onVerticalDragEnd,
            onVerticalDragCancel: widget.onVerticalDragCancel,
          ),
        );
      },
    );
  }
}
