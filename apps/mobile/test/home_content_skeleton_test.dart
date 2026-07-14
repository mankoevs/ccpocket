import 'dart:async';

import 'package:ccpocket/features/session_list/state/session_list_cubit.dart';
import 'package:ccpocket/features/session_list/state/session_list_state.dart';
import 'package:ccpocket/features/session_list/widgets/home_content.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/models/offline_pending_action.dart';
import 'package:ccpocket/l10n/app_localizations.dart';
import 'package:ccpocket/services/bridge_service.dart';
import 'package:ccpocket/services/draft_service.dart';
import 'package:ccpocket/services/in_app_review_service.dart';
import 'package:ccpocket/services/revenuecat_service.dart';
import 'package:ccpocket/services/support_banner_service.dart';
import 'package:ccpocket/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skeletonizer/src/widgets/skeletonizer.dart';

/// Minimal mock for BridgeService that satisfies SessionListCubit.
class _MockBridgeService extends BridgeService {
  final _recentSessionsController =
      StreamController<List<RecentSession>>.broadcast();
  final _projectHistoryController = StreamController<List<String>>.broadcast();

  @override
  Stream<List<RecentSession>> get recentSessionsStream =>
      _recentSessionsController.stream;

  @override
  Stream<List<String>> get projectHistoryStream =>
      _projectHistoryController.stream;

  @override
  bool get recentSessionsHasMore => false;

  @override
  String? get currentProjectFilter => null;

  @override
  void switchProjectFilter(String? projectPath, {int pageSize = 20}) {}

  @override
  void requestSessionList() {}

  @override
  void requestRecentSessions({int? limit, int? offset, String? projectPath}) {}

  @override
  void requestProjectHistory() {}

  @override
  void send(ClientMessage message) {}

  @override
  void dispose() {
    _recentSessionsController.close();
    _projectHistoryController.close();
  }
}

RecentSession _session({
  required String id,
  String projectPath = '/home/user/project-a',
}) {
  return RecentSession(
    sessionId: id,
    firstPrompt: 'test prompt for $id',
    created: '2025-01-01T00:00:00Z',
    modified: '2025-01-01T00:00:00Z',
    gitBranch: 'main',
    projectPath: projectPath,
    isSidechain: false,
  );
}

SessionInfo _runningSession({required String id}) {
  return SessionInfo.fromJson({
    'id': id,
    'projectPath': '/home/user/project-a',
    'status': 'running',
    'createdAt': '2025-01-01T12:00:00Z',
    'lastActivityAt': '2025-01-01T12:00:00Z',
    'gitBranch': 'main',
    'lastMessage': 'Working on something',
    'messageCount': 1,
  });
}

