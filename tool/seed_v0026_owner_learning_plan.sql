-- Idempotent production-data installation for DayVector v0.0.26.
--
-- Run only against the linked DayVector project. Ownership is bound to
-- the authenticated Supabase user UUID supplied by the release owner, never
-- inferred from email. This is operational seed data, not a schema migration.

do $seed$
#variable_conflict use_variable
declare
  owner_id constant uuid := '4bd3e32d-1dcd-48ed-9f64-9099675047f1';
  plan_start constant date := date '2026-07-28';
  plans constant jsonb := $plans$
  [
    {
      "title": "Full-Stack Development",
      "description": "A production-oriented path from a verified development baseline through full-stack delivery, portfolio work, interviews, and employment.",
      "outcome": "Job-ready full-stack portfolio completed",
      "target_days": 602,
      "required_effort_hours": 1500,
      "phases": [
        {
          "title": "Phase 0 — Environment and Baseline",
          "duration": "1 week",
          "days": 7,
          "milestone": "Development environment ready",
          "checkpoints": [
            "VS Code, Node.js LTS, Git, and browser tools verified",
            "Learning repository created",
            "Responsive page rebuilt without tutorial guidance"
          ],
          "tasks": [
            {"title":"Verify Visual Studio Code","minutes":45,"mode":"checklist","url":"https://code.visualstudio.com/docs"},
            {"title":"Verify Node.js LTS","minutes":45,"mode":"checklist","url":"https://nodejs.org/en/download"},
            {"title":"Verify Git and GitHub","minutes":60,"mode":"checklist","url":"https://docs.github.com/en/get-started/start-your-journey"},
            {"title":"Create learning journal and error log","minutes":60,"mode":"continuous","url":"https://docs.github.com/en/repositories/creating-and-managing-repositories/quickstart-for-repositories"},
            {"title":"Rebuild one responsive page independently","minutes":180,"mode":"pomodoro","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/Core/CSS_layout/Responsive_Design"}
          ]
        },
        {
          "title": "Phase 1 — JavaScript Fundamentals",
          "duration": "10 weeks",
          "days": 70,
          "milestone": "JavaScript fundamentals completed",
          "checkpoints": [
            "Functions, scope, closures, callbacks",
            "DOM and event handling",
            "Promises, Fetch, and async/await",
            "JavaScript certification projects completed"
          ],
          "tasks": [
            {"title":"Finish Spam Filter","minutes":180,"mode":"pomodoro","url":"https://www.freecodecamp.org/learn/javascript-algorithms-and-data-structures-v8/"},
            {"title":"Build palindrome checker","minutes":120,"mode":"pomodoro","url":"https://www.freecodecamp.org/learn/javascript-algorithms-and-data-structures-v8/"},
            {"title":"Build expense tracker","minutes":300,"mode":"pomodoro","url":"https://www.freecodecamp.org/learn/javascript-algorithms-and-data-structures-v8/"},
            {"title":"Build searchable list","minutes":180,"mode":"pomodoro","url":"https://developer.mozilla.org/en-US/docs/Web/API/Document_Object_Model"},
            {"title":"Build quiz application","minutes":300,"mode":"pomodoro","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/Core/Scripting/Events"},
            {"title":"Build local-storage task manager","minutes":420,"mode":"pomodoro","url":"https://developer.mozilla.org/en-US/docs/Web/API/Window/localStorage"}
          ]
        },
        {
          "title": "Phase 2 — Professional Front-End Foundations",
          "duration": "10 weeks",
          "days": 70,
          "milestone": "Professional responsive front-end portfolio completed",
          "checkpoints": [
            "Accessibility and semantic HTML",
            "Responsive Grid and Flexbox",
            "APIs and browser tools",
            "Git branches and deployment"
          ],
          "tasks": [
            {"title":"Corporate website","minutes":600,"mode":"pomodoro","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development"},
            {"title":"Administrative dashboard","minutes":720,"mode":"pomodoro","url":"https://developer.mozilla.org/en-US/docs/Learn_web_development/Core/CSS_layout"},
            {"title":"Product catalogue","minutes":600,"mode":"pomodoro","url":"https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API"},
            {"title":"Accessible registration interface","minutes":360,"mode":"pomodoro","url":"https://www.w3.org/WAI/tutorials/forms/"},
            {"title":"Modern rebuild of one Hsoub project","minutes":720,"mode":"pomodoro","url":"https://academy.hsoub.com/"}
          ]
        },
        {
          "title": "Phase 3 — React and TypeScript",
          "duration": "14 weeks",
          "days": 98,
          "milestone": "Production-style typed React application completed",
          "checkpoints": [
            "Components, state, forms, routing",
            "TypeScript types and API models",
            "Testing and error handling"
          ],
          "tasks": [
            {"title":"React expense manager","minutes":720,"mode":"pomodoro","url":"https://react.dev/learn"},
            {"title":"Typed dashboard","minutes":720,"mode":"pomodoro","url":"https://www.typescriptlang.org/docs/"},
            {"title":"Product-management interface","minutes":900,"mode":"pomodoro","url":"https://react.dev/learn"},
            {"title":"DayVector front-end prototype","minutes":900,"mode":"pomodoro","url":"https://react.dev/learn/thinking-in-react"},
            {"title":"REST API client application","minutes":600,"mode":"pomodoro","url":"https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API"}
          ]
        },
        {
          "title": "Phase 4 — Back-End JavaScript and APIs",
          "duration": "12 weeks",
          "days": 84,
          "milestone": "Secure tested backend API completed",
          "checkpoints": [
            "Express routing and middleware",
            "Authentication and authorization",
            "Validation and error handling",
            "API test coverage"
          ],
          "tasks": [
            {"title":"Notes API","minutes":480,"mode":"pomodoro","url":"https://expressjs.com/en/starter/installing.html"},
            {"title":"Authentication API","minutes":720,"mode":"pomodoro","url":"https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html"},
            {"title":"Task and roadmap API","minutes":900,"mode":"pomodoro","url":"https://expressjs.com/en/guide/routing.html"},
            {"title":"File-upload service","minutes":480,"mode":"pomodoro","url":"https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html"},
            {"title":"API test suite","minutes":600,"mode":"pomodoro","url":"https://nodejs.org/api/test.html"}
          ]
        },
        {
          "title": "Phase 5 — SQL and Database Engineering",
          "duration": "8 weeks",
          "days": 56,
          "milestone": "DayVector relational database designed",
          "checkpoints": [
            "Relationships and normalization",
            "Joins, indexes, and transactions",
            "Migrations and constraints",
            "RLS and access control"
          ],
          "tasks": [
            {"title":"Create entity-relationship diagram","minutes":300,"mode":"continuous","url":"https://www.postgresql.org/docs/current/ddl.html"},
            {"title":"Design user and profile tables","minutes":240,"mode":"pomodoro","url":"https://www.postgresql.org/docs/current/ddl-constraints.html"},
            {"title":"Design task/session tables","minutes":360,"mode":"pomodoro","url":"https://www.postgresql.org/docs/current/ddl-constraints.html"},
            {"title":"Design roadmap tables","minutes":300,"mode":"pomodoro","url":"https://www.postgresql.org/docs/current/ddl.html"},
            {"title":"Design Activity and notification tables","minutes":360,"mode":"pomodoro","url":"https://www.postgresql.org/docs/current/datatype.html"},
            {"title":"Add migrations and indexes","minutes":480,"mode":"pomodoro","url":"https://supabase.com/docs/guides/database/postgres/row-level-security"}
          ]
        },
        {
          "title": "Phase 6 — Full-Stack Integration",
          "duration": "14 weeks",
          "days": 98,
          "milestone": "DayVector full-stack MVP completed",
          "checkpoints": [
            "Authentication and profile",
            "Tasks and roadmaps",
            "Pomodoro and time tracking",
            "Reports and responsive interface",
            "Tested deployment pipeline"
          ],
          "tasks": []
        },
        {
          "title": "Phase 7 — Portfolio, Interviews, and Employment",
          "duration": "14–20 weeks",
          "days": 119,
          "milestone": "Job-ready full-stack portfolio completed",
          "checkpoints": [
            "Three strong portfolio projects",
            "Technical interview preparation",
            "Professional profile and applications",
            "Open-source contribution"
          ],
          "tasks": []
        }
      ]
    },
    {
      "title": "German to Professional Fluency",
      "description": "A staged German plan from placement and pronunciation through professional fluency and near-native refinement.",
      "outcome": "Advanced natural German communication",
      "target_days": 1825,
      "required_effort_hours": 1200,
      "phases": [
        {
          "title": "Phase G0 — Placement and Pronunciation",
          "duration": "2 weeks",
          "days": 14,
          "milestone": "Starting German level confirmed",
          "checkpoints": [],
          "tasks": [
            {"title":"Complete Goethe placement test","minutes":60,"mode":"continuous","url":"https://www.goethe.de/en/spr/kup/tsd.html"},
            {"title":"Study German sound system","minutes":120,"mode":"continuous","url":"https://learngerman.dw.com/en/pronunciation/l-37780374"},
            {"title":"Record one-minute introduction","minutes":30,"mode":"continuous","url":"https://learngerman.dw.com/en/nicos-weg/c-36519789"},
            {"title":"Set initial A1 targets","minutes":45,"mode":"checklist","url":"https://www.goethe.de/en/spr/kup/prf/prf/sd1.html"}
          ]
        },
        {
          "title": "Phase G1 — A1 Foundation",
          "duration": "Months 1–4",
          "days": 120,
          "milestone": "A1 foundation completed",
          "checkpoints": [
            "Introduce yourself and family",
            "Describe work and daily routine",
            "Arrange simple appointments",
            "Speak for 3–5 minutes"
          ],
          "tasks": [
            {"title":"Nicos Weg A1 sessions","minutes":1800,"mode":"continuous","url":"https://learngerman.dw.com/en/nicos-weg/c-36519789"},
            {"title":"Duolingo 10 minutes daily","minutes":1200,"mode":"habit","url":"https://www.duolingo.com/learn"},
            {"title":"Goethe A1 exercises","minutes":1200,"mode":"continuous","url":"https://www.goethe.de/en/spr/kup/prf/prf/sd1/ueb.html"},
            {"title":"Pronunciation practice","minutes":900,"mode":"habit","url":"https://learngerman.dw.com/en/pronunciation/l-37780374"},
            {"title":"Weekly speaking session","minutes":960,"mode":"continuous","url":"https://www.goethe.de/en/spr/ueb.html"}
          ]
        },
        {
          "title": "Phase G2 — A2 Functional Conversation",
          "duration": "Months 5–8",
          "days": 122,
          "milestone": "A2 functional conversation reached",
          "checkpoints": [
            "Ten-minute conversation",
            "Describe past and future plans",
            "Handle travel and appointments",
            "Explain programming study simply"
          ],
          "tasks": [
            {"title":"Nicos Weg A2","minutes":1800,"mode":"continuous","url":"https://learngerman.dw.com/en/nicos-weg/c-36519797"},
            {"title":"Easy German beginner videos","minutes":1200,"mode":"continuous","url":"https://www.easygerman.org/"},
            {"title":"Weekly 30–45-minute conversation","minutes":1440,"mode":"continuous","url":"https://www.goethe.de/en/spr/ueb.html"},
            {"title":"Two short texts weekly","minutes":1440,"mode":"continuous","url":"https://www.goethe.de/en/spr/ueb.html"},
            {"title":"Correction notebook","minutes":900,"mode":"continuous","url":"https://www.goethe.de/en/spr/ueb.html"}
          ]
        },
        {
          "title": "Phase G3 — B1 Conversational Independence",
          "duration": "Months 9–14",
          "days": 183,
          "milestone": "B1 conversational independence reached",
          "checkpoints": [
            "15–20-minute conversation",
            "Explain a programming project",
            "Give reasons and opinions",
            "Understand standard German"
          ],
          "tasks": []
        },
        {
          "title": "Phase G4 — B2 Professional Fluency",
          "duration": "Months 15–24",
          "days": 304,
          "milestone": "B2 professional communication reached",
          "checkpoints": [
            "Participate in meetings",
            "Explain technical problems",
            "Give project presentations",
            "Write professional emails"
          ],
          "tasks": []
        },
        {
          "title": "Phase G5 — C1 Advanced Professional Fluency",
          "duration": "Months 25–42",
          "days": 548,
          "milestone": "C1 professional fluency reached",
          "checkpoints": [
            "Work in German",
            "Handle technical interviews",
            "Explain architecture decisions",
            "Write formal documentation"
          ],
          "tasks": []
        },
        {
          "title": "Phase G6 — C2 and Near-Native Refinement",
          "duration": "Months 43–60+",
          "days": 548,
          "milestone": "Advanced natural German communication",
          "checkpoints": [
            "Understand unscripted discussions",
            "Use idiomatic expression",
            "Speak on unfamiliar subjects",
            "Write advanced analytical texts"
          ],
          "tasks": []
        }
      ]
    }
  ]
  $plans$::jsonb;
  schedules constant jsonb := $schedules$
  [
    {"key":"german_structured_sat_thu","title":"German structured lesson","resource_name":"DW Nicos Weg A1","roadmap":"German to Professional Fluency","phase":"Phase G1 — A1 Foundation","frequency":"weekly","weekdays":[1,2,3,4,6,7],"time":"06:30","minutes":40,"mode":"continuous","reminder":10,"url":"https://learngerman.dw.com/en/nicos-weg/c-36519789"},
    {"key":"programming_sat_hsoub","title":"Hsoub Academy","resource_name":"Hsoub Academy","roadmap":"Full-Stack Development","phase":"Phase 2 — Professional Front-End Foundations","frequency":"weekly","weekdays":[6],"time":"19:30","minutes":90,"mode":"pomodoro","reminder":10,"url":"https://academy.hsoub.com/"},
    {"key":"programming_sun_fcc","title":"freeCodeCamp","resource_name":"freeCodeCamp JavaScript curriculum","roadmap":"Full-Stack Development","phase":"Phase 1 — JavaScript Fundamentals","frequency":"weekly","weekdays":[7],"time":"19:30","minutes":90,"mode":"pomodoro","reminder":10,"url":"https://www.freecodecamp.org/learn/javascript-algorithms-and-data-structures-v8/"},
    {"key":"programming_mon_hsoub","title":"Hsoub Academy","resource_name":"Hsoub Academy","roadmap":"Full-Stack Development","phase":"Phase 2 — Professional Front-End Foundations","frequency":"weekly","weekdays":[1],"time":"19:30","minutes":90,"mode":"pomodoro","reminder":10,"url":"https://academy.hsoub.com/"},
    {"key":"programming_tue_fcc","title":"freeCodeCamp","resource_name":"freeCodeCamp JavaScript curriculum","roadmap":"Full-Stack Development","phase":"Phase 1 — JavaScript Fundamentals","frequency":"weekly","weekdays":[2],"time":"19:30","minutes":90,"mode":"pomodoro","reminder":10,"url":"https://www.freecodecamp.org/learn/javascript-algorithms-and-data-structures-v8/"},
    {"key":"programming_wed_project","title":"Independent programming project","resource_name":"React official learning path","roadmap":"Full-Stack Development","phase":"Phase 3 — React and TypeScript","frequency":"weekly","weekdays":[3],"time":"19:30","minutes":90,"mode":"pomodoro","reminder":10,"url":"https://react.dev/learn"},
    {"key":"german_tue_shadowing","title":"German shadowing","resource_name":"DW German pronunciation","roadmap":"German to Professional Fluency","phase":"Phase G0 — Placement and Pronunciation","frequency":"weekly","weekdays":[2],"time":"21:10","minutes":25,"mode":"continuous","reminder":5,"url":"https://learngerman.dw.com/en/pronunciation/l-37780374"},
    {"key":"german_thu_listening","title":"German listening and shadowing","resource_name":"DW Nicos Weg A1","roadmap":"German to Professional Fluency","phase":"Phase G1 — A1 Foundation","frequency":"weekly","weekdays":[4],"time":"21:10","minutes":25,"mode":"continuous","reminder":5,"url":"https://learngerman.dw.com/en/nicos-weg/c-36519789"},
    {"key":"german_daily_duolingo","title":"Duolingo — 10 minutes","resource_name":"Duolingo German","roadmap":"German to Professional Fluency","phase":"Phase G1 — A1 Foundation","frequency":"daily","weekdays":[],"time":"07:15","minutes":10,"mode":"habit","reminder":5,"url":"https://www.duolingo.com/learn"},
    {"key":"programming_fri_main","title":"Main programming project","resource_name":"React official learning path","roadmap":"Full-Stack Development","phase":"Phase 3 — React and TypeScript","frequency":"weekly","weekdays":[5],"time":"08:00","minutes":120,"mode":"pomodoro","reminder":15,"url":"https://react.dev/learn"},
    {"key":"programming_fri_review","title":"freeCodeCamp, Hsoub review, or technical documentation","resource_name":"MDN Web Development","roadmap":"Full-Stack Development","phase":"Phase 2 — Professional Front-End Foundations","frequency":"weekly","weekdays":[5],"time":"10:30","minutes":120,"mode":"pomodoro","reminder":10,"url":"https://developer.mozilla.org/en-US/docs/Learn_web_development","additional_resources":[{"name":"freeCodeCamp JavaScript curriculum","url":"https://www.freecodecamp.org/learn/javascript-algorithms-and-data-structures-v8/"},{"name":"Hsoub Academy","url":"https://academy.hsoub.com/"}]},
    {"key":"german_fri_structured","title":"German structured study","resource_name":"DW Nicos Weg A1","roadmap":"German to Professional Fluency","phase":"Phase G1 — A1 Foundation","frequency":"weekly","weekdays":[5],"time":"16:00","minutes":75,"mode":"continuous","reminder":10,"url":"https://learngerman.dw.com/en/nicos-weg/c-36519789"},
    {"key":"german_fri_speaking","title":"German speaking session","resource_name":"Goethe-Institut German practice","roadmap":"German to Professional Fluency","phase":"Phase G1 — A1 Foundation","frequency":"weekly","weekdays":[5],"time":"18:00","minutes":45,"mode":"continuous","reminder":10,"url":"https://www.goethe.de/en/spr/ueb.html"}
  ]
  $schedules$::jsonb;
  roadmap_plan jsonb;
  phase_plan jsonb;
  task_plan jsonb;
  schedule_plan jsonb;
  additional_resource jsonb;
  checkpoint_title text;
  roadmap_id uuid;
  phase_id uuid;
  milestone_id uuid;
  checkpoint_id uuid;
  task_id uuid;
  template_id uuid;
  rule_id uuid;
  resource_id uuid;
  reminder_id uuid;
  link_id uuid;
  phase_start date;
  phase_finish date;
  task_date date;
  first_date date;
  planned_start_at timestamptz;
  planned_end_at timestamptz;
  phase_index integer;
  task_index integer;
  task_count integer;
  duration_days integer;
  duration_minutes integer;
  reminder_minutes integer;
  weekday_values integer[];
  roadmap_phase_title text;
