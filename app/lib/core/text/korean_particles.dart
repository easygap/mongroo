/// 이름 끝 글자의 받침 유무에 맞는 목적격 조사를 붙입니다.
String koreanObject(String word) =>
    '$word${_hasFinalConsonant(word) ? '을' : '를'}';

/// 이름 끝 글자의 받침 유무에 맞는 주격 조사를 붙입니다.
String koreanSubject(String word) =>
    '$word${_hasFinalConsonant(word) ? '이' : '가'}';

/// 이름 끝 글자의 받침 유무에 맞는 동반격 조사를 붙입니다.
String koreanWith(String word) =>
    '$word${_hasFinalConsonant(word) ? '과' : '와'}';

bool _hasFinalConsonant(String word) {
  final trimmed = word.trimRight();
  if (trimmed.isEmpty) return false;
  final codePoint = trimmed.runes.last;
  if (codePoint >= 0xAC00 && codePoint <= 0xD7A3) {
    return (codePoint - 0xAC00) % 28 != 0;
  }

  // 숫자는 한국어로 읽었을 때의 받침 유무를 따른다.
  if (codePoint >= 0x30 && codePoint <= 0x39) {
    return const {0, 1, 3, 6, 7, 8}.contains(codePoint - 0x30);
  }
  return false;
}
