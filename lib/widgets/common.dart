import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/progress_service.dart';
import '../services/tts_service.dart';

/// 窗口够宽（平板横屏、Windows 桌面）时用侧边导航
const kSideNavWidth = 640.0;

/// 计划页分两栏显示的宽度
const kTwoColumnWidth = 1000.0;

/// 是否运行在桌面系统上（显示快捷键提示用）
bool get isDesktop => switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux =>
        true,
      _ => false,
    };

/// 课程 JSON 里的 icon 名 → 图标
IconData lessonIcon(String name) => switch (name) {
      'waving' => Icons.waving_hand_outlined,
      'money' => Icons.payments_outlined,
      'badge' => Icons.badge_outlined,
      'flight_takeoff' => Icons.flight_takeoff,
      'security' => Icons.security,
      'airline_seat' => Icons.airline_seat_recline_normal,
      'connecting' => Icons.connecting_airports,
      'work' => Icons.work_outline,
      'customs' => Icons.inventory_2_outlined,
      'luggage' => Icons.luggage_outlined,
      'review' => Icons.replay,
      'taxi' => Icons.local_taxi_outlined,
      'hotel' => Icons.hotel_outlined,
      'key' => Icons.key_outlined,
      'room_service' => Icons.room_service_outlined,
      'build' => Icons.build_outlined,
      'receipt' => Icons.receipt_long_outlined,
      'directions' => Icons.directions_outlined,
      'restaurant' => Icons.restaurant_outlined,
      'shopping' => Icons.shopping_bag_outlined,
      'emergency' => Icons.local_hospital_outlined,
      'handshake' => Icons.handshake_outlined,
      'phone' => Icons.phone_in_talk_outlined,
      'flag' => Icons.flag_outlined,
      // 基础入门
      'abc' => Icons.abc,
      'numbers' => Icons.pin_outlined,
      'person' => Icons.person_outline,
      'chat' => Icons.chat_bubble_outline,
      'question' => Icons.help_outline,
      'calendar' => Icons.calendar_today_outlined,
      'family' => Icons.family_restroom,
      'mood' => Icons.mood,
      // 日常沟通
      'weather' => Icons.wb_sunny_outlined,
      'hobby' => Icons.palette_outlined,
      'event' => Icons.event_available_outlined,
      'home' => Icons.home_outlined,
      'cooking' => Icons.soup_kitchen_outlined,
      'cart' => Icons.shopping_cart_outlined,
      'coffee' => Icons.local_cafe_outlined,
      'commute' => Icons.directions_bus_outlined,
      'bank' => Icons.account_balance_outlined,
      'doctor' => Icons.medical_services_outlined,
      'services' => Icons.content_cut,
      'message' => Icons.sms_outlined,
      'opinion' => Icons.lightbulb_outline,
      'request' => Icons.pan_tool_outlined,
      'thanks' => Icons.volunteer_activism_outlined,
      'history' => Icons.history,
      'future' => Icons.update,
      'describe' => Icons.face_outlined,
      // 课程图标
      'school' => Icons.school_outlined,
      'forum' => Icons.forum_outlined,
      _ => Icons.menu_book_outlined,
    };

/// 语速按钮（课程页、测验页顶部）：显示当前倍速，点开调快调慢
class SpeedButton extends StatelessWidget {
  const SpeedButton({super.key});

  @override
  Widget build(BuildContext context) {
    final progress = ProgressService.to;
    return Obx(() => TextButton.icon(
          key: const ValueKey('speed-button'),
          onPressed: () => showSpeedPanel(context),
          icon: const Icon(Icons.speed, size: 20),
          label: Text('${progress.speed.value.toStringAsFixed(1)}x'),
        ));
  }
}

/// 从底部弹出语速面板
Future<void> showSpeedPanel(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const SpeedPanel(),
    );

/// 语速面板：滑块、调慢 / 调快按钮、快捷档位、试听。
/// 改了马上保存；正在连续播放时从下一句开始按新语速读
class SpeedPanel extends StatelessWidget {
  const SpeedPanel({super.key});

  static const sample = 'Could you speak more slowly, please?';

  @override
  Widget build(BuildContext context) {
    final progress = ProgressService.to;
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final v = progress.speed.value;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('语速', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('${v.toStringAsFixed(1)}x',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: scheme.primary)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                IconButton.outlined(
                  tooltip: '调慢',
                  onPressed: v > ProgressService.minSpeed
                      ? () => progress.changeSpeed(-1)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                Expanded(
                  child: Slider(
                    value: v,
                    min: ProgressService.minSpeed,
                    max: ProgressService.maxSpeed,
                    divisions:
                        ((ProgressService.maxSpeed - ProgressService.minSpeed) *
                                10)
                            .round(),
                    label: '${v.toStringAsFixed(1)}x',
                    onChanged: progress.setSpeed,
                  ),
                ),
                IconButton.outlined(
                  tooltip: '调快',
                  onPressed: v < ProgressService.maxSpeed
                      ? () => progress.changeSpeed(1)
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ]),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (speed, label) in ProgressService.speedPresets)
                    ChoiceChip(
                      label: Text('$label ${speed.toStringAsFixed(1)}x'),
                      selected: v == speed,
                      onSelected: (_) => progress.setSpeed(speed),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(children: [
                FilledButton.tonalIcon(
                  onPressed: () => TtsService.to.say(sample),
                  icon: const Icon(Icons.volume_up_outlined),
                  label: const Text('试听'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isDesktop
                        ? '刚开始用 0.7x–0.9x 听清每个词，熟练后调到 1.0x 以上。快捷键：- 调慢，= 调快'
                        : '刚开始用 0.7x–0.9x 听清每个词，熟练后调到 1.0x 以上',
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                ),
              ]),
            ],
          ),
        ),
      );
    });
  }
}