begin
  if not exists (
    select 1 from auth.users account where account.id = owner_id
  ) then
    raise exception 'Configured DayVector owner UUID does not exist';
  end if;

  for roadmap_plan in
    select value from jsonb_array_elements(plans)
  loop
    select roadmap.id
    into roadmap_id
    from public.roadmaps roadmap
    where roadmap.user_id = owner_id
      and roadmap.title = roadmap_plan ->> 'title'
      and roadmap.deleted_at is null
    order by roadmap.created_at
    limit 1;

    if roadmap_id is null then
      roadmap_id := gen_random_uuid();
      insert into public.roadmaps (
        id, user_id, title, description, status, planned_start,
        original_target_date, forecast_target_date, final_outcome,
        required_effort_ms, data
      ) values (
        roadmap_id,
        owner_id,
        roadmap_plan ->> 'title',
        roadmap_plan ->> 'description',
        'active',
        plan_start,
        plan_start + ((roadmap_plan ->> 'target_days')::integer),
        plan_start + ((roadmap_plan ->> 'target_days')::integer),
        roadmap_plan ->> 'outcome',
        (roadmap_plan ->> 'required_effort_hours')::bigint * 3600000,
        jsonb_build_object(
          'installed_release', '0.0.26',
          'owner_uuid_bound', true,
          'source', 'owner_learning_plan'
        )
      );
    end if;

    for checkpoint_title in
      select value
      from jsonb_array_elements_text(
        '["active_work_seconds","practice_seconds","reading_time","research_time"]'::jsonb
      )
    loop
      if not exists (
        select 1
        from public.roadmap_progress_rules rule_row
        where rule_row.user_id = owner_id
          and rule_row.roadmap_id = roadmap_id
          and rule_row.contribution_type = checkpoint_title
          and rule_row.deleted_at is null
      ) then
        insert into public.roadmap_progress_rules (
          id, user_id, roadmap_id, roadmap_phase_id, contribution_type,
          weight, automatic_credit_allowed, rule_config, data
        ) values (
          gen_random_uuid(), owner_id, roadmap_id, null, checkpoint_title,
          1, false,
          '{"requires_approved_attribution":true,"source":"owner_learning_plan"}'::jsonb,
          '{"installed_release":"0.0.26"}'::jsonb
        );
      end if;
    end loop;

    phase_start := plan_start;
    phase_index := 0;
    for phase_plan in
      select value from jsonb_array_elements(roadmap_plan -> 'phases')
    loop
      duration_days := (phase_plan ->> 'days')::integer;
      phase_finish := phase_start + duration_days - 1;

      select phase.id
      into phase_id
      from public.roadmap_phases phase
      where phase.user_id = owner_id
        and phase.roadmap_id = roadmap_id
        and phase.title = phase_plan ->> 'title'
        and phase.deleted_at is null
      order by phase.created_at
      limit 1;

      if phase_id is null then
        phase_id := gen_random_uuid();
        insert into public.roadmap_phases (
          id, user_id, roadmap_id, title, description, position,
          planned_start, planned_finish, forecast_finish,
          required_effort_ms, status, risk_level, completion_rules, data
        ) values (
          phase_id,
          owner_id,
          roadmap_id,
          phase_plan ->> 'title',
          'Duration: ' || (phase_plan ->> 'duration'),
          phase_index,
          phase_start,
          phase_finish,
          phase_finish,
          null,
          'planned',
          'low',
          '["all_required_tasks","all_required_checkpoints"]'::jsonb,
          jsonb_build_object(
            'duration_label', phase_plan ->> 'duration',
            'duration_days', duration_days,
            'installed_release', '0.0.26'
          )
        );
      end if;

      select milestone.id
      into milestone_id
      from public.roadmap_milestones milestone
      where milestone.user_id = owner_id
        and milestone.roadmap_id = roadmap_id
        and milestone.phase_id = phase_id
        and milestone.title = phase_plan ->> 'milestone'
        and milestone.deleted_at is null
      order by milestone.created_at
      limit 1;

      if milestone_id is null then
        milestone_id := gen_random_uuid();
        insert into public.roadmap_milestones (
          id, user_id, roadmap_id, phase_id, title, description,
          target_date, position, weight, status, data
        ) values (
          milestone_id,
          owner_id,
          roadmap_id,
          phase_id,
          phase_plan ->> 'milestone',
          'Review the phase tasks and checkpoints before completion.',
          phase_finish,
          phase_index,
          1,
          'not_started',
          '{"completion_rule":"all_required_tasks","installed_release":"0.0.26"}'::jsonb
        );
      end if;

      checkpoint_id := null;
      for checkpoint_title in
        select value
        from jsonb_array_elements_text(phase_plan -> 'checkpoints')
      loop
        select checkpoint.id
        into checkpoint_id
        from public.roadmap_checkpoints checkpoint
        where checkpoint.user_id = owner_id
          and checkpoint.roadmap_id = roadmap_id
          and checkpoint.phase_id = phase_id
          and checkpoint.title = checkpoint_title
          and checkpoint.deleted_at is null
        order by checkpoint.created_at
        limit 1;

        if checkpoint_id is null then
          checkpoint_id := gen_random_uuid();
          insert into public.roadmap_checkpoints (
            id, user_id, roadmap_id, phase_id, milestone_id, title,
            objective, target_date, estimated_effort_ms, status, weight,
            completion_criteria, evidence, data
          ) values (
            checkpoint_id,
            owner_id,
            roadmap_id,
            phase_id,
            milestone_id,
            checkpoint_title,
            checkpoint_title,
            phase_finish,
            3600000,
            'not_started',
            1,
            jsonb_build_array(checkpoint_title),
            '[]'::jsonb,
            '{"required":true,"completion_rule":"user_review","installed_release":"0.0.26"}'::jsonb
          );
        end if;
      end loop;

      task_count := jsonb_array_length(phase_plan -> 'tasks');
      task_index := 0;
      for task_plan in
        select value from jsonb_array_elements(phase_plan -> 'tasks')
      loop
        duration_minutes := (task_plan ->> 'minutes')::integer;
        task_date := phase_start + case
          when task_count <= 1 then 0
          else floor(
            task_index::numeric * greatest(duration_days - 1, 0) /
            greatest(task_count - 1, 1)
          )::integer
        end;
        planned_start_at :=
          (task_date::timestamp + time '19:00') at time zone 'Africa/Cairo';
        planned_end_at := planned_start_at + make_interval(
          mins => duration_minutes
        );

        select task.id
        into task_id
        from public.task_occurrences task
        where task.user_id = owner_id
          and task.roadmap_id = roadmap_id
          and task.roadmap_phase_id = phase_id
          and task.title = task_plan ->> 'title'
          and task.data ->> 'v0026_plan_task' = 'true'
          and task.deleted_at is null
        order by task.created_at
        limit 1;

        if task_id is null then
          task_id := gen_random_uuid();
          insert into public.task_occurrences (
            id, user_id, title, description, status, priority,
            execution_mode, scheduled_date, planned_start, planned_end,
            due_at, estimated_duration_ms, roadmap_id, roadmap_phase_id,
            data
          ) values (
            task_id,
            owner_id,
            task_plan ->> 'title',
            'Executable roadmap task for ' || (phase_plan ->> 'title'),
            'scheduled',
            2,
            (task_plan ->> 'mode')::public.execution_mode,
            task_date,
            planned_start_at,
            planned_end_at,
            planned_end_at,
            duration_minutes * 60000,
            roadmap_id,
            phase_id,
            jsonb_build_object(
              'v0026_plan_task', true,
              'completion_method', case
                when task_plan ->> 'mode' = 'checklist' then 'checklist'
                else 'duration'
              end,
              'suggested_resource', task_plan ->> 'url',
              'time_zone', 'Africa/Cairo'
            )
          );
        end if;

        if not exists (
          select 1
          from public.roadmap_task_links task_link
          where task_link.user_id = owner_id
            and task_link.roadmap_id = roadmap_id
            and task_link.phase_id = phase_id
            and task_link.task_id = task_id
            and task_link.relationship_type = 'primary'
            and task_link.deleted_at is null
        ) then
          link_id := gen_random_uuid();
          insert into public.roadmap_task_links (
            id, user_id, roadmap_id, phase_id, milestone_id,
            checkpoint_id, task_id, relationship_type, contribution_rule,
            progress_weight, title, status, position, data
          ) values (
            link_id, owner_id, roadmap_id, phase_id, milestone_id,
            checkpoint_id, task_id, 'primary', 'completion_only',
            1, 'Task connection', 'active', task_index,
            '{"installed_release":"0.0.26"}'::jsonb
          );
        end if;

        if not exists (
          select 1
          from public.task_resources resource
          where resource.user_id = owner_id
            and resource.task_occurrence_id = task_id
            and resource.storage_path = task_plan ->> 'url'
            and resource.deleted_at is null
        ) then
          resource_id := gen_random_uuid();
          insert into public.task_resources (
            id, user_id, task_occurrence_id, roadmap_id, name,
            resource_type, description, storage_location, storage_path,
            privacy_state, data
          ) values (
            resource_id, owner_id, task_id, roadmap_id,
            task_plan ->> 'title', 'url',
            'Relevant website resource for this roadmap task',
            'url', task_plan ->> 'url', 'private',
            '{"installed_release":"0.0.26"}'::jsonb
          );
        end if;

        task_index := task_index + 1;
      end loop;

      phase_start := phase_finish + 1;
      phase_index := phase_index + 1;
    end loop;
  end loop;

  for schedule_plan in
    select value from jsonb_array_elements(schedules)
  loop
    select roadmap.id
    into roadmap_id
    from public.roadmaps roadmap
    where roadmap.user_id = owner_id
      and roadmap.title = schedule_plan ->> 'roadmap'
      and roadmap.deleted_at is null
    order by roadmap.created_at
    limit 1;

    roadmap_phase_title := schedule_plan ->> 'phase';
    select phase.id
    into phase_id
    from public.roadmap_phases phase
    where phase.user_id = owner_id
      and phase.roadmap_id = roadmap_id
      and phase.title = roadmap_phase_title
      and phase.deleted_at is null
    order by phase.created_at
    limit 1;

    if roadmap_id is null or phase_id is null then
      raise exception 'Missing roadmap hierarchy for schedule %',
        schedule_plan ->> 'key';
    end if;

    duration_minutes := (schedule_plan ->> 'minutes')::integer;
    reminder_minutes := (schedule_plan ->> 'reminder')::integer;
    select coalesce(array_agg(value::integer order by ordinality), '{}')
    into weekday_values
    from jsonb_array_elements_text(schedule_plan -> 'weekdays')
      with ordinality as weekday(value, ordinality);

    select template.id
    into template_id
    from public.task_templates template
    where template.user_id = owner_id
      and template.data ->> 'v0026_schedule_key' =
        schedule_plan ->> 'key'
      and template.deleted_at is null
    order by template.created_at
    limit 1;

    if template_id is null then
      template_id := gen_random_uuid();
      insert into public.task_templates (
        id, user_id, title, description, priority, execution_mode,
        default_duration_ms, roadmap_id, roadmap_phase_id,
        reminder_defaults, execution_settings, progress_settings, data
      ) values (
        template_id,
        owner_id,
        schedule_plan ->> 'title',
        'Recurring study timetable for DayVector v0.0.26',
        2,
        (schedule_plan ->> 'mode')::public.execution_mode,
        duration_minutes * 60000,
        roadmap_id,
        phase_id,
        jsonb_build_array(
          jsonb_build_object(
            'reminder_type', 'scheduled_start',
            'offset_ms', reminder_minutes * 60000,
            'sound_key', 'selected',
            'enabled', true
          )
        ),
        jsonb_build_object(
          'completion_method', 'duration',
          'suggested_resource', schedule_plan ->> 'url',
          'time_zone', 'Africa/Cairo'
        ),
        '{"completion_method":"duration"}'::jsonb,
        jsonb_build_object(
          'v0026_schedule_key', schedule_plan ->> 'key',
          'resource_url', schedule_plan ->> 'url',
          'time_zone', 'Africa/Cairo'
        )
      );
    end if;

    select rule.id
    into rule_id
    from public.recurrence_rules rule
    where rule.user_id = owner_id
      and rule.data ->> 'v0026_schedule_key' =
        schedule_plan ->> 'key'
      and rule.deleted_at is null
    order by rule.created_at
    limit 1;

    if rule_id is null then
      rule_id := gen_random_uuid();
      insert into public.recurrence_rules (
        id, user_id, frequency, interval_value, weekdays, starts_on,
        ends_on, maximum_occurrences, rule_data, data
      ) values (
        rule_id,
        owner_id,
        schedule_plan ->> 'frequency',
        1,
        weekday_values,
        plan_start,
        null,
        null,
        jsonb_build_object(
          'template_id', template_id,
          'frequency', schedule_plan ->> 'frequency',
          'interval_value', 1,
          'weekdays', schedule_plan -> 'weekdays',
          'starts_on', plan_start,
          'local_time', schedule_plan ->> 'time',
          'time_zone', 'Africa/Cairo',
          'created_from_owner_timetable', true
        ),
        jsonb_build_object(
          'v0026_schedule_key', schedule_plan ->> 'key',
          'installed_release', '0.0.26'
        )
      );

      update public.task_templates
      set recurrence_rule_id = rule_id
      where user_id = owner_id and id = template_id;
    end if;

    first_date := plan_start;
    if schedule_plan ->> 'frequency' = 'weekly' then
      while not (extract(isodow from first_date)::integer = any(weekday_values))
      loop
        first_date := first_date + 1;
      end loop;
    end if;
    planned_start_at :=
      (first_date::timestamp + (schedule_plan ->> 'time')::time)
      at time zone 'Africa/Cairo';
    planned_end_at := planned_start_at + make_interval(
      mins => duration_minutes
    );

    select task.id
    into task_id
    from public.task_occurrences task
    where task.user_id = owner_id
      and task.template_id = template_id
      and task.occurrence_key = to_char(first_date, 'YYYY-MM-DD')
      and task.deleted_at is null
    order by task.created_at
    limit 1;

    if task_id is null then
      task_id := gen_random_uuid();
      insert into public.task_occurrences (
        id, user_id, template_id, title, description, status, priority,
        execution_mode, scheduled_date, planned_start, planned_end, due_at,
        estimated_duration_ms, roadmap_id, roadmap_phase_id,
        occurrence_key, data
      ) values (
        task_id,
        owner_id,
        template_id,
        schedule_plan ->> 'title',
        'Recurring owner timetable linked to ' || roadmap_phase_title,
        'scheduled',
        2,
        (schedule_plan ->> 'mode')::public.execution_mode,
        first_date,
        planned_start_at,
        planned_end_at,
        planned_end_at,
        duration_minutes * 60000,
        roadmap_id,
        phase_id,
        to_char(first_date, 'YYYY-MM-DD'),
        jsonb_build_object(
          'completion_method', 'duration',
          'suggested_resource', schedule_plan ->> 'url',
          'reminder_offset_minutes', reminder_minutes,
          'schedule_template_key', schedule_plan ->> 'key',
          'time_zone', 'Africa/Cairo'
        )
      );
    end if;

    select milestone.id
    into milestone_id
    from public.roadmap_milestones milestone
    where milestone.user_id = owner_id
      and milestone.roadmap_id = roadmap_id
      and milestone.phase_id = phase_id
      and milestone.deleted_at is null
    order by milestone.position, milestone.created_at
    limit 1;

    select checkpoint.id
    into checkpoint_id
    from public.roadmap_checkpoints checkpoint
    where checkpoint.user_id = owner_id
      and checkpoint.roadmap_id = roadmap_id
      and checkpoint.phase_id = phase_id
      and checkpoint.deleted_at is null
    order by checkpoint.created_at
    limit 1;

    if not exists (
      select 1
      from public.roadmap_task_links task_link
      where task_link.user_id = owner_id
        and task_link.roadmap_id = roadmap_id
        and task_link.phase_id = phase_id
        and task_link.task_id = task_id
        and task_link.relationship_type = 'primary'
        and task_link.deleted_at is null
    ) then
      insert into public.roadmap_task_links (
        id, user_id, roadmap_id, phase_id, milestone_id, checkpoint_id,
        task_id, relationship_type, contribution_rule, progress_weight,
        title, status, data
      ) values (
        gen_random_uuid(), owner_id, roadmap_id, phase_id, milestone_id,
        checkpoint_id, task_id, 'primary', 'completion_only', 1,
        'Recurring timetable connection', 'active',
        jsonb_build_object(
          'schedule_template_key', schedule_plan ->> 'key',
          'installed_release', '0.0.26'
        )
      );
    end if;

    update public.task_resources resource
    set
      name = coalesce(
        schedule_plan ->> 'resource_name',
        schedule_plan ->> 'title'
      ),
      resource_type = 'url',
      revision = resource.revision + 1,
      updated_at = now()
    where resource.user_id = owner_id
      and resource.task_template_id = template_id
      and resource.storage_path = schedule_plan ->> 'url'
      and resource.deleted_at is null
      and (
        resource.name is distinct from coalesce(
          schedule_plan ->> 'resource_name',
          schedule_plan ->> 'title'
        )
        or resource.resource_type is distinct from 'url'
      );

    if not exists (
      select 1
      from public.task_resources resource
      where resource.user_id = owner_id
        and resource.task_template_id = template_id
        and resource.storage_path = schedule_plan ->> 'url'
        and resource.deleted_at is null
    ) then
      insert into public.task_resources (
        id, user_id, task_occurrence_id, task_template_id, roadmap_id,
        name, resource_type, description, storage_location, storage_path,
        privacy_state, data
      ) values (
        gen_random_uuid(), owner_id, task_id, template_id, roadmap_id,
        coalesce(
          schedule_plan ->> 'resource_name',
          schedule_plan ->> 'title'
        ),
        'url',
        'Website resource for this recurring study session',
        'url', schedule_plan ->> 'url', 'private',
        jsonb_build_object(
          'schedule_template_key', schedule_plan ->> 'key',
          'installed_release', '0.0.26'
        )
      );
    end if;

    for additional_resource in
      select value
      from jsonb_array_elements(
        coalesce(schedule_plan -> 'additional_resources', '[]'::jsonb)
      )
    loop
      if not exists (
        select 1
        from public.task_resources resource
        where resource.user_id = owner_id
          and resource.task_template_id = template_id
          and resource.storage_path = additional_resource ->> 'url'
          and resource.deleted_at is null
      ) then
        insert into public.task_resources (
          id, user_id, task_occurrence_id, task_template_id, roadmap_id,
          name, resource_type, description, storage_location, storage_path,
          privacy_state, data
        ) values (
          gen_random_uuid(), owner_id, task_id, template_id, roadmap_id,
          additional_resource ->> 'name', 'url',
          'Additional website resource for this recurring study session',
          'url', additional_resource ->> 'url', 'private',
          jsonb_build_object(
            'schedule_template_key', schedule_plan ->> 'key',
            'installed_release', '0.0.26'
          )
        );
      end if;
    end loop;

    if not exists (
      select 1
      from public.task_reminders reminder
      where reminder.user_id = owner_id
        and reminder.task_occurrence_id = task_id
        and reminder.reminder_type = 'scheduled_start'
        and reminder.deleted_at is null
    ) then
      reminder_id := gen_random_uuid();
      insert into public.task_reminders (
        id, user_id, task_template_id, task_occurrence_id, reminder_type,
        scheduled_at, offset_ms, repeat_rule, sound_key, enabled, data
      ) values (
        reminder_id, owner_id, template_id, task_id, 'scheduled_start',
        planned_start_at - make_interval(mins => reminder_minutes),
        reminder_minutes * 60000,
        jsonb_build_object(
          'frequency', schedule_plan ->> 'frequency',
          'weekdays', schedule_plan -> 'weekdays',
          'time_zone', 'Africa/Cairo'
        ),
        'selected',
        true,
        jsonb_build_object(
          'schedule_template_key', schedule_plan ->> 'key',
          'installed_release', '0.0.26'
        )
      );
    end if;
  end loop;
end
$seed$;
