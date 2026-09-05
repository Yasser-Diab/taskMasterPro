import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/updates/release_notes_markdown.dart';

void main() {
  test('renders GitHub details and summary blocks without raw HTML', () {
    final segments = parseReleaseNotesSegments('''
DayVector 0.0.30-beta

<details open>
<summary><strong>English</strong></summary>

New **planning** tools and <em>safer</em> sync recovery.
</details>
''');

    expect(segments, hasLength(2));
    expect(segments.first.isDetails, isFalse);
    expect(segments.last.isDetails, isTrue);
    expect(segments.last.open, isTrue);
    expect(segments.last.summary, '**English**');
    expect(segments.last.markdown, contains('New **planning** tools'));
    expect(segments.last.markdown, isNot(contains('<')));
  });

  test('strips unsupported remote HTML while preserving readable text', () {
    final segments = parseReleaseNotesSegments(
      'A <script>alert(1)</script> <span>safe note</span>.',
    );

    expect(segments.single.markdown, 'A alert(1) safe note.');
  });
}