/// 朗读按钮：正在读这句时显示声波图标，再点一下停止
class SpeakButton extends StatelessWidget {
  const SpeakButton(this.text, {super.key, this.speed, this.tooltip = '朗读'});

  final String text;
  final double? speed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final tts = TtsService.to;
    return Obx(() {
      final active = tts.speaking.value == text;
      return IconButton(
        tooltip: active ? '停止' : tooltip,
        icon: Icon(active ? Icons.graphic_eq : Icons.volume_up_outlined),
        color: active ? Theme.of(context).colorScheme.primary : null,
        onPressed: () => active ? tts.stop() : tts.say(text, speed: speed),
      );
    });
  }
}

/// 生词本收藏按钮
class NoteButton extends StatelessWidget {
  const NoteButton(this.itemKey, {super.key});

  final String itemKey;

  @override
  Widget build(BuildContext context) {
    final progress = ProgressService.to;
    return Obx(() {
      final saved = progress.notebook.containsKey(itemKey);
      return IconButton(
        tooltip: saved ? '移出生词本' : '加入生词本',
        icon: Icon(saved ? Icons.star_rounded : Icons.star_outline_rounded),
        color: saved ? Colors.amber.shade700 : null,
        onPressed: () => progress.toggleNote(itemKey),
      );
    });
  }
}

/// 平板和 Windows 上限制内容宽度，避免一行字拉得太长
class MaxWidth extends StatelessWidget {
  const MaxWidth({super.key, required this.child, this.width = 720});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: child,
        ),
      );
}

/// 被遮住的文字：点一下显示
class HiddenText extends StatelessWidget {
  const HiddenText({super.key, this.label = '点击显示'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
    );
  }
}

/// 列表里的小节标题
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: Theme.of(context).colorScheme.primary)),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// 条目下面显示的标注。没有标注时什么都不显示；点一下可以修改
class AnnotationView extends StatelessWidget {
  const AnnotationView(this.itemKey,
      {super.key, this.title, this.padding = const EdgeInsets.only(top: 6)});

  final String itemKey;

  /// 编辑框标题里显示的原文
  final String? title;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final progress = ProgressService.to;
    return Obx(() {
      final text = progress.annotations[itemKey]?.text;
      if (text == null) return const SizedBox.shrink();
      final scheme = Theme.of(context).colorScheme;
      return Padding(
        padding: padding,
        child: Material(
          color: Colors.amber.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => editAnnotation(context, itemKey, title: title),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.edit_note, size: 18, color: Colors.amber.shade800),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(text,
                        style: TextStyle(
                            fontSize: 13.5,
                            color: scheme.onSurface,
                            height: 1.35)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// 加标注 / 改标注的按钮。已经有标注时图标是实心的
class AnnotationButton extends StatelessWidget {
  const AnnotationButton(this.itemKey,
      {super.key, this.title, this.size, this.compact = false});

  final String itemKey;
  final String? title;
  final double? size;

  /// 小号按钮（对话气泡旁边用），不占 48 的点击区域
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final progress = ProgressService.to;
    return Obx(() {
      final has = progress.annotations.containsKey(itemKey);
      return IconButton(
        tooltip: has ? '修改标注' : '加标注',
        iconSize: size ?? (compact ? 20 : null),
        visualDensity: compact ? VisualDensity.compact : null,
        padding: compact ? EdgeInsets.zero : null,
        constraints:
            compact ? const BoxConstraints(minWidth: 32, minHeight: 32) : null,
        icon: Icon(has ? Icons.edit_note : Icons.edit_note_outlined),
        color: has ? Colors.amber.shade800 : null,
        onPressed: () => editAnnotation(context, itemKey, title: title),
      );
    });
  }
}

/// 弹出编辑框写标注。保存空内容 = 删除标注
Future<void> editAnnotation(BuildContext context, String itemKey,
    {String? title}) async {
  final progress = ProgressService.to;
  final result = await showDialog<String>(
    context: context,
    builder: (context) => _AnnotationDialog(
        title: title, initialText: progress.annotationOf(itemKey) ?? ''),
  );
  if (result != null) progress.setAnnotation(itemKey, result);
}

class _AnnotationDialog extends StatefulWidget {
  const _AnnotationDialog({required this.title, required this.initialText});

  final String? title;
  final String initialText;

  @override
  State<_AnnotationDialog> createState() => _AnnotationDialogState();
}

class _AnnotationDialogState extends State<_AnnotationDialog> {
  // 对话框自己持有输入框的 controller，关闭（淡出动画结束）后随 State 一起释放
  late final _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    return AlertDialog(
      title: const Text('我的标注'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: '写点什么：谐音、例句、什么场合用、容易错的地方……',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.initialText.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: Text('删除',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('保存')),
      ],
    );
  }
}
