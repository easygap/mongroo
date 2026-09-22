part of 'expedition_screen.dart';

const _atlasInk = Color(0xFF202020);
const _atlasPaper = Color(0xFFFFFFFF);
const _atlasAction = Color(0xFF242424);

/// Locations are authored against each map image, at the foot of its landmarks.
/// They are independent of progression: the server still owns unlocks and rewards.
class _AtlasArt {
  const _AtlasArt(this.file, this.stops);
  final String file;
  final List<Offset> stops;

  static _AtlasArt forRegion(String region) => switch (region) {
        'echo_well' => const _AtlasArt('echo-well-atlas-v3.png', [
            Offset(.50, .927),
            Offset(.245, .713),
            Offset(.845, .715),
            Offset(.49, .427),
            Offset(.19, .217),
            Offset(.638, .343),
            Offset(.84, .282),
            Offset(.625, .212),
          ]),
        'heartwood_observatory' => const _AtlasArt('heartwood-atlas-v3.png', [
            Offset(.51, .938),
            Offset(.268, .652),
            Offset(.735, .598),
            Offset(.697, .496),
            Offset(.215, .407),
            Offset(.50, .31),
            Offset(.80, .244),
            Offset(.60, .185),
          ]),
        'starlight_seed_vault' => const _AtlasArt('starlight-atlas-v3.png', [
            Offset(.28, .89),
            Offset(.68, .934),
            Offset(.32, .584),
            Offset(.70, .623),
            Offset(.80, .392),
            Offset(.675, .25),
            Offset(.44, .163),
            Offset(.70, .164),
          ]),
        _ => const _AtlasArt('moss-archive-atlas-v3.png', [
            Offset(.50, .895),
            Offset(.735, .79),
            Offset(.28, .61),
            Offset(.765, .52),
            Offset(.385, .395),
            Offset(.315, .272),
            Offset(.475, .17),
            Offset(.78, .202),
          ]),
      };

  String get asset => 'assets/adventure/$file';
}

/// The exploration entrance is the world itself. Only the current destination
/// sits in the thumb zone; descriptions and secondary modes open on request.
class _ExpeditionAtlas extends StatefulWidget {
  const _ExpeditionAtlas({
    required this.stageMap,
    required this.roster,
    required this.selectedPlantIds,
    required this.busy,
    required this.resume,
    required this.onDepart,
    required this.onRefresh,
    required this.onParty,
    required this.onStage,
    required this.onPrepare,
    required this.onRegions,
    required this.onJournal,
    required this.onRoutes,
    this.onBack,
  });

  final ExpeditionStageMap stageMap;
  final List<ExpeditionRosterItem> roster;
  final Set<int> selectedPlantIds;
  final bool busy;
  final bool resume;
  final VoidCallback onDepart;
  final Future<void> Function() onRefresh;
  final VoidCallback onParty;
  final ValueChanged<ExpeditionStage> onStage;
  final ValueChanged<ExpeditionStage> onPrepare;
  final VoidCallback onRegions;
  final VoidCallback onJournal;
  final VoidCallback onRoutes;
  final VoidCallback? onBack;

  @override
  State<_ExpeditionAtlas> createState() => _ExpeditionAtlasState();
}

class _ExpeditionAtlasState extends State<_ExpeditionAtlas> {
  final _camera = ScrollController();
  final _cameraX = ScrollController();
  String? _cameraPlace;
  int? _selectedNo;
  bool _closer = false;

