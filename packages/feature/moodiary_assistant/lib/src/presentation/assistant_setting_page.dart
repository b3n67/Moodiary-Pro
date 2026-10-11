import 'dart:async';

import 'package:gap/gap.dart';
import 'package:moodiary_assistant/src/data/assistant_defs.dart';
import 'package:moodiary_assistant/src/data/llm_provider_repository.dart';
import 'package:moodiary_assistant/src/data/prompt_preset_repository.dart';
import 'package:moodiary_assistant/src/presentation/assistant_tool_ui.dart';
import 'package:moodiary_assistant/src/presentation/permission_mode_sheet.dart';
import 'package:moodiary_components/moodiary_components.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:mui/mui.dart';

class AssistantSettingPage extends StatelessWidget {
  const AssistantSettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.assistant.settingTitle)),
      body: Padding(
        padding: const .symmetric(horizontal: 8.0),
        child: CustomScrollView(
          slivers: [
            const _ProviderSection(),
            const _PersonalSection(),
            const _PromptSection(),
            const _ToolSection(),
            SliverGap(context.safeBottom),
          ],
        ),
      ),
    );
  }
}

class _ProviderSection extends StatelessWidget {
  const _ProviderSection();

  @override
  Widget build(BuildContext context) {
    return MSliverSettingGroup(
      title: context.l10n.assistant.modelProviderTitle,
      children: const [_ProviderEntryTile()],
    );
  }
}

class _ProviderEntryTile extends StatefulWidget {
  const _ProviderEntryTile();

  @override
  State<_ProviderEntryTile> createState() => _ProviderEntryTileState();
}

class _ProviderEntryTileState extends State<_ProviderEntryTile> {
  LlmProvider? _active;
  bool _loaded = false;
  StreamSubscription<void>? _sub;
  late final VoidCallback _activeListener;
  late final ValueNotifier<String> _activeNotifier;

  late final _repo = getIt<LlmProviderRepository>();

  @override
  void initState() {
    super.initState();
    _activeNotifier = MoodiaryKVs.assistantActiveProviderId.getNotifier();
    _activeListener = _load;
    _activeNotifier.addListener(_activeListener);
    _sub = _repo.providerEvents.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _activeNotifier.removeListener(_activeListener);
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final active = await _repo.getActiveProvider();
    if (mounted) {
      setState(() {
        _active = active;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final active = _active;
    final subtitle = !_loaded
        ? l10n.assistant.providerEntryLoading
        : active == null
        ? l10n.assistant.providerEntryEmpty
        : '${active.name} · ${active.defaultModel}';
    return SettingListTile(
      title: l10n.assistant.modelProviderTitle,
      subtitle: subtitle,
      leading: const Icon(LucideIcons.cloud),
      trailing: const Icon(LucideIcons.chevronRight),
      onTap: () => const AssistantProvidersRoute().push(context),
    );
  }
}

class _PersonalSection extends StatefulWidget {
  const _PersonalSection();

  @override
  State<_PersonalSection> createState() => _PersonalSectionState();
}

class _PersonalSectionState extends State<_PersonalSection> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final notes = (MoodiaryKVs.assistantUserNotes.get() ?? '').trim();
    final memoryOn = MoodiaryKVs.assistantMemoryEnabled.get() ?? true;
    return MSliverSettingGroup(
      title: l10n.assistant.personalSectionTitle,
      children: [
        SettingListTile(
          title: l10n.assistant.notesTitle,
          subtitle: notes.isEmpty
              ? l10n.assistant.notesEmpty
              : notes.split('\n').first,
          leading: const Icon(LucideIcons.notebookPen),
          trailing: const Icon(LucideIcons.chevronRight),
          onTap: () async {
            await const AssistantNotesRoute().push(context);
            if (mounted) setState(() {});
          },
        ),
        SettingListTile(
          title: l10n.assistant.memoryTitle,
          subtitle: l10n.assistant.memoryTileSubtitle,
          leading: const Icon(LucideIcons.brain),
          trailing: Switch(
            value: memoryOn,
            onChanged: (v) {
              MoodiaryKVs.assistantMemoryEnabled.set(v);
              setState(() {});
            },
          ),
          onTap: memoryOn
              ? () => const AssistantMemoriesRoute().push(context)
              : null,
        ),
      ],
    );
  }
}

class _PromptSection extends StatefulWidget {
  const _PromptSection();

  @override
  State<_PromptSection> createState() => _PromptSectionState();
}

class _PromptSectionState extends State<_PromptSection> {
  final _repo = PromptPresetRepository();

  List<PromptPreset> _presets = const [];
  String _activeId = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() async {
    await _repo.ensureSeeded();
    if (!mounted) return;
    setState(() {
      _presets = _repo.getAll();
      _activeId = _repo.activeId();
    });
  }

