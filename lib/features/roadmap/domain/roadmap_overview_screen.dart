import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/platform/app_notification_service.dart';
import '../../../core/platform/task_browser_surface_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_controls.dart';
import '../../sessions/application/time_analytics_service.dart';
import '../../sessions/domain/session_models.dart';
import '../../tasks/application/task_action_controller.dart';
import '../../tasks/domain/task_item.dart';
import '../../tasks/presentation/task_workspace_screen.dart';
import '../data/roadmap_repository.dart';
import 'roadmap_phase.dart';
import 'roadmap_plan.dart';

class RoadmapOverviewScreen extends StatefulWidget {
  const RoadmapOverviewScreen({
    required this.phases,
    required this.tasks,
    required this.sessions,
    required this.taskController,
    super.key,
  });

  final List<RoadmapPhase> phases;
  final List<TaskItem> tasks;
  final List<TrackedSession> sessions;
  final TaskActionController taskController;

  @override
  State<RoadmapOverviewScreen> createState() => _RoadmapOverviewScreenState();
}

class _RoadmapOverviewScreenState extends State<RoadmapOverviewScreen> {
  bool _timelineMode = false;
  RoadmapRepository? _repository;
  List<RoadmapPlan> _roadmaps = const [];
  final Map<String, List<RoadmapPhase>> _phasesByRoadmap = {};
  String? _selectedRoadmapId;
  bool _loadingRoadmaps = true;

  RoadmapPlan? get _selectedRoadmap {
    final id = _selectedRoadmapId;
    if (id == null) {
      return null;
    }
    for (final roadmap in _roadmaps) {
      if (roadmap.id == id) {
        return roadmap;
      }
    }
    return null;
  }

  List<RoadmapPhase> get _selectedPhases {
    final id = _selectedRoadmapId;
    if (id == null) {
      return _sortPhases(widget.phases);
    }
    return _sortPhases(_phasesByRoadmap[id] ?? const []);
  }

  List<RoadmapPhase> _sortPhases(List<RoadmapPhase> phases) {
    return List<RoadmapPhase>.of(phases)
      ..sort((a, b) => a.phaseOrder.compareTo(b.phaseOrder));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(TaskBrowserSurfaceController.hideAll());
    final nextRepository = RoadmapRepository(
      AppServices.of(context).supabaseService,
    );
    if (_repository != null) {
      return;
    }
    _repository = nextRepository;
    unawaited(_loadRoadmaps());
  }

