import 'package:flutter/material.dart';
import 'package:kazumi/modules/collect/collect_layout.dart';

/// 卡片/列表布局切换分段按钮，追番页与时间表页共用同一样式。
class CollectLayoutSwitch extends StatelessWidget {
  const CollectLayoutSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final CollectLayout value;
  final ValueChanged<CollectLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        for (final layout in [CollectLayout.cards, CollectLayout.list])
          Semantics(
            selected: value == layout,
            inMutuallyExclusiveGroup: true,
            child: IconButton.filledTonal(
              tooltip: '${layout.label}布局',
              isSelected: value == layout,
              onPressed: () => onChanged(layout),
              style: ButtonStyle(
                minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
                visualDensity: VisualDensity.standard,
                backgroundColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected)
                        ? colors.secondaryContainer
                        : colors.surfaceContainerLow),
                foregroundColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.selected)
                        ? colors.onSecondaryContainer
                        : colors.onSurfaceVariant),
                shape: WidgetStateProperty.resolveWith((states) =>
                    RoundedRectangleBorder(
                      borderRadius: states.contains(WidgetState.pressed)
                          ? BorderRadius.circular(12)
                          : states.contains(WidgetState.selected)
                              ? BorderRadius.circular(24)
                              : BorderRadiusDirectional.horizontal(
                                  start: Radius.circular(
                                      layout == CollectLayout.cards ? 24 : 8),
                                  end: Radius.circular(
                                      layout == CollectLayout.list ? 24 : 8),
                                ),
                    )),
                animationDuration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
              ),
              icon: Icon(layout == CollectLayout.list
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded),
            ),
          ),
      ],
    );
  }
}
