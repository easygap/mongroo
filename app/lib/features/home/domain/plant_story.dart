import '../../../core/text/korean_particles.dart';
import 'plant.dart';

/// 한 식물의 성장을 숫자 대신 에피소드로 기억하게 하는 5장 이야기.
class PlantStoryChapter {
  const PlantStoryChapter({
    required this.stage,
    required this.title,
    required this.story,
    required this.unlocked,
    required this.current,
  });

  final int stage;
  final String title;
  final String story;
  final bool unlocked;
  final bool current;

  String get stageLabel => '제$stage장 · ${plantStageName(stage)}';
}

extension ActivePlantStory on ActivePlant {
  List<PlantStoryChapter> get storyChapters => [
        _chapter(
          1,
          '흙 아래 첫 숨',
          '첫 이야기가 화분에 닿은 날, ${koreanTopic(name)} 흙 아래에서 작게 몸을 움직였어요.',
        ),
        _chapter(
          2,
          '잎맥에 비친 마음빛',
          emotionProfile.total > 0
              ? '지금까지 들은 일기 ${emotionProfile.total}편이 새잎의 색과 잎맥에 천천히 스며들었어요.'
              : '새잎은 아직 빈 도화지예요. 다음 이야기가 첫 마음빛을 남겨요.',
        ),
        _chapter(3, _branchTitle(3), _branchStory(3)),
        _chapter(4, _branchTitle(4), _branchStory(4)),
        _chapter(5, _branchTitle(5), _branchStory(5)),
      ];

  PlantStoryChapter get currentStoryChapter => storyChapters[stage - 1];

  PlantStoryChapter? get nextStoryChapter =>
      stage >= 5 ? null : storyChapters[stage];

  PlantStoryChapter _chapter(int chapterStage, String title, String story) =>
      PlantStoryChapter(
        stage: chapterStage,
        title: title,
        story: story,
        unlocked: stage >= chapterStage,
        current: stage == chapterStage,
      );

  String _branchTitle(int chapterStage) {
    final form = growthForm;
    final baseTitle = switch ((chapterStage, form)) {
      (3, PlantGrowthForm.sunny) => '햇빛 자리의 발견',
      (3, PlantGrowthForm.rainy) => '물방울을 세는 오후',
      (3, PlantGrowthForm.ember) => '작은 불씨의 선언',
      (3, PlantGrowthForm.moonlit) => '달빛 아래 준비 목록',
      (3, PlantGrowthForm.sparkling) => '반짝임을 쫓는 잎',
      (3, PlantGrowthForm.mosaic) => '서로 다른 빛의 자리',
      (3, _) => '아직 이름 없는 결',
      (4, PlantGrowthForm.sunny) => '온실에 나누어 준 빛',
      (4, PlantGrowthForm.rainy) => '비가 머문 꽃망울',
      (4, PlantGrowthForm.ember) => '또렷해진 꽃 가장자리',
      (4, PlantGrowthForm.moonlit) => '은빛이 열리는 밤',
      (4, PlantGrowthForm.sparkling) => '뜻밖의 무늬 발견',
      (4, PlantGrowthForm.mosaic) => '색마다 피어난 꽃망울',
      (4, _) => '꽃망울의 비밀',
      (5, PlantGrowthForm.sunny) => '햇살꽃의 초대장',
      (5, PlantGrowthForm.rainy) => '빗방울꽃의 초대장',
      (5, PlantGrowthForm.ember) => '불씨꽃의 초대장',
      (5, PlantGrowthForm.moonlit) => '달그늘꽃의 초대장',
      (5, PlantGrowthForm.sparkling) => '반짝꽃의 초대장',
      (5, PlantGrowthForm.mosaic) => '마음모아꽃의 초대장',
      _ => '박물관에서 온 초대장',
    };
    if (chapterStage == 4 && secondaryForm != null) {
      return '$baseTitle · ${secondaryForm!.emotionLabel}빛';
    }
    final characterTitle = growthTraits.title.trim();
    if (chapterStage == 5 && form != null && characterTitle.isNotEmpty) {
      return '${form.label} · $characterTitle의 초대장';
    }
    return baseTitle;
  }

