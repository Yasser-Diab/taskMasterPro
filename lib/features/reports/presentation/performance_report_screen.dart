import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:printing/printing.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../activity/presentation/activity_review_screen.dart';
import '../../roadmaps/presentation/roadmaps_screen.dart';
import '../../tasks/domain/task_occurrence_policy.dart';
import '../../tasks/presentation/task_card.dart';
import '../../tasks/presentation/task_workspace_screen.dart';
import '../data/performance_report_service.dart';

enum _ReportAction { print, export, share }

class PerformanceReportScreen extends ConsumerStatefulWidget {
  const PerformanceReportScreen({
    this.reportType,
    this.taskId,
    this.roadmapId,
    super.key,
  });

  final PerformanceReportType? reportType;
  final String? taskId;
  final String? roadmapId;

  @override
  ConsumerState<PerformanceReportScreen> createState() =>
      _PerformanceReportScreenState();
}

class _PerformanceReportScreenState
    extends ConsumerState<PerformanceReportScreen> {
  late DateTime _from;
  late DateTime _to;
  late String _localeCode;
  bool _landscape = false;
  Set<String> _sections = {
    'summary',
    'tasks',
    'roadmaps',
    'activity',
    'coaching',
  };
  Future<Uint8List>? _bytes;
  Future<PerformanceReportSnapshot>? _snapshot;
  StreamSubscription<dynamic>? _reportInputSubscription;
  Timer? _reportRefreshDebounce;
  bool _initialized = false;
  bool _showPdf = false;

  PerformanceReportType get _reportType =>
      widget.reportType ??
      (widget.roadmapId != null
          ? PerformanceReportType.roadmap
          : widget.taskId != null
          ? PerformanceReportType.task
          : PerformanceReportType.account);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _to = DateTime(now.year, now.month, now.day);
    _from = _to.subtract(const Duration(days: 29));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _localeCode = context.l10n.locale.languageCode;
    _regenerate();
    _watchReportInputs();
  }

  PerformanceReportOptions get _options => PerformanceReportOptions(
    type: _reportType,
    roadmapId: widget.roadmapId,
    taskId: widget.taskId,
    from: _from,
    to: _to,
    localeCode: _localeCode,
    landscape: _landscape,
    sections: _sections,
    timeZone: ref.read(appSettingsProvider).value?.timeZone ?? 'UTC',
    includeHealth:
        _sections.contains(PerformanceReportService.healthSection) &&
        (ref.read(appSettingsProvider).value?.healthReportPrivacy ?? 'ask') !=
            'never',
  );

  void _regenerate() {
    if (!mounted) return;
    final service = PerformanceReportService(ref.read(databaseProvider));
    final options = _options;
    final snapshot = service.load(options);
    setState(() {
      _snapshot = snapshot;
      _bytes = snapshot.then((value) => service.buildPdf(value, options));
    });
  }

  void _watchReportInputs() {
    final database = ref.read(databaseProvider);
    // Listen to invalidations only. This avoids materializing every report
    // table while still refreshing when a synchronized row arrives.
    _reportInputSubscription = database
        .tableUpdates(
          TableUpdateQuery.onAllTables({
            database.localProfiles,
            database.localAppSettings,
            database.localTasks,
            database.localDomains,
            database.localRoadmaps,
            database.localActivitySegments,
            database.localAttributions,
            database.localContributions,
            database.localEntityRecords,
            database.localRuntimeStates,
          }),
        )
        .listen((_) => _scheduleReportRefresh());
  }

  void _scheduleReportRefresh() {
    _reportRefreshDebounce?.cancel();
    _reportRefreshDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _regenerate();
    });
  }

  @override
  void dispose() {
    _reportRefreshDebounce?.cancel();
    final subscription = _reportInputSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }

  Future<void> _pickRange() async {
    final value = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (value == null) return;
    setState(() {
      _from = value.start;
      _to = value.end;
    });
    _regenerate();
  }

  Future<void> _print() async {
    final bytes = await _bytes;
    if (bytes == null) return;
    if (!await _confirmHealthExport()) return;
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _share() async {
    final bytes = await _bytes;
    if (bytes == null) return;
    if (!await _confirmHealthExport()) return;
    await Printing.sharePdf(bytes: bytes, filename: _fileName);
  }

  Future<void> _export() async {
    final bytes = await _bytes;
    if (bytes == null || !mounted) return;
    if (!await _confirmHealthExport()) return;
    if (!mounted) return;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: context.l10n.text('report_export_pdf'),
      fileName: _fileName,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      bytes: Platform.isAndroid || Platform.isIOS ? bytes : null,
      lockParentWindow: true,
    );
    if (path == null) return;
    if (!Platform.isAndroid && !Platform.isIOS) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.text('report_exported'))),
    );
  }

  Future<bool> _confirmHealthExport() async {
    if (!_sections.contains(PerformanceReportService.healthSection)) {
      return true;
    }
    final privacy =
        ref.read(appSettingsProvider).value?.healthReportPrivacy ?? 'ask';
    if (privacy == 'private' || privacy == 'selected') return true;
    if (privacy == 'never') {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('health_reports_disabled'))),
      );
      return false;
    }
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.l10n.text('include_health_summaries')),
            content: Text(context.l10n.text('health_report_share_warning')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.text('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.text('continue_action')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _setSection(String section, bool selected) async {
    if (!selected && _sections.length == 1) return;
    if (section == PerformanceReportService.healthSection && selected) {
      final privacy =
          ref.read(appSettingsProvider).value?.healthReportPrivacy ?? 'ask';
      if (privacy == 'never') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.text('health_reports_disabled'))),
        );
        return;
      }
      if (privacy == 'ask') {
        final accepted =
            await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(context.l10n.text('include_health_summaries')),
                content: Text(
                  context.l10n.text('health_report_include_warning'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(context.l10n.text('cancel')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(context.l10n.text('include')),
                  ),
                ],
              ),
            ) ??
            false;
        if (!accepted) return;
      }
    }
    setState(() {
      if (selected) {
        _sections = {..._sections, section};
      } else {
        _sections = {..._sections}..remove(section);
      }
    });
    _regenerate();
  }

  String get _fileName {
    return 'DayVector-${_reportType.fileSlug}-'
        '${DateFormat('yyyy-MM-dd').format(_to)}.pdf';
  }

  void _selectLanguage(String? value) {
    if (value == null) return;
    setState(() => _localeCode = value);
    _regenerate();
  }

  void _selectOrientation(bool? value) {
    if (value == null) return;
    setState(() => _landscape = value);
    _regenerate();
  }

  void _selectPreview(bool? value) {
    if (value == null) return;
    setState(() => _showPdf = value);
  }

  Future<void> _runReportAction(_ReportAction action) async {
    switch (action) {
      case _ReportAction.print:
        return _print();
      case _ReportAction.export:
        return _export();
      case _ReportAction.share:
        return _share();
    }
  }

  Future<Set<String>> _updateMobileSection(
    String section,
    bool selected,
  ) async {
    await _setSection(section, selected);
    return _sections;
  }

  Future<void> _showMobileSettings(Map<String, String> sectionLabels) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _MobileReportSettingsSheet(
        localeCode: _localeCode,
        landscape: _landscape,
        showPdf: _showPdf,
        sections: _sections,
        sectionLabels: sectionLabels,
        onLanguageChanged: _selectLanguage,
        onOrientationChanged: _selectOrientation,
        onPreviewChanged: _selectPreview,
        onSectionChanged: _updateMobileSection,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appSettingsProvider, (previous, next) {
      final before = previous?.asData?.value;
      final after = next.asData?.value;
      if (before?.timeZone != after?.timeZone ||
          before?.healthReportPrivacy != after?.healthReportPrivacy) {
        _scheduleReportRefresh();
      }
    });
    final l10n = context.l10n;
    final phone = MediaQuery.sizeOf(context).width < 600;
    final sectionLabels = <String, String>{
      'summary': l10n.text('report_summary'),
      'tasks': l10n.text('report_tasks'),
      'roadmaps': l10n.text('report_roadmap_progress'),
      'activity': l10n.text('report_activity'),
      'coaching': l10n.text('report_coaching'),
      PerformanceReportService.healthSection: l10n.text(
        'report_health_context',
      ),
    };
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<PerformanceReportSnapshot>(
          future: _snapshot,
          builder: (context, report) {
            final snapshot = report.data;
            final name = switch (_reportType) {
              PerformanceReportType.roadmap => snapshot?.roadmap?.title,
              PerformanceReportType.task => snapshot?.tasks.firstOrNull?.title,
              PerformanceReportType.household ||
              PerformanceReportType.account => null,
            };
            return Text(
              name?.trim().isNotEmpty == true
                  ? name!.trim()
                  : l10n.text(_reportType.titleLocalizationKey),
              maxLines: phone ? 2 : 1,
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
        actions: phone
            ? [
                PopupMenuButton<_ReportAction>(
                  key: const ValueKey('mobile-report-actions'),
                  tooltip: l10n.text('settings'),
                  onSelected: _runReportAction,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _ReportAction.print,
                      child: _ReportActionLabel(
                        icon: Icons.print_outlined,
                        label: l10n.text('report_print'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _ReportAction.export,
                      child: _ReportActionLabel(
                        icon: Icons.picture_as_pdf_outlined,
                        label: l10n.text('report_export_pdf'),
                      ),
                    ),
                    if (Platform.isAndroid)
                      PopupMenuItem(
                        value: _ReportAction.share,
                        child: _ReportActionLabel(
                          icon: Icons.share_outlined,
                          label: l10n.text('report_share'),
                        ),
                      ),
                  ],
                ),
              ]
            : [
                IconButton(
                  tooltip: l10n.text('report_print'),
                  onPressed: _print,
                  icon: const Icon(Icons.print_outlined),
                ),
                IconButton(
                  tooltip: l10n.text('report_export_pdf'),
                  onPressed: _export,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                ),
                if (Platform.isAndroid)
                  IconButton(
                    tooltip: l10n.text('report_share'),
                    onPressed: _share,
                    icon: const Icon(Icons.share_outlined),
                  ),
              ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final dateRange =
                          '${DateFormat.yMMMd(l10n.locale.toLanguageTag()).format(_from)} - '
                          '${DateFormat.yMMMd(l10n.locale.toLanguageTag()).format(_to)}';
                      if (constraints.maxWidth < 600) {
                        return Row(
                          key: const ValueKey('mobile-report-controls'),
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                key: const ValueKey('mobile-report-date'),
                                onPressed: _pickRange,
                                icon: const Icon(Icons.date_range_outlined),
                                label: Text(
                                  dateRange,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              key: const ValueKey('mobile-report-settings'),
                              tooltip: l10n.text('settings'),
                              onPressed: () =>
                                  _showMobileSettings(sectionLabels),
                              icon: const Icon(Icons.tune_rounded),
                            ),
                          ],
                        );
                      }

                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pickRange,
                            icon: const Icon(Icons.date_range_outlined),
                            label: Text(dateRange),
                          ),
                          DropdownMenu<String>(
                            initialSelection: _localeCode,
                            label: Text(l10n.text('report_language')),
                            dropdownMenuEntries: const [
                              DropdownMenuEntry(value: 'en', label: 'English'),
                              DropdownMenuEntry(value: 'ar', label: 'العربية'),
                              DropdownMenuEntry(value: 'de', label: 'Deutsch'),
                            ],
                            onSelected: _selectLanguage,
                          ),
                          SegmentedButton<bool>(
                            segments: [
                              ButtonSegment(
                                value: false,
                                icon: const Icon(Icons.stay_current_portrait),
                                label: Text(l10n.text('report_portrait')),
                              ),
                              ButtonSegment(
                                value: true,
                                icon: const Icon(Icons.stay_current_landscape),
                                label: Text(l10n.text('report_landscape')),
                              ),
                            ],
                            selected: {_landscape},
                            onSelectionChanged: (value) =>
                                _selectOrientation(value.first),
                          ),
                          SegmentedButton<bool>(
                            segments: [
                              ButtonSegment(
                                value: false,
                                icon: const Icon(Icons.insights_outlined),
                                label: Text(
                                  l10n.text('report_interactive_preview'),
                                ),
                              ),
                              ButtonSegment(
                                value: true,
                                icon: const Icon(Icons.picture_as_pdf_outlined),
                                label: Text(l10n.text('report_pdf_preview')),
                              ),
                            ],
                            selected: {_showPdf},
                            onSelectionChanged: (value) =>
                                _selectPreview(value.first),
                          ),
                        ],
                      );
                    },
                  ),
                  if (!phone) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: sectionLabels.entries.map((entry) {
                          return FilterChip(
                            label: Text(entry.value),
                            selected: _sections.contains(entry.key),
                            onSelected: (selected) =>
                                _setSection(entry.key, selected),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: _showPdf
                ? FutureBuilder<Uint8List>(
                    future: _bytes,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _ReportFailure(onRetry: _regenerate);
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return PdfPreview(
                        build: (_) async => snapshot.requireData,
                        canChangeOrientation: false,
                        canChangePageFormat: false,
                        allowPrinting: false,
                        allowSharing: false,
                        useActions: false,
                        pdfFileName: _fileName,
                      );
                    },
                  )
                : FutureBuilder<PerformanceReportSnapshot>(
                    future: _snapshot,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _ReportFailure(onRetry: _regenerate);
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _InteractivePerformanceReport(
                        snapshot: snapshot.requireData,
                        options: _options,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReportActionLabel extends StatelessWidget {
  const _ReportActionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
    );
  }
}

class _MobileReportSettingsSheet extends StatefulWidget {
  const _MobileReportSettingsSheet({
    required this.localeCode,
    required this.landscape,
    required this.showPdf,
    required this.sections,
    required this.sectionLabels,
    required this.onLanguageChanged,
    required this.onOrientationChanged,
    required this.onPreviewChanged,
    required this.onSectionChanged,
  });

  final String localeCode;
  final bool landscape;
  final bool showPdf;
  final Set<String> sections;
  final Map<String, String> sectionLabels;
  final ValueChanged<String?> onLanguageChanged;
  final ValueChanged<bool?> onOrientationChanged;
  final ValueChanged<bool?> onPreviewChanged;
  final Future<Set<String>> Function(String section, bool selected)
  onSectionChanged;

  @override
  State<_MobileReportSettingsSheet> createState() =>
      _MobileReportSettingsSheetState();
}

class _MobileReportSettingsSheetState
    extends State<_MobileReportSettingsSheet> {
  late String _localeCode = widget.localeCode;
  late bool _landscape = widget.landscape;
  late bool _showPdf = widget.showPdf;
  late Set<String> _sections = {...widget.sections};

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FractionallySizedBox(
      heightFactor: 0.88,
      child: Material(
        key: const ValueKey('mobile-report-settings-sheet'),
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.text('settings'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.text('close'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _localeCode,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.text('report_language'),
                        prefixIcon: const Icon(Icons.language_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'en', child: Text('English')),
                        DropdownMenuItem(value: 'ar', child: Text('العربية')),
                        DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _localeCode = value);
                        widget.onLanguageChanged(value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<bool>(
                      initialValue: _landscape,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.text('report_orientation'),
                        prefixIcon: const Icon(Icons.screen_rotation_outlined),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: false,
                          child: Text(l10n.text('report_portrait')),
                        ),
                        DropdownMenuItem(
                          value: true,
                          child: Text(l10n.text('report_landscape')),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _landscape = value);
                        widget.onOrientationChanged(value);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<bool>(
                      initialValue: _showPdf,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.text('report_preview_type'),
                        prefixIcon: const Icon(Icons.preview_outlined),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: false,
                          child: Text(l10n.text('report_interactive_preview')),
                        ),
                        DropdownMenuItem(
                          value: true,
                          child: Text(l10n.text('report_pdf_preview')),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _showPdf = value);
                        widget.onPreviewChanged(value);
                      },
                    ),
                    const SizedBox(height: 18),
                    Text(
                      l10n.text('report_sections'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: widget.sectionLabels.entries
                          .map((entry) {
                            return FilterChip(
                              label: Text(entry.value),
                              selected: _sections.contains(entry.key),
                              onSelected: (selected) async {
                                final result = await widget.onSectionChanged(
                                  entry.key,
                                  selected,
                                );
                                if (!mounted) return;
                                setState(() => _sections = {...result});
                              },
                            );
                          })
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(l10n.text('done')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportFailure extends StatelessWidget {
  const _ReportFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42),
            const SizedBox(height: 12),
            Text(
              context.l10n.text('report_generation_failed'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.text('retry')),
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractivePerformanceReport extends StatelessWidget {
  const _InteractivePerformanceReport({
    required this.snapshot,
    required this.options,
  });

  final PerformanceReportSnapshot snapshot;
  final PerformanceReportOptions options;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final facts = PerformanceReportService.factsForSnapshot(
      snapshot,
      options,
      l10n,
    );
    final health = PerformanceReportService.healthSummariesForReport(
      snapshot.health,
      options,
    );
    final completed = snapshot.tasks
        .where(TaskOccurrencePolicy.isCompletedOccurrence)
        .toList(growable: false);
    final overdue = TaskOccurrencePolicy.overdueOccurrences(
      snapshot.tasks,
      now: DateTime.now(),
      timeZone: options.timeZone,
    );
    final productive = snapshot.tasks
        .where((task) => task.activeDurationMs > 0)
        .toList(growable: false);
    final focusTasks = snapshot.tasks
        .where((task) => task.executionMode == 'pomodoro')
        .toList(growable: false);
    final continuousTasks = snapshot.tasks
        .where((task) => task.executionMode == 'continuous')
        .toList(growable: false);
    final reportName = switch (options.type) {
      PerformanceReportType.roadmap => snapshot.roadmap?.title,
      PerformanceReportType.task => snapshot.tasks.firstOrNull?.title,
      PerformanceReportType.household ||
      PerformanceReportType.account => snapshot.profile?.displayName,
    };
    final hasAnyData =
        snapshot.tasks.isNotEmpty ||
        snapshot.activity.isNotEmpty ||
        snapshot.interruptions.isNotEmpty ||
        health.isNotEmpty;
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final phone = constraints.maxWidth < 600;
        final horizontalPadding = phone ? 12.0 : 20.0;
        final contentWidth = math.max(
          0.0,
          math.min(1480.0, constraints.maxWidth - horizontalPadding * 2),
        );
        final scaledBodySize = MediaQuery.textScalerOf(context).scale(14);
        final phoneGrid =
            phone && contentWidth >= 330 && scaledBodySize <= 15.5;
        final columns = phone
            ? (phoneGrid ? 2 : 1)
            : contentWidth >= 1180
            ? 4
            : contentWidth >= 760
            ? 2
            : 1;
        final metricWidth = math.max(
          0.0,
          (contentWidth - (columns - 1) * (phone ? 8 : 12)) / columns,
        );
        return SingleChildScrollView(
          key: const ValueKey('interactive-performance-report'),
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            phone ? 12 : 18,
            horizontalPadding,
            phone ? 24 : 36,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ReportHero(
                    compact: phone,
                    title: l10n.text(options.type.titleLocalizationKey),
                    name: reportName,
                    from: options.from,
                    to: options.to,
                    recordCount:
                        snapshot.tasks.length +
                        snapshot.activity.length +
                        snapshot.sessions.length +
                        snapshot.interruptions.length +
                        health.length,
                  ),
                  const SizedBox(height: 14),
                  if (!hasAnyData)
                    _ReportEmptyState()
                  else ...[
                    Wrap(
                      key: const ValueKey('report-metric-grid'),
                      spacing: phone ? 8 : 12,
                      runSpacing: phone ? 8 : 12,
                      children: [
                        _ReportMetricCard(
                          width: metricWidth,
                          compact: phone,
                          icon: Icons.calendar_today_outlined,
                          color: colorScheme.primary,
                          label: l10n.text('report_planned_effort'),
                          value: _duration(context, facts.plannedMs),
                          onTap: () => _openTasks(
                            context,
                            l10n.text('report_planned_effort'),
                            snapshot.tasks,
                          ),
                        ),
                        _ReportMetricCard(
                          width: metricWidth,
                          compact: phone,
                          icon: Icons.bolt_rounded,
                          color: const Color(0xFF2FCF8F),
                          label: l10n.text('report_productive_work'),
                          value: _duration(context, facts.productiveMs),
                          onTap: () => _openTasks(
                            context,
                            l10n.text('report_productive_work'),
                            productive,
                          ),
                        ),
                        _ReportMetricCard(
                          width: metricWidth,
                          compact: phone,
                          icon: Icons.center_focus_strong,
                          color: const Color(0xFF43A5FF),
                          label: l10n.text('report_focus_time'),
                          value: _duration(context, facts.focusMs),
                          onTap: () => _openTasks(
                            context,
                            l10n.text('report_focus_time'),
                            focusTasks,
                          ),
                        ),
                        _ReportMetricCard(
                          width: metricWidth,
                          compact: phone,
                          icon: Icons.free_breakfast_outlined,
                          color: const Color(0xFF4CC6CE),
                          label: l10n.text('report_break_time'),
                          value: _duration(context, facts.breakMs),
                          onTap: () => _openTasks(
                            context,
                            l10n.text('report_break_time'),
                            focusTasks,
                          ),
                        ),
                        _ReportMetricCard(
                          width: metricWidth,
                          compact: phone,
                          icon: Icons.timelapse_rounded,
                          color: const Color(0xFF8B7CFF),
                          label: l10n.text('report_continuous_work'),
                          value: _duration(context, facts.continuousMs),
                          onTap: () => _openTasks(
                            context,
                            l10n.text('report_continuous_work'),
                            continuousTasks,
                          ),
                        ),
                        _ReportMetricCard(
                          width: metricWidth,
                          compact: phone,
                          icon: Icons.warning_amber_rounded,
                          color: const Color(0xFFFFA24B),
                          label: l10n.text('report_interruptions'),
                          value: facts.interruptionCount == 0
                              ? l10n.text('report_no_interruptions_short')
                              : l10n.format('report_interruption_value', {
                                  'count': facts.interruptionCount,
                                  'duration': _duration(
                                    context,
                                    facts.interruptionMs,
                                  ),
                                }),
                          onTap: () =>
                              _openInterruptions(context, snapshot, facts),
                        ),
                        _ReportMetricCard(
                          width: metricWidth,
                          compact: phone,
                          icon: Icons.task_alt_rounded,
                          color: const Color(0xFF32C57A),
                          label: l10n.text('report_completed_tasks'),
                          value: facts.completedTasks.toString(),
                          onTap: () => _openTasks(
                            context,
                            l10n.text('report_completed_tasks'),
                            completed,
                          ),
                        ),
                        _ReportMetricCard(
                          width: metricWidth,
                          compact: phone,
                          icon: Icons.schedule_outlined,
                          color: const Color(0xFFE87171),
                          label: l10n.text('report_overdue_tasks'),
                          value: facts.overdueTasks.toString(),
                          onTap: () => _openTasks(
                            context,
                            l10n.text('report_overdue_tasks'),
                            overdue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _ResponsiveReportPanels(
                      compact: phone,
                      children: [
                        _ReportPanel(
                          title: l10n.text(
                            'report_planned_and_productive_by_day',
                          ),
                          subtitle: l10n.text('report_open_records'),
                          onTap: () => _openTasks(
                            context,
                            l10n.text('report_planned_and_productive_by_day'),
                            snapshot.tasks,
                          ),
                          child: _DailyWorkChart(points: facts.daily),
                        ),
                        _ReportPanel(
                          title: l10n.text('report_completion_trend'),
                          subtitle: l10n.text('report_open_records'),
                          onTap: () => _openTasks(
                            context,
                            l10n.text('report_completed_tasks'),
                            completed,
                          ),
                          child: _CompletionTrendChart(points: facts.daily),
                        ),
                        _ReportPanel(
                          title: l10n.text('report_application_usage'),
                          subtitle: l10n.text('report_open_records'),
                          onTap: () => _openActivityReview(context),
                          child: _BreakdownBars(
                            entries: facts.applications,
                            emptyLabel: l10n.text(
                              'report_no_application_usage',
                            ),
                            onEntryTap: (entry) => _openActivityRecords(
                              context,
                              entry.label,
                              snapshot.activity
                                  .where(
                                    (segment) =>
                                        PerformanceReportService.applicationLabel(
                                          segment,
                                          unavailableLabel: l10n.text(
                                            'report_record_unavailable',
                                          ),
                                        ) ==
                                        entry.label,
                                  )
                                  .toList(growable: false),
                            ),
                          ),
                        ),
                        _ReportPanel(
                          title: l10n.text('report_website_usage'),
                          subtitle: l10n.text('report_open_records'),
                          onTap: () => _openActivityReview(context),
                          child: _BreakdownBars(
                            entries: facts.websites,
                            emptyLabel: l10n.text('report_no_website_usage'),
                            onEntryTap: (entry) => _openActivityRecords(
                              context,
                              entry.label,
                              snapshot.activity
                                  .where(
                                    (segment) =>
                                        PerformanceReportService.websiteLabel(
                                          segment,
                                        ) ==
                                        entry.label,
                                  )
                                  .toList(growable: false),
                            ),
                          ),
                        ),
                        _ReportPanel(
                          title: l10n.text('report_task_domain_distribution'),
                          subtitle: l10n.text('report_open_records'),
                          onTap: () => _openTasks(
                            context,
                            l10n.text('report_task_domain_distribution'),
                            snapshot.tasks,
                          ),
                          child: _BreakdownBars(
                            entries: facts.taskDomains,
                            emptyLabel: l10n.text('report_no_domain_data'),
                            onEntryTap: (entry) => _openTasks(
                              context,
                              entry.label,
                              snapshot.tasks
                                  .where(
                                    (task) => (task.domainId ?? '') == entry.id,
                                  )
                                  .toList(growable: false),
                            ),
                          ),
                        ),
                        _ReportPanel(
                          title: l10n.text('report_roadmap_contribution'),
                          subtitle: l10n.text('report_open_records'),
                          onTap: facts.roadmaps.isEmpty
                              ? null
                              : () => _openRoadmap(
                                  context,
                                  snapshot,
                                  facts.roadmaps.first.id,
                                ),
                          child: _BreakdownBars(
                            entries: facts.roadmaps,
                            emptyLabel: l10n.text('report_no_chart_data'),
                            onEntryTap: (entry) =>
                                _openRoadmap(context, snapshot, entry.id),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _ActivityTotalsPanel(facts: facts, compact: phone),
                    if (health.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _HealthReportPanel(entries: health),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _duration(BuildContext context, int milliseconds) =>
      context.l10n.duration(Duration(milliseconds: milliseconds));

  void _openTasks(BuildContext context, String title, List<LocalTask> tasks) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ReportTaskRecordsScreen(title: title, tasks: tasks),
      ),
    );
  }

  void _openInterruptions(
    BuildContext context,
    PerformanceReportSnapshot snapshot,
    PerformanceReportFacts facts,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ReportInterruptionRecordsScreen(
          records: snapshot.interruptions,
          tasks: snapshot.tasks,
          totalDurationMs: facts.interruptionMs,
        ),
      ),
    );
  }

  void _openActivityRecords(
    BuildContext context,
    String title,
    List<LocalActivitySegment> segments,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            _ReportActivityRecordsScreen(title: title, segments: segments),
      ),
    );
  }

  void _openActivityReview(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ActivityReviewScreen(initialFilter: 'all'),
      ),
    );
  }

  void _openRoadmap(
    BuildContext context,
    PerformanceReportSnapshot snapshot,
    String roadmapId,
  ) {
    final exists = snapshot.roadmaps.any(
      (roadmap) => roadmap.id == roadmapId && roadmap.deletedAt == null,
    );
    if (!exists) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoadmapDetailScreen(roadmapId: roadmapId),
      ),
    );
  }
}

class _ReportHero extends StatelessWidget {
  const _ReportHero({
    required this.compact,
    required this.title,
    required this.name,
    required this.from,
    required this.to,
    required this.recordCount,
  });

  final bool compact;
  final String title;
  final String? name;
  final DateTime from;
  final DateTime to;
  final int recordCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: compact ? 2 : null,
          overflow: compact ? TextOverflow.ellipsis : null,
          style:
              (compact
                      ? theme.textTheme.titleLarge
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (name?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Text(
            name!.trim(),
            maxLines: compact ? 2 : null,
            overflow: compact ? TextOverflow.ellipsis : null,
            style:
                (compact
                        ? theme.textTheme.titleSmall
                        : theme.textTheme.titleMedium)
                    ?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
          ),
        ],
      ],
    );
    final dateBlock = Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Text(
          '${dateFormat.format(from)} — ${dateFormat.format(to)}',
          maxLines: compact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          context.l10n.format('report_record_basis', {'count': recordCount}),
          maxLines: compact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.72),
            theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
          ],
        ),
        borderRadius: BorderRadius.circular(compact ? 18 : 24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 22),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [titleBlock, const SizedBox(height: 12), dateBlock],
              )
            : Wrap(
                alignment: WrapAlignment.spaceBetween,
                runAlignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 18,
                runSpacing: 12,
                children: [titleBlock, dateBlock],
              ),
      ),
    );
  }
}

class _ReportEmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(34),
        child: Column(
          children: [
            Icon(
              Icons.insights_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              context.l10n.text('report_empty_title'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.text('report_empty_body'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportMetricCard extends StatelessWidget {
  const _ReportMetricCard({
    required this.width,
    required this.compact,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final double width;
  final bool compact;
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      key: ValueKey('report-metric-$label'),
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked = compact && constraints.maxWidth < 210;
              final iconBox = DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(compact ? 11 : 14),
                ),
                child: Padding(
                  padding: EdgeInsets.all(compact ? 8 : 11),
                  child: Icon(icon, color: color, size: compact ? 21 : null),
                ),
              );
              final copy = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (compact
                                ? theme.textTheme.titleMedium
                                : theme.textTheme.titleLarge)
                            ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        (compact
                                ? theme.textTheme.bodySmall
                                : theme.textTheme.bodyMedium)
                            ?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                  ),
                ],
              );
              return Padding(
                padding: EdgeInsets.all(compact ? 12 : 18),
                child: stacked
                    ? ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 112),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                iconBox,
                                const Spacer(),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 19,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            copy,
                          ],
                        ),
                      )
                    : Row(
                        children: [
                          iconBox,
                          SizedBox(width: compact ? 10 : 14),
                          Expanded(child: copy),
                          const Icon(Icons.chevron_right_rounded, size: 20),
                        ],
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ResponsiveReportPanels extends StatelessWidget {
  const _ResponsiveReportPanels({
    required this.children,
    required this.compact,
  });

  final List<Widget> children;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 900
            ? (constraints.maxWidth - 14) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final child in children)
              SizedBox(width: width, height: compact ? 285 : 330, child: child),
          ],
        );
      },
    );
  }
}