  @override
  Widget build(BuildContext context) {
    final activePhases = _selectedPhases;
    final roadmapTasks = _tasksForPhases(activePhases);
    final roadmapSessions = _sessionsForTasks(roadmapTasks);
    final summary = _RoadmapSummary.from(
      roadmap: _selectedRoadmap,
      phases: activePhases,
      tasks: roadmapTasks,
      sessions: roadmapSessions,
    );
    _logRoadmapConsistency(activePhases, summary);
    final signedIn =
        AppServices.of(context).supabaseService.currentUser != null;

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.text('roadmap')),
          actions: [
            if (_roadmaps.isNotEmpty)
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedRoadmapId,
                  items: [
                    for (final roadmap in _roadmaps)
                      DropdownMenuItem(
                        value: roadmap.id,
                        child: Text(roadmap.title),
                      ),
                  ],
                  onChanged: _selectRoadmap,
                ),
              ),
            if (signedIn)
              AppButton.text(
                onPressed: _showCreateRoadmapDialog,
                icon: const Icon(Icons.add_road_outlined),
                label: Text(context.text('createRoadmap')),
              ),
            if (_selectedRoadmap != null)
              AppButton.text(
                onPressed: _showAddPhaseDialog,
                icon: const Icon(Icons.add_outlined),
                label: Text(context.text('addPhase')),
              ),
            IconButton(
              tooltip: context.text('timeline'),
              onPressed: () => setState(() => _timelineMode = !_timelineMode),
              icon: Icon(
                _timelineMode
                    ? Icons.view_list_outlined
                    : Icons.timeline_outlined,
              ),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: context.text('overview')),
              Tab(text: context.text('timeline')),
              Tab(text: context.text('phases')),
              Tab(text: context.text('analytics')),
              Tab(text: context.text('recommendations')),
              Tab(text: context.text('activity')),
            ],
          ),
        ),
        body: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: SafeArea(
            child: _loadingRoadmaps
                ? const Center(child: CircularProgressIndicator())
                : _roadmaps.isEmpty && activePhases.isEmpty
                ? _EmptyRoadmap(onCreate: _showCreateRoadmapDialog)
                : TabBarView(
                    children: [
                      _OverviewTab(
                        summary: summary,
                        roadmap: _selectedRoadmap,
                        phases: activePhases,
                        tasks: roadmapTasks,
                        sessions: roadmapSessions,
                        controller: widget.taskController,
                        onOpenPhase: _openPhase,
                      ),
                      _TimelineTab(phases: activePhases, summary: summary),
                      _PhasesTab(
                        phases: activePhases,
                        summary: summary,
                        tasks: roadmapTasks,
                        sessions: roadmapSessions,
                        onOpenPhase: _openPhase,
                        onEditPhase: _showEditPhaseDialog,
                        onDuplicatePhase: _duplicatePhase,
                        onMovePhase: _movePhase,
                        onArchivePhase: _archivePhase,
                        onAddPhase: _showAddPhaseDialog,
                      ),
                      _AnalyticsTab(
                        summary: summary,
                        sessions: roadmapSessions,
                      ),
                      _RecommendationsTab(summary: summary),
                      _ActivityTab(summary: summary),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  List<TaskItem> _tasksForPhases(List<RoadmapPhase> phases) {
    final phaseIds = phases
        .map((phase) => phase.id)
        .whereType<String>()
        .toSet();
    final phaseNumbers = phases.map((phase) => phase.phase).toSet();
    if (phaseIds.isNotEmpty) {
      return widget.tasks
          .where((task) => phaseIds.contains(task.roadmapPhaseId))
          .toList(growable: false);
    }
    return widget.tasks
        .where((task) => phaseNumbers.contains(task.roadmapPhase))
        .toList(growable: false);
  }

  List<TaskItem> _tasksForPhase(
    RoadmapPhase phase,
    List<TaskItem> scopedTasks,
  ) {
    return scopedTasks
        .where((task) => _taskBelongsToPhase(task, phase))
        .toList(growable: false);
  }

  List<TrackedSession> _sessionsForTasks(List<TaskItem> tasks) {
    final taskIds = tasks.map((task) => task.id).toSet();
    return widget.sessions
        .where((session) => taskIds.contains(session.taskId))
        .toList(growable: false);
  }

  void _logRoadmapConsistency(
    List<RoadmapPhase> phases,
    _RoadmapSummary summary,
  ) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('Selected roadmap: $_selectedRoadmapId');
    for (final phase in phases) {
      debugPrint('Phase ${phase.phase}: ${phase.status}');
    }
    debugPrint('Resolved active phase: ${summary.activePhase?.phase}');
    debugPrint('Remote phase count: ${phases.length}');
    debugPrint('Selected roadmap ID: $_selectedRoadmapId');
    debugPrint('Active phase ID: ${summary.activePhase?.id}');
    debugPrint('Active phase number: ${summary.activePhase?.phase}');
    debugPrint(
      'Last remote refresh: '
      '${AppServices.of(context).supabaseService.lastFullRemoteRefreshAt}',
    );
  }

  void _openPhase(RoadmapPhase phase) {
    final roadmapTasks = _tasksForPhases(_selectedPhases);
    final phaseTasks = _tasksForPhase(phase, roadmapTasks);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PhaseDetailsSheet(
        phase: phase,
        tasks: phaseTasks,
        sessions: _sessionsForTasks(phaseTasks),
        controller: widget.taskController,
      ),
    );
  }

  Future<void> _showCreateRoadmapDialog() async {
    final input = await showDialog<CreateRoadmapInput>(
      context: context,
      builder: (context) => const _CreateRoadmapDialog(),
    );
    if (input == null) {
      return;
    }
    await _createRoadmap(input);
  }

  Future<void> _showAddPhaseDialog() async {
    final roadmap = _selectedRoadmap;
    if (roadmap == null) {
      return;
    }
    final phase = await showDialog<RoadmapPhase>(
      context: context,
      builder: (context) => _CreatePhaseDialog(
        roadmapId: roadmap.id,
        nextPhaseNumber: (_phasesByRoadmap[roadmap.id]?.length ?? 0) + 1,
      ),
    );
    if (phase == null) {
      return;
    }
    await _addPhase(phase);
  }

  Future<void> _showEditPhaseDialog(RoadmapPhase phase) async {
    final updated = await showDialog<RoadmapPhase>(
      context: context,
      builder: (context) => _EditPhaseDialog(phase: phase),
    );
    if (updated == null) {
      return;
    }
    await _updatePhase(updated);
  }

  Future<void> _updatePhase(RoadmapPhase phase) async {
    final services = AppServices.of(context);
    final repository = _repository;
    final roadmapId = phase.roadmapId;
    if (repository == null || roadmapId == null) {
      return;
    }
    final previous = _phasesByRoadmap[roadmapId] ?? const [];
    setState(() {
      _phasesByRoadmap[roadmapId] = [
        for (final item in previous) item.id == phase.id ? phase : item,
      ]..sort((a, b) => a.phaseOrder.compareTo(b.phaseOrder));
    });
    try {
      final saved = await repository.updatePhase(phase);
      if (!mounted) {
        return;
      }
      setState(() {
        final current = _phasesByRoadmap[roadmapId] ?? const [];
        _phasesByRoadmap[roadmapId] = [
          for (final item in current) item.id == saved.id ? saved : item,
        ]..sort((a, b) => a.phaseOrder.compareTo(b.phaseOrder));
      });
      services.notificationService.showSuccess(context.text('changesSaved'));
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() => _phasesByRoadmap[roadmapId] = previous);
      services.notificationService.showError(context.text('phaseUpdateFailed'));
    }
  }

  Future<void> _duplicatePhase(RoadmapPhase phase) async {
    final services = AppServices.of(context);
    final repository = _repository;
    final roadmapId = phase.roadmapId;
    if (repository == null || roadmapId == null) {
      return;
    }
    try {
      final saved = await repository.duplicatePhase(phase);
      if (!mounted) {
        return;
      }
      final previous = _phasesByRoadmap[roadmapId] ?? const [];
      setState(() {
        _phasesByRoadmap[roadmapId] = [...previous, saved]
          ..sort((a, b) => a.phaseOrder.compareTo(b.phaseOrder));
      });
      services.notificationService.showSuccess(context.text('changesSaved'));
    } on Object {
      if (!mounted) {
        return;
      }
      services.notificationService.showError(context.text('phaseUpdateFailed'));
    }
  }

  Future<void> _movePhase(RoadmapPhase phase, int delta) async {
    final services = AppServices.of(context);
    final repository = _repository;
    final roadmapId = phase.roadmapId;
    if (repository == null || roadmapId == null) {
      return;
    }
    final previous = _sortPhases(_phasesByRoadmap[roadmapId] ?? const []);
    final index = previous.indexWhere((item) => item.id == phase.id);
    final targetIndex = index + delta;
    if (index < 0 || targetIndex < 0 || targetIndex >= previous.length) {
      return;
    }
    final reordered = [...previous];
    final item = reordered.removeAt(index);
    reordered.insert(targetIndex, item);
    final renumbered = [
      for (var i = 0; i < reordered.length; i += 1)
        reordered[i].copyWith(phase: i + 1, phaseOrder: i + 1),
    ];
    setState(() => _phasesByRoadmap[roadmapId] = renumbered);
    try {
      await repository.reorderPhases(renumbered);
      if (!mounted) {
        return;
      }
      services.notificationService.showSuccess(context.text('changesSaved'));
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() => _phasesByRoadmap[roadmapId] = previous);
      services.notificationService.showError(context.text('phaseUpdateFailed'));
    }
  }

  Future<void> _archivePhase(RoadmapPhase phase) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.text('archivePhase')),
        content: Text(context.text('archivePhaseWarning')),
        actions: [
          AppButton.text(
            onPressed: () => Navigator.of(context).pop(false),
            label: Text(context.text('cancel')),
          ),
          AppButton.filled(
            onPressed: () => Navigator.of(context).pop(true),
            label: Text(context.text('archivePhase')),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (_repository == null || phase.roadmapId == null) {
      return;
    }
    await _updatePhase(phase.copyWith(status: 'archived'));
  }

  Future<void> _loadRoadmaps() async {
    final repository = _repository;
    if (repository == null) {
      return;
    }
    final roadmaps = <RoadmapPlan>[];
    final phases = <String, List<RoadmapPhase>>{};
    try {
      roadmaps.addAll(await repository.loadRoadmaps());
      for (final roadmap in roadmaps) {
        phases[roadmap.id] = await repository.loadPhases(roadmap.id);
      }
    } on Object {
      if (mounted) {
        AppServices.of(context).notificationService.showWarning(
          context.text('accountDataRefreshFailed'),
        );
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _roadmaps = roadmaps;
      _phasesByRoadmap
        ..clear()
        ..addAll(phases);
      _selectedRoadmapId = roadmaps.isEmpty
          ? null
          : _selectedRoadmapId ?? roadmaps.first.id;
      _loadingRoadmaps = false;
    });
  }

  void _selectRoadmap(String? id) {
    if (id == null) {
      return;
    }
    setState(() => _selectedRoadmapId = id);
  }

  Future<void> _createRoadmap(CreateRoadmapInput input) async {
    final services = AppServices.of(context);
    final repository = _repository;
    final userId = services.supabaseService.currentUser?.id;
    if (repository == null || userId == null) {
      services.notificationService.showError(
        context.text('roadmapCreateSignInRequired'),
      );
      return;
    }
    final localRoadmap = RoadmapPlan.fromInput(userId: userId, input: input);
    final previousRoadmaps = _roadmaps;
    final previousSelected = _selectedRoadmapId;
    setState(() {
      _roadmaps = [localRoadmap, ..._roadmaps];
      _selectedRoadmapId = localRoadmap.id;
      _phasesByRoadmap[localRoadmap.id] = const [];
    });
    services.notificationService.showSuccess(
      context.text('roadmapCreatedNextStep'),
    );

    try {
      final saved = await repository.createRoadmap(localRoadmap);
      if (!mounted) {
        return;
      }
      setState(() {
        _roadmaps = [
          saved,
          ..._roadmaps.where((roadmap) => roadmap.id != localRoadmap.id),
        ];
        _selectedRoadmapId = saved.id;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _roadmaps = previousRoadmaps;
        _selectedRoadmapId = previousSelected;
        _phasesByRoadmap.remove(localRoadmap.id);
      });
      services.notificationService.showError(
        context.text('roadmapCreateFailed'),
        action: AppNotificationAction(
          label: context.text('retry'),
          onPressed: () => unawaited(_createRoadmap(input)),
        ),
      );
    }
  }

  Future<void> _addPhase(RoadmapPhase phase) async {
    final services = AppServices.of(context);
    final repository = _repository;
    if (repository == null || phase.roadmapId == null) {
      return;
    }
    final roadmapId = phase.roadmapId!;
    final previous = _phasesByRoadmap[roadmapId] ?? const [];
    setState(() {
      _phasesByRoadmap[roadmapId] = [...previous, phase]
        ..sort((a, b) => a.phaseOrder.compareTo(b.phaseOrder));
    });
    try {
      final saved = await repository.addPhase(phase);
      if (!mounted) {
        return;
      }
      setState(() {
        final current = _phasesByRoadmap[roadmapId] ?? const [];
        _phasesByRoadmap[roadmapId] = [
          for (final item in current) item.id == phase.id ? saved : item,
        ]..sort((a, b) => a.phaseOrder.compareTo(b.phaseOrder));
      });
      services.notificationService.showSuccess(context.text('changesSaved'));
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() => _phasesByRoadmap[roadmapId] = previous);
      services.notificationService.showError(context.text('phaseCreateFailed'));
    }
  }
}

class _CreateRoadmapDialog extends StatefulWidget {
  const _CreateRoadmapDialog();

  @override
  State<_CreateRoadmapDialog> createState() => _CreateRoadmapDialogState();
}

