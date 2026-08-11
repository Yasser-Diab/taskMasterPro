import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('owner learning plan uses real official task resources', () {
    final seed = File(
      'tool/seed_v0026_owner_learning_plan.sql',
    ).readAsStringSync();

    for (final url in const [
      'https://www.freecodecamp.org/learn/javascript-algorithms-and-data-structures-v8/',
      'https://academy.hsoub.com/',
      'https://www.duolingo.com/learn',
      'https://learngerman.dw.com/en/nicos-weg/c-36519789',
      'https://www.goethe.de/en/spr/ueb.html',
      'https://www.easygerman.org/',
      'https://code.visualstudio.com/docs',
      'https://nodejs.org/en/download',
      'https://docs.github.com/en/get-started/start-your-journey',
    ]) {
      expect(seed, contains(url), reason: 'Missing official resource $url');
    }
    expect(seed, contains('"additional_resources"'));
    expect(seed, anyOf(contains("'resource_type', 'url'"), contains("'url',")));
    expect(seed, isNot(contains('example.com')));
    expect(seed, isNot(contains('Milestone 1')));
    expect(seed, contains('4bd3e32d-1dcd-48ed-9f64-9099675047f1'));
  });
}
