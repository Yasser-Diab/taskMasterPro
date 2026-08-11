-- Cover roadmap hierarchy foreign keys used by task linking and progress reads.
-- These indexes are additive and preserve all existing roadmap relationships.

create index if not exists roadmap_checkpoints_milestone_fk_idx
  on public.roadmap_checkpoints (milestone_id)
  where milestone_id is not null;

create index if not exists roadmap_task_links_roadmap_fk_idx
  on public.roadmap_task_links (roadmap_id);

create index if not exists roadmap_task_links_phase_fk_idx
  on public.roadmap_task_links (phase_id)
  where phase_id is not null;

create index if not exists roadmap_task_links_milestone_fk_idx
  on public.roadmap_task_links (milestone_id)
  where milestone_id is not null;

create index if not exists roadmap_task_links_checkpoint_fk_idx
  on public.roadmap_task_links (checkpoint_id)
  where checkpoint_id is not null;

create index if not exists roadmap_task_links_task_fk_idx
  on public.roadmap_task_links (task_id);
