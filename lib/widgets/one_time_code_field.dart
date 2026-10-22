import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:checkpoint/l10n/l10n.dart';

/// The six-digit code an authenticator app shows. Only digits go in (a pasted
/// code keeps its digits), and [onSubmit] runs once all six are typed, or on
/// the keyboard's done key.
class OneTimeCodeField extends StatelessWidget {
  const OneTimeCodeField({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.enabled = true,
    this.autofocus = false,
    this.errorText,
  });

  static const length = 6;

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool enabled;
  final bool autofocus;

  /// Shown under the field, as for a form field that failed its check.
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.oneTimeCode],
      autocorrect: false,
      enableSuggestions: false,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 8,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(length),
      ],
      decoration: InputDecoration(
        labelText: context.l10n.sixDigitCode,
        errorText: errorText,
        errorMaxLines: 3,
      ),
      onChanged: (value) {
        if (value.length == length) onSubmit();
      },
      onSubmitted: (_) => onSubmit(),
    );
  }
}
