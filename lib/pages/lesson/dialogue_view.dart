import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../models/lesson.dart';
import '../../services/tts_service.dart';
import '../../widgets/common.dart';
import 'lesson_controller.dart';

/// 对话标签：聊天气泡。可以听完整对话，也可以角色扮演（你说“我”的部分）
class DialogueView extends StatefulWidget {
  const DialogueView({super.key, required this.c});

  final LessonController c;

  @override
  State<DialogueView> createState() => _DialogueViewState();
}

class _DialogueViewState extends State<DialogueView> {
  LessonController get c => widget.c;

  late final List<GlobalKey> _keys = [for (final _ in c.lines) GlobalKey()];
  late final Worker _follow;

  @override
  void initState() {
    super.initState();
    // 播放或角色扮演到哪一行，就把那一行滚到屏幕中间
    _follow = ever<int>(c.lineIndex, (i) {
      if (i < 0) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _keys[i].currentContext;
        if (!mounted || context == null) return;
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    });
  }

  @override
  void dispose() {
    _follow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dialogue = c.lesson.dialogue;
    final scheme = Theme.of(context).colorScheme;
    return MaxWidth(
      child: Column(
        children: [
          Expanded(
            // 不用 ListView：它只构建屏幕附近的行，屏幕外的行拿不到 context，
            // 没法自动滚过去。对话最多十几行，全部构建也没负担
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.forum_outlined, color: scheme.primary, size: 20),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(dialogue.title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ]),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text('左边：${dialogue.other}　右边：我',
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.onSurfaceVariant)),
                  ),
                  for (var i = 0; i < c.lines.length; i++)
                    _Bubble(
                        key: _keys[i],
                        index: i,
                        line: c.lines[i],
                        other: dialogue.other,
                        c: c),
                ],
              ),
            ),
          ),
          _DialogueBar(c: c),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.index,
    required this.line,
    required this.other,
    required this.c,
  });

  final int index;
  final DialogueLine line;
  final String other;
  final LessonController c;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final me = line.isMe;
    return Obx(() {
      final current = c.lineIndex.value == index;
      // 角色扮演时，“我”的英文要等你自己说过（听完示范）才显示
      final hideEn =
          me && c.rolePlaying.value && !c.spokenLines.contains(index);
      final myTurn = current && c.waitingForMe.value;
      final bg = me ? scheme.primaryContainer : scheme.surfaceContainerHigh;
      final title = '${line.en}\n${line.zh}';

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment:
              me ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!me)
              _Avatar(label: (line.who ?? other).characters.first, me: false),
            // 标注按钮放在气泡外侧：别人的话在右边，自己的话在左边
            if (me && !hideEn)
              AnnotationButton(line.key, title: title, compact: true),
            Flexible(
              child: GestureDetector(
                onTap: hideEn ? null : () => c.sayLine(index),
                onLongPress: hideEn
                    ? null
                    : () => editAnnotation(context, line.key, title: title),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  constraints: const BoxConstraints(maxWidth: 520),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(me ? 16 : 4),
                      bottomRight: Radius.circular(me ? 4 : 16),
                    ),
                    border: Border.all(
                      color: current ? scheme.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (line.who != null)
                        Text(line.who!,
                            style: TextStyle(
                                fontSize: 11.5, color: scheme.tertiary)),
                      if (myTurn)
                        Text('轮到你说：',
                            style: TextStyle(
                                fontSize: 12,
                                color: scheme.primary,
                                fontWeight: FontWeight.bold)),
                      if (hideEn)
                        Text(line.zh,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: myTurn
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant))
                      else ...[
                        Text(line.en,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(line.zh,
                            style: TextStyle(
                                fontSize: 13, color: scheme.onSurfaceVariant)),
                        AnnotationView(line.key, title: title),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (!me && !hideEn)
              AnnotationButton(line.key, title: title, compact: true),
            if (me) const _Avatar(label: '我', me: true),
          ],
        ),
      );
    });
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, required this.me});

  final String label;
  final bool me;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 16,
      backgroundColor: me ? scheme.primary : scheme.tertiaryContainer,
      foregroundColor: me ? scheme.onPrimary : scheme.onTertiaryContainer,
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}

class _DialogueBar extends StatelessWidget {
  const _DialogueBar({required this.c});

  final LessonController c;

  @override
  Widget build(BuildContext context) {
    final tts = TtsService.to;
    return Material(
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Obx(() {
            if (c.waitingForMe.value) {
              return Row(children: [
                IconButton.outlined(
                  tooltip: '停止',
                  onPressed: tts.stop,
                  icon: const Icon(Icons.stop_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: c.finishMyTurn,
                    icon: const Icon(Icons.mic_none_rounded),
                    label: Text(isDesktop ? '我说完了，听示范（空格）' : '我说完了，听示范'),
                  ),
                ),
              ]);
            }
            if (tts.sequenceRunning.value) {
              return SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: tts.stop,
                  icon: const Icon(Icons.stop_rounded),
                  label: Text(c.rolePlaying.value ? '停止角色扮演' : '停止播放'),
                ),
              );
            }
            return Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: c.playDialogue,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(isDesktop ? '听完整对话（空格）' : '听完整对话'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: c.rolePlay,
                  icon: const Icon(Icons.theater_comedy_outlined),
                  label: Text(isDesktop ? '角色扮演（R）' : '角色扮演'),
                ),
              ),
            ]);
          }),
        ),
      ),
    );
  }
}
