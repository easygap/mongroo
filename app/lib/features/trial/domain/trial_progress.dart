import 'dart:convert';

import '../../home/domain/plant.dart';

enum TrialStage { welcome, diary, growth, exploration, complete }

class TrialProgress {
  const TrialProgress({
    this.stage = TrialStage.welcome,
    this.diaryText = '',
    this.emotionCode,
    this.explorationStep = 0,
    this.selectedPath,
    this.selectedChoice,
  });

  static const schemaVersion = 1;

  final TrialStage stage;
  final String diaryText;
  final String? emotionCode;
  final int explorationStep;
  final String? selectedPath;
  final String? selectedChoice;

  bool get hasDiary => diaryText.trim().length >= 10 && emotionCode != null;
  bool get hasCompletedExploration => stage == TrialStage.complete;

  /// 이 체험이 키우는 결. 본편과 같은 표를 읽어 이름과 코드가 갈리지 않는다.
  PlantGrowthForm get growth =>
      PlantGrowthForm.fromCode(emotionCode) ?? PlantGrowthForm.mosaic;

  String get growthForm => growth.code;

  TrialProgress copyWith({
    TrialStage? stage,
    String? diaryText,
    Object? emotionCode = _unset,
    int? explorationStep,
    Object? selectedPath = _unset,
    Object? selectedChoice = _unset,
  }) =>
      TrialProgress(
        stage: stage ?? this.stage,
        diaryText: diaryText ?? this.diaryText,
        emotionCode:
            emotionCode == _unset ? this.emotionCode : emotionCode as String?,
        explorationStep: explorationStep ?? this.explorationStep,
        selectedPath: selectedPath == _unset
            ? this.selectedPath
            : selectedPath as String?,
        selectedChoice: selectedChoice == _unset
            ? this.selectedChoice
            : selectedChoice as String?,
      );

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'stage': stage.name,
        'diary_text': diaryText,
        'emotion_code': emotionCode,
        'exploration_step': explorationStep,
        'selected_path': selectedPath,
        'selected_choice': selectedChoice,
      };

  String encode() => jsonEncode(toJson());

  factory TrialProgress.decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic> ||
        decoded['schema_version'] != schemaVersion) {
      throw const FormatException('지원하지 않는 체험 데이터입니다.');
    }
    final stageName = decoded['stage'] as String?;
    final stage = TrialStage.values.where((item) => item.name == stageName);
    final rawStep = decoded['exploration_step'];
    final rawDiary = decoded['diary_text'] as String? ?? '';
    return TrialProgress(
      stage: stage.firstOrNull ?? TrialStage.welcome,
      diaryText: rawDiary.length > 280 ? rawDiary.substring(0, 280) : rawDiary,
      emotionCode: _validEmotion(decoded['emotion_code'] as String?),
      explorationStep: rawStep is int ? rawStep.clamp(0, 2) : 0,
      selectedPath: _validPath(decoded['selected_path'] as String?),
      selectedChoice: decoded['selected_choice'] as String?,
    );
  }

  // 여섯 결은 서로 우열이 없다. 셋만 받으면 불안·놀람·여러 마음을 적은
  // 사람에게 자기 마음에 해당하는 칸이 아예 없다.
  static String? _validEmotion(String? value) =>
      PlantGrowthForm.fromCode(value)?.code;

  static String? _validPath(String? value) =>
      const {'labels', 'roots'}.contains(value) ? value : null;
}

const _unset = Object();
