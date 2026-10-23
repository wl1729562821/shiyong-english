import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/lesson_repository.dart';
import '../../models/lesson.dart';
import '../../services/tts_service.dart';
import '../../widgets/common.dart';
import 'lesson_controller.dart';
import 'words_view.dart';

/// 听说标签：每组是“对方说 → 你回答”。盲听模式下先只听声音，自己回答后再点开看
class ExchangesView extends StatelessWidget {
  const ExchangesView({super.key, required this.c});

  final LessonController c;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = LessonRepository.to;
    final rows = <Object>[];
    int? lastDay;
    for (final e in c.exchanges) {
      if (c.lesson.isReview && e.day != lastDay) {
        rows.add(e.day);
        lastDay = e.day;
      }
      rows.add(e);
    }

    return MaxWidth(
      child: Column(
        children: [
          PlayBar(
            left: Obx(() => FilterChip(
                  avatar: const Icon(Icons.hearing, size: 18),
                  label: const Text('盲听模式'),
                  selected: c.blind.value,
                  onSelected: (_) => c.toggleBlind(),
                )),
            onPlay: c.playExchanges,
            playLabel: '全部播放',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Obx(() => Text(
                  c.blind.value
                      ? '先点 ▶ 听对方说什么，大声说出你的回答，再点卡片看答案。'
                      : '全部播放时，每句之后有停顿，跟着说出回答。',
                  style:
                      TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                )),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final row = rows[i];
                if (row is int) {
                  return SectionTitle(
                      '第 $row 课  ${repo.lesson(c.courseId, row).title}');
                }
                return _ExchangeCard(exchange: row as Exchange, c: c);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ExchangeCard extends StatelessWidget {
  const _ExchangeCard({required this.exchange, required this.c});

  final Exchange exchange;
  final LessonController c;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Obx(() {
        final hidden = c.blind.value && !c.isRevealed(exchange.key);
        final speaking = TtsService.to.speaking.value;
        return InkWell(
          onTap: hidden ? () => c.reveal(exchange.key) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Line(
                  label: '对方说',
                  icon: Icons.record_voice_over_outlined,
                  color: scheme.tertiary,
                  en: exchange.hear,
                  zh: exchange.hearZh,
                  hidden: hidden,
                  active: speaking == exchange.hear,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnnotationButton(exchange.key,
                          title: '${exchange.hear}\n${exchange.reply}'),
                      NoteButton(exchange.key),
                    ],
                  ),
                ),
                const Divider(height: 16),
                _Line(
                  label: '你回答',
                  icon: Icons.chat_bubble_outline,
                  color: scheme.primary,
                  en: exchange.reply,
                  zh: exchange.replyZh,
                  hidden: hidden,
                  active: speaking == exchange.reply,
                ),
                if (!hidden)
                  AnnotationView(exchange.key,
                      title: '${exchange.hear}\n${exchange.reply}',
                      padding: const EdgeInsets.only(top: 8, right: 10)),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.icon,
    required this.color,
    required this.en,
    required this.zh,
    required this.hidden,
    required this.active,
    this.trailing,
  });

  final String label;
  final IconData icon;
  final Color color;
  final String en;
  final String zh;
  final bool hidden;
  final bool active;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 12, color: color)),
              ]),
              const SizedBox(height: 4),
              if (hidden)
                const HiddenText(label: '点击卡片显示文字')
              else ...[
                Text(en,
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w600,
                      color: active ? color : null,
                    )),
                const SizedBox(height: 2),
                Text(zh,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
        SpeakButton(en),
        if (trailing != null) trailing!,
      ],
    );
  }
}