class _ReportPanel extends StatelessWidget {
  const _ReportPanel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 420;
                  final titleWidget = Text(
                    title,
                    maxLines: compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  );
                  final action = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  );
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleWidget,
                        const SizedBox(height: 4),
                        action,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: titleWidget),
                      const SizedBox(width: 8),
                      action,
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyWorkChart extends StatelessWidget {
  const _DailyWorkChart({required this.points});

  final List<PerformanceReportDailyPoint> points;

  @override
  Widget build(BuildContext context) {
    final visible = points.length > 14
        ? points.sublist(points.length - 14)
        : points;
    if (!visible.any(
      (point) => point.plannedMs > 0 || point.productiveMs > 0,
    )) {
      return _ChartEmpty(context.l10n.text('report_no_chart_data'));
    }
    return CustomPaint(
      painter: _DailyWorkPainter(
        points: visible,
        plannedColor: Theme.of(context).colorScheme.primary,
        productiveColor: const Color(0xFF36C98F),
        gridColor: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.45),
        labelColor: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _DailyWorkPainter extends CustomPainter {
  const _DailyWorkPainter({
    required this.points,
    required this.plannedColor,
    required this.productiveColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<PerformanceReportDailyPoint> points;
  final Color plannedColor;
  final Color productiveColor;
  final Color gridColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 28.0;
    const top = 8.0;
    final chartHeight = math.max(1.0, size.height - bottom - top);
    final maxValue = points.fold<int>(
      1,
      (current, point) =>
          math.max(current, math.max(point.plannedMs, point.productiveMs)),
    );
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = top + chartHeight * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final slot = size.width / math.max(1, points.length);
    final barWidth = math.min(12.0, slot * 0.26);
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final center = slot * index + slot / 2;
      void bar(int value, double x, Color color) {
        final height = chartHeight * value / maxValue;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top + chartHeight - height, barWidth, height),
          const Radius.circular(4),
        );
        canvas.drawRRect(rect, Paint()..color = color);
      }

      bar(point.plannedMs, center - barWidth - 1.5, plannedColor);
      bar(point.productiveMs, center + 1.5, productiveColor);
      if (points.length <= 10 || index.isEven) {
        final text = DateFormat.E().format(point.day);
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(color: labelColor, fontSize: 9),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: slot);
        painter.paint(
          canvas,
          Offset(center - painter.width / 2, size.height - 18),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DailyWorkPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.plannedColor != plannedColor ||
      oldDelegate.productiveColor != productiveColor;
}

class _CompletionTrendChart extends StatelessWidget {
  const _CompletionTrendChart({required this.points});

  final List<PerformanceReportDailyPoint> points;

  @override
  Widget build(BuildContext context) {
    if (!points.any((point) => point.completedTasks > 0)) {
      return _ChartEmpty(context.l10n.text('report_no_chart_data'));
    }
    return CustomPaint(
      painter: _CompletionTrendPainter(
        points: points,
        lineColor: Theme.of(context).colorScheme.primary,
        fillColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: 0.18),
        gridColor: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.45),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _CompletionTrendPainter extends CustomPainter {
  const _CompletionTrendPainter({
    required this.points,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
  });

  final List<PerformanceReportDailyPoint> points;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = points.length > 42
        ? points.sublist(points.length - 42)
        : points;
    final cumulative = <int>[];
    var total = 0;
    for (final point in visible) {
      total += point.completedTasks;
      cumulative.add(total);
    }
    if (cumulative.isEmpty || total == 0) return;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = 10 + (size.height - 28) * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final line = Path();
    for (var index = 0; index < cumulative.length; index++) {
      final x = cumulative.length == 1
          ? size.width / 2
          : size.width * index / (cumulative.length - 1);
      final y =
          size.height -
          18 -
          (size.height - 34) * cumulative[index] / math.max(1, total);
      if (index == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height - 18)
      ..lineTo(0, size.height - 18)
      ..close();
    canvas.drawPath(fill, Paint()..color = fillColor);
    canvas.drawPath(
      line,
      Paint()
        ..color = lineColor
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CompletionTrendPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.lineColor != lineColor;
}

class _BreakdownBars extends StatelessWidget {
  const _BreakdownBars({
    required this.entries,
    required this.emptyLabel,
    required this.onEntryTap,
  });

  final List<PerformanceReportBreakdown> entries;
  final String emptyLabel;
  final ValueChanged<PerformanceReportBreakdown> onEntryTap;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return _ChartEmpty(emptyLabel);
    final maximum = math.max(1, entries.first.durationMs);
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: math.min(6, entries.length),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onEntryTap(entry),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.l10n.duration(
                        Duration(milliseconds: entry.durationMs),
                      ),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: entry.durationMs / maximum,
                    minHeight: 7,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChartEmpty extends StatelessWidget {
  const _ChartEmpty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < 160) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                message,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.query_stats_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActivityTotalsPanel extends StatelessWidget {
  const _ActivityTotalsPanel({required this.facts, required this.compact});

  final PerformanceReportFacts facts;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final entries = [
              _InlineTotal(
                expanded: compact,
                icon: Icons.auto_graph_rounded,
                label: context.l10n.text('report_active_activity'),
                value: context.l10n.duration(
                  Duration(milliseconds: facts.activeActivityMs),
                ),
              ),
              _InlineTotal(
                expanded: compact,
                icon: Icons.hourglass_empty_rounded,
                label: context.l10n.text('report_idle_activity'),
                value: context.l10n.duration(
                  Duration(milliseconds: facts.idleActivityMs),
                ),
              ),
              _InlineTotal(
                expanded: compact,
                icon: Icons.pause_circle_outline_rounded,
                label: context.l10n.text('report_paused_time'),
                value: context.l10n.duration(
                  Duration(milliseconds: facts.pausedMs),
                ),
              ),
            ];
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < entries.length; index++) ...[
                    entries[index],
                    if (index != entries.length - 1) const SizedBox(height: 12),
                  ],
                ],
              );
            }
            return Wrap(spacing: 24, runSpacing: 14, children: entries);
          },
        ),
      ),
    );
  }
}