class _CreateRoadmapDialogState extends State<_CreateRoadmapDialog> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _currentLevelController = TextEditingController();
  final _targetLevelController = TextEditingController();
  DateTime _startDate = DateTime.now();
  DateTime? _targetDate;
  double _weeklyHours = 4;
  double _maxDailyMinutes = 90;
  final Set<int> _preferredDays = {DateTime.saturday, DateTime.monday};
  RoadmapSchedulingMode _schedulingMode = RoadmapSchedulingMode.capacityDriven;
  String _structureChoice = 'empty';

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _currentLevelController.dispose();
    _targetLevelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.text('roadmapCreateTitle')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.text('roadmapCreateDescription')),
              const SizedBox(height: 16),
              _SectionTitle(text: context.text('roadmapStepGoal')),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: context.text('roadmapTitle'),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: context.text('goalDescription'),
                ),
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _currentLevelController,
                      decoration: InputDecoration(
                        labelText: context.text('currentLevel'),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _targetLevelController,
                      decoration: InputDecoration(
                        labelText: context.text('targetLevel'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _pickStartDate(context),
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      '${context.text('startDate')}: ${_dateLabel(context, _startDate)}',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickTargetDate(context),
                    icon: const Icon(Icons.flag_outlined),
                    label: Text(
                      '${context.text('targetDate')}: ${_targetDate == null ? context.text('none') : _dateLabel(context, _targetDate!)}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SectionTitle(text: context.text('roadmapStepAvailableTime')),
              Text(
                '${context.text('weeklyAvailableHours')}: ${_weeklyHours.toStringAsFixed(1)}',
              ),
              Slider(
                value: _weeklyHours,
                min: 0,
                max: 40,
                divisions: 80,
                onChanged: (value) => setState(() => _weeklyHours = value),
              ),
              Text(
                '${context.text('maximumDailyTime')}: ${_maxDailyMinutes.round()} ${context.text('minutes')}',
              ),
              Slider(
                value: _maxDailyMinutes,
                min: 0,
                max: 360,
                divisions: 24,
                onChanged: (value) => setState(() => _maxDailyMinutes = value),
              ),
              const SizedBox(height: 8),
              Text(context.text('preferredDays')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final day in const [
                    DateTime.monday,
                    DateTime.tuesday,
                    DateTime.wednesday,
                    DateTime.thursday,
                    DateTime.friday,
                    DateTime.saturday,
                    DateTime.sunday,
                  ])
                    FilterChip(
                      selected: _preferredDays.contains(day),
                      label: Text(_dayLabel(context, day)),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _preferredDays.add(day);
                          } else {
                            _preferredDays.remove(day);
                          }
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _SectionTitle(text: context.text('roadmapStepPlanningMethod')),
              DropdownButtonFormField<RoadmapSchedulingMode>(
                initialValue: _schedulingMode,
                decoration: InputDecoration(
                  labelText: context.text('planningMethod'),
                ),
                items: [
                  DropdownMenuItem(
                    value: RoadmapSchedulingMode.deadlineDriven,
                    child: Text(context.text('planningDeadlineDriven')),
                  ),
                  DropdownMenuItem(
                    value: RoadmapSchedulingMode.capacityDriven,
                    child: Text(context.text('planningCapacityDriven')),
                  ),
                  DropdownMenuItem(
                    value: RoadmapSchedulingMode.balanced,
                    child: Text(context.text('planningBalanced')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _schedulingMode = value);
                  }
                },
              ),
              const SizedBox(height: 18),
              _SectionTitle(text: context.text('roadmapStepStructure')),
              DropdownButtonFormField<String>(
                initialValue: _structureChoice,
                decoration: InputDecoration(
                  labelText: context.text('roadmapStructure'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'empty',
                    child: Text(context.text('roadmapStructureEmpty')),
                  ),
                  DropdownMenuItem(
                    value: 'manual',
                    child: Text(context.text('roadmapStructureManual')),
                  ),
                  DropdownMenuItem(
                    value: 'template',
                    child: Text(context.text('roadmapStructureTemplate')),
                  ),
                  DropdownMenuItem(
                    value: 'suggested',
                    child: Text(context.text('roadmapStructureSuggested')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _structureChoice = value);
                  }
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppButton.text(
          onPressed: () => Navigator.of(context).pop(),
          label: Text(context.text('cancel')),
        ),
        AppButton.filled(
          onPressed: _submit,
          label: Text(context.text('createRoadmap')),
        ),
      ],
    );
  }

  Future<void> _pickStartDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _startDate,
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _pickTargetDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: _startDate,
      lastDate: DateTime(2100),
      initialDate: _targetDate ?? _startDate.add(const Duration(days: 90)),
    );
    if (picked != null) {
      setState(() => _targetDate = picked);
    }
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      AppServices.of(
        context,
      ).notificationService.showWarning(context.text('roadmapTitleRequired'));
      return;
    }
    Navigator.of(context).pop(
      CreateRoadmapInput(
        title: title,
        description: _descriptionController.text.trim(),
        currentLevel: _currentLevelController.text.trim(),
        targetLevel: _targetLevelController.text.trim(),
        startDate: _startDate,
        targetDate: _targetDate,
        weeklyCapacityMinutes: (_weeklyHours * 60).round(),
        maximumDailyMinutes: _maxDailyMinutes.round(),
        preferredDays: _preferredDays.toList()..sort(),
        schedulingMode: _schedulingMode,
        structureChoice: _structureChoice,
      ),
    );
  }
}

class _CreatePhaseDialog extends StatefulWidget {
  const _CreatePhaseDialog({
    required this.roadmapId,
    required this.nextPhaseNumber,
  });

  final String roadmapId;
  final int nextPhaseNumber;

  @override
  State<_CreatePhaseDialog> createState() => _CreatePhaseDialogState();
}