  @override
  void didUpdateWidget(covariant _ExpeditionAtlas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stageMap.region.code != widget.stageMap.region.code ||
        oldWidget.stageMap.clearedCount != widget.stageMap.clearedCount) {
      _selectedNo = null;
    }
  }

  @override
  void dispose() {
    _camera.dispose();
    _cameraX.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final map = widget.stageMap;
    final art = _AtlasArt.forRegion(map.region.code);
    final current = widget.resume
        ? map.stageOf(map.activeStageNo) ?? map.nextStage
        : map.nextStage ?? map.stages.lastOrNull;
    final leader = widget.roster
            .where((item) => widget.selectedPlantIds.contains(item.plantId))
            .firstOrNull ??
        widget.roster.where((item) => item.eligible).firstOrNull;
    final selected = map.stageOf(_selectedNo) ?? current;
    final currentSelected = selected?.no == current?.no;
    final completed = map.regionCleared && _selectedNo == null;
    void depart() {
      if (selected == null) return;
      if (currentSelected) {
        widget.onDepart();
      } else {
        widget.onPrepare(selected);
      }
    }

    Widget dock({bool vertical = false}) => _AtlasDepartureDock(
        stage: selected,
        completed: completed,
        busy: widget.busy,
        resume: widget.resume && currentSelected,
        blockedByRun: widget.resume && !currentSelected,
        onDepart: depart,
        onParty: selected == null
            ? widget.onParty
            : () => widget.onPrepare(selected),
        onDetails: selected == null ? null : () => widget.onStage(selected),
        onRegions: widget.onRegions,
        vertical: vertical);
    return ColoredBox(
      color: _atlasInk,
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        return Row(children: [
          Expanded(
            child: Stack(children: [
              const Positioned.fill(child: ColoredBox(color: _atlasInk)),
              Positioned.fill(
                child: LayoutBuilder(builder: (context, view) {
                  // The scene can be examined in both directions. Zoom changes
                  // the artwork scale while touch targets keep their size.
                  final worldWidth =
                      math.max(view.maxWidth, view.maxHeight * 2 / 3) *
                          (_closer ? 1.45 : 1.0);
                  final worldHeight = worldWidth * 1.5;
                  const topInset = 88.0;
                  final bottomInset = wide
                      ? 24.0
                      : MediaQuery.textScalerOf(context).scale(1) >= 1.5
                          ? 260.0
                          : 152.0;
                  const left = 0.0;
                  final place =
                      '${map.region.code}:${current?.no}:${view.maxWidth}:${view.maxHeight}:$_closer';
                  if (_cameraPlace != place) {
                    _cameraPlace = place;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted || !_camera.hasClients || current == null) {
                        return;
                      }
                      final index = ((selected ?? current).no - 1)
                          .clamp(0, art.stops.length - 1);
                      final target = topInset +
                          art.stops[index].dy * worldHeight -
                          view.maxHeight * .57;
                      _camera.jumpTo(
                          target.clamp(0, _camera.position.maxScrollExtent));
                      if (_cameraX.hasClients) {
                        final targetX = art.stops[index].dx * worldWidth -
                            view.maxWidth / 2;
                        _cameraX.jumpTo(targetX.clamp(
                            0, _cameraX.position.maxScrollExtent));
                      }
                    });
                  }
                  return ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: const {
                        ui.PointerDeviceKind.touch,
                        ui.PointerDeviceKind.mouse,
                        ui.PointerDeviceKind.trackpad,
                        ui.PointerDeviceKind.stylus,
                      },
                    ),
                    child: RefreshIndicator(
                        // Flutter web retains a native semantic scroll offset when
                        // the map changes size. Recreate that scroll surface so its
                        // touch coordinates follow the newly laid out artwork.
                        key: ValueKey(
                            'atlas-camera-${map.region.code}-${view.maxWidth}-${view.maxHeight}-$_closer'),
                        onRefresh: widget.onRefresh,
                        child: SingleChildScrollView(
                          key: const ValueKey('expedition-world-map'),
                          controller: _camera,
                          padding: EdgeInsets.only(
                              top: topInset, bottom: bottomInset),
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: SingleChildScrollView(
                            key: const ValueKey('atlas-horizontal-view'),
                            controller: _cameraX,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: worldWidth,
                              height: worldHeight,
                              child:
                                  Stack(clipBehavior: Clip.hardEdge, children: [
                                Positioned(
                                    left: left,
                                    top: 0,
                                    width: worldWidth,
                                    height: worldHeight,
                                    child: Image.asset(art.asset,
                                        fit: BoxFit.fill,
                                        excludeFromSemantics: true,
                                        filterQuality: FilterQuality.medium)),
                                for (final stage in map.stages)
                                  if (stage.no >= 1 &&
                                      stage.no <= art.stops.length)
                                    Positioned(
                                      left: left +
                                          art.stops[stage.no - 1].dx *
                                              worldWidth -
                                          34,
                                      top: art.stops[stage.no - 1].dy *
                                              worldHeight -
                                          34,
                                      width: 68,
                                      height: 68,
                                      child: _AtlasStop(
                                        key:
                                            ValueKey('stage-point-${stage.no}'),
                                        stage: stage,
                                        current: stage.no == selected?.no,
                                        busy: widget.busy,
                                        onTap: () => setState(
                                            () => _selectedNo = stage.no),
                                      ),
                                    ),
                                if (current != null && leader != null)
                                  Positioned(
                                    left: left +
                                        art.stops[(current.no - 1).clamp(0, 7)]
                                                .dx *
                                            worldWidth -
                                        86,
                                    top: art.stops[(current.no - 1).clamp(0, 7)]
                                                .dy *
                                            worldHeight -
                                        116,
                                    width: 120,
                                    height: 134,
                                    child: IgnorePointer(
                                        child: Semantics(
                                      label:
                                          '${leader.name}, 현재 위치 ${current.title}',
                                      image: true,
                                      child: ExcludeSemantics(
                                          child: PlantView(
                                        key: const ValueKey(
                                            'atlas-party-leader'),
                                        stage: leader.stage,
                                        form: PlantGrowthForm.fromCode(
                                            leader.form),
                                        speciesCode: leader.speciesCode,
                                        speciesName: leader.speciesName,
                                        outfitKey: leader.outfitKey,
                                        spritePose: PlantSpritePose.idle,
                                        width: 120,
                                        height: 134,
                                      )),
                                    )),
                                  ),
                              ]),
                            ),
                          ),
                        )),
                  );
                }),
              ),
              Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.onBack != null) ...[
                          _AtlasTool(
                              icon: Icons.arrow_back_rounded,
                              label: '탐험으로',
                              onTap: widget.onBack!),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child: _AtlasRegionButton(
                                    map: map,
                                    onTap: widget.busy || widget.resume
                                        ? null
                                        : widget.onRegions))),
                        const SizedBox(width: 8),
                        _AtlasTool(
                            key: const ValueKey('atlas-journal'),
                            icon: Icons.menu_book_rounded,
                            label: '현장 수첩',
                            onTap: widget.busy ? null : widget.onJournal),
                        const SizedBox(width: 6),
                        _AtlasTool(
                            key: const ValueKey('atlas-routes'),
                            icon: Icons.more_horiz_rounded,
                            label: '다른 탐험',
                            onTap: widget.busy ? null : widget.onRoutes),
                      ])),
              Positioned(
                  top: 84,
                  right: 12,
                  child: _AtlasTool(
                      key: const ValueKey('atlas-zoom'),
                      icon: _closer
                          ? Icons.zoom_out_rounded
                          : Icons.zoom_in_rounded,
                      label: _closer ? '지도 축소' : '지도 확대',
                      onTap: () => setState(() => _closer = !_closer))),
              if (!wide)
                Positioned(left: 12, right: 12, bottom: 12, child: dock()),
            ]),
          ),
          if (wide)
            SizedBox(
                width: 288,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('탐험대',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(color: _atlasPaper)),
                        const SizedBox(height: 24),
                        if (leader != null) ...[
                          PlantView(
                              stage: leader.stage,
                              form: PlantGrowthForm.fromCode(leader.form),
                              speciesCode: leader.speciesCode,
                              speciesName: leader.speciesName,
                              outfitKey: leader.outfitKey,
                              width: 160,
                              height: 190),
                          Text(leader.name,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: _atlasPaper)),
                        ],
                        const Spacer(),
                        dock(vertical: true),
                      ]),
                )),
        ]);
      }),
    );
  }
}

