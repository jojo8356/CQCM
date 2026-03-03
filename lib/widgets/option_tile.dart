import 'package:flutter/material.dart';

class OptionTile extends StatelessWidget {
  final String text;
  final int index;
  final bool isSelected;
  final bool isMultipleChoice;
  final bool hasValidated;
  final bool isCorrect;
  final VoidCallback onTap;

  const OptionTile({
    super.key,
    required this.text,
    required this.index,
    required this.isSelected,
    required this.isMultipleChoice,
    required this.hasValidated,
    required this.isCorrect,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Color? backgroundColor;
    Color? borderColor;
    Color? textColor;

    if (hasValidated) {
      if (isCorrect) {
        backgroundColor = Colors.green.withValues(alpha: 0.1);
        borderColor = Colors.green;
        textColor = Colors.green.shade800;
      } else if (isSelected) {
        backgroundColor = Colors.red.withValues(alpha: 0.1);
        borderColor = Colors.red;
        textColor = Colors.red.shade800;
      }
    } else if (isSelected) {
      backgroundColor = colorScheme.primaryContainer;
      borderColor = colorScheme.primary;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: hasValidated ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: backgroundColor ?? colorScheme.surface,
            border: Border.all(
              color: borderColor ?? colorScheme.outlineVariant,
              width: isSelected || (hasValidated && isCorrect) ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _buildLeading(colorScheme),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: isSelected || (hasValidated && isCorrect)
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
              if (hasValidated && isCorrect)
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
              if (hasValidated && isSelected && !isCorrect)
                const Icon(Icons.cancel, color: Colors.red, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeading(ColorScheme colorScheme) {
    if (isMultipleChoice) {
      return Icon(
        isSelected ? Icons.check_box : Icons.check_box_outline_blank,
        color: isSelected ? colorScheme.primary : colorScheme.outline,
        size: 24,
      );
    }
    return Icon(
      isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      color: isSelected ? colorScheme.primary : colorScheme.outline,
      size: 24,
    );
  }
}
