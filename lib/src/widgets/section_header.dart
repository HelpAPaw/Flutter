import 'package:flutter/material.dart';

/// Heading above a group of fields, with an optional grey note beside it.
///
/// One implementation on purpose. There were two private copies of this — one
/// in the old new-signal form at a hardcoded `fontSize: 13`, one in the helper
/// tags onboarding page on `titleMedium` — so the same heading rendered at two
/// different sizes on two screens that sit one tap apart. This is the
/// onboarding version, because it scales with the user's text-size setting
/// instead of pinning a pixel value.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.hint});

  final String text;

  /// Secondary note rendered beside [text] — a cap, a "(optional)", a count.
  /// Ellipsised rather than wrapped so it can never push the heading around.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(fontWeight: FontWeight.w600);

    if (hint == null) return Text(text, style: style);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(text, style: style),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            hint!,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