class _AtlasRegionButton extends StatelessWidget {
  const _AtlasRegionButton({required this.map, required this.onTap});
  final ExpeditionStageMap map;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: _atlasPaper,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: const ValueKey('atlas-regions'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                          child: Text(map.region.shortName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: _atlasInk))),
                      const Icon(Icons.expand_more_rounded,
                          color: _atlasInk, size: 18),
                    ]),
                    const SizedBox(height: 2),
                    Text('${map.clearedCount}/${map.total}곳 탐험',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: _atlasInk)),
                  ])),
        ),
      );
}

class _AtlasTool extends StatelessWidget {
  const _AtlasTool(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
      color: _atlasPaper,
      borderRadius: BorderRadius.circular(14),
      child: IconButton(
          tooltip: label,
          onPressed: onTap,
          icon: Icon(icon, color: _atlasInk, size: 23),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48)));
}

class _AtlasStop extends StatelessWidget {
  const _AtlasStop(
      {super.key,
      required this.stage,
      required this.current,
      required this.busy,
      required this.onTap});
  final ExpeditionStage stage;
  final bool current;
  final bool busy;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final locked = !stage.unlocked;
    void select() {
      HapticFeedback.selectionClick();
      onTap();
    }

    return Semantics(
      container: true,
      button: true,
      enabled: !busy,
      onTap: busy ? null : select,
      label:
          '${stage.label}, ${stage.title}. ${locked ? stage.lockReason ?? '잠김' : stage.cleared ? '탐험 완료' : '다음 목적지'}',
      child: ExcludeSemantics(
          child: Material(
        color: Colors.transparent,
        child: InkResponse(
            onTap: busy ? null : select,
            radius: 28,
            child: Align(
                alignment: Alignment.center,
                child: AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  width: current ? 42 : 28,
                  height: current ? 42 : 28,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: current
                          ? const Color(0xFFD8D8D8)
                          : stage.cleared
                              ? _atlasInk
                              : _atlasPaper,
                      border: Border.all(
                          color: current ? _atlasInk : const Color(0xFF929BAB),
                          width: current ? 2.5 : 1.5)),
                  child: Center(
                      child: locked || stage.cleared
                          ? Icon(
                              locked
                                  ? Icons.lock_outline_rounded
                                  : Icons.check_rounded,
                              color: stage.cleared && !current
                                  ? _atlasPaper
                                  : _atlasInk,
                              size: current ? 22 : 15)
                          : Text('${stage.no}',
                              style: TextStyle(
                                  color: _atlasInk,
                                  fontSize: current ? 17 : 13,
                                  fontWeight: FontWeight.w800))),
                ))),
      )),
    );
  }
}

