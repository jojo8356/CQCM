import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

class MarkdownText extends StatelessWidget {
  final String data;
  final TextStyle? textStyle;
  final bool shrinkWrap;

  const MarkdownText({
    super.key,
    required this.data,
    this.textStyle,
    this.shrinkWrap = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final config = isDark
        ? MarkdownConfig.darkConfig.copy(configs: [
            PreConfig(theme: _darkCodeTheme),
            PConfig(textStyle: textStyle ?? const TextStyle()),
          ])
        : MarkdownConfig.defaultConfig.copy(configs: [
            PreConfig(theme: _lightCodeTheme),
            PConfig(textStyle: textStyle ?? const TextStyle()),
          ]);

    return MarkdownBlock(
      data: data,
      config: config,
    );
  }
}

// VS Code-like dark theme
const _darkCodeTheme = {
  'root': TextStyle(color: Color(0xFFD4D4D4), backgroundColor: Color(0xFF1E1E1E)),
  'keyword': TextStyle(color: Color(0xFF569CD6)),
  'built_in': TextStyle(color: Color(0xFF4EC9B0)),
  'type': TextStyle(color: Color(0xFF4EC9B0)),
  'literal': TextStyle(color: Color(0xFFB5CEA8)),
  'number': TextStyle(color: Color(0xFFB5CEA8)),
  'string': TextStyle(color: Color(0xFFCE9178)),
  'symbol': TextStyle(color: Color(0xFFD4D4D4)),
  'class': TextStyle(color: Color(0xFF4EC9B0)),
  'function': TextStyle(color: Color(0xFFDCDCAA)),
  'title': TextStyle(color: Color(0xFF4EC9B0)),
  'params': TextStyle(color: Color(0xFF9CDCFE)),
  'comment': TextStyle(color: Color(0xFF6A9955)),
  'doctag': TextStyle(color: Color(0xFF608B4E)),
  'meta': TextStyle(color: Color(0xFFD7BA7D)),
  'meta-keyword': TextStyle(color: Color(0xFF569CD6)),
  'meta-string': TextStyle(color: Color(0xFFCE9178)),
  'attr': TextStyle(color: Color(0xFF9CDCFE)),
  'attribute': TextStyle(color: Color(0xFF9CDCFE)),
  'variable': TextStyle(color: Color(0xFF9CDCFE)),
  'addition': TextStyle(color: Color(0xFF6A9955)),
  'deletion': TextStyle(color: Color(0xFFCE9178)),
};

// VS Code-like light theme
const _lightCodeTheme = {
  'root': TextStyle(color: Color(0xFF383A42), backgroundColor: Color(0xFFF6F8FA)),
  'keyword': TextStyle(color: Color(0xFF0000FF)),
  'built_in': TextStyle(color: Color(0xFF267F99)),
  'type': TextStyle(color: Color(0xFF267F99)),
  'literal': TextStyle(color: Color(0xFF098658)),
  'number': TextStyle(color: Color(0xFF098658)),
  'string': TextStyle(color: Color(0xFFA31515)),
  'symbol': TextStyle(color: Color(0xFF383A42)),
  'class': TextStyle(color: Color(0xFF267F99)),
  'function': TextStyle(color: Color(0xFF795E26)),
  'title': TextStyle(color: Color(0xFF267F99)),
  'params': TextStyle(color: Color(0xFF001080)),
  'comment': TextStyle(color: Color(0xFF008000)),
  'doctag': TextStyle(color: Color(0xFF008000)),
  'meta': TextStyle(color: Color(0xFFAF00DB)),
  'meta-keyword': TextStyle(color: Color(0xFF0000FF)),
  'meta-string': TextStyle(color: Color(0xFFA31515)),
  'attr': TextStyle(color: Color(0xFF001080)),
  'attribute': TextStyle(color: Color(0xFF001080)),
  'variable': TextStyle(color: Color(0xFF001080)),
  'addition': TextStyle(color: Color(0xFF008000)),
  'deletion': TextStyle(color: Color(0xFFA31515)),
};