class _CreatePhaseDialogState extends State<_CreatePhaseDialog> {
  late final TextEditingController _numberController;
  final _titleController = TextEditingController();
  final _periodController = TextEditingController();
  final _evidenceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _numberController = TextEditingController(
      text: widget.nextPhaseNumber.toString(),
    );
  }

  @override
  void dispose() {
    _numberController.dispose();
    _titleController.dispose();
    _periodController.dispose();
    _evidenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.text('addPhase')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _numberController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.text('phaseNumber'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: context.text('phaseTitle'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _periodController,
                decoration: InputDecoration(
                  labelText: context.text('phasePeriod'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _evidenceController,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: context.text('phaseEvidenceRequired'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppButton.text(
          onPressed: () => Navigator.of(context).pop(),
          label: Text(context.text('cancel')),
        ),
        AppButton.filled(onPressed: _submit, label: Text(context.text('save'))),
      ],
    );
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      AppServices.of(
        context,
      ).notificationService.showWarning(context.text('phaseTitleRequired'));
      return;
    }
    Navigator.of(context).pop(
      RoadmapPhase.create(
        roadmapId: widget.roadmapId,
        phase:
            int.tryParse(_numberController.text.trim()) ??
            widget.nextPhaseNumber,
        objective: title,
        period: _periodController.text.trim(),
        exitEvidence: _evidenceController.text.trim(),
      ),
    );
  }
}

class _EditPhaseDialog extends StatefulWidget {
  const _EditPhaseDialog({required this.phase});

  final RoadmapPhase phase;

  @override
  State<_EditPhaseDialog> createState() => _EditPhaseDialogState();
}

class _EditPhaseDialogState extends State<_EditPhaseDialog> {
  late final TextEditingController _numberController;
  late final TextEditingController _titleController;
  late final TextEditingController _periodController;
  late final TextEditingController _evidenceController;
  late String _status;

  @override
  void initState() {
    super.initState();
    _numberController = TextEditingController(
      text: widget.phase.phase.toString(),
    );
    _titleController = TextEditingController(text: widget.phase.objective);
    _periodController = TextEditingController(text: widget.phase.period);
    _evidenceController = TextEditingController(
      text: widget.phase.exitEvidence,
    );
    _status = widget.phase.status;
  }

  @override
  void dispose() {
    _numberController.dispose();
    _titleController.dispose();
    _periodController.dispose();
    _evidenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.text('editPhase')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _numberController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.text('phaseNumber'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: context.text('phaseTitle'),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _periodController,
                decoration: InputDecoration(
                  labelText: context.text('phasePeriod'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _evidenceController,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: context.text('phaseEvidenceRequired'),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: InputDecoration(labelText: context.text('status')),
                items: [
                  DropdownMenuItem(
                    value: 'not_started',
                    child: Text(context.text('notStarted')),
                  ),
                  DropdownMenuItem(
                    value: 'active',
                    child: Text(context.text('active')),
                  ),
                  DropdownMenuItem(
                    value: 'paused',
                    child: Text(context.text('paused')),
                  ),
                  DropdownMenuItem(
                    value: 'completed',
                    child: Text(context.text('completed')),
                  ),
                  DropdownMenuItem(
                    value: 'archived',
                    child: Text(context.text('archived')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppButton.text(
          onPressed: () => Navigator.of(context).pop(),
          label: Text(context.text('cancel')),
        ),
        AppButton.filled(onPressed: _submit, label: Text(context.text('save'))),
      ],
    );
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      AppServices.of(
        context,
      ).notificationService.showWarning(context.text('phaseTitleRequired'));
      return;
    }
    final number =
        int.tryParse(_numberController.text.trim()) ?? widget.phase.phase;
    Navigator.of(context).pop(
      widget.phase.copyWith(
        phase: number,
        phaseOrder: number,
        objective: title,
        period: _periodController.text.trim(),
        exitEvidence: _evidenceController.text.trim(),
        status: _status,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

String _dateLabel(BuildContext context, DateTime date) {
  return MaterialLocalizations.of(context).formatMediumDate(date.toLocal());
}

String _formatRoadmapDateTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final material = MaterialLocalizations.of(context);
  return '${material.formatMediumDate(local)} · '
      '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

String _dayLabel(BuildContext context, int weekday) {
  return switch (weekday) {
    DateTime.monday => context.text('monday'),
    DateTime.tuesday => context.text('tuesday'),
    DateTime.wednesday => context.text('wednesday'),
    DateTime.thursday => context.text('thursday'),
    DateTime.friday => context.text('friday'),
    DateTime.saturday => context.text('saturday'),
    _ => context.text('sunday'),
  };
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.summary,
    required this.roadmap,
    required this.phases,
    required this.tasks,
    required this.sessions,
    required this.controller,
    required this.onOpenPhase,
  });

  final _RoadmapSummary summary;
  final RoadmapPlan? roadmap;
  final List<RoadmapPhase> phases;
  final List<TaskItem> tasks;
  final List<TrackedSession> sessions;
  final TaskActionController controller;
  final ValueChanged<RoadmapPhase> onOpenPhase;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _RoadmapCoachCard(summary: summary, controller: controller),
        const SizedBox(height: 16),
        _RoadmapSummaryHeader(summary: summary, title: roadmap?.title),
        const SizedBox(height: 16),
        Text(
          context.text('activePhase'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (phases.isEmpty)
          _EmptyPhaseCard(roadmap: roadmap)
        else if (summary.activePhase == null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(context.text('noActivePhase')),
              subtitle: Text(context.text('choosePhaseToContinue')),
            ),
          )
        else
          _PhaseCard(
            phase: summary.activePhase!,
            summary: summary,
            tasks: tasks,
            sessions: sessions,
            onTap: () => onOpenPhase(summary.activePhase!),
            prominent: true,
          ),
        const SizedBox(height: 16),
        Text(
          context.text('nextRoadmapAction'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _NextActionCard(task: summary.nextTask, controller: controller),
      ],
    );
  }
}

class _RoadmapCoachCard extends StatelessWidget {
  const _RoadmapCoachCard({required this.summary, required this.controller});

  final _RoadmapSummary summary;
  final TaskActionController controller;

  @override
  Widget build(BuildContext context) {
    final profile = AppServices.of(context).supabaseService.profile;
    final name = profile?.preferredName.trim() ?? '';
    final focusTasks = summary.todayTasks.isNotEmpty
        ? summary.todayTasks.take(3).toList(growable: false)
        : <TaskItem>[?summary.nextTask];
    final dates = MaterialLocalizations.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name.isEmpty
                  ? context.text('roadmapCoachHello')
                  : '${context.text('roadmapCoachHello')} $name.',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            Text(
              context.text('todaysFocus'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            if (focusTasks.isEmpty)
              Text(context.text('noRoadmapTasksToday'))
            else
              for (final task in focusTasks)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    task.isCompleted
                        ? Icons.check_circle_outline
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(task.title),
                  subtitle: task.displayStart == null
                      ? null
                      : Text(
                          dates.formatTimeOfDay(
                            TimeOfDay.fromDateTime(task.displayStart!),
                          ),
                        ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TaskWorkspaceScreen(
                        controller: controller,
                        task: task,
                      ),
                    ),
                  ),
                ),
            const Divider(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _MetricChip(
                  label: context.text('remainingPomodoros'),
                  value: '${summary.remainingPomodoros}',
                ),
                _MetricChip(
                  label: context.text('remainingPlannedTime'),
                  value: formatDurationCompact(summary.remainingMinutes * 60),
                ),
                _MetricChip(
                  label: context.text('recentConsistency'),
                  value:
                      '${summary.activeDaysPerWeek.toStringAsFixed(1)} ${context.text('daysPerWeek')}',
                ),
                if (summary.productivePeriodKey != null)
                  _MetricChip(
                    label: context.text('mostProductiveTime'),
                    value: context.text(summary.productivePeriodKey!),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _CoachMessage(summary: summary),
            if (summary.hasForecastData) ...[
              const SizedBox(height: 12),
              Text(
                '${context.text('estimatedPhaseCompletion')}: '
                '${summary.activePhaseForecastLabel(context)}',
              ),
              Text(
                '${context.text('estimatedRoadmapCompletion')}: '
                '${summary.forecastLabel(context)}',
              ),
            ],
            if (summary.bottleneckTask != null) ...[
              const SizedBox(height: 12),
              Text(
                '${context.text('currentBottleneck')}: '
                '${summary.bottleneckTask!.title}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '${context.text('basedOnStoredActivity')} '
              '${summary.sessionCount} ${context.text('sessions').toLowerCase()}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachMessage extends StatelessWidget {
  const _CoachMessage({required this.summary});

  final _RoadmapSummary summary;

  @override
  Widget build(BuildContext context) {
    if (summary.daysSinceLastActivity >= 4 && summary.sessionCount > 0) {
      return _CoachNotice(
        icon: Icons.restart_alt_outlined,
        title:
            '${context.text('noRoadmapActivityFor')} ${summary.daysSinceLastActivity} ${context.text('days')}.',
        body: summary.nextTask == null
            ? context.text('reviewRoadmapNextStep')
            : '${context.text('suggestedRestart')}: ${summary.nextTask!.title}',
      );
    }
    if (!summary.hasForecastData) {
      return _CoachNotice(
        icon: Icons.insights_outlined,
        title: context.text('forecastNeedsMoreActivity'),
        body:
            '${context.text('completeAtLeast')} '
            '${summary.sessionsNeeded} ${context.text('focusSessions')}, '
            '${summary.tasksNeeded} ${context.text('roadmapTasksLower')}, '
            '${summary.reviewsNeeded} ${context.text('milestoneReviews')}.',
      );
    }
    if (summary.scheduleVarianceDays >= 1) {
      return _CoachNotice(
        icon: Icons.trending_up_outlined,
        title:
            '${context.text('aheadByApproximately')} ${summary.scheduleVarianceDays} ${context.text('days')}.',
        body: context.text('maintainPaceWithoutMoreWork'),
      );
    }
    if (summary.scheduleVarianceDays <= -1) {
      return _CoachNotice(
        icon: Icons.trending_down_outlined,
        title:
            '${context.text('behindByApproximately')} ${summary.scheduleVarianceDays.abs()} ${context.text('days')}.',
        body: summary.nextTask == null
            ? context.text('reviewRoadmapNextStep')
            : '${context.text('recommendedRecovery')}: ${summary.nextTask!.title}',
      );
    }
    return _CoachNotice(
      icon: Icons.check_circle_outline,
      title: context.text('roadmapPaceMatchesPlan'),
      body: context.text('continueNextUsefulAction'),
    );
  }
}

class _CoachNotice extends StatelessWidget {
  const _CoachNotice({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhasesTab extends StatelessWidget {
  const _PhasesTab({
    required this.phases,
    required this.summary,
    required this.tasks,
    required this.sessions,
    required this.onOpenPhase,
    required this.onEditPhase,
    required this.onDuplicatePhase,
    required this.onMovePhase,
    required this.onArchivePhase,
    required this.onAddPhase,
  });

  final List<RoadmapPhase> phases;
  final _RoadmapSummary summary;
  final List<TaskItem> tasks;
  final List<TrackedSession> sessions;
  final ValueChanged<RoadmapPhase> onOpenPhase;
  final ValueChanged<RoadmapPhase> onEditPhase;
  final ValueChanged<RoadmapPhase> onDuplicatePhase;
  final void Function(RoadmapPhase phase, int delta) onMovePhase;
  final ValueChanged<RoadmapPhase> onArchivePhase;
  final VoidCallback onAddPhase;

  @override
  Widget build(BuildContext context) {
    if (phases.isEmpty) {
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverToBoxAdapter(
              child: _BoundedEmptyState(
                title: context.text('noPhasesFound'),
                actionLabel: context.text('addPhase'),
                onAction: onAddPhase,
              ),
            ),
          ),
        ],
      );
    }
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              if (index.isOdd) {
                return const SizedBox(height: 10);
              }
              final phaseIndex = index ~/ 2;
              final phase = phases[phaseIndex];
              final active = phase.phase == summary.activePhase?.phase;
              return _PhaseCard(
                phase: phase,
                summary: summary,
                tasks: tasks,
                sessions: sessions,
                onTap: () => onOpenPhase(phase),
                onEdit: () => onEditPhase(phase),
                onDuplicate: () => onDuplicatePhase(phase),
                onMoveUp: phaseIndex == 0 ? null : () => onMovePhase(phase, -1),
                onMoveDown: phaseIndex == phases.length - 1
                    ? null
                    : () => onMovePhase(phase, 1),
                onArchive: () => onArchivePhase(phase),
                prominent: active,
              );
            }, childCount: phases.length * 2 - 1),
          ),
        ),
      ],
    );
  }
}

class _BoundedEmptyState extends StatelessWidget {
  const _BoundedEmptyState({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 180),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.flag_outlined, size: 40),
                const SizedBox(height: 12),
                Text(title, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                AppButton.filled(
                  onPressed: onAction,
                  icon: const Icon(Icons.add_outlined),
                  label: Text(actionLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyPhaseCard extends StatelessWidget {
  const _EmptyPhaseCard({required this.roadmap});

  final RoadmapPlan? roadmap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.flag_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                roadmap == null
                    ? context.text('createRoadmapPrompt')
                    : context.text('roadmapAddFirstPhaseHint'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoadmapSummaryHeader extends StatelessWidget {
  const _RoadmapSummaryHeader({required this.summary, this.title});

  final _RoadmapSummary summary;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title ?? context.text('roadmap'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                _StatusBadge(status: summary.status),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (summary.overallProgress / 100).clamp(0.0, 1.0).toDouble(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricChip(
                  label: context.text('overallProgress'),
                  value: '${summary.overallProgress.round()}%',
                ),
                _MetricChip(
                  label: context.text('plannedByToday'),
                  value: '${summary.plannedByToday.round()}%',
                ),
                _MetricChip(
                  label: context.text('scheduleVariance'),
                  value: summary.progressVarianceLabel,
                ),
                _MetricChip(
                  label: context.text('actualFocusedHours'),
                  value:
                      '${(summary.actualFocusedSeconds / 3600).toStringAsFixed(1)}h',
                ),
                _MetricChip(
                  label: context.text('fourWeekVelocity'),
                  value: '${summary.fourWeekHours.toStringAsFixed(1)}h/wk',
                ),
                _MetricChip(
                  label: context.text('forecastFinish'),
                  value: summary.forecastLabel(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(context.text(summary.interpretationKey)),
          ],
        ),
      ),
    );
  }
}

class _PhaseCard extends StatelessWidget {
  const _PhaseCard({
    required this.phase,
    required this.summary,
    required this.tasks,
    required this.sessions,
    required this.onTap,
    this.onEdit,
    this.onDuplicate,
    this.onArchive,
    this.onMoveUp,
    this.onMoveDown,
    this.prominent = false,
  });

  final RoadmapPhase phase;
  final _RoadmapSummary summary;
  final List<TaskItem> tasks;
  final List<TrackedSession> sessions;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onArchive;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final phaseTasks = tasks
        .where((task) => _taskBelongsToPhase(task, phase))
        .toList();
    final activeSeconds = sessions
        .where((session) => phaseTasks.any((task) => task.id == session.taskId))
        .fold<int>(0, (total, session) => total + session.activeSeconds);
    final progress = _PhaseProgressBreakdown.from(
      phase: phase,
      summary: summary,
      tasks: phaseTasks,
      activeSeconds: activeSeconds,
    );

    return Card(
      elevation: prominent ? 5 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(child: Text('${phase.phase}')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Phase ${phase.phase} - ${phase.objective}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          phase.period,
                          style: TextStyle(color: context.appColors.mutedText),
                        ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _StatusBadge(
                        status: _phaseStatus(phase, summary, progress.percent),
                      ),
                      if (onEdit != null)
                        IconButton(
                          tooltip: context.text('editPhase'),
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      if (onDuplicate != null || onArchive != null)
                        PopupMenuButton<String>(
                          tooltip: context.text('phaseActions'),
                          onSelected: (value) {
                            switch (value) {
                              case 'duplicate':
                                onDuplicate?.call();
                                break;
                              case 'move_up':
                                onMoveUp?.call();
                                break;
                              case 'move_down':
                                onMoveDown?.call();
                                break;
                              case 'archive':
                                onArchive?.call();
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'duplicate',
                              enabled: onDuplicate != null,
                              child: Text(context.text('duplicatePhase')),
                            ),
                            PopupMenuItem(
                              value: 'move_up',
                              enabled: onMoveUp != null,
                              child: Text(context.text('movePhaseUp')),
                            ),
                            PopupMenuItem(
                              value: 'move_down',
                              enabled: onMoveDown != null,
                              child: Text(context.text('movePhaseDown')),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'archive',
                              enabled: onArchive != null,
                              child: Text(context.text('archivePhase')),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: (progress.percent / 100).clamp(0.0, 1.0).toDouble(),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _MetricChip(
                    label: context.text('progress'),
                    value: '${progress.percent.round()}%',
                  ),
                  _MetricChip(
                    label: context.text('tasks'),
                    value:
                        '${progress.completedTasks} / ${progress.totalTasks}',
                  ),
                  _MetricChip(
                    label: context.text('focusedTime'),
                    value:
                        '${formatDurationCompact(progress.focusedSeconds)} / '
                        '${formatDurationCompact(progress.focusTargetSeconds)}',
                  ),
                  _MetricChip(
                    label: context.text('forecastFinish'),
                    value: _phaseForecast(phase, summary, context),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                phase.exitEvidence,
                maxLines: prominent ? 3 : 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                '${context.text('nextAction')}: ${_nextAction(phaseTasks, context)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _nextAction(List<TaskItem> tasks, BuildContext context) {
    final next = tasks.where((task) => !task.isCompleted).firstOrNull;
    return next?.title ?? context.text('attachEvidenceOrReview');
  }

  String _phaseForecast(
    RoadmapPhase phase,
    _RoadmapSummary summary,
    BuildContext context,
  ) {
    if (!summary.hasForecastData) {
      return context.text('needsMoreData');
    }
    if (phase.status == 'completed' ||
        phase.phase < (summary.activePhase?.phase ?? 1)) {
      return context.text('completed');
    }
    return summary.activePhaseForecastLabel(context);
  }

  RoadmapStatus _phaseStatus(
    RoadmapPhase phase,
    _RoadmapSummary summary,
    double progress,
  ) {
    if (phase.status == 'completed' || progress >= 100) {
      return RoadmapStatus.completed;
    }
    if (phase.status == 'paused') {
      return RoadmapStatus.paused;
    }
    final isActive = phase.id != null && summary.activePhase?.id != null
        ? phase.id == summary.activePhase?.id
        : phase.phaseOrder == summary.activePhase?.phaseOrder;
    if (!isActive) {
      return RoadmapStatus.notStarted;
    }
    return summary.status;
  }
}

class _PhaseProgressBreakdown {
  const _PhaseProgressBreakdown({
    required this.percent,
    required this.completedTasks,
    required this.totalTasks,
    required this.focusedSeconds,
    required this.focusTargetSeconds,
  });

  final double percent;
  final int completedTasks;
  final int totalTasks;
  final int focusedSeconds;
  final int focusTargetSeconds;

  static _PhaseProgressBreakdown from({
    required RoadmapPhase phase,
    required _RoadmapSummary summary,
    required List<TaskItem> tasks,
    required int activeSeconds,
  }) {
    final completed = tasks.where((task) => task.isCompleted).length;
    final totalWeight = tasks.fold<int>(
      0,
      (sum, task) => sum + task.estimatedMinutes.clamp(1, 1000000),
    );
    final linkedTaskProgress = totalWeight <= 0
        ? _fallbackPhaseProgress(phase, summary)
        : tasks.fold<double>(
                0,
                (sum, task) =>
                    sum +
                    task.estimatedMinutes.clamp(1, 1000000) *
                        (task.progressPercentage.clamp(0, 100) / 100),
              ) /
              totalWeight *
              100;
    final focusTarget = totalWeight * 60;
    final focusedProgress = focusTarget <= 0
        ? linkedTaskProgress
        : (activeSeconds / focusTarget * 100).clamp(0.0, 100.0);
    final percent = tasks.isEmpty
        ? linkedTaskProgress
        : (linkedTaskProgress * 0.7) + (focusedProgress * 0.3);
    return _PhaseProgressBreakdown(
      percent: percent.clamp(0.0, 100.0),
      completedTasks: completed,
      totalTasks: tasks.length,
      focusedSeconds: activeSeconds,
      focusTargetSeconds: focusTarget,
    );
  }

  static double _fallbackPhaseProgress(
    RoadmapPhase phase,
    _RoadmapSummary summary,
  ) {
    if (phase.status == 'completed') return 100;
    if (phase.phase < (summary.activePhase?.phase ?? 1)) return 0;
    if (phase.phase == summary.activePhase?.phase) {
      return summary.overallProgress;
    }
    return 0;
  }
}

class _PhaseDetailsSheet extends StatelessWidget {
  const _PhaseDetailsSheet({
    required this.phase,
    required this.tasks,
    required this.sessions,
    required this.controller,
  });

  final RoadmapPhase phase;
  final List<TaskItem> tasks;
  final List<TrackedSession> sessions;
  final TaskActionController controller;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return DefaultTabController(
          length: 8,
          child: Column(
            children: [
              AppBar(
                automaticallyImplyLeading: false,
                title: Text('Phase ${phase.phase} - ${phase.objective}'),
                actions: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_outlined),
                  ),
                ],
                bottom: TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: context.text('overview')),
                    Tab(text: context.text('milestones')),
                    Tab(text: context.text('tasks')),
                    Tab(text: context.text('time')),
                    Tab(text: context.text('progress')),
                    Tab(text: context.text('resources')),
                    Tab(text: context.text('evidence')),
                    Tab(text: context.text('forecast')),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _TextTab(text: phase.exitEvidence),
                    _TaskListAsMilestones(tasks: tasks, controller: controller),
                    _TaskListAsMilestones(tasks: tasks, controller: controller),
                    _PhaseTimeTab(tasks: tasks, sessions: sessions),
                    _TextTab(text: context.text('progressBasedOnTasks')),
                    _TextTab(text: context.text('resourcesLinkedFromTasks')),
                    _TextTab(text: context.text('evidenceRequiredText')),
                    _TextTab(text: context.text('forecastNeedsMoreData')),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TaskListAsMilestones extends StatelessWidget {
  const _TaskListAsMilestones({required this.tasks, required this.controller});

  final List<TaskItem> tasks;
  final TaskActionController controller;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return Center(child: Text(context.text('noRoadmapTasks')));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final task in tasks)
          ListTile(
            leading: Icon(
              task.isCompleted
                  ? Icons.check_circle_outline
                  : Icons.radio_button_unchecked,
            ),
            title: Text(task.title),
            subtitle: Text('${task.category} - ${task.progressPercentage}%'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      TaskWorkspaceScreen(controller: controller, task: task),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _PhaseTimeTab extends StatelessWidget {
  const _PhaseTimeTab({required this.tasks, required this.sessions});

  final List<TaskItem> tasks;
  final List<TrackedSession> sessions;

  @override
  Widget build(BuildContext context) {
    final taskIds = tasks.map((task) => task.id).toSet();
    final phaseSessions = sessions
        .where((session) => taskIds.contains(session.taskId))
        .toList();
    final total = phaseSessions.fold<int>(
      0,
      (sum, session) => sum + session.activeSeconds,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MetricChip(
          label: context.text('actualFocusedTime'),
          value: formatDurationCompact(total),
        ),
        const SizedBox(height: 12),
        for (final session in phaseSessions)
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(formatDurationCompact(session.activeSeconds)),
            subtitle: Text(
              '${_formatRoadmapDateTime(context, session.startedAt)} - '
              '${context.text('trackingMode_${session.trackingMode.name}')}',
            ),
          ),
        if (phaseSessions.isEmpty) Text(context.text('noRecordedSessions')),
      ],
    );
  }
}

class _TimelineTab extends StatelessWidget {
  const _TimelineTab({required this.phases, required this.summary});

  final List<RoadmapPhase> phases;
  final _RoadmapSummary summary;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (final phase in phases)
          ListTile(
            leading: Icon(
              phase.phase == summary.activePhase?.phase
                  ? Icons.play_circle_outline
                  : Icons.timeline_outlined,
            ),
            title: Text('Phase ${phase.phase}: ${phase.objective}'),
            subtitle: Text(
              '${phase.period} - ${phase.phase == summary.activePhase?.phase ? context.text('activePhase') : context.text('planned')}',
            ),
          ),
      ],
    );
  }
}

class _AnalyticsTab extends StatelessWidget {
  const _AnalyticsTab({required this.summary, required this.sessions});

  final _RoadmapSummary summary;
  final List<TrackedSession> sessions;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _RoadmapSummaryHeader(summary: summary),
        const SizedBox(height: 16),
        Text(
          context.text('timeInvested'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final session in sessions.take(20))
          ListTile(
            leading: const Icon(Icons.access_time_outlined),
            title: Text(formatDurationCompact(session.activeSeconds)),
            subtitle: Text(_formatRoadmapDateTime(context, session.startedAt)),
          ),
      ],
    );
  }
}

class _RecommendationsTab extends StatelessWidget {
  const _RecommendationsTab({required this.summary});

  final _RoadmapSummary summary;

  @override
  Widget build(BuildContext context) {
    final recommendation = !summary.hasForecastData
        ? context.text('roadmapRecommendationNeedData')
        : summary.status == RoadmapStatus.behind
        ? context.text('roadmapRecommendationBehind')
        : context.text('roadmapRecommendationOnTrack');
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.tips_and_updates_outlined),
            title: Text(context.text('recommendations')),
            subtitle: Text(recommendation),
          ),
        ),
      ],
    );
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.summary});

  final _RoadmapSummary summary;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ListTile(
          leading: const Icon(Icons.history_outlined),
          title: Text(context.text('baselinePreserved')),
          subtitle: Text(context.text(summary.interpretationKey)),
        ),
      ],
    );
  }
}

class _NextActionCard extends StatelessWidget {
  const _NextActionCard({required this.task, required this.controller});

  final TaskItem? task;
  final TaskActionController controller;

  @override
  Widget build(BuildContext context) {
    if (task == null) {
      return Card(
        child: ListTile(title: Text(context.text('attachEvidenceOrReview'))),
      );
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.flag_outlined),
        title: Text(task!.title),
        subtitle: Text(task!.category),
        trailing: const Icon(Icons.chevron_right_outlined),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  TaskWorkspaceScreen(controller: controller, task: task!),
            ),
          );
        },
      ),
    );
  }
}

