import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers.dart';
import '../core/widgets/glass.dart';
import '../features/auth/presentation/auth_screens.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/due_items/presentation/due_list_screen.dart';
import '../features/due_items/presentation/due_form_screen.dart';
import '../features/due_items/presentation/due_detail_screen.dart';
import '../features/calendar/presentation/calendar_screen.dart';
import '../features/documents/presentation/documents_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/companies/presentation/company_screens.dart';
import '../features/users/presentation/team_screens.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/settings/presentation/settings_screens.dart';
import '../features/settings/presentation/storage_screen.dart';
import '../features/security/presentation/lock_screen.dart';
import '../features/compliance/presentation/compliance_setup_screen.dart';

String normalizeDeepLink(Uri uri) =>
    uri.scheme == 'duedesk' && uri.host == 'due'
    ? '/due${uri.path}'
    : uri.toString();

/// Auth pages cross-fade with a slight rise, so switching between log in,
/// sign up and password reset feels like one continuous screen.
Page<void> _authPage(GoRouterState state, Widget child) => CustomTransitionPage(
  key: state.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 320),
  reverseTransitionDuration: const Duration(milliseconds: 220),
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, .02),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  },
);

class RouterRefresh extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = RouterRefresh();
  String? pendingLink;
  ref.listen(authProvider, (_, _) => refresh.refresh());
  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      if (state.uri.scheme == 'duedesk') return normalizeDeepLink(state.uri);
      final auth = ref.read(authProvider), path = state.uri.path;
      final public = [
        '/welcome',
        '/login',
        '/register',
        '/forgot-password',
      ].contains(path);
      if (auth.isLoading || auth.hasError) {
        return path == '/splash'
            ? null
            : '/splash?from=${Uri.encodeComponent(state.uri.toString())}';
      }
      if (auth.value == null) {
        if (path.startsWith('/due/') && path != '/due/new') {
          pendingLink = state.uri.toString();
        }
        final from = state.uri.queryParameters['from'];
        if (from != null && from.startsWith('/due/')) pendingLink = from;
        return public ? null : '/welcome';
      }
      if (path == '/splash' || public) {
        final from = pendingLink ?? state.uri.queryParameters['from'];
        pendingLink = null;
        if (from != null && from.startsWith('/due/')) return from;
        return ref.read(preferencesProvider).getBool('onboarding') == true
            ? '/home'
            : '/onboarding';
      }
      return null;
    },
    errorBuilder: (context, state) => DueDeskScaffold(
      title: 'Page not found',
      child: EmptyState(
        title: 'Let’s get you back on track.',
        message: 'This link is not available.',
        action: 'Go to Dashboard',
        onAction: () => context.go('/home'),
      ),
    ),
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(
        path: '/login',
        pageBuilder: (_, s) =>
            _authPage(s, const AuthFormScreen(mode: 'login')),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (_, s) =>
            _authPage(s, const AuthFormScreen(mode: 'register')),
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (_, s) =>
            _authPage(s, const AuthFormScreen(mode: 'forgot')),
      ),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const DashboardScreen()),
          GoRoute(
            path: '/due',
            builder: (_, s) => DueListScreen(
              initialFilter: s.uri.queryParameters['filter'] ?? 'All',
            ),
          ),
          GoRoute(
            path: '/calendar',
            builder: (_, s) => CalendarScreen(
              initialDate: DateTime.tryParse(
                s.uri.queryParameters['date'] ?? '',
              ),
            ),
          ),
          GoRoute(
            path: '/documents',
            builder: (_, s) => DocumentsScreen(
              upload: s.uri.queryParameters['upload'] == 'true',
            ),
          ),
          GoRoute(path: '/more', builder: (_, _) => const MoreScreen()),
        ],
      ),
      GoRoute(
        path: '/due/new',
        builder: (_, s) => DueFormScreen(
          showTemplates: s.uri.queryParameters['templates'] == 'true',
        ),
      ),
      GoRoute(
        path: '/due/:id/edit',
        builder: (_, s) => DueFormScreen(id: s.pathParameters['id']),
      ),
      GoRoute(
        path: '/due/:id',
        builder: (_, s) => DueDetailScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(path: '/company', builder: (_, _) => const CompanyScreen()),
      GoRoute(path: '/team', builder: (_, _) => const TeamScreen()),
      GoRoute(
        path: '/team/invite',
        builder: (_, _) => const InviteMemberScreen(),
      ),
      GoRoute(path: '/categories', builder: (_, _) => const CategoriesScreen()),
      GoRoute(
        path: '/compliance',
        builder: (_, _) => const ComplianceSetupScreen(),
      ),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/activity', builder: (_, _) => const ActivityScreen()),
      GoRoute(path: '/settings', redirect: (_, _) => '/more'),
      GoRoute(
        path: '/settings/notifications',
        builder: (_, _) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/appearance',
        builder: (_, _) => const AppearanceScreen(),
      ),
      GoRoute(
        path: '/settings/security',
        builder: (_, _) => const SecurityScreen(),
      ),
      GoRoute(
        path: '/settings/security/passcode',
        builder: (_, _) => const PasscodeSetupScreen(),
      ),
      GoRoute(
        path: '/settings/storage',
        builder: (_, _) => const StorageScreen(),
      ),
      GoRoute(path: '/about', builder: (_, _) => const AboutScreen()),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
