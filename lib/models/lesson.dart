/// 一门课：基础入门 / 日常沟通 / 旅行出行，对应 assets/courses/courses.json 里的一项
class Course {
  Course({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.phases,
  });

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        id: json['id'] as String,
        title: json['title'] as String,
        subtitle: json['subtitle'] as String? ?? '',
        icon: json['icon'] as String? ?? '',
        phases: [
          for (final p in json['phases'] as List)
            Phase.fromJson(p as Map<String, dynamic>),
        ],
      );

  /// 目录名，课程文件在 assets/courses/{id}/dayNN.json
  final String id;
  final String title;
  final String subtitle;
  final String icon;
  final List<Phase> phases;

  /// 由 LessonRepository 读完 JSON 后填进来
  late final List<Lesson> lessons;

  int get totalDays => phases.last.to;

  Phase phaseOf(int day) => phases.firstWhere((p) => p.contains(day));
}

/// 一门课里分成的几个阶段
class Phase {
  const Phase(this.name, this.from, this.to, this.colorValue);

  /// color 写成 "5C6BC0" 这样的十六进制
  factory Phase.fromJson(Map<String, dynamic> json) => Phase(
        json['name'] as String,
        json['from'] as int,
        json['to'] as int,
        0xFF000000 | int.parse(json['color'] as String, radix: 16),
      );

  final String name;
  final int from;
  final int to;
  final int colorValue;

  bool contains(int day) => day >= from && day <= to;
}

/// 一课，对应 assets/courses/{course}/dayNN.json
class Lesson {
  const Lesson({
    required this.course,
    required this.day,
    required this.title,
    required this.en,
    required this.icon,
    required this.goal,
    required this.tips,
    required this.words,
    required this.exchanges,
    required this.dialogue,
    this.reviewFrom,
    this.reviewTo,
  });

  factory Lesson.fromJson(Map<String, dynamic> json, String course) {
    final day = json['day'] as int;
    final review = (json['review'] as List?)?.cast<int>();
    return Lesson(
      course: course,
      day: day,
      title: json['title'] as String,
      en: json['en'] as String,
      icon: json['icon'] as String? ?? '',
      goal: json['goal'] as String,
      tips: (json['tips'] as List? ?? const []).cast<String>(),
      words: [
        for (final w in json['words'] as List? ?? const [])
          Word.fromJson(w as Map<String, dynamic>, course, day),
      ],
      exchanges: [
        for (final e in json['exchanges'] as List? ?? const [])
          Exchange.fromJson(e as Map<String, dynamic>, course, day),
      ],
      dialogue: Dialogue.fromJson(
          json['dialogue'] as Map<String, dynamic>, course, day),
      reviewFrom: review?.first,
      reviewTo: review?.last,
    );
  }

  /// 所属课程的 id
  final String course;

  /// 课内序号（第几课）
  final int day;
  final String title;

  /// 英文标题，比如 Airport Check-in
  final String en;

  /// 图标名，见 lib/widgets/common.dart 的 lessonIcon
  final String icon;
  final String goal;
  final List<String> tips;
  final List<Word> words;
  final List<Exchange> exchanges;
  final Dialogue dialogue;

  /// 复习课没有新单词，复习同一门课里 [reviewFrom, reviewTo] 这几课的内容
  final int? reviewFrom;
  final int? reviewTo;

  bool get isReview => reviewFrom != null;

  /// 全局唯一，比如 travel:8。进度、测验成绩都按它存
  String get id => lessonId(course, day);

  static String lessonId(String course, int day) => '$course:$day';
}

/// 能放进生词本、加标注、被搜索到的学习条目
sealed class StudyItem {
  const StudyItem(this.course, this.day);

  final String course;
  final int day;

  String get lessonId => Lesson.lessonId(course, day);

  /// 生词本和标注用的唯一键。用英文原文而不是下标，以后改 JSON 插入新词也不会错位；
  /// 同一句话出现在几课里（比如 Thank you.），共用同一个生词记录和标注
  String get key;

  /// 朗读的英文
  String get en;
  String get zh;
}

/// 单词或词组
class Word extends StudyItem {
  const Word(
      {required this.en,
      required this.zh,
      required String course,
      required int day})
      : super(course, day);

  factory Word.fromJson(Map<String, dynamic> json, String course, int day) =>
      Word(
          en: json['en'] as String,
          zh: json['zh'] as String,
          course: course,
          day: day);

  @override
  final String en;
  @override
  final String zh;

  @override
  String get key => 'w|$en';
}

/// 一组问答：对方说的话 [hear]，和你可以怎么回答 [reply]
class Exchange extends StudyItem {
  const Exchange({
    required this.hear,
    required this.hearZh,
    required this.reply,
    required this.replyZh,
    required String course,
    required int day,
    this.generic = false,
  }) : super(course, day);

  factory Exchange.fromJson(
          Map<String, dynamic> json, String course, int day) =>
      Exchange(
        hear: json['hear'] as String,
        hearZh: json['hearZh'] as String,
        reply: json['reply'] as String,
        replyZh: json['replyZh'] as String,
        generic: json['generic'] as bool? ?? false,
        course: course,
        day: day,
      );

  final String hear;
  final String hearZh;
  final String reply;
  final String replyZh;

  /// 回答很通用（比如 Thank you. / Sorry, I didn't catch that.），放到别的问题下面也说得通。
  /// 这种回答不出“听问题选回答”的题，也不当干扰项，免得一道题有两个对的选项
  final bool generic;

  @override
  String get key => 'e|$hear';

  @override
  String get en => hear;

  @override
  String get zh => hearZh;
}

class Dialogue {
  const Dialogue(
      {required this.title, required this.other, required this.lines});

  factory Dialogue.fromJson(
          Map<String, dynamic> json, String course, int day) =>
      Dialogue(
        title: json['title'] as String,
        other: json['other'] as String,
        lines: [
          for (final l in json['lines'] as List)
            DialogueLine.fromJson(l as Map<String, dynamic>, course, day),
        ],
      );

  final String title;

  /// 对方的身份，比如“移民官”。单句可以用 [DialogueLine.who] 覆盖
  final String other;
  final List<DialogueLine> lines;
}

class DialogueLine extends StudyItem {
  const DialogueLine({
    required this.isMe,
    required this.en,
    required this.zh,
    required String course,
    required int day,
    this.who,
  }) : super(course, day);

  factory DialogueLine.fromJson(
          Map<String, dynamic> json, String course, int day) =>
      DialogueLine(
        isMe: json['s'] == 'me',
        en: json['en'] as String,
        zh: json['zh'] as String,
        who: json['who'] as String?,
        course: course,
        day: day,
      );

  /// true = 我（学习者）说的话，角色扮演时轮到你说
  final bool isMe;
  @override
  final String en;
  @override
  final String zh;
  final String? who;

  @override
  String get key => 'l|$en';
}