class _AtlasDepartureDock extends StatelessWidget {
  const _AtlasDepartureDock(
      {required this.stage,
      required this.completed,
      required this.busy,
      required this.resume,
      required this.blockedByRun,
      required this.onDepart,
      required this.onParty,
      required this.onRegions,
      required this.onDetails,
      this.vertical = false});
  final ExpeditionStage? stage;
  final bool completed;
  final bool busy;
  final bool resume;
  final bool blockedByRun;
  final VoidCallback onDepart;
  final VoidCallback onParty;
  final VoidCallback onRegions;
  final VoidCallback? onDetails;
  final bool vertical;
  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final locked = stage?.unlocked != true || blockedByRun;
    final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
              resume
                  ? '탐험 중'
                  : completed
                      ? '지역 탐험 완료'
                      : stage?.label ?? '탐험',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: _atlasInk)),
          const SizedBox(height: 3),
          Text(completed && !resume ? '다음 지역으로' : stage?.title ?? '목적지 고르기',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: _atlasInk)),
          if (locked && !completed) ...[
            const SizedBox(height: 6),
            Text(
                blockedByRun
                    ? '진행 중인 탐험을 마치면 출발할 수 있어요.'
                    : stage?.lockReason ?? '앞 장소를 탐험하면 열려요.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: _atlasInk)),
          ],
        ]);
    final controls = Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          if (!completed && !resume && !locked)
            IconButton(
                key: const ValueKey('hub-choose-stage'),
                tooltip: '탐험대 편성',
                onPressed: busy ? null : onParty,
                icon: const Icon(Icons.groups_outlined, color: _atlasInk)),
          if (!completed && onDetails != null)
            TextButton(
                onPressed: busy ? null : onDetails,
                style: TextButton.styleFrom(foregroundColor: _atlasInk),
                child: const Text('살펴보기')),
          FilledButton(
              key: const ValueKey('hub-continue-card'),
              onPressed: busy || (locked && !completed)
                  ? null
                  : completed && !resume
                      ? onRegions
                      : onDepart,
              style: FilledButton.styleFrom(
                  backgroundColor: _atlasAction,
                  foregroundColor: _atlasPaper,
                  minimumSize: const Size(104, 52),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _atlasPaper))
                  : Text(resume
                      ? '계속하기'
                      : completed
                          ? '지역 선택'
                          : locked
                              ? '잠김'
                              : '탐험하기')),
        ]);
    return Material(
      key: const ValueKey('atlas-departure-dock'),
      color: _atlasPaper,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFDEE2E9))),
      child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
          child: vertical || large || MediaQuery.sizeOf(context).width < 600
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [heading, const SizedBox(height: 8), controls])
              : Row(children: [
                  Expanded(child: heading),
                  const SizedBox(width: 8),
                  SizedBox(width: 280, child: controls)
                ])),
    );
  }
}
