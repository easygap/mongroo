import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

int _invocationEnd(String source, int openingParenthesis) {
  var depth = 0;
  String? quote;
  var escaped = false;
  for (var index = openingParenthesis; index < source.length; index++) {
    final character = source[index];
    if (quote != null) {
      if (escaped) {
        escaped = false;
      } else if (character == '\\') {
        escaped = true;
      } else if (character == quote) {
        quote = null;
      }
      continue;
    }
    if (character == "'" || character == '"') {
      quote = character;
    } else if (character == '(') {
      depth += 1;
    } else if (character == ')') {
      depth -= 1;
      if (depth == 0) return index + 1;
    }
  }
  return source.length;
}

void main() {
  test('모든 PlantView 호출은 장착 의상 키를 명시적으로 전달한다', () {
    final files =
        Directory('lib').listSync(recursive: true).whereType<File>().where(
              (file) =>
                  file.path.endsWith('.dart') &&
                  !file.path.endsWith('plant_view.dart'),
            );
    final pattern = RegExp(r'\bPlantView\s*\(');
    var callCount = 0;

    for (final file in files) {
      final source = file.readAsStringSync();
      for (final match in pattern.allMatches(source)) {
        callCount += 1;
        final end = _invocationEnd(source, match.end - 1);
        final invocation = source.substring(match.start, end);
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        expect(
          invocation,
          contains(RegExp(r'\boutfitKey\s*:')),
          reason: '${file.path}:$line PlantView 의상 키가 누락됨',
        );
      }
    }

    expect(callCount, greaterThanOrEqualTo(4));
  });
}
