import '../domain/expedition_models.dart';
import 'expedition_combat_audio.dart';

/// Use the region's own arrangement and raise it at meaningful battle turns.
/// Diary emotion never determines danger or the intensity of the music.
({ExpeditionMusicState state, double volume}) expeditionMusicMix({
  ExpeditionBattle? battle,
  bool guardianEncounter = false,
}) {
  if (battle != null && !battle.isActive) {
    return (state: ExpeditionMusicState.base, volume: .16);
  }
  final guardian = battle?.enemyKind == 'guardian' || guardianEncounter;
  if (battle == null) {
    return (
      state:
          guardian ? ExpeditionMusicState.guardian : ExpeditionMusicState.base,
      volume: .18
    );
  }
  final living = battle.livingParty;
  final threatened = living.isNotEmpty &&
      living
          .any((member) => member.maxHp > 0 && member.hp / member.maxHp <= .30);
  final finalRound = battle.round >= battle.maxRounds;
  if (guardian) {
    final phase = (battle.bossPhase?.index ?? 1).clamp(1, 3);
    return (
      state: ExpeditionMusicState.guardian,
      volume: .19 + (phase - 1) * .025 + (threatened || finalRound ? .02 : 0)
    );
  }
  final finalWave = battle.wave != null &&
      battle.wave!.count > 1 &&
      battle.wave!.index == battle.wave!.count;
  return (
    state: ExpeditionMusicState.combat,
    volume: threatened || finalRound
        ? .22
        : finalWave
            ? .20
            : .18
  );
}