  Future<void> _edit([PromptPreset? preset]) async {
    final saved = await MSheet.show<bool>(
      context,
      builder: (_) => _PromptEditSheet(preset: preset),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _delete(PromptPreset preset) async {
    final l10n = context.l10n;
    final confirmed = await MAlert.confirm(
      context,
      title: l10n.assistant.promptDeleteTitle,
      message: l10n.assistant.promptDeleteMessage(name: preset.name),
      confirmLabel: l10n.common.delete,
      isDestructive: true,
    );
    if (!confirmed) return;
    await _repo.remove(preset.id);
    if (mounted) _reload();
  }

  Future<void> _activate(String id) async {
    await _repo.setActiveId(id);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MSliverSettingGroup(
      title: l10n.assistant.promptSectionTitle,
      children: [
        SettingListTile(
          title: l10n.assistant.presetFactoryName,
          subtitle: l10n.assistant.presetFactoryDesc,
          leading: Switch(
            value: _activeId.isEmpty,
            onChanged: (v) {
              if (v) _activate('');
            },
          ),
          trailing: Text(
            l10n.assistant.presetBuiltIn,
            style: context.theme.typography.labelSmall.onSurfaceVariant,
          ),
          onTap: () => _activate(''),
        ),
        if (_presets.isEmpty)
          SettingListTile(
            title: l10n.assistant.promptEmpty,
            leading: const Icon(LucideIcons.messagesSquare),
            trailing: const Icon(LucideIcons.plus),
            onTap: () => _edit(),
          )
        else
          for (final preset in _presets)
            SettingListTile(
              title: preset.name,
              subtitle: Text(
                preset.content.split('\n').first,
                maxLines: 1,
                overflow: .ellipsis,
              ),
              leading: Switch(
                value: _activeId == preset.id,
                onChanged: (v) {
                  if (v) _activate(preset.id);
                },
              ),
              trailing: Row(
                mainAxisSize: .min,
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.pencil),
                    onPressed: () => _edit(preset),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.trash2),
                    onPressed: () => _delete(preset),
                  ),
                ],
              ),
              onTap: () => _edit(preset),
            ),
        SettingListTile(
          title: l10n.assistant.promptAdd,
          leading: const Icon(LucideIcons.plus),
          trailing: const Icon(LucideIcons.chevronRight),
          onTap: () => _edit(),
        ),
      ],
    );
  }
}

class _PromptEditSheet extends StatefulWidget {
  final PromptPreset? preset;

  const _PromptEditSheet({this.preset});

  @override
  State<_PromptEditSheet> createState() => _PromptEditSheetState();
}

class _PromptEditSheetState extends State<_PromptEditSheet> {
  late final TextEditingController _nameCtl;
  late final TextEditingController _contentCtl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtl = TextEditingController(text: widget.preset?.name ?? '');
    _contentCtl = TextEditingController(text: widget.preset?.content ?? '');
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _contentCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtl.text.trim();
    final content = _contentCtl.text.trim();
    if (name.isEmpty || content.isEmpty) return;
    setState(() => _saving = true);
    try {
      await PromptPresetRepository().upsert(
        id: widget.preset?.id,
        name: name,
        content: content,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return MSheetScaffold<bool>(
      title: widget.preset == null
          ? l10n.assistant.promptAdd
          : l10n.assistant.promptEdit,
      icon: LucideIcons.messagesSquare,
      actions: [
        MAction(label: l10n.common.cancel, value: false, enabled: !_saving),
        MAction(
          label: l10n.common.save,
          isPrimary: true,
          busy: _saving,
          enabled: !_saving,
          onPressed: _save,
        ),
      ],
      child: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        spacing: 14,
        children: [
          MField(
            controller: _nameCtl,
            label: l10n.assistant.promptNameLabel,
            hintText: l10n.assistant.promptNameHint,
            enabled: !_saving,
            textInputAction: .next,
          ),
          MField(
            controller: _contentCtl,
            label: l10n.assistant.promptContentLabel,
            hintText: l10n.assistant.promptContentHint,
            enabled: !_saving,
            maxLines: 8,
            maxLength: PromptPresetRepository.maxContentChars,
          ),
        ],
      ),
    );
  }
}

class _ToolSection extends StatefulWidget {  const _ToolSection();

  @override
  State<_ToolSection> createState() => _ToolSectionState();
}

class _ToolSectionState extends State<_ToolSection> {
  AssistantPermissionMode get _mode =>
      AssistantPermissionMode.fromId(MoodiaryKVs.assistantPermissionMode.get());

  Future<void> _pickMode() async {
    final mode = await showPermissionModePicker(context, selected: _mode);
    if (mode == null) return;
    MoodiaryKVs.assistantPermissionMode.set(mode.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SliverMainAxisGroup(
      slivers: [
        MSliverSettingGroup(
          title: l10n.assistant.tool,
          children: [
            SettingListTile(
              title: l10n.assistant.permissionTitle,
              subtitle: permissionModeLabel(l10n, _mode),
              leading: const Icon(LucideIcons.shieldCheck),
              trailing: const Icon(LucideIcons.chevronRight),
              onTap: _pickMode,
            ),
            for (final tool in AssistantTool.values) _toolTile(context, tool),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const .fromLTRB(16, 8, 16, 0),
            child: Text(
              l10n.assistant.toolSectionNote,
              style: context.theme.typography.bodySmall.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _toolTile(BuildContext context, AssistantTool tool) {
    final display = assistantToolDisplay(context, tool);
    return SettingListTile(
      leading: Icon(display.icon),
      title: display.title,
      subtitle: display.description,
    );
  }
}