class _InlineTotal extends StatelessWidget {
  const _InlineTotal({
    required this.expanded,
    required this.icon,
    required this.label,
    required this.value,
  });

  final bool expanded;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        if (expanded)
          Expanded(
            child: Text(
              '$label · $value',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          )
        else
          Text('$label · $value'),
      ],
    );
  }
}

class _HealthReportPanel extends StatelessWidget {
  const _HealthReportPanel({required this.entries});

  final List<PerformanceHealthSummaryEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.text('report_health_context'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: entries
                  .take(12)
                  .map((entry) {
                    return Chip(
                      avatar: const Icon(
                        Icons.health_and_safety_outlined,
                        size: 18,
                      ),
                      label: Text(
                        '${_healthMetricLabel(context, entry.metricType)}: '
                        '${_healthValue(context, entry)}',
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }

  static String _healthMetricLabel(BuildContext context, String metric) =>
      context.l10n.text(switch (metric) {
        'steps' => 'health_steps',
        'distance' => 'health_distance',
        'active_calories' => 'health_active_energy',
        'average_heart_rate' => 'health_average_heart_rate',
        'sleep_duration' => 'health_sleep',
        'exercise_sessions' => 'health_workouts',
        _ => 'health_data',
      });

  static String _healthValue(
    BuildContext context,
    PerformanceHealthSummaryEntry entry,
  ) {
    final value = entry.value.toDouble();
    return switch (entry.metricType) {
      'steps' => value.round().toString(),
      'distance' =>
        value >= 1000
            ? '${(value / 1000).toStringAsFixed(1)} km'
            : '${value.round()} m',
      'active_calories' => '${value.round()} kcal',
      'average_heart_rate' => '${value.round()} bpm',
      'sleep_duration' => context.l10n.duration(
        Duration(minutes: value.round()),
      ),
      'exercise_sessions' => value.round().toString(),
      _ => value.toStringAsFixed(1),
    };
  }
}

class _ReportTaskRecordsScreen extends StatelessWidget {
  const _ReportTaskRecordsScreen({required this.title, required this.tasks});

  final String title;
  final List<LocalTask> tasks;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: tasks.isEmpty
          ? _ReportRecordsEmpty()
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: tasks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => TaskCard(task: tasks[index]),
            ),
    );
  }
}

class _ReportActivityRecordsScreen extends StatelessWidget {
  const _ReportActivityRecordsScreen({
    required this.title,
    required this.segments,
  });

