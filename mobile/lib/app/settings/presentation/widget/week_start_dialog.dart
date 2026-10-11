import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:mui/mui.dart';

class WeekStartDialog extends StatelessWidget {
  const WeekStartDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final stored = MoodiaryKVs.weekStart.get() ?? DateTime.monday;
    final current = stored == DateTime.sunday ? DateTime.sunday : DateTime.monday;
    return SimpleDialog(
      title: Text(context.l10n.app.weekStart),
      children: [
        _Option(
          label: context.l10n.app.weekStartMonday,
          selected: current == DateTime.monday,
          onTap: () {
            MoodiaryKVs.weekStart.set(DateTime.monday);
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
        _Option(
          label: context.l10n.app.weekStartSunday,
          selected: current == DateTime.sunday,
          onTap: () {
            MoodiaryKVs.weekStart.set(DateTime.sunday);
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Option({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SimpleDialogOption(
      onPressed: onTap,
      child: Row(
        children: [
          Icon(selected ? LucideIcons.check : LucideIcons.calendar),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
