import 'package:flutter/material.dart';

import '../app_icons.dart';
import '../theme.dart';

// The instrument vocabulary the tabs already speak — low bordered chips, the
// caps section label, hairline dividers, the accent primary button — as
// shared widgets, so a new surface can't drift into stock Material controls.
//
// Every glyph here comes from [AppIcons]: a Shorebird patch ships code only,
// and a Material glyph the release never drew is missing from the icon font
// on installed devices.

/// The small caps label that heads a section or sits above a readout, with
/// an optional dimmed count or hint trailing it.
class AppSectionLabel extends StatelessWidget {
  final String label;
  final String? trailing;
  const AppSectionLabel(this.label, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      text: label.toUpperCase(),
      style: AppTextStyles.statLabel(),
      children: [
        if (trailing != null)
          TextSpan(
            text: '  $trailing',
            style: AppTextStyles.statLabel(color: AppColors.textDimmed),
          ),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

/// A low selectable chip: 1px border, accent border and tinted fill when
/// active — the dispersion filter chips, one size up for touch.
class AppChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final IconData? icon;

  /// Marks the chip with the setup or club colour instead of the accent.
  final Color? color;

  const AppChip({
    super.key,
    required this.label,
    required this.active,
    this.onTap,
    this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.accent;
    final enabled = onTap != null;
    final foreground = active
        ? tint
        : enabled
        ? AppColors.textMuted
        : AppColors.textDimmed;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active ? tint.withAlpha(30) : Colors.transparent,
            border: Border.all(
              color: active ? tint : AppColors.border2,
              width: active ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: foreground),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: AppTextStyles.sans(
                  size: 12,
                  weight: active ? FontWeight.w600 : FontWeight.w400,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pill that opens a sheet or fires an action — the table tab's Export
/// and Customize chips. [emphasis] switches it to the accent treatment for a
/// live state the golfer must not lose track of (a recording in progress).
class AppActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool emphasis;

  const AppActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = emphasis ? context.accent : AppColors.textMuted;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        label: label,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: emphasis ? context.accentSubtle : AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: emphasis ? context.accentBorder : AppColors.border2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.sans(
                  size: 12,
                  weight: emphasis ? FontWeight.w600 : FontWeight.w400,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one accent-filled button a surface gets — Apply on the customize
/// sheets. Full width, 48 tall, radius 12.
class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: context.accent,
      foregroundColor: Colors.black,
      disabledBackgroundColor: AppColors.card,
      disabledForegroundColor: AppColors.textDimmed,
      minimumSize: const Size.fromHeight(48),
      textStyle: AppTextStyles.sans(size: 14, weight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    return SizedBox(
      width: double.infinity,
      child: icon == null
          ? FilledButton(style: style, onPressed: onPressed, child: Text(label))
          : FilledButton.icon(
              style: style,
              onPressed: onPressed,
              icon: Icon(icon, size: 16),
              label: Text(label),
            ),
    );
  }
}

/// A quiet secondary action: muted text, optional leading glyph, no fill.
class AppTextAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  const AppTextAction({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Semantics(
      button: true,
      label: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppTextStyles.sans(size: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A section that folds away under a caps label and chevron, hairline
/// above — the app's answer to [ExpansionTile], which draws a Material glyph
/// the release font lacks and pads like a list row.
class AppCollapsible extends StatefulWidget {
  final String label;
  final List<Widget> children;
  final bool initiallyExpanded;

  const AppCollapsible({
    super.key,
    required this.label,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  State<AppCollapsible> createState() => _AppCollapsibleState();
}

class _AppCollapsibleState extends State<AppCollapsible> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(color: AppColors.border),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _expanded = !_expanded),
        child: Semantics(
          button: true,
          expanded: _expanded,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(child: AppSectionLabel(widget.label)),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: kThemeAnimationDuration,
                  curve: Curves.easeOutCubic,
                  child: const Icon(
                    AppIcons.chevronDown,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      AnimatedSize(
        duration: kThemeAnimationDuration,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: _expanded
            ? Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.children,
                ),
              )
            : const SizedBox(width: double.infinity),
      ),
    ],
  );
}

/// A text field in the app's panel language: caps label above, card fill,
/// hairline border that turns accent on focus and critical on error.
class AppField extends StatelessWidget {
  final String label;
  final String? hint;
  final String? initialValue;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final bool numeric;
  final Key? fieldKey;

  const AppField({
    super.key,
    required this.label,
    this.hint,
    this.initialValue,
    this.errorText,
    this.onChanged,
    this.numeric = false,
    this.fieldKey,
  });

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: color, width: width),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionLabel(label, trailing: hint),
        const SizedBox(height: 6),
        TextFormField(
          key: fieldKey,
          initialValue: initialValue,
          style: AppTextStyles.sans(size: 14),
          cursorColor: context.accent,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          textInputAction: TextInputAction.next,
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.card,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            errorText: errorText,
            errorStyle: AppTextStyles.sans(
              size: 11,
              color: AppColors.severityCritical,
            ),
            enabledBorder: border(AppColors.border2),
            focusedBorder: border(context.accent, 1.5),
            errorBorder: border(AppColors.severityCritical),
            focusedErrorBorder: border(AppColors.severityCritical, 1.5),
          ),
        ),
      ],
    );
  }
}

/// One choice in a short list of exclusive options — a bordered card row
/// that takes the accent when selected, in place of a radio tile.
class AppOptionRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const AppOptionRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Semantics(
      button: true,
      selected: selected,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? context.accentGhost : AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? context.accent : AppColors.border2,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.sans(
                      size: 13,
                      weight: FontWeight.w600,
                      color: selected ? context.accent : Colors.white,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: AppTextStyles.sans(
                        size: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            if (selected)
              Icon(AppIcons.check, size: 16, color: context.accent),
          ],
        ),
      ),
    ),
  );
}

