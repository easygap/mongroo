/// 이름 끝 글자의 받침 유무에 맞는 목적격 조사를 붙입니다.
String koreanObject(String word) =>
    '$word${_hasFinalConsonant(word) ? '을' : '를'}';

/// 이름 끝 글자의 받침 유무에 맞는 주격 조사를 붙입니다.
String koreanSubject(String word) =>
    '$word${_hasFinalConsonant(word) ? '이' : '가'}';

/// 이름 끝 글자의 받침 유무에 맞는 동반격 조사를 붙입니다.
String koreanWith(String word) =>
    '$word${_hasFinalConsonant(word) ? '과' : '와'}';

/// 이름 끝 글자의 받침 유무에 맞는 보조사(은/는)를 붙입니다.
String koreanTopic(String word) =>
    '$word${_hasFinalConsonant(word) ? '은' : '는'}';

/// 이름 끝 글자에 맞는 방향·자격 조사(로/으로)를 붙입니다.
///
/// 다른 조사와 규칙이 하나 다르다. **`ㄹ` 받침은 받침이 있어도 `로`를 쓴다.**
/// 그래서 `모아결으로`가 아니라 `모아결로`이고, 숫자도 끝자리를 한국어로
/// 읽어 갈린다 — `109로`(구), `1393으로`(삼), `1391로`(일).
String koreanDirection(String word) =>
    '$word${_hasFinalConsonant(word) && !_endsWithRieul(word) ? '으로' : '로'}';

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

/// 마지막 글자의 받침이 `ㄹ`인지. 일(1)·칠(7)·팔(8)도 여기 들어간다.
bool _endsWithRieul(String word) {
  final trimmed = word.trimRight();
  if (trimmed.isEmpty) return false;
  final codePoint = trimmed.runes.last;
  if (codePoint >= 0xAC00 && codePoint <= 0xD7A3) {
    return (codePoint - 0xAC00) % 28 == 8;
  }
  if (codePoint >= 0x30 && codePoint <= 0x39) {
    return const {1, 7, 8}.contains(codePoint - 0x30);
  }
  return false;
}