  String _branchStory(int chapterStage) {
    final form = growthForm;
    if (form == null) {
      return switch (chapterStage) {
        3 => '일기가 조금 더 쌓이면 외형과 말투에 이 식물만의 결이 드러나요.',
        4 => '결이 자리 잡은 뒤에는 고유한 꽃봉오리와 움직임을 만나게 돼요.',
        _ => '만개한 모습과 함께한 기록은 박물관의 한 자리로 오래 남아요.',
      };
    }
    final baseStory = switch ((chapterStage, form)) {
      (3, PlantGrowthForm.sunny) =>
        '가장 따뜻한 자리를 찾은 뒤, 옆 화분에도 빛이 닿도록 잎을 넓게 펼쳤어요.',
      (3, PlantGrowthForm.rainy) => '잎 끝마다 맺힌 물방울의 속도가 다르다는 걸 알아차리고 오래 바라보았어요.',
      (3, PlantGrowthForm.ember) => '작지만 또렷한 불씨 무늬를 처음 드러내며 자기 자리를 밝혔어요.',
      (3, PlantGrowthForm.moonlit) => '온실이 잠든 뒤 움직일 길을 차분히 살피고 은빛 표시를 남겼어요.',
      (3, PlantGrowthForm.sparkling) =>
        '새잎에서 번쩍인 무늬를 따라가며 온실 구석의 작은 단서를 찾아냈어요.',
      (3, PlantGrowthForm.mosaic) => '서로 다른 색의 잎이 겹치지 않도록 각자의 자리를 천천히 만들었어요.',
      (4, PlantGrowthForm.sunny) => '모아 둔 빛을 꽃봉오리에 담아 온실의 그늘진 칸까지 따뜻하게 비췄어요.',
      (4, PlantGrowthForm.rainy) => '물방울을 품은 꽃봉오리가 비가 그친 뒤에도 고유한 리듬으로 흔들렸어요.',
      (4, PlantGrowthForm.ember) => '꽃 가장자리의 주황빛 무늬가 선명해지며 숨기지 않는 말투가 생겼어요.',
      (4, PlantGrowthForm.moonlit) => '달이 기우는 순서에 맞춰 꽃봉오리를 하나씩 열 준비를 마쳤어요.',
      (4, PlantGrowthForm.sparkling) =>
        '꽃봉오리마다 다른 무늬가 나타나자 신이 나서 이름을 하나씩 붙였어요.',
      (4, PlantGrowthForm.mosaic) => '여러 색의 꽃봉오리가 어느 하나를 가리지 않고 같은 줄기에서 자랐어요.',
      (5, PlantGrowthForm.sunny) =>
        '활짝 편 꽃잎에 함께 보낸 햇빛 같은 장면을 담아 박물관으로 갈 준비를 마쳤어요.',
      (5, PlantGrowthForm.rainy) =>
        '잎 끝의 물방울과 오래 바라본 장면을 간직한 채 박물관의 창가 자리를 골랐어요.',
      (5, PlantGrowthForm.ember) =>
        '또렷한 불씨 무늬와 솔직했던 순간을 품고 박물관의 조명 아래 설 준비를 했어요.',
      (5, PlantGrowthForm.moonlit) =>
        '은빛 잎 안쪽에 차분히 살핀 시간들을 기록하고 박물관의 밤 전시를 기다려요.',
      (5, PlantGrowthForm.sparkling) =>
        '발견한 반짝임을 꽃마다 나누어 담고 박물관에서 다음 관찰자를 기다려요.',
      (5, PlantGrowthForm.mosaic) =>
        '서로 다른 마음빛을 한 그루에 그대로 품은 채 박물관의 넓은 선반으로 향해요.',
      _ => '조금씩 달라진 모습을 한 장씩 모아 이 식물만의 이야기를 완성했어요.',
    };
    if (chapterStage < 4) return baseStory;
    return _withRevealedCharacterDetails(baseStory, chapterStage);
  }

  String _withRevealedCharacterDetails(String baseStory, int chapterStage) {
    final details = <String>[];
    final secondary = secondaryForm;
    if (secondary != null) {
      // 서버가 주는 결 문구(`온기를 나누는`)는 뒤에 이름이 와야 끝나는
      // 관형구다. 그대로 조사를 붙이면 `온기를 나누는도`가 화면에 나간다.
      // 서버가 `growth_persona.trait`을 만들 때와 같이 `결`을 붙여 닫는다.
      final secondaryTrait = growthTraits.traits.length >= 2
          ? '${growthTraits.traits[1]} 결'
          : secondary.personalityName;
      details.add(
        chapterStage == 4
            ? '${secondary.emotionLabel}에서 온 $secondaryTrait도 꽃잎 가장자리와 움직임에 스며들었어요.'
            : '${secondary.emotionLabel} 보조결과 $secondaryTrait도 만개한 모습에 함께 남았어요.',
      );
    }
    final temperament = temperamentSummary;
    if (temperament.isNotEmpty) {
      details.add(
        chapterStage == 4
            ? '「$temperament」의 식물 기질이 움직임과 말걸음의 리듬으로 처음 또렷해졌어요.'
            : '「$temperament」의 식물 기질이 고유한 움직임과 대화 습관으로 완성됐어요.',
      );
    }
    return details.isEmpty ? baseStory : '$baseStory ${details.join(' ')}';
  }
}