Widget _buildHomeContent({
  List<SessionInfo> sessions = const [],
  List<OfflinePendingAction> offlinePendingActions = const [],
  List<RecentSession> recentSessions = const [],
  Set<String> accumulatedProjectPaths = const {},
  Set<String> exhaustedProjectPaths = const {},
  Map<String, int> projectSessionDisplayLimits = const {},
  String? currentProjectFilter,
  bool hasMoreSessions = false,
  bool isInitialLoading = false,
  bool showMacOSNativeAppBanner = false,
  VoidCallback? onDismissMacOSNativeAppBanner,
  VoidCallback? onLoadMore,
  ValueChanged<String>? onNewSessionForProject,
  required SessionListCubit cubit,
  required DraftService draftService,
  required RevenueCatService revenueCatService,
  required SupportBannerService supportBannerService,
}) {
  return MultiRepositoryProvider(
    providers: [
      RepositoryProvider<DraftService>.value(value: draftService),
      RepositoryProvider<RevenueCatService>.value(value: revenueCatService),
      ChangeNotifierProvider<SupportBannerService>.value(
        value: supportBannerService,
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [BlocProvider<SessionListCubit>.value(value: cubit)],
          child: HomeContent(
            connectionState: BridgeConnectionState.connected,
            sessions: sessions,
            offlinePendingActions: offlinePendingActions,
            recentSessions: recentSessions,
            accumulatedProjectPaths: accumulatedProjectPaths,
            exhaustedProjectPaths: exhaustedProjectPaths,
            projectSessionDisplayLimits: projectSessionDisplayLimits,
            searchQuery: '',
            isLoadingMore: false,
            isInitialLoading: isInitialLoading,
            hasMoreSessions: hasMoreSessions,
            currentProjectFilter: currentProjectFilter,
            onNewSession: () {},
            onNewSessionForProject: onNewSessionForProject,
            onTapRunning:
                (
                  id, {
                  projectPath,
                  gitBranch,
                  worktreePath,
                  provider,
                  permissionMode,
                  sandboxMode,
                  approvalPolicy,
                  approvalsReviewer,
                }) {},
            onStopSession: (_) {},
            onResumeSession: (_) {},
            onLongPressRecentSession: (_, _) {},
            onArchiveSession: (_) {},
            onLongPressRunningSession: (_, _) {},
            onSelectProject: (_) {},
            onLoadMore: onLoadMore ?? () {},
            onLoadMoreProject: (_) {},
            providerFilter: ProviderFilter.all,
            namedOnly: false,
            onToggleProvider: () {},
            onToggleNamed: () {},
            showMacOSNativeAppBanner: showMacOSNativeAppBanner,
            onDismissMacOSNativeAppBanner: onDismissMacOSNativeAppBanner,
          ),
        ),
      ),
    ),
  );
}

