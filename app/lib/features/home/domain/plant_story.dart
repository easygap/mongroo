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
          '화분이 한 번 흔들렸다',
          '물을 주고 돌아서자 화분이 달그락거렸다. ${koreanTopic(name)} 아직 흙 밖으로 나올 생각은 없는 모양이다.',
        ),
        _chapter(
          2,
          '잎 두 장, 고집 하나',
          emotionProfile.total > 0
              ? '일기를 ${emotionProfile.total}편 읽어 주는 동안 잎이 두 장 나왔다. 화분을 돌려 놓아도 꼭 같은 쪽을 본다.'
              : '작은 잎 두 장이 화분 밖으로 나왔다. 한쪽은 창문을, 다른 쪽은 물뿌리개를 향해 있다.',
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
    final title = switch ((chapterStage, growthForm)) {
      (3, PlantGrowthForm.sunny) => '창가 쟁탈전',
      (3, PlantGrowthForm.rainy) => '물받이 담당',
      (3, PlantGrowthForm.ember) => '여기 내 자리',
      (3, PlantGrowthForm.moonlit) => '야간 점검',
      (3, PlantGrowthForm.sparkling) => '단추의 주인',
      (3, PlantGrowthForm.mosaic) => '짝이 다른 잎',
      (4, PlantGrowthForm.sunny) => '그늘 한 칸',
      (4, PlantGrowthForm.rainy) => '비 오는 날의 합주',
      (4, PlantGrowthForm.ember) => '끈은 두 번 묶기',
      (4, PlantGrowthForm.moonlit) => '밤에만 펴는 지도',
      (4, PlantGrowthForm.sparkling) => '이름 없는 서랍',
      (4, PlantGrowthForm.mosaic) => '꽃잎 색 견본',
      (5, PlantGrowthForm.sunny) => '창가 자리 예약',
      (5, PlantGrowthForm.rainy) => '물받이도 함께',
      (5, PlantGrowthForm.ember) => '이삿짐은 직접',
      (5, PlantGrowthForm.moonlit) => '문 닫은 뒤의 이사',
      (5, PlantGrowthForm.sparkling) => '서랍째 이사',
      (5, PlantGrowthForm.mosaic) => '선반 끝 두 자리',
      (3, _) => '창문 너머 구경',
      (4, _) => '아직 닫힌 꽃봉오리',
      _ => '박물관으로 이사',
    };
    final characterTitle = growthTraits.title.trim();
    if (chapterStage == 5 && characterTitle.isNotEmpty) {
      return '$characterTitle의 이사';
    }
    return title;
  }

  String _branchStory(int chapterStage) {
    final story = switch ((chapterStage, growthForm)) {
      (3, PlantGrowthForm.sunny) =>
        '아침마다 화분을 창가로 조금씩 밀었다. 오늘은 커튼에 걸려 멈췄다. 잠깐 고민하더니 잎으로 커튼을 걷었다.',
      (3, PlantGrowthForm.rainy) =>
        '천장에서 떨어지는 물을 세고 있었다. 서른일곱에서 빗방울이 두 개 겹쳤다. 처음부터 다시 센다.',
      (3, PlantGrowthForm.ember) =>
        '자리를 옮겨 줬더니 원래 있던 칸으로 돌아왔다. 화분 밑에 작은 쪽지를 끼워 뒀다. “여기.”',
      (3, PlantGrowthForm.moonlit) =>
        '밤에만 잎을 펴는 줄 알았는데, 낮에는 창가가 너무 붐벼서 기다린 거였다. 빈 선반 세 칸을 벌써 찾아 뒀다.',
      (3, PlantGrowthForm.sparkling) =>
        '화분 뒤에서 단추를 주웠다. 온실을 한 바퀴 돌며 주인을 찾았지만 모두 고개를 저었다. 일단 보관하기로 했다.',
      (3, PlantGrowthForm.mosaic) =>
        '새잎 둘의 색이 달랐다. 서로 맞대 보더니 굳이 화분을 반 바퀴 돌렸다. 이쪽이 더 잘 보인다고 한다.',
      (4, PlantGrowthForm.sunny) =>
        '꽃봉오리가 커지자 옆 화분이 그늘에 가렸다. 한참 자리를 재더니 자기 화분 밑에 책 한 권을 받쳤다. 둘 다 볕이 든다.',
      (4, PlantGrowthForm.rainy) =>
        '물받이를 세 개 놓고 떨어지는 소리를 들었다. 가운데 것만 살짝 옮겼다. 이유를 묻자 한 번 들어 보라고 했다.',
      (4, PlantGrowthForm.ember) =>
        '꽃봉오리가 문손잡이에 걸렸다. 화를 내다 말고 끈을 꺼내 묶었다. 다음 날부터는 문을 지날 때 먼저 고개를 숙인다.',
      (4, PlantGrowthForm.moonlit) =>
        '선반 사이를 걷는 지도를 그렸다. 의자가 옮겨진 자리에 작은 엑스표를 쳤다. 지도는 남에게 보여 줄 때만 거꾸로 든다.',
      (4, PlantGrowthForm.sparkling) =>
        '주운 물건을 서랍에 정리했다. 단추 칸, 나사 칸, 아직 모르는 것 칸. 마지막 칸이 가장 빨리 찬다.',
      (4, PlantGrowthForm.mosaic) =>
        '꽃봉오리마다 색이 조금씩 다르다. 종이에 견본을 그리려다 색연필이 모자랐다. 두 자루를 한 손에 잡고 칠했다.',
      (5, PlantGrowthForm.sunny) =>
        '박물관 창가를 먼저 둘러보고 왔다. 좋은 자리가 두 칸이라며 자기 이름표는 한쪽에만 붙였다. 다른 한 칸은 비워 뒀다.',
      (5, PlantGrowthForm.rainy) =>
        '이삿짐 맨 위에 물받이를 챙겼다. 박물관에는 비가 안 샌다고 하자, 창문을 열면 된다고 대답했다.',
      (5, PlantGrowthForm.ember) =>
        '짐은 직접 들겠다고 했다. 문 앞에서 꽃이 걸릴 뻔했지만 이번에는 먼저 몸을 낮췄다. 뒤도 돌아보지 않고 문을 잡아 줬다.',
      (5, PlantGrowthForm.moonlit) =>
        '관람 시간이 끝나기를 기다렸다가 박물관으로 갔다. 새 선반의 치수를 재고 지도를 폈다. 이번 지도에는 우리 온실도 있다.',
      (5, PlantGrowthForm.sparkling) =>
        '보관하던 단추의 주인을 드디어 찾았다. 박물관 관리인의 앞치마에서 하나가 비어 있었다. 서랍 하나를 비우고 이사했다.',
      (5, PlantGrowthForm.mosaic) =>
        '박물관 선반 끝에 자리를 잡았다. 어느 쪽에서 봐도 꽃 색이 다르게 보이는 자리다. 이름표는 가운데에 놓았다.',
      (3, _) => '잎이 자라면서 화분 밖을 자주 내다본다. 창문 앞에 놓인 신발을 특히 오래 본다.',
      (4, _) => '꽃봉오리를 덮어 둔 잎이 조금 벌어졌다. 들여다보려 하니 다시 닫는다. 기다려 보기로 했다.',
      _ => '꽃이 다 피었다. 박물관의 빈 선반을 보여 주자 화분째 들어가도 되느냐고 물었다.',
    };
    if (chapterStage < 4 || secondaryForm == null) return story;
    final habit = switch (secondaryForm!) {
      PlantGrowthForm.sunny => '그 와중에도 창가 쪽 자리는 확인했다.',
      PlantGrowthForm.rainy => '돌아오는 길에는 물 떨어지는 소리를 잠깐 들었다.',
      PlantGrowthForm.ember => '할 말을 마친 뒤 팔짱을 꼈다.',
      PlantGrowthForm.moonlit => '수첩에 시간을 적는 것도 잊지 않았다.',
      PlantGrowthForm.sparkling => '바닥에서 뭔가를 주웠지만, 아직 보여 주지는 않는다.',
      PlantGrowthForm.mosaic => '이름표 옆에는 색이 다른 점 두 개를 찍었다.',
    };
    return '$story $habit';
  }
}
