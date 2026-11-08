import 'dart:async';
import 'package:flutter/material.dart';

/// Deadline-based so returning from the background does not extend the wait.
class VerificationCooldown extends ChangeNotifier {
  VerificationCooldown({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  DateTime? _deadline;
  Timer? _timer;
  int get remaining {
    final end = _deadline;
    if (end == null) return 0;
    return ((end.difference(_now()).inMilliseconds + 999) ~/ 1000).clamp(
      0,
      86400,
    );
  }

  void start([Duration duration = const Duration(seconds: 60)]) {
    _timer?.cancel();
    _deadline = _now().add(duration);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (remaining == 0) _timer?.cancel();
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

mixin VerificationCooldownState<T extends StatefulWidget> on State<T> {
  late final cooldown = VerificationCooldown()..addListener(_tick);
  int get countdown => cooldown.remaining;
  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    cooldown.dispose();
    super.dispose();
  }
}

class CatalogAccountField extends StatelessWidget {
  const CatalogAccountField({
    super.key,
    required this.controller,
    required this.label,
    this.secret = false,
    this.required = false,
    this.enabled = true,
    this.keyboardType,
    this.autofillHints,
    this.validator,
  });
  final TextEditingController controller;
  final String label;
  final bool secret, required, enabled;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final FormFieldValidator<String>? validator;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: secret,
      enableSuggestions: !secret,
      autocorrect: !secret,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      validator:
          validator ??
          (required
              ? (value) =>
                    value == null || value.trim().isEmpty ? '请填写$label' : null
              : null),
    ),
  );
}
