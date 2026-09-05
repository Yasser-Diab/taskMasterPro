import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Renders the small, safe HTML subset that GitHub release notes commonly
/// contain alongside Markdown.
///
/// GitHub accepts disclosure blocks such as `<details><summary>…`, but the
/// Flutter Markdown package treats raw HTML as literal text.  Rather than
/// enabling arbitrary HTML, this parser recognises just the structural tags
/// that release notes need, converts safe inline formatting to Markdown, and
/// exposes each disclosure as a native [ExpansionTile].  Unknown tags are
/// stripped while their text remains visible, so release copy cannot execute
/// or inject UI into the app.
class ReleaseNotesMarkdown extends StatelessWidget {
  const ReleaseNotesMarkdown({required this.data, this.onTapLink, super.key});

  final String data;
  final MarkdownTapLinkCallback? onTapLink;

  @override
  Widget build(BuildContext context) {
    final segments = parseReleaseNotesSegments(data);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: segments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final segment = segments[index];
        if (!segment.isDetails) {
          return MarkdownBody(
            data: segment.markdown,
            selectable: true,
            onTapLink: onTapLink,
          );
        }
        return Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            key: ValueKey('release-note-details-$index'),
            initiallyExpanded: segment.open,
            title: MarkdownBody(
              data: segment.summary,
              selectable: true,
              onTapLink: onTapLink,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              MarkdownBody(
                data: segment.markdown,
                selectable: true,
                onTapLink: onTapLink,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A parsed release-note portion. This is public to keep the content policy
/// independently testable without a rendered update dialog.
class ReleaseNotesSegment {
  const ReleaseNotesSegment.markdown(this.markdown)
    : isDetails = false,
      summary = '',
      open = false;

  const ReleaseNotesSegment.details({
    required this.summary,
    required this.markdown,
    required this.open,
  }) : isDetails = true;

  final bool isDetails;
  final String summary;
  final String markdown;
  final bool open;
}

/// Splits GitHub-style HTML disclosure blocks from ordinary Markdown. The
/// parser is deliberately narrow and case-insensitive: no attributes or tags
/// are passed to the widget tree.
List<ReleaseNotesSegment> parseReleaseNotesSegments(String source) {
  final segments = <ReleaseNotesSegment>[];
  final detailsPattern = RegExp(
    r'<details(?<attributes>[^>]*)>(?<body>[\s\S]*?)</details\s*>',
    caseSensitive: false,
  );
  var cursor = 0;
  for (final match in detailsPattern.allMatches(source)) {
    _addMarkdownSegment(segments, source.substring(cursor, match.start));
    final body = match.namedGroup('body') ?? '';
    final summaryMatch = RegExp(
      r'^\s*<summary[^>]*>(?<summary>[\s\S]*?)</summary\s*>',
      caseSensitive: false,
    ).firstMatch(body);
    final summary = _cleanReleaseNoteHtml(
      summaryMatch?.namedGroup('summary') ?? 'Details',
    );
    final content = summaryMatch == null
        ? body
        : body.substring(summaryMatch.end);
    segments.add(
      ReleaseNotesSegment.details(
        summary: summary.isEmpty ? 'Details' : summary,
        markdown: _cleanReleaseNoteHtml(content),
        open: (match.namedGroup('attributes') ?? '').toLowerCase().contains(
          RegExp(r'\bopen\b'),
        ),
      ),
    );
    cursor = match.end;
  }
  _addMarkdownSegment(segments, source.substring(cursor));
  return segments.isEmpty
      ? const [ReleaseNotesSegment.markdown('')]
      : List.unmodifiable(segments);
}

void _addMarkdownSegment(List<ReleaseNotesSegment> segments, String raw) {
  final markdown = _cleanReleaseNoteHtml(raw).trim();
  if (markdown.isNotEmpty) segments.add(ReleaseNotesSegment.markdown(markdown));
}

String _cleanReleaseNoteHtml(String source) {
  var result = source
      .replaceAll(RegExp(r'<\s*(strong|b)\s*>', caseSensitive: false), '**')
      .replaceAll(RegExp(r'<\s*/\s*(strong|b)\s*>', caseSensitive: false), '**')
      .replaceAll(RegExp(r'<\s*(em|i)\s*>', caseSensitive: false), '*')
      .replaceAll(RegExp(r'<\s*/\s*(em|i)\s*>', caseSensitive: false), '*')
      .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<\s*/?p\s*>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<\s*li\s*>', caseSensitive: false), '- ')
      .replaceAll(RegExp(r'<\s*/\s*li\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<\s*/?(ul|ol)\s*>', caseSensitive: false), '\n');
  // This final pass removes unsupported tags but deliberately keeps their
  // human-readable contents. It is the safety boundary for remote release
  // bodies fetched from GitHub.
  result = result.replaceAll(RegExp(r'<[^>]*>'), '');
  return result.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}
