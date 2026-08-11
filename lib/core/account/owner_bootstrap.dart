/// Optional, build-time owner guard for deliberately supplied starter content.
///
/// There is intentionally no default owner.  A test installation must never
/// infer ownership from email, the last account on the device, or a cached
/// profile.  A release that genuinely needs owner-only sample content can set
/// `--dart-define=TASKMASTER_OWNER_USER_ID=<Supabase UUID>` during its own
/// build; normal user builds create no personal starter tasks or roadmaps.
const configuredOwnerUserId = String.fromEnvironment(
  'TASKMASTER_OWNER_USER_ID',
);

bool mayBootstrapOwnerContent(String userId) =>
    configuredOwnerUserId.isNotEmpty && configuredOwnerUserId == userId;