  final String title;
  final List<LocalActivitySegment> segments;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: segments.isEmpty
          ? _ReportRecordsEmpty()
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: segments.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final segment = segments[index];
                final label = PerformanceReportService.activityDisplayLabel(
                  segment,
                  unavailableLabel: context.l10n.text(
                    'report_record_unavailable',
                  ),
                );
                final duration = segment.endedAt
                    .difference(segment.startedAt)
                    .abs();
                return Card(
                  child: ListTile(
                    leading: Icon(
                      segment.url?.isNotEmpty == true
                          ? Icons.public_outlined
                          : Icons.apps_outlined,
                    ),
                    title: Text(label),
                    subtitle: Text(
                      '${context.l10n.duration(duration)} · '
                      '${DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).add_jm().format(segment.startedAt.toLocal())}',
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _ReportInterruptionRecordsScreen extends StatelessWidget {
  const _ReportInterruptionRecordsScreen({
    required this.records,
    required this.tasks,
    required this.totalDurationMs,
  });

  final List<LocalEntityRecord> records;
  final List<LocalTask> tasks;
  final int totalDurationMs;

  @override
  Widget build(BuildContext context) {
    final taskNames = {for (final task in tasks) task.id: task.title};
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text('report_interruptions'))),
      body: records.isEmpty
          ? _ReportRecordsEmpty()
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: Text(
                      context.l10n.duration(
                        Duration(milliseconds: totalDurationMs),
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.format('report_record_basis', {
                        'count': records.length,
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final record in records)
                  _InterruptionRecordTile(
                    record: record,
                    task: tasks
                        .where((task) => task.id == record.parentId)
                        .firstOrNull,
                    taskName:
                        taskNames[record.parentId] ??
                        context.l10n.text('report_task_unavailable'),
                  ),
              ],
            ),
    );
  }
}

class _InterruptionRecordTile extends StatelessWidget {
  const _InterruptionRecordTile({
    required this.record,
    required this.taskName,
    required this.task,
  });

  final LocalEntityRecord record;
  final String taskName;
  final LocalTask? task;

  @override
  Widget build(BuildContext context) {
    Map<String, Object?> data;
    try {
      final decoded = jsonDecode(record.dataJson);
      data = decoded is Map
          ? decoded.map((key, value) => MapEntry(key.toString(), value))
          : const {};
    } catch (_) {
      data = const {};
    }
    final type = data['interruption_type']?.toString().trim().isNotEmpty == true
        ? data['interruption_type'].toString()
        : record.title;
    final notes = data['notes']?.toString().trim();
    return Card(
      child: ListTile(
        leading: const Icon(Icons.warning_amber_rounded),
        title: Text(type.replaceAll('_', ' ')),
        subtitle: Text(
          [
            taskName,
            if (notes?.isNotEmpty == true) notes!,
            DateFormat.yMMMd(
              Localizations.localeOf(context).toLanguageTag(),
            ).add_jm().format(record.createdAt.toLocal()),
          ].join(' · '),
        ),
        trailing: task == null ? null : const Icon(Icons.chevron_right),
        onTap: task == null
            ? null
            : () => TaskWorkspaceScreen.open(context, task!, initialSection: 8),
      ),
    );
  }
}

class _ReportRecordsEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          context.l10n.text('report_no_chart_data'),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
