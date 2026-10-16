import 'package:flutter/material.dart';

import '../services/text_scoring.dart';

/// Affichage mot à mot de la comparaison entre la saisie et la référence.
class WordDiffView extends StatelessWidget {
  final TextScore score;
  final bool showLegend;

  const WordDiffView({super.key, required this.score, this.showLegend = true});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasTyped = score.typedTokens.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, 'Ta copie'),
        const SizedBox(height: 6),
        if (!hasTyped)
          Text(
            'Réponse vide',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colorScheme.outline),
          )
        else
          _tokenWrap(context, score.typedTokens, isReference: false),
        const SizedBox(height: 14),
        _sectionTitle(context, 'Réponse attendue'),
        const SizedBox(height: 6),
        _tokenWrap(context, score.expectedTokens, isReference: true),
        if (showLegend) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: const [
              _Legend(color: Colors.green, label: 'juste'),
              _Legend(color: Colors.red, label: 'manquant'),
              _Legend(color: Colors.deepOrange, label: 'faute de frappe'),
              _Legend(color: Colors.amber, label: 'en trop'),
            ],
          ),
        ],
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String label) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  Widget _tokenWrap(
    BuildContext context, List<ScoredToken> tokens, {required bool isReference}) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final token in tokens)
          _tokenChip(context, token, isReference: isReference),
      ],
    );
  }

  Widget _tokenChip(
    BuildContext context,
    ScoredToken token, {
    required bool isReference,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    Color background = Colors.transparent;
    Color foreground = colorScheme.onSurface;
    TextDecoration decoration = TextDecoration.none;
    FontWeight weight = FontWeight.w400;

    switch (token.status) {
      case TokenStatus.matched:
        background = Colors.green.withValues(alpha: 0.16);
        foreground = Colors.green.shade800;
      case TokenStatus.missing:
        background = Colors.red.withValues(alpha: 0.14);
        foreground = Colors.red.shade800;
        weight = FontWeight.w700;
      case TokenStatus.extra:
        background = Colors.amber.withValues(alpha: 0.22);
        foreground = Colors.orange.shade900;
        decoration = TextDecoration.lineThrough;
      case TokenStatus.typo:
        background = Colors.deepOrange.withValues(alpha: 0.16);
        foreground = Colors.deepOrange.shade800;
        decoration = TextDecoration.underline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        token.value,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: foreground,
          fontWeight: weight,
          decoration: decoration,
          decorationColor: foreground,
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
