import 'dart:io';

import 'app_environment.dart';

class BuildInfo {
  const BuildInfo._();

  static const version = String.fromEnvironment(
    'TASKMASTER_APP_VERSION',
    defaultValue: '0.1.1',
  );
  static const buildNumber = String.fromEnvironment(
    'TASKMASTER_BUILD_NUMBER',
    defaultValue: '2',
  );
  static const gitCommit = String.fromEnvironment(
    'TASKMASTER_GIT_COMMIT',
    defaultValue: 'not-provided',
  );
  static const buildDate = String.fromEnvironment(
    'TASKMASTER_BUILD_DATE',
    defaultValue: 'not-provided',
  );
  static const migrationVersion = String.fromEnvironment(
    'TASKMASTER_DB_MIGRATION',
    defaultValue: '20260718173000',
  );

  static String get flutterEnvironment => AppEnvironment.environmentName;
  static String get platform => Platform.operatingSystem;
}
