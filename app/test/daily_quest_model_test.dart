import 'package:flutter_test/flutter_test.dart';
import 'package:mongroo/features/quest/domain/daily_quest.dart';

void main() {
  test('오늘 퀘스트 계약을 중첩 quest 정의까지 파싱한다', () {
    final feed = DailyQuestFeed.fromJson({
      'date': '2026-07-13',
      'suspended': false,
      'suspension_reason': null,
      'context_status': 'diary_matched',
      'context_emotion': '슬픔',
      'journey': {
        'recorded_day_count': 4,
        'completed_quest_count': 2,
        'weekly_recorded_days': 3,
        'weekly_completed_quests': 1,
        'next_unlock': {
          'item_id': 8,
          'code': 'room_moonlit',
          'name': '달빛 몽상 온실',
          'item_type': 'room_theme',
          'acquisition_type': 'quest_count',
          'label': '일일 퀘스트 3회 완료',
          'current': 2,
          'target': 3,
          'eligible': false,
        },
      },
      'items': [
        {
          'id': 21,
          'quest_date': '2026-07-13',
          'status': 'assigned',
          'completed_at': null,
          'quest': {
            'id': 3,
            'code': 'name_the_feeling',
            'title': '감정에 이름 붙이기',
            'description': '지금 마음에 가장 가까운 단어를 하나 골라 보세요.',
            'category': 'grounding',
            'burden_level': 1,
            'estimated_minutes': 2,
            'reward_exp': 20,
            'reward_seeds': 5,
          },
        },
      ],
    });

    expect(feed.suspended, isFalse);
    expect(feed.contextTitle, '오늘 일기에서 읽힌 슬픔');
    expect(feed.contextDescription, contains('평가하지 않고'));
    expect(feed.nextAssigned?.id, 21);
    expect(feed.items.single.quest.title, '감정에 이름 붙이기');
    expect(feed.items.single.quest.categoryLabel, '관찰');
    expect(feed.items.single.quest.rewardSeeds, 5);
    expect(feed.journey.weeklyRecordedDays, 3);
    expect(feed.journey.nextUnlock?.name, '달빛 몽상 온실');
    expect(feed.journey.nextUnlock?.progress, closeTo(2 / 3, .001));
    expect(feed.journey.nextUnlock?.typeLabel, '방 테마');
  });

  test('완료 항목으로 교체하면 진행 가능한 퀘스트가 사라진다', () {
    final assigned = DailyQuest.fromJson({
      'id': 7,
      'quest_date': '2026-07-13',
      'status': 'assigned',
      'quest': {'id': 1, 'title': '물 한 잔 마시기'},
    });
    final feed = DailyQuestFeed(
      date: '2026-07-13',
      suspended: false,
      items: [assigned],
    );

    final updated = feed.replace(
      assigned.copyWith(status: DailyQuestStatus.completed),
    );

    expect(updated.nextAssigned, isNull);
    expect(updated.allFinished, isTrue);
    expect(updated.items.single.status, DailyQuestStatus.completed);
  });

  test('안전 지원 상태에서는 퀘스트 목록과 무관하게 suspended를 보존한다', () {
    final feed = DailyQuestFeed.fromJson({
      'date': '2026-07-13',
      'suspended': true,
      'suspension_reason': 'safety_support_active',
      'items': const [],
    });

    expect(feed.suspended, isTrue);
    expect(feed.suspensionReason, 'safety_support_active');
  });

  test('일기 분석 중에는 퀘스트가 다시 연결될 시점을 설명한다', () {
    final feed = DailyQuestFeed.fromJson({
      'date': '2026-07-13',
      'suspended': false,
      'context_status': 'analyzing',
      'items': const [],
    });

    expect(feed.contextTitle, '식물이 오늘 마음을 읽는 중');
    expect(feed.contextDescription, contains('완료 전 퀘스트'));
  });

  test('퀘스트 카테고리와 준비 정도를 짧은 표기로 바꾼다', () {
    const categories = <String, String>{
      'reflection': '기록',
      'senses': '관찰',
      'space': '정리',
      'body': '몸풀기',
      'rest': '휴식',
      'planning': '준비',
      'creativity': '만들기',
      'self_kindness': '내 선택',
      'connection': '안부',
      'movement': '움직임',
    };

    for (final entry in categories.entries) {
      final quest = QuestDefinition.fromJson({
        'category': entry.key,
        'burden_level': 1,
      });
      expect(quest.categoryLabel, entry.value, reason: entry.key);
      expect(quest.burdenLabel, '준비 거의 없음');
    }
  });
}
