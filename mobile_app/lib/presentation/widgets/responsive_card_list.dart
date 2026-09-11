import 'package:flutter/material.dart';

/// One column of cards on phones; a wrapping grid on wide (PC / web) screens.
/// Always scrollable, so it works inside a RefreshIndicator.
class ResponsiveCardList extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double minItemWidth;

  const ResponsiveCardList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.minItemWidth = 420,
  });

  @override
  Widget build(BuildContext context) {
    const pad = 16.0;
    const gap = 12.0;

    return LayoutBuilder(builder: (context, constraints) {
      final columns = ((constraints.maxWidth - 2 * pad + gap) / (minItemWidth + gap))
          .floor()
          .clamp(1, 4)
          .toInt();

      if (columns == 1) {
        return ListView.separated(
          padding: const EdgeInsets.all(pad),
          itemCount: itemCount,
          separatorBuilder: (_, _) => const SizedBox(height: gap),
          itemBuilder: itemBuilder,
        );
      }

      final itemWidth = (constraints.maxWidth - 2 * pad - gap * (columns - 1)) / columns;
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(pad),
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < itemCount; i++)
              SizedBox(width: itemWidth, child: itemBuilder(context, i)),
          ],
        ),
      );
    });
  }
}