class _TextTab extends StatelessWidget {
  const _TextTab({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(20), children: [Text(text)]);
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      avatar: const Icon(Icons.insights_outlined, size: 16),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final RoadmapStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (status) {
      RoadmapStatus.ahead => (
        Icons.trending_up_outlined,
        context.text('ahead'),
        Colors.green,
      ),
      RoadmapStatus.onTrack => (
        Icons.check_circle_outline,
        context.text('onTrack'),
        Theme.of(context).colorScheme.primary,
      ),
      RoadmapStatus.atRisk => (
        Icons.warning_amber_outlined,
        context.text('atRisk'),
        Colors.orange,
      ),
      RoadmapStatus.behind => (
        Icons.trending_down_outlined,
        context.text('behind'),
        Theme.of(context).colorScheme.error,
      ),
      RoadmapStatus.needsMoreData => (
        Icons.insights_outlined,
        context.text('needsMoreData'),
        Colors.blueGrey,
      ),
      RoadmapStatus.paused => (
        Icons.pause_circle_outline,
        context.text('paused'),
        Colors.grey,
      ),
      RoadmapStatus.notStarted => (
        Icons.radio_button_unchecked,
        context.text('notStarted'),
        Colors.grey,
      ),
      RoadmapStatus.completed => (
        Icons.verified_outlined,
        context.text('completed'),
        Colors.green,
      ),
    };
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: 0.5)),
    );
  }
}