/// A compact figures table: caps column headings, hairline rows, muted row
/// labels and tabular values — the table tab's grammar without its scroll
/// machinery, for a handful of rows side by side.
class AppFiguresTable extends StatelessWidget {
  final List<String> columns;
  final List<List<String>> rows;

  const AppFiguresTable({
    super.key,
    required this.columns,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    Widget cell(String text, {required bool head, required bool label}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            head ? text.toUpperCase() : text,
            textAlign: label ? TextAlign.left : TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: head
                ? AppTextStyles.statLabel()
                : label
                ? AppTextStyles.sans(size: 12, color: AppColors.textMuted)
                : AppTextStyles.statValue(size: 13),
          ),
        );
    const line = BorderSide(color: AppColors.border);
    return Table(
      columnWidths: {
        0: const FlexColumnWidth(2.2),
        for (var i = 1; i < columns.length; i++) i: const FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: const TableBorder(
        horizontalInside: line,
        bottom: line,
      ),
      children: [
        TableRow(
          children: [
            for (var i = 0; i < columns.length; i++)
              cell(columns[i], head: true, label: i == 0),
          ],
        ),
        for (final row in rows)
          TableRow(
            children: [
              for (var i = 0; i < row.length; i++)
                cell(row[i], head: false, label: i == 0),
            ],
          ),
      ],
    );
  }
}

/// The grab handle, title row and hairline every bottom sheet opens with.
class AppSheetHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onClose;
  const AppSheetHeader({super.key, required this.title, this.onClose});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SizedBox(height: 12),
      Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.border2,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTextStyles.sans(size: 16, weight: FontWeight.w600),
              ),
            ),
            if (onClose != null)
              IconButton(
                tooltip: 'Close',
                onPressed: onClose,
                icon: const Icon(
                  AppIcons.close,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      const Divider(color: AppColors.border),
    ],
  );
}
