import 'dart:async';

import 'package:get/get.dart';

import '../../data/lesson_repository.dart';
import '../../models/lesson.dart';
import '../../services/tts_service.dart';

/// 一天课程页面的状态：遮挡开关、连续播放、对话角色扮演
class LessonController extends GetxController {
  LessonController(this.courseId, this.day);

  final String courseId;
  final int day;
  final _repo = LessonRepository.to;
  final _tts = TtsService.to;

  late final Lesson lesson = _repo.lesson(courseId, day);
  late final Course course = _repo.course(courseId);

  /// 复习日是复习范围内全部的单词和问答
  late final List<Word> words = _repo.wordsFor(lesson);
  late final List<Exchange> exchanges = _repo.exchangesFor(lesson);
  List<DialogueLine> get lines => lesson.dialogue.lines;

  /// 单词页：遮住中文，先听再想意思
  final hideZh = false.obs;

  /// 听说页：盲听模式，先只听声音，自己回答后再看文字
  final blind = false.obs;

  /// 遮挡模式下点开看过的条目
  final revealed = <String>{}.obs;

  /// 对话里正在读（或轮到你说）的那一行，-1 = 没有
  final lineIndex = (-1).obs;

  /// 角色扮演中
  final rolePlaying = false.obs;

  /// 角色扮演：轮到你说了，等你点“我说完了”
  final waitingForMe = false.obs;

  /// 角色扮演：你已经说过（听过示范）的行，英文才显示出来
  final spokenLines = <int>{}.obs;

  Completer<void>? _myTurn;
  late final Worker _sequenceWorker;

  @override
  void onInit() {
    super.onInit();
    // 用户在别处点了单句播放或停止，连续播放会被打断（sequenceRunning 变 false），
    // 这时如果角色扮演正在等你说话，要把等待也结束掉
    _sequenceWorker = ever<bool>(_tts.sequenceRunning, (running) {
      if (!running) _releaseMyTurn();
    });
  }

  @override
  void onClose() {
    _sequenceWorker.dispose();
    _releaseMyTurn();
    // onClose 是在页面 dispose 里调的，这时 widget 树是锁住的；stop() 会改
    // speaking 等 Rx，触发别的页面上的 Obx 重建就会报 “widget tree was locked”。
    // 放到微任务里，等这一帧结束再停
    Future.microtask(_tts.stop);
    super.onClose();
  }

  bool isRevealed(String key) => revealed.contains(key);

  void reveal(String key) => revealed.add(key);

  void toggleHideZh() {
    hideZh.toggle();
    revealed.clear();
  }

  void toggleBlind() {
    blind.toggle();
    revealed.clear();
  }

  Future<void> stop() => _tts.stop();

  Future<void> playWords() async {
    _resetDialogue();
    final seq = _tts.beginSequence();
    for (final word in words) {
      if (!await _tts.sayInSequence(seq, word.en)) break;
      if (!await _tts.pause(seq, const Duration(milliseconds: 800))) break;
    }
    _tts.endSequence(seq);
  }

  /// 每组问答：对方说 → 停一下（留时间自己回答）→ 示范回答
  Future<void> playExchanges() async {
    _resetDialogue();
    final seq = _tts.beginSequence();
    for (final e in exchanges) {
      if (!await _tts.sayInSequence(seq, e.hear)) break;
      if (!await _tts.pause(seq, const Duration(milliseconds: 1500))) break;
      if (!await _tts.sayInSequence(seq, e.reply)) break;
      if (!await _tts.pause(seq, const Duration(milliseconds: 1000))) break;
    }
    _tts.endSequence(seq);
  }

  Future<void> playDialogue() async {
    _resetDialogue();
    final seq = _tts.beginSequence();
    for (var i = 0; i < lines.length; i++) {
      lineIndex.value = i;
      if (!await _tts.sayInSequence(seq, lines[i].en)) break;
      if (!await _tts.pause(seq, const Duration(milliseconds: 500))) break;
    }
    if (_tts.isActive(seq)) lineIndex.value = -1;
    _tts.endSequence(seq);
  }

  /// 角色扮演：对方的话自动播放；轮到你时只显示中文，你说完点按钮，再播放示范
  Future<void> rolePlay() async {
    _resetDialogue();
    rolePlaying.value = true;
    final seq = _tts.beginSequence();
    for (var i = 0; i < lines.length; i++) {
      if (!_tts.isActive(seq)) break;
      lineIndex.value = i;
      if (lines[i].isMe) {
        waitingForMe.value = true;
        _myTurn = Completer<void>();
        await _myTurn!.future;
        waitingForMe.value = false;
        if (!_tts.isActive(seq)) break;
        spokenLines.add(i);
      }
      if (!await _tts.sayInSequence(seq, lines[i].en)) break;
      if (!await _tts.pause(seq, const Duration(milliseconds: 500))) break;
    }
    if (_tts.isActive(seq)) {
      // 正常结束：全部英文都显示出来
      lineIndex.value = -1;
      spokenLines.addAll([for (var i = 0; i < lines.length; i++) i]);
    }
    // 被另一段连续播放接管时，状态已经由它重置过，不要再改
    if (_tts.isActive(seq) || !_tts.sequenceRunning.value) {
      rolePlaying.value = false;
    }
    _tts.endSequence(seq);
  }

  /// 角色扮演中你说完了，播放示范
  void finishMyTurn() => _releaseMyTurn();

  /// 点对话里的某一行：单独读这一行（会打断连续播放）
  void sayLine(int index) {
    lineIndex.value = index;
    _tts.say(lines[index].en).then((_) {
      if (lineIndex.value == index && !_tts.sequenceRunning.value) {
        lineIndex.value = -1;
      }
    });
  }

  void _resetDialogue() {
    _releaseMyTurn();
    rolePlaying.value = false;
    waitingForMe.value = false;
    lineIndex.value = -1;
    spokenLines.clear();
  }

  void _releaseMyTurn() {
    final turn = _myTurn;
    _myTurn = null;
    if (turn != null && !turn.isCompleted) turn.complete();
  }
}
