import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n/app_localizations.dart';
import 'l10n/locale_controller.dart';
import 'models/server_status.dart';
import 'services/api_service.dart';
import 'theme/app_motion.dart';
import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';
import 'theme/theme_controller.dart';
import 'views/about_view.dart';
import 'views/admins_view.dart';
import 'views/config_view.dart';
import 'views/console_view.dart';
import 'views/dashboard_view.dart';
import 'views/instances_view.dart';
import 'views/mods_view.dart';
import 'views/worlds_view.dart';
import 'widgets/navigation_dock.dart';
import 'widgets/navigation_sidebar.dart';
import 'widgets/no_instance_barrier.dart';
import 'widgets/restart_pending_pill.dart';
import 'services/restart_state_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.instance.init();
  await LocaleController.instance.init();
  runApp(const CoreKeeperManagerApp());
}

class CoreKeeperManagerApp extends StatelessWidget {
  const CoreKeeperManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        ThemeController.instance,
        LocaleController.instance,
      ]),
      builder: (context, _) {
        final themeMode = ThemeController.instance.value;
        final language = LocaleController.instance.value;
        final theme = themeMode == AppThemeMode.dark ? AppTheme.darkTheme : AppTheme.lightTheme;

        return MaterialApp(
          title: 'Core Keeper Server Manager',
          debugShowCheckedModeBanner: false,
          theme: theme,
          scrollBehavior: const AppScrollBehavior(),
          locale: language.locale,
          supportedLocales: AppLanguage.values.map((l) => l.locale).toList(),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const MainShell(),
        );
      },
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  bool _isSidebarCollapsed = false;
  ServerStatus? _status;
  Timer? _statusTimer;
  int _viewRebuildKey = 0;

  @override
  void initState() {
    super.initState();
    _loadSidebarState();
    ApiService.instance.activeInstanceNotifier.addListener(_onActiveInstanceChanged);
    ApiService.instance.tabNavigationNotifier.addListener(_onTabNavigation);
    _initInstances();
    final tabParam = Uri.base.queryParameters['tab'];
    if (tabParam != null) {
      final tabIdx = int.tryParse(tabParam);
      if (tabIdx != null && tabIdx >= 0 && tabIdx < 8) {
        _selectedIndex = tabIdx;
      }
    }
    _fetchStatus();
    // Poll status every 4 seconds
    _statusTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _fetchStatus();
    });
  }

  Future<void> _initInstances() async {
    try {
      final list = await ApiService.instance.getInstances();
      if (list.isEmpty && mounted) {
        setState(() => _selectedIndex = 1);
      }
    } catch (_) {}
  }

  void _onActiveInstanceChanged() {
    if (mounted) {
      if (ApiService.instance.currentInstanceId == null) {
        _selectedIndex = 1;
      }
      setState(() => _viewRebuildKey++);
      _fetchStatus();
    }
  }

  Future<void> _loadSidebarState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final collapsed = prefs.getBool('ck_sidebar_collapsed') ?? false;
      if (mounted) setState(() => _isSidebarCollapsed = collapsed);
    } catch (_) {}
  }

  void _toggleSidebar() async {
    setState(() => _isSidebarCollapsed = !_isSidebarCollapsed);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('ck_sidebar_collapsed', _isSidebarCollapsed);
    } catch (_) {}
  }

  Future<void> _fetchStatus() async {
    try {
      final s = await ApiService.instance.getStatus();
      if (mounted) {
        setState(() => _status = s);
        RestartStateController.instance.syncStatus(
          restartRequired: s.restartRequired,
          isRunning: s.isRunning,
        );
      }
    } catch (_) {}
  }

  void _onTabNavigation() {
    final idx = ApiService.instance.tabNavigationNotifier.value;
    if (idx != null && mounted) {
      _selectTab(idx);
      ApiService.instance.tabNavigationNotifier.value = null;
    }
  }

  @override
  void dispose() {
    ApiService.instance.activeInstanceNotifier.removeListener(_onActiveInstanceChanged);
    ApiService.instance.tabNavigationNotifier.removeListener(_onTabNavigation);
    _statusTimer?.cancel();
    super.dispose();
  }

  void _selectTab(int idx) {
    setState(() => _selectedIndex = idx);
    _fetchStatus();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 768;
        final currentInst = ApiService.instance.currentInstanceId;
        final hasInstance = currentInst != null && currentInst.isNotEmpty;

        Widget wrapWithBarrierIfNeeded(Widget view) {
          if (!hasInstance) {
            return NoInstanceBarrierWidget(
              onGoToInstances: () => _selectTab(1),
            );
          }
          return view;
        }

        final views = [
          wrapWithBarrierIfNeeded(
            DashboardView(
              key: ValueKey('dash_${currentInst}_$_viewRebuildKey'),
              status: _status,
              onRefresh: _fetchStatus,
              onNavigate: _selectTab,
            ),
          ),
          InstancesView(
            key: ValueKey('instances_${currentInst}_$_viewRebuildKey'),
            onInstanceChanged: _onActiveInstanceChanged,
          ),
          wrapWithBarrierIfNeeded(
            ConsoleView(
              key: ValueKey('console_${currentInst}_$_viewRebuildKey'),
            ),
          ),
          wrapWithBarrierIfNeeded(
            ConfigView(
              key: ValueKey('config_${currentInst}_$_viewRebuildKey'),
              onConfigSaved: _fetchStatus,
            ),
          ),
          wrapWithBarrierIfNeeded(
            AdminsView(
              key: ValueKey('admins_${currentInst}_$_viewRebuildKey'),
            ),
          ),
          wrapWithBarrierIfNeeded(
            WorldsView(
              key: ValueKey('worlds_${currentInst}_$_viewRebuildKey'),
              onWorldChanged: _fetchStatus,
            ),
          ),
          wrapWithBarrierIfNeeded(
            ModsView(
              key: ValueKey('mods_${currentInst}_$_viewRebuildKey'),
            ),
          ),
          AboutView(
            key: ValueKey('about_${currentInst}_$_viewRebuildKey'),
          ),
        ];

        final l10n = context.l10n;
        final dockDestinations = [
          DockDestination(icon: Icons.dashboard_rounded, label: l10n.navOverview),
          DockDestination(icon: Icons.dns_rounded, label: l10n.navInstances),
          DockDestination(icon: Icons.terminal_rounded, label: l10n.navLogs),
          DockDestination(icon: Icons.tune_rounded, label: l10n.navConfig),
          DockDestination(icon: Icons.admin_panel_settings_rounded, label: l10n.navAdmins),
          DockDestination(icon: Icons.public_rounded, label: l10n.navWorlds),
          DockDestination(icon: Icons.extension_rounded, label: l10n.navMods),
          DockDestination(icon: Icons.info_outline_rounded, label: l10n.navAbout),
        ];

        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationSidebar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _selectTab,
                  status: _status,
                  isCollapsed: _isSidebarCollapsed,
                  onToggleCollapse: _toggleSidebar,
                  onInstanceChanged: _onActiveInstanceChanged,
                ),
                Expanded(
                  child: Container(
                    color: SurfaceLevel.page.colorOf(context),
                    child: Stack(
                      children: [
                        AnimatedIndexedStack(
                          index: _selectedIndex,
                          children: views,
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: RestartPendingPill(onRestartSuccess: _fetchStatus),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        } else {
          // Compact / Mobile layout with Floating Liquid Navigation Dock
          return Scaffold(
            body: SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  AnimatedIndexedStack(
                    index: _selectedIndex,
                    children: views,
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: RestartPendingPill(onRestartSuccess: _fetchStatus),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: NavigationDock(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _selectTab,
              destinations: dockDestinations,
            ),
          );
        }
      },
    );
  }
}

/// Lazy Animated Indexed Stack
/// Keeps view state alive while only initializing views when first visited
class AnimatedIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const AnimatedIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = AppMotion.tabFade,
  });

  @override
  State<AnimatedIndexedStack> createState() => _AnimatedIndexedStackState();
}

class _AnimatedIndexedStackState extends State<AnimatedIndexedStack> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _fadeAnimation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _slideAnimation = Tween<Offset>(
    begin: const Offset(0.012, 0.0),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  ));

  int _currentIndex = 0;
  late final Set<int> _activatedIndices = {widget.index};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.index;
    _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant AnimatedIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_activatedIndices.contains(widget.index)) {
      _activatedIndices.add(widget.index);
    }
    if (widget.index != oldWidget.index) {
      setState(() => _currentIndex = widget.index);
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: IndexedStack(
          index: _currentIndex,
          children: [
            for (int i = 0; i < widget.children.length; i++)
              _activatedIndices.contains(i)
                  ? widget.children[i]
                  : const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}
