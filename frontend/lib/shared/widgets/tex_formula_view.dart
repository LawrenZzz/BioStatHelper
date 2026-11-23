import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class TexFormulaView extends StatelessWidget {
  const TexFormulaView({
    super.key,
    required this.expression,
  });

  final String expression;

  @override
  Widget build(BuildContext context) {
    final latex = _normalizeExpression(expression);
    final textStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w500,
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Center(
          child: _buildMath(context, latex, textStyle),
        ),
      ),
    );
  }

  Widget _buildMath(BuildContext context, String latex, TextStyle? textStyle) {
    try {
      return Math.tex(
        latex,
        mathStyle: MathStyle.display,
        textStyle: textStyle,
      );
    } catch (_) {
      return SelectableText(
        expression,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      );
    }
  }

  String _normalizeExpression(String value) {
    var text = value.trim();
    text = text.replaceAll('Σ', r'\sum ');
    text = text.replaceAll('Π', r'\prod ');
    text = text.replaceAll('∞', r'\infty ');
    text = text.replaceAll('±', r'\pm ');
    text = text.replaceAll('>=', r'\ge ');
    text = text.replaceAll('<=', r'\le ');
    text = text.replaceAll('*', r'\cdot ');
    text = text.replaceAll('sqrt(n)', r'\sqrt{n}');
    text = _replaceFunction(text, 'sqrt', r'\sqrt');
    text = _replacePlainSubscripts(text);
    text = text.replaceAll('alpha', r'\alpha');
    text = text.replaceAll('beta', r'\beta');
    text = text.replaceAll('epsilon', r'\epsilon');
    text = text.replaceAll('lambda', r'\lambda');
    text = _restorePlaceholders(text);
    return text;
  }

  String _replaceFunction(String value, String name, String replacement) {
    final index = value.indexOf('$name(');
    if (index == -1) return value;
    final start = index + name.length + 1;
    var depth = 1;
    for (var i = start; i < value.length; i++) {
      final char = value[i];
      if (char == '(') depth++;
      if (char == ')') depth--;
      if (depth == 0) {
        final inner = value.substring(start, i);
        return '${value.substring(0, index)}$replacement{$inner}${value.substring(i + 1)}';
      }
    }
    return value;
  }

  String _replacePlainSubscripts(String value) {
    var text = value;
    final replacements = {
      "beta'": '__BETA_T__',
      'beta0': '__BETA_0__',
      'beta1': '__BETA_1__',
      'betap': '__BETA_P__',
      'X1': r'X_1',
      'Xp': r'X_p',
      'x_i': r'x_i',
      'd_i': r'd_i',
      'n_i': r'n_i',
      'h0': r'h_0',
      'z_obs': r'z_{obs}',
      'xbar': r'\bar{x}',
    };
    for (final entry in replacements.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    return text;
  }

  String _restorePlaceholders(String value) {
    return value
        .replaceAll('__BETA_T__', r'\beta^T')
        .replaceAll('__BETA_0__', r'\beta_0')
        .replaceAll('__BETA_1__', r'\beta_1')
        .replaceAll('__BETA_P__', r'\beta_p');
  }
}