class _EmptyRoadmap extends StatelessWidget {
  const _EmptyRoadmap({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.route_outlined, size: 56),
            const SizedBox(height: 12),
            Text(
              context.text('createRoadmapPrompt'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            AppButton.filled(
              onPressed: onCreate,
              icon: const Icon(Icons.add_outlined),
              label: Text(context.text('createRoadmap')),
            ),
          ],
        ),
      ),
    );
  }
}

enum RoadmapStatus {
  ahead,
  onTrack,
  atRisk,
  behind,
  needsMoreData,
  paused,
  notStarted,
  completed,
}

class _RoadmapSummary {
  const _RoadmapSummary({
    required this.overallProgress,
    required this.plannedByToday,
    required this.actualFocusedSeconds,
    required this.fourWeekHours,
    required this.status,
    required this.interpretationKey,
    required this.hasForecastData,
    required this.todayTasks,
    required this.remainingPomodoros,
    required this.remainingMinutes,
    required this.activeDaysPerWeek,
    required this.daysSinceLastActivity,
    required this.scheduleVarianceDays,
    required this.sessionCount,
    required this.completedTaskCount,
    required this.completedReviewCount,
    this.forecastDate,
    this.activePhaseForecastDate,
    this.productivePeriodKey,
    this.bottleneckTask,
    this.activePhase,
    this.nextTask,
  });