void main() {
  late _MockBridgeService mockBridge;
  late SessionListCubit cubit;
  late DraftService draftService;
  late RevenueCatService revenueCatService;
  late SupportBannerService supportBannerService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    draftService = DraftService(prefs);
    revenueCatService = RevenueCatService(
      publicApiKey: '',
      platform: TargetPlatform.macOS,
    );
    supportBannerService = SupportBannerService(
      prefs: prefs,
      reviewService: InAppReviewService(
        prefs: prefs,
        appVersionLoader: () async => '1.0.0',
      ),
    );
    mockBridge = _MockBridgeService();
    cubit = SessionListCubit(bridge: mockBridge);
  });

  tearDown(() async {
    cubit.close();
    mockBridge.dispose();
    await revenueCatService.dispose();
  });

  group('HomeContent skeleton', () {
    testWidgets('shows Skeletonizer when isInitialLoading is true and '
        'no sessions exist', (tester) async {
      await tester.pumpWidget(
        _buildHomeContent(
          recentSessions: const [],
          isInitialLoading: true,
          cubit: cubit,
          draftService: draftService,
          revenueCatService: revenueCatService,
          supportBannerService: supportBannerService,
        ),
      );
      await tester.pump();

      // Skeletonizer internally renders as _Skeletonizer + SkeletonizerScope.
      // Use SkeletonizerScope to detect presence.
      expect(find.byType(SkeletonizerScope), findsOneWidget);
      expect(find.text('Chats'), findsAtLeast(1));
    });

    testWidgets('shows empty state when isInitialLoading is false and '
        'no sessions exist', (tester) async {
      await tester.pumpWidget(
        _buildHomeContent(
          recentSessions: const [],
          isInitialLoading: false,
          cubit: cubit,
          draftService: draftService,
          revenueCatService: revenueCatService,
          supportBannerService: supportBannerService,
        ),
      );
      await tester.pump();

      // Skeletonizer should NOT be present
      expect(find.byType(SkeletonizerScope), findsNothing);
      // Empty state should show the "New Session" button
      expect(find.text('New Session'), findsOneWidget);
    });

    testWidgets('shows real session cards (not skeleton) when sessions exist '
        'and isInitialLoading is false', (tester) async {
      await tester.pumpWidget(
        _buildHomeContent(
          recentSessions: [
            _session(id: 's1'),
            _session(id: 's2'),
          ],
          isInitialLoading: false,
          cubit: cubit,
          draftService: draftService,
          revenueCatService: revenueCatService,
          supportBannerService: supportBannerService,
        ),
      );
      await tester.pump();

      // No skeleton
      expect(find.byType(SkeletonizerScope), findsNothing);
      // Real session cards should be visible
      expect(find.text('test prompt for s1'), findsOneWidget);
      expect(find.text('test prompt for s2'), findsOneWidget);
    });

    testWidgets('renders home chats as compact title-only rows', (
      tester,
    ) async {
      final running = SessionInfo(
        id: 'running-compact',
        name: 'Active refactor',
        projectPath: '/home/user/project-a',
        status: 'running',
        createdAt: '2025-01-01T12:00:00Z',
        lastActivityAt: '2025-01-01T12:00:00Z',
        gitBranch: 'feat/compact-list',
        lastMessage: 'Editing the session card',
      );
      final recent = RecentSession(
        sessionId: 'recent-compact',
        name: 'Finished setup',
        firstPrompt: 'Set up the entire project',
        created: '2025-01-01T00:00:00Z',
        modified: '2025-01-01T00:00:00Z',
        gitBranch: 'main',
        projectPath: '/home/user/project-a',
        isSidechain: false,
      );

      await tester.pumpWidget(
        _buildHomeContent(
          sessions: [running],
          recentSessions: [recent],
          isInitialLoading: false,
          cubit: cubit,
          draftService: draftService,
          revenueCatService: revenueCatService,
          supportBannerService: supportBannerService,
        ),
      );
      await tester.pump();

      expect(find.text('Active refactor'), findsOneWidget);
      expect(find.text('Finished setup'), findsOneWidget);
      expect(find.text('Editing the session card'), findsNothing);
      expect(find.text('Set up the entire project'), findsNothing);
      expect(find.text('feat/compact-list'), findsNothing);
      expect(
        find.byKey(const ValueKey('compact_session_working')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    });

    testWidgets('shows every loaded chat without project grouping', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildHomeContent(
          recentSessions: [for (var i = 1; i <= 6; i++) _session(id: 's$i')],
          isInitialLoading: false,
          cubit: cubit,
          draftService: draftService,
          revenueCatService: revenueCatService,
          supportBannerService: supportBannerService,
        ),
      );
      await tester.pump();

      expect(find.text('test prompt for s1'), findsOneWidget);
      expect(find.text('test prompt for s5'), findsOneWidget);
      expect(find.text('test prompt for s6'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('project_show_more_/home/user/project-a')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('recent_grouping_toggle')),
        findsNothing,
      );
    });

    testWidgets('groups chats by today yesterday and earlier', (tester) async {
      final now = DateTime.now();
      String iso(DateTime value) => value.toUtc().toIso8601String();

      await tester.pumpWidget(
        _buildHomeContent(
          recentSessions: [
            RecentSession(
              sessionId: 'today',
              firstPrompt: 'Today chat',
              created: iso(now),
              modified: iso(now),
              gitBranch: '',
              projectPath: '/one',
              isSidechain: false,
            ),
            RecentSession(
              sessionId: 'yesterday',
              firstPrompt: 'Yesterday chat',
              created: iso(now.subtract(const Duration(days: 1))),
              modified: iso(now.subtract(const Duration(days: 1))),
              gitBranch: '',
              projectPath: '/two',
              isSidechain: false,
            ),
            RecentSession(
              sessionId: 'earlier',
              firstPrompt: 'Earlier chat',
              created: '2025-01-01T00:00:00Z',
              modified: '2025-01-01T00:00:00Z',
              gitBranch: '',
              projectPath: '/three',
              isSidechain: false,
            ),
          ],
          isInitialLoading: false,
          cubit: cubit,
          draftService: draftService,
          revenueCatService: revenueCatService,
          supportBannerService: supportBannerService,
        ),
      );
      await tester.pump();

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Earlier'), findsOneWidget);
      expect(find.text('Today chat'), findsOneWidget);
      expect(find.text('Yesterday chat'), findsOneWidget);
      expect(find.text('Earlier chat'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('compact_session_timestamp')),
        findsNWidgets(3),
      );
    });

    testWidgets('loads more automatically without project controls', (
      tester,
    ) async {
      var loadMoreCalls = 0;
      await tester.pumpWidget(
        _buildHomeContent(
          recentSessions: [_session(id: 's1')],
          hasMoreSessions: true,
          onLoadMore: () => loadMoreCalls += 1,
          isInitialLoading: false,
          cubit: cubit,
          draftService: draftService,
          revenueCatService: revenueCatService,
          supportBannerService: supportBannerService,
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('project_show_more_/home/user/project-a')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('load_more_button')), findsNothing);
      expect(loadMoreCalls, 1);
    });

    testWidgets('project view sorts by latest chat and expands project chats', (
      tester,
    ) async {
      String? openedProject;
      final projectA = _session(
        id: 'project-a-chat',
        projectPath: '/work/project-a',
      );
      final projectB = RecentSession(
        sessionId: 'project-b-chat',
        firstPrompt: 'Newest project chat',
        created: '2025-01-03T00:00:00Z',
        modified: '2025-01-03T00:00:00Z',
        gitBranch: 'main',
        projectPath: '/work/project-b',
        isSidechain: false,
      );

      await tester.pumpWidget(
        _buildHomeContent(
          recentSessions: [projectA, projectB],
          accumulatedProjectPaths: const {'/work/project-a', '/work/project-b'},
          onNewSessionForProject: (path) => openedProject = path,
          isInitialLoading: false,
          cubit: cubit,
          draftService: draftService,
          revenueCatService: revenueCatService,
          supportBannerService: supportBannerService,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('session_list_view_projects')),
      );
      await tester.pumpAndSettle();

      final projectARow = find.byKey(
        const ValueKey('project_row_/work/project-a'),
      );
      final projectBRow = find.byKey(
        const ValueKey('project_row_/work/project-b'),
      );
      expect(projectARow, findsOneWidget);
      expect(projectBRow, findsOneWidget);
      expect(
        tester.getTopLeft(projectBRow).dy,
        lessThan(tester.getTopLeft(projectARow).dy),
      );
      expect(find.text('Newest project chat'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('project_expand_/work/project-b')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Newest project chat'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('project_open_/work/project-b')),
      );
      expect(openedProject, '/work/project-b');
    });

    testWidgets('pinned project moves first and persists', (tester) async {
      await tester.pumpWidget(
        _buildHomeContent(
          recentSessions: [
            _session(id: 'older', projectPath: '/work/older-project'),
            RecentSession(
              sessionId: 'newer',
              firstPrompt: 'Newer',
              created: '2025-01-03T00:00:00Z',
              modified: '2025-01-03T00:00:00Z',
              gitBranch: 'main',
              projectPath: '/work/newer-project',
              isSidechain: false,
            ),
          ],
          isInitialLoading: false,
          cubit: cubit,
          draftService: draftService,
          revenueCatService: revenueCatService,
          supportBannerService: supportBannerService,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('session_list_view_projects')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('project_pin_/work/older-project')),
      );
      await tester.pumpAndSettle();

      final older = find.byKey(
        const ValueKey('project_row_/work/older-project'),
      );
      final newer = find.byKey(
        const ValueKey('project_row_/work/newer-project'),
      );
      expect(
        tester.getTopLeft(older).dy,
        lessThan(tester.getTopLeft(newer).dy),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList('session_list_pinned_projects'),
        contains('/work/older-project'),
      );
    });

    testWidgets('shows skeleton below running sessions when '
        'isInitialLoading is true', (tester) async {
      await tester.pumpWidget(
        _buildHomeContent(
          sessions: [_runningSession(id: 'r1')],
          recentSessions: const [],
          isInitialLoading: true,
          cubit: cubit,
          draftService: draftService,
          revenueCatService: revenueCatService,
          supportBannerService: supportBannerService,
        ),
      );
      await tester.pump();

      expect(find.text('Earlier'), findsOneWidget);
      expect(find.byKey(const ValueKey('running_session_r1')), findsOneWidget);
      // Skeleton should show for recent sessions section
      expect(find.byType(SkeletonizerScope), findsOneWidget);
      expect(find.text('Chats'), findsAtLeast(1));
    });

    testWidgets('shows real recent sessions (not skeleton) below running '
        'sessions when loaded', (tester) async {
      await tester.pumpWidget(
        _buildHomeContent(
          sessions: [_runningSession(id: 'r1')],
          recentSessions: [_session(id: 's1')],
          isInitialLoading: false,
          cubit: cubit,
          draftService: draftService,
          revenueCatService: revenueCatService,
          supportBannerService: supportBannerService,
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('running_session_r1')), findsOneWidget);
      // No skeleton
      expect(find.byType(SkeletonizerScope), findsNothing);
      // Real recent session visible
      expect(find.text('test prompt for s1'), findsOneWidget);
    });

    testWidgets(
      'shows pending resume under Running and hides matching Recent',
      (tester) async {
        await tester.pumpWidget(
          _buildHomeContent(
            offlinePendingActions: [
              OfflinePendingAction(
                id: 'pending-resume-s1',
                kind: OfflinePendingActionKind.resume,
                projectPath: '/home/user/project-a',
                provider: 'claude',
                sessionId: 's1',
                createdAt: DateTime.utc(2026, 1, 1),
              ),
            ],
            recentSessions: [
              _session(id: 's1'),
              _session(id: 's2'),
            ],
            isInitialLoading: false,
            cubit: cubit,
            draftService: draftService,
            revenueCatService: revenueCatService,
            supportBannerService: supportBannerService,
          ),
        );
        await tester.pump();

        expect(find.text('Chats'), findsAtLeast(1));
        expect(find.text('Resume pending'), findsOneWidget);
        expect(find.text('test prompt for s1'), findsNothing);
        expect(find.text('test prompt for s2'), findsOneWidget);
      },
    );

    testWidgets('shows skeleton while loading even if recent sessions exist', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildHomeContent(
          recentSessions: [_session(id: 's1')],
          isInitialLoading: true,
          cubit: cubit,
          draftService: draftService,
          revenueCatService: revenueCatService,
          supportBannerService: supportBannerService,
        ),
      );
      await tester.pump();

      // While loading, skeleton should be preferred over stale cards.
      expect(find.byType(SkeletonizerScope), findsOneWidget);
      expect(find.text('test prompt for s1'), findsNothing);
    });

    testWidgets('shows macOS native app banner when requested', (tester) async {
      await tester.pumpWidget(
        _buildHomeContent(
          recentSessions: [_session(id: 's1')],
          showMacOSNativeAppBanner: true,
          cubit: cubit,
          draftService: draftService,
          revenueCatService: revenueCatService,
          supportBannerService: supportBannerService,
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('macos_native_app_banner')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('macos_native_app_banner_open_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('macos_native_app_banner_dismiss_button')),
        findsOneWidget,
      );
    });

    testWidgets('calls dismiss callback from macOS native app banner', (
      tester,
    ) async {
      var dismissed = false;
      await tester.pumpWidget(
        _buildHomeContent(
          recentSessions: [_session(id: 's1')],
          showMacOSNativeAppBanner: true,
          onDismissMacOSNativeAppBanner: () => dismissed = true,
          cubit: cubit,
          draftService: draftService,
          revenueCatService: revenueCatService,
          supportBannerService: supportBannerService,
        ),
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey('macos_native_app_banner_dismiss_button')),
      );

      expect(dismissed, isTrue);
    });
  });
}
