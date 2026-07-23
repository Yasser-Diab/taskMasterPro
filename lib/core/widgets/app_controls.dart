import 'package:flutter/material.dart';

import '../../app/app_services.dart';

class AppButton extends StatelessWidget {
  const AppButton.filled({
    required this.onPressed,
    required this.label,
    this.icon,
    this.loading = false,
    super.key,
  }) : _variant = _AppButtonVariant.filled;

  const AppButton.outlined({
    required this.onPressed,
    required this.label,
    this.icon,
    this.loading = false,
    super.key,
  }) : _variant = _AppButtonVariant.outlined;

  const AppButton.text({
    required this.onPressed,
    required this.label,
    this.icon,
    this.loading = false,
    super.key,
  }) : _variant = _AppButtonVariant.text;

  final VoidCallback? onPressed;
  final Widget label;
  final Widget? icon;
  final bool loading;
  final _AppButtonVariant _variant;

  @override
  Widget build(BuildContext context) {
    final effectivePressed = onPressed == null || loading
        ? null
        : () {
            AppServices.of(context).feedbackService.playUiClick();
            onPressed!();
          };
    final effectiveIcon = loading
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : icon;

    return switch (_variant) {
      _AppButtonVariant.filled =>
        effectiveIcon == null
            ? FilledButton(onPressed: effectivePressed, child: label)
            : FilledButton.icon(
                onPressed: effectivePressed,
                icon: effectiveIcon,
                label: label,
              ),
      _AppButtonVariant.outlined =>
        effectiveIcon == null
            ? OutlinedButton(onPressed: effectivePressed, child: label)
            : OutlinedButton.icon(
                onPressed: effectivePressed,
                icon: effectiveIcon,
                label: label,
              ),
      _AppButtonVariant.text =>
        effectiveIcon == null
            ? TextButton(onPressed: effectivePressed, child: label)
            : TextButton.icon(
                onPressed: effectivePressed,
                icon: effectiveIcon,
                label: label,
              ),
    };
  }
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    required this.onPressed,
    required this.icon,
    required this.tooltip,
    super.key,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed == null
          ? null
          : () {
              AppServices.of(context).feedbackService.playUiClick();
              onPressed!();
            },
      icon: icon,
    );
  }
}

class AppSwitchListTile extends StatelessWidget {
  const AppSwitchListTile({
    required this.value,
    required this.title,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  final bool value;
  final Widget title;
  final Widget? subtitle;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      title: title,
      subtitle: subtitle,
      onChanged: onChanged == null
          ? null
          : (value) {
              AppServices.of(context).feedbackService.playUiClick();
              onChanged!(value);
            },
    );
  }
}

class AppCheckboxListTile extends StatelessWidget {
  const AppCheckboxListTile({
    required this.value,
    required this.title,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final Widget title;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      title: title,
      onChanged: onChanged == null
          ? null
          : (value) {
              AppServices.of(context).feedbackService.playUiClick();
              onChanged!(value);
            },
    );
  }
}

enum _AppButtonVariant { filled, outlined, text }
