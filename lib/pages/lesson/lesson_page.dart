import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../services/tts_service.dart';
import '../../widgets/common.dart';
import 'dialogue_view.dart';
import 'exchanges_view.dart';
import 'lesson_controller.dart';
import 'practice_view.dart';
import 'words_view.dart';

/// 一天的课程：单词 / 听说 / 对话 / 测验 四个标签
class LessonPage extends StatefulWidget {
  const LessonPage({super.key, required this.courseId, required this.day});

  final String courseId;
  final int day;

  @override
  State<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends State<LessonPage>
    with SingleTickerProviderStateMixin {
  late final String _tag = 'lesson-${widget.courseId}-${widget.day}';
  late final LessonController _c =
      Get.put(LessonController(widget.courseId, widget.day), tag: _tag);
  late final TabController _tabs = TabController(length: 4, vsync: this)
    // 切换标签时停止朗读，免得上一页的连续播放还在响
    ..addListener(() {
      if (_tabs.indexIsChanging) TtsService.to.stop();
    });

  @override
  void dispose() {
    _tabs.dispose();
    Get.delete<LessonController>(tag: _tag);
    super.dispose();
  }

  /// 空格：轮到你说时 = “我说完了”；正在读 = 停止；否则播放当前标签的全部内容
  void _onSpace() {
    final tts = TtsService.to;
    if (_c.waitingForMe.value) {
      _c.finishMyTurn();
    } else if (tts.sequenceRunning.value || tts.speaking.value != null) {
      tts.stop();
    } else {
      switch (_tabs.index) {
        case 0:
          _c.playWords();
        case 1:
          _c.playExchanges();
        case 2:
          _c.playDialogue();
        case 3:
          PracticeView.startQuiz(_c);
      }
    }
  }

  /// Esc：正在读就停止，否则返回上一页
  void _onEscape() {
    final tts = TtsService.to;
    if (tts.sequenceRunning.value || tts.speaking.value != null) {
      tts.stop();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): _onSpace,
        const SingleActivator(LogicalKeyboardKey.escape): _onEscape,
        // R：在对话标签开始角色扮演
        const SingleActivator(LogicalKeyboardKey.keyR): () {
          if (_tabs.index == 2 && !TtsService.to.sequenceRunning.value) {
            _c.rolePlay();
          }
        },
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_tabs.index == 3) PracticeView.startQuiz(_c);
        },
      },
      child: Focus(autofocus: true, child: _buildPage(context)),
    );
  }

  Widget _buildPage(BuildContext context) {
    final lesson = _c.lesson;
    final phase = _c.course.phaseOf(lesson.day);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_c.course.title} · 第 ${lesson.day} 课 · ${phase.name}',
                style: TextStyle(fontSize: 12, color: Color(phase.colorValue))),
            Text(lesson.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
        // 桌面宽窗口时标签栏和下面的内容一样宽、居中，不铺满整行
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kTextTabBarHeight),
          child: MaxWidth(
            width: 760,
            child: TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: '单词'),
                Tab(text: '听说'),
                Tab(text: '对话'),
                Tab(text: '测验'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          WordsView(c: _c),
          ExchangesView(c: _c),
          DialogueView(c: _c),
          PracticeView(c: _c),
        ],
      ),
    );
  }
}