  final double overallProgress;
  final double plannedByToday;
  final int actualFocusedSeconds;
  final double fourWeekHours;
  final RoadmapStatus status;
  final String interpretationKey;
  final bool hasForecastData;
  final List<TaskItem> todayTasks;
  final int remainingPomodoros;
  final int remainingMinutes;
  final double activeDaysPerWeek;
  final int daysSinceLastActivity;
  final int scheduleVarianceDays;
  final int sessionCount;
  final int completedTaskCount;
  final int completedReviewCount;
  final DateTime? forecastDate;
  final DateTime? activePhaseForecastDate;
  final String? productivePeriodKey;
  final TaskItem? bottleneckTask;
  final RoadmapPhase? activePhase;
  final TaskItem? nextTask;

  int get sessionsNeeded => (3 - sessionCount).clamp(0, 3);
  int get tasksNeeded => (2 - completedTaskCount).clamp(0, 2);
  int get reviewsNeeded => (1 - completedReviewCount).clamp(0, 1);

  String get progressVarianceLabel {
    final variance = overallProgress - plannedByToday;
    if (variance.abs() < 1) {
      return 'On schedule';
    }
    return '${variance > 0 ? '+' : ''}${variance.toStringAsFixed(0)} pts';
  }

  String forecastLabel(BuildContext context) {
    final value = forecastDate;
    if (value == null) return context.text('needsMoreData');
    return MaterialLocalizations.of(context).formatMediumDate(value);
  }

  String activePhaseForecastLabel(BuildContext context) {
    final value = activePhaseForecastDate;
    if (value == null) return context.text('needsMoreData');
    return MaterialLocalizations.of(context).formatMediumDate(value);
  }

  static _RoadmapSummary from({
    required RoadmapPlan? roadmap,
    required List<RoadmapPhase> phases,
    required List<TaskItem> tasks,
    required List<TrackedSession> sessions,
  }) {
    final roadmapTasks = List<TaskItem>.of(tasks);
    final completedWeight = roadmapTasks.fold<double>(
      0,
      (sum, task) =>
          sum + task.estimatedMinutes * (task.progressPercentage / 100),
    );
    final totalWeight = roadmapTasks.fold<double>(
      0,
      (sum, task) => sum + task.estimatedMinutes,
    );
    final progress = totalWeight <= 0
        ? 0.0
        : completedWeight / totalWeight * 100;
    final now = DateTime.now();
    final fourWeeksAgo = now.subtract(const Duration(days: 28));
    final focused = sessions.fold<int>(
      0,
      (sum, session) => sum + session.activeSeconds,
    );
    final recent = sessions
        .where((session) => session.startedAt.isAfter(fourWeeksAgo))
        .fold<int>(0, (sum, session) => sum + session.activeSeconds);
    final fourWeekHours = recent / 3600 / 4;
    final planned = _plannedProgress(
      now: now,
      roadmap: roadmap,
      phases: phases,
      tasks: roadmapTasks,
    );
    final active = resolveActivePhase(phases);
    final completedTasks = roadmapTasks.where((task) => task.isCompleted);
    final completedTaskCount = completedTasks.length;
    final completedReviewCount = completedTasks.where((task) {
      final text = '${task.title} ${task.category}'.toLowerCase();
      return text.contains('review') || text.contains('مراجعة');
    }).length;
    final sessionDays = {
      for (final session in sessions)
        DateTime(
          session.startedAt.year,
          session.startedAt.month,
          session.startedAt.day,
        ),
    };
    final hasMeaningfulData =
        roadmapTasks.isNotEmpty &&
        sessions.length >= 3 &&
        completedTaskCount >= 2 &&
        completedReviewCount >= 1 &&
        recent > 0;
    final allCompleted =
        roadmapTasks.isNotEmpty &&
        roadmapTasks.every((task) => task.isCompleted);
    final variance = progress - planned;
    final status = allCompleted
        ? RoadmapStatus.completed
        : roadmap?.status == 'paused'
        ? RoadmapStatus.paused
        : !hasMeaningfulData
        ? RoadmapStatus.needsMoreData
        : variance >= 5
        ? RoadmapStatus.ahead
        : variance <= -10
        ? RoadmapStatus.behind
        : variance <= -4
        ? RoadmapStatus.atRisk
        : RoadmapStatus.onTrack;
    final activeTasks = active == null
        ? const <TaskItem>[]
        : roadmapTasks
              .where((task) => _taskBelongsToPhase(task, active))
              .where((task) => !task.isCompleted)
              .toList(growable: false);
    activeTasks.sort(_compareNextTasks);
    final incomplete = roadmapTasks.where((task) => !task.isCompleted).toList()
      ..sort(_compareNextTasks);
    final next = activeTasks.firstOrNull ?? incomplete.firstOrNull;
    final todayTasks = roadmapTasks.where((task) => task.isDueToday).toList()
      ..sort(_compareNextTasks);
    final remainingMinutes = incomplete.fold<int>(0, (sum, task) {
      final fraction = (100 - task.progressPercentage).clamp(0, 100) / 100;
      return sum + (task.estimatedMinutes * fraction).round();
    });
    final activeRemainingMinutes = activeTasks.fold<int>(0, (sum, task) {
      final fraction = (100 - task.progressPercentage).clamp(0, 100) / 100;
      return sum + (task.estimatedMinutes * fraction).round();
    });
    final plannedPomodoros = incomplete.fold<int>(
      0,
      (sum, task) => sum + task.estimatedPomodoros,
    );
    final completedPomodoros = sessions.fold<int>(
      0,
      (sum, session) => sum + session.pomodorosCompleted,
    );
    final remainingPomodoros = (plannedPomodoros - completedPomodoros).clamp(
      0,
      plannedPomodoros,
    );
    final recentWeeklySeconds = recent / 4;
    final forecastDate = hasMeaningfulData && recentWeeklySeconds > 0
        ? now.add(
            Duration(
              days: ((remainingMinutes * 60 / recentWeeklySeconds) * 7).ceil(),
            ),
          )
        : null;
    final activePhaseForecastDate =
        hasMeaningfulData &&
            recentWeeklySeconds > 0 &&
            activeRemainingMinutes > 0
        ? now.add(
            Duration(
              days: ((activeRemainingMinutes * 60 / recentWeeklySeconds) * 7)
                  .ceil(),
            ),
          )
        : active?.isCompleted == true
        ? active?.plannedFinish
        : null;
    final target = roadmap?.currentTargetDate ?? roadmap?.originalTargetDate;
    final totalPlanDays = target == null
        ? _phasePlanDuration(phases)
        : target.difference(roadmap!.startDate).inDays.abs();
    final scheduleVarianceDays = (variance / 100 * totalPlanDays.clamp(1, 3650))
        .round();
    final lastSession = sessions.isEmpty
        ? null
        : (List<TrackedSession>.of(
            sessions,
          )..sort((a, b) => b.startedAt.compareTo(a.startedAt))).first;
    final daysSinceLastActivity = lastSession == null
        ? 0
        : now.difference(lastSession.startedAt).inDays.clamp(0, 36500);
    final activeDaysPerWeek = sessionDays.length / 4;
    final productivePeriodKey = sessions.length < 3
        ? null
        : _productivePeriodKey(sessions);
    final overdue = incomplete.where((task) => task.isOverdue).toList()
      ..sort(_compareNextTasks);
    final bottleneckTask =
        overdue.firstOrNull ??
        (incomplete.isEmpty
            ? null
            : (List<TaskItem>.of(incomplete)..sort(
                    (a, b) =>
                        (b.estimatedMinutes * (100 - b.progressPercentage))
                            .compareTo(
                              a.estimatedMinutes * (100 - a.progressPercentage),
                            ),
                  ))
                  .first);
    return _RoadmapSummary(
      overallProgress: progress,
      plannedByToday: planned,
      actualFocusedSeconds: focused,
      fourWeekHours: fourWeekHours,
      status: status,
      activePhase: active,
      nextTask: next,
      forecastDate: forecastDate,
      activePhaseForecastDate: activePhaseForecastDate,
      interpretationKey: hasMeaningfulData
          ? 'forecastUsesStoredActivity'
          : 'forecastNeedsMoreActivity',
      hasForecastData: hasMeaningfulData,
      todayTasks: todayTasks,
      remainingPomodoros: remainingPomodoros,
      remainingMinutes: remainingMinutes,
      activeDaysPerWeek: activeDaysPerWeek,
      daysSinceLastActivity: daysSinceLastActivity,
      scheduleVarianceDays: scheduleVarianceDays,
      sessionCount: sessions.length,
      completedTaskCount: completedTaskCount,
      completedReviewCount: completedReviewCount,
      productivePeriodKey: productivePeriodKey,
      bottleneckTask: bottleneckTask,
    );
  }

