import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/tts_service.dart';
import '../../widgets/common.dart';
import 'notebook_tab.dart';
import 'plan_tab.dart';
import 'search_tab.dart';
import 'settings_tab.dart';

/// 首页：计划、速查、生词本、设置四个标签。
/// 手机上是底部导航栏；窗口够宽（Windows 桌面）时改成左侧导航栏
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  final _searchFocus = FocusNode(debugLabel: 'search');

  static const _items = [
    (Icons.menu_book_outlined, Icons.menu_book, '课程'),
    (Icons.search, Icons.search, '速查'),
    (Icons.star_outline_rounded, Icons.star_rounded, '生词本'),
    (Icons.settings_outlined, Icons.settings, '设置'),
  ];

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  void _select(int i) {
    TtsService.to.stop();
    setState(() => _index = i);
  }

  /// Ctrl+F：跳到速查并把光标放进搜索框
  void _openSearch() {
    _select(1);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final body = IndexedStack(
      index: _index,
      children: [
        const PlanTab(),
        SearchTab(focusNode: _searchFocus),
        const NotebookTab(),
        const SettingsTab(),
      ],
    );

    final Widget page;
    if (width < kSideNavWidth) {
      page = Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: [
            for (final (icon, selected, label) in _items)
              NavigationDestination(
                  icon: Icon(icon), selectedIcon: Icon(selected), label: label),
          ],
        ),
      );
    } else {
      final extended = width >= 1100;
      final scheme = Theme.of(context).colorScheme;
      page = Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: extended,
              minExtendedWidth: 180,
              selectedIndex: _index,
              onDestinationSelected: _select,
              labelType: extended
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: extended
                    ? Row(children: [
                        Icon(Icons.flight_takeoff, color: scheme.primary),
                        const SizedBox(width: 8),
                        Text('实用英语',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: scheme.primary)),
                      ])
                    : Icon(Icons.flight_takeoff, color: scheme.primary),
              ),
              trailing: extended
                  ? Expanded(
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 16, 20),
                          child: Text('Ctrl+F 搜索\nEsc 停止朗读',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant)),
                        ),
                      ),
                    )
                  : null,
              destinations: [
                for (final (icon, selected, label) in _items)
                  NavigationRailDestination(
                    icon: Icon(icon),
                    selectedIcon: Icon(selected),
                    label: Text(label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
        const SingleActivator(LogicalKeyboardKey.escape): TtsService.to.stop,
      },
      child: Focus(autofocus: true, child: page),
    );
  }
}
