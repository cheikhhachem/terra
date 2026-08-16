import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

class TerraHeader extends StatelessWidget {
  const TerraHeader({
    super.key,
    required this.title,
    this.actions = const [],
    this.nested = true,
  });

  final Widget title;
  final List<Widget> actions;
  final bool nested;

  @override
  Widget build(BuildContext context) => nested
      ? FHeader.nested(
          title: title,
          prefixes: [FHeaderAction.back(onPress: () => Navigator.of(context).maybePop())],
          suffixes: actions,
        )
      : FHeader(title: title, suffixes: actions);
}
