import 'package:uuid/uuid.dart';

import '../../../core/config/supabase_service.dart';
import '../domain/roadmap_phase.dart';
import '../domain/roadmap_plan.dart';

class RoadmapRepository {
  RoadmapRepository(this._supabaseService);

  final SupabaseService _supabaseService;

  String? get currentUserId => _supabaseService.currentUser?.id;

  Future<List<RoadmapPlan>> loadRoadmaps() async {
    final client = _supabaseService.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return const [];
    }

    try {
      final rows = await client
          .from('roadmaps')
          .select()
          .eq('user_id', user.id)
          .isFilter('deleted_at', null)
          .order('updated_at', ascending: false);
      return rows.map<RoadmapPlan>((row) => RoadmapPlan.fromMap(row)).toList();
    } on Object {
      return const [];
    }
  }

  Future<List<RoadmapPhase>> loadPhases(String roadmapId) async {
    final client = _supabaseService.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      return const [];
    }

    try {
      final rows = await client
          .from('roadmap_phases')
          .select()
          .eq('user_id', user.id)
          .eq('roadmap_id', roadmapId)
          .isFilter('deleted_at', null)
          .order('phase_order', ascending: true);
      final phases = rows
          .map<RoadmapPhase>((row) => RoadmapPhase.fromMap(row))
          .toList();
      phases.sort((a, b) => a.phaseOrder.compareTo(b.phaseOrder));
      return phases;
    } on Object {
      return const [];
    }
  }

  Future<RoadmapPlan> createRoadmap(RoadmapPlan roadmap) async {
    final client = _supabaseService.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError('You need to sign in before creating a roadmap.');
    }

    final row = await client
        .from('roadmaps')
        .insert(roadmap.toInsertMap())
        .select()
        .single();
    return RoadmapPlan.fromMap(row);
  }

  Future<RoadmapPhase> addPhase(RoadmapPhase phase) async {
    final client = _supabaseService.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null) {
      throw StateError('You need to sign in before adding a phase.');
    }

    final row = await client
        .from('roadmap_phases')
        .insert(phase.toInsertMap(userId: user.id))
        .select()
        .single();
    return RoadmapPhase.fromMap(row);
  }

  Future<RoadmapPhase> updatePhase(RoadmapPhase phase) async {
    final client = _supabaseService.clientOrNull;
    final user = client?.auth.currentUser;
    if (client == null || user == null || phase.id == null) {
      throw StateError('You need to sign in before editing a phase.');
    }

    final values = phase.toInsertMap(userId: user.id)
      ..remove('id')
      ..remove('user_id')
      ..remove('roadmap_id');
    final row = await client
        .from('roadmap_phases')
        .update(values)
        .eq('id', phase.id!)
        .eq('user_id', user.id)
        .select()
        .single();
    return RoadmapPhase.fromMap(row);
  }

  Future<void> reorderPhases(List<RoadmapPhase> phases) async {
    for (var index = 0; index < phases.length; index += 1) {
      await updatePhase(
        phases[index].copyWith(phase: index + 1, phaseOrder: index + 1),
      );
    }
  }

  Future<RoadmapPhase> duplicatePhase(RoadmapPhase phase) {
    final copy = phase.copyWith(
      id: const Uuid().v4(),
      phase: phase.phase + 1,
      phaseOrder: phase.phaseOrder + 1,
      objective: '${phase.objective} (copy)',
      status: 'not_started',
      plannedProgress: 0,
      actualHours: 0,
      clearNextAction: true,
    );
    return addPhase(copy);
  }

  Future<RoadmapPhase> archivePhase(RoadmapPhase phase) {
    return updatePhase(phase.copyWith(status: 'archived'));
  }
}
