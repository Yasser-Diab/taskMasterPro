import 'dart:io';

final _visibleLiteralPatterns = <RegExp>[
  RegExp(r'''\b(?:Text|SelectableText)\(\s*(['"])(?!TaskMaster Pro\1)'''),
  RegExp(
    r'''\b(?:labelText|helperText|hintText|tooltip|semanticsLabel)\s*:\s*(['"])''',
  ),
  RegExp(r'''\bSnackBarAction\(\s*label\s*:\s*(['"])'''),
];

void main(List<String> arguments) {
  final root = Directory('lib');
  final findings = <String>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final lines = entity.readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.contains('// localization-audit: allow')) continue;
      if (_visibleLiteralPatterns.any((pattern) => pattern.hasMatch(line))) {
        findings.add('${entity.path}:${index + 1}: ${line.trim()}');
      }
    }
  }
  if (findings.isEmpty) {
    stdout.writeln('Localization audit passed.');
    return;
  }
  stdout
    ..writeln('Hard-coded user-facing string candidates:')
    ..writeln(findings.join('\n'))
    ..writeln('${findings.length} candidate(s) found.');
  if (arguments.contains('--enforce')) exitCode = 1;
}