  static double _plannedProgress({
    required DateTime now,
    required RoadmapPlan? roadmap,
    required List<RoadmapPhase> phases,
    required List<TaskItem> tasks,
  }) {
    final scheduled = tasks.where(
      (task) => task.displayStart != null || task.effectiveDue != null,
    );
    final scheduledWeight = scheduled.fold<int>(
      0,
      (sum, task) => sum + task.estimatedMinutes,
    );
    final totalWeight = tasks.fold<int>(
      0,
      (sum, task) => sum + task.estimatedMinutes,
    );
    if (totalWeight > 0 && scheduledWeight >= totalWeight * 0.5) {
      final expected = tasks.fold<double>(0, (sum, task) {
        final start = task.displayStart;
        final end = task.effectiveDue ?? task.displayEnd ?? start;
        var plannedFraction = 0.0;
        if (end != null && !end.isAfter(now)) {
          plannedFraction = 1;
        } else if (start != null && !start.isAfter(now)) {
          if (end != null && end.isAfter(start)) {
            plannedFraction =
                (now.difference(start).inSeconds /
                        end.difference(start).inSeconds)
                    .clamp(0.0, 1.0);
          } else {
            plannedFraction = 1;
          }
        }
        return sum + task.estimatedMinutes * plannedFraction;
      });
      return expected / totalWeight * 100;
    }
    final start =
        roadmap?.startDate ??
        phases
            .map((phase) => phase.plannedStart)
            .whereType<DateTime>()
            .firstOrNull;
    final end =
        roadmap?.currentTargetDate ??
        roadmap?.originalTargetDate ??
        phases
            .map((phase) => phase.plannedFinish)
            .whereType<DateTime>()
            .lastOrNull;
    if (start == null || end == null || !end.isAfter(start)) {
      return 0;
    }
    if (now.isBefore(start)) return 0;
    if (now.isAfter(end)) return 100;
    return now.difference(start).inDays / end.difference(start).inDays * 100;
  }

  static int _phasePlanDuration(List<RoadmapPhase> phases) {
    final starts =
        phases.map((phase) => phase.plannedStart).whereType<DateTime>().toList()
          ..sort();
    final finishes =
        phases
            .map((phase) => phase.plannedFinish)
            .whereType<DateTime>()
            .toList()
          ..sort();
    if (starts.isEmpty || finishes.isEmpty) return 365;
    return finishes.last.difference(starts.first).inDays.abs().clamp(1, 3650);
  }

  static String _productivePeriodKey(List<TrackedSession> sessions) {
    final totals = <String, int>{
      'productiveMorning': 0,
      'productiveAfternoon': 0,
      'productiveEvening': 0,
    };
    for (final session in sessions) {
      final hour = session.startedAt.toLocal().hour;
      final key = hour < 12
          ? 'productiveMorning'
          : hour < 18
          ? 'productiveAfternoon'
          : 'productiveEvening';
      totals[key] = totals[key]! + session.activeSeconds;
    }
    return totals.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}

int _compareNextTasks(TaskItem a, TaskItem b) {
  if (a.isOverdue != b.isOverdue) return a.isOverdue ? -1 : 1;
  final aDate = a.displayStart ?? a.effectiveDue;
  final bDate = b.displayStart ?? b.effectiveDue;
  if (aDate != null && bDate != null) {
    final compared = aDate.compareTo(bDate);
    if (compared != 0) return compared;
  } else if (aDate != null) {
    return -1;
  } else if (bDate != null) {
    return 1;
  }
  return a.priority.rank.compareTo(b.priority.rank);
}

RoadmapPhase? resolveActivePhase(List<RoadmapPhase> phases) {
  if (phases.isEmpty) {
    return null;
  }
  final ordered = List<RoadmapPhase>.of(phases)
    ..sort((a, b) => a.phaseOrder.compareTo(b.phaseOrder));
  final explicit = ordered
      .where((phase) => phase.isExplicitlyActive || phase.status == 'active')
      .firstOrNull;
  if (explicit != null) {
    return explicit;
  }
  final today = DateTime.now();
  final current = ordered.where((phase) {
    final start = phase.plannedStart;
    final finish = phase.plannedFinish;
    return !phase.isCompleted &&
        start != null &&
        finish != null &&
        !today.isBefore(start) &&
        !today.isAfter(finish.add(const Duration(days: 1)));
  }).firstOrNull;
  if (current != null) {
    return current;
  }
  final startedIncomplete = ordered
      .where(
        (phase) =>
            !phase.isCompleted &&
            phase.plannedStart != null &&
            !phase.plannedStart!.isAfter(today),
      )
      .firstOrNull;
  if (startedIncomplete != null) {
    return startedIncomplete;
  }
  final firstIncomplete = ordered
      .where((phase) => !phase.isCompleted)
      .firstOrNull;
  return firstIncomplete ?? ordered.last;
}

bool _taskBelongsToPhase(TaskItem task, RoadmapPhase phase) {
  final phaseId = phase.id;
  if (phaseId != null && phaseId.isNotEmpty) {
    return task.roadmapPhaseId == phaseId;
  }
  if (task.roadmapPhaseId != null && task.roadmapPhaseId!.isNotEmpty) {
    return false;
  }
  return task.roadmapPhase == phase.phase;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }

  T? get lastOrNull {
    T? result;
    for (final item in this) {
      result = item;
    }
    return result;
  }
}
