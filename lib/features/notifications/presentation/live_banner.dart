import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/widgets/glass.dart';
import '../../../shared/models/models.dart';
import '../domain/reminders.dart';
import 'notification_style.dart';

/// An iOS-style notification bar that drops in from the top when something
/// new arrives: a reminder comes due, or (with a server) a teammate changes
/// an obligation. Tap to open, swipe up to dismiss; it also hides by itself.
class LiveNotificationBanner extends ConsumerStatefulWidget {
  const LiveNotificationBanner({super.key});
  static const visibleFor = Duration(seconds: 5);
  @override
  ConsumerState<LiveNotificationBanner> createState() => _BannerState();
}

class _BannerState extends ConsumerState<LiveNotificationBanner> {
  /// Notifications already known for the current account and organisation.
  Set<String>? _seen;
  String? _scope;
  List<DueNotification> _showing = const [];
  bool _visible = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      notificationsProvider,
      (_, next) => _arrived(next),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _arrived(List<DueNotification> all) {
    final workspace = ref.read(workspaceProvider);
    if (workspace.value == null) return;
    final scope =
        '${ref.read(currentUserProvider).id}:${ref.read(organisationProvider).id}';
    final ids = all.map((n) => n.id).toSet();
    // A new account or organisation starts from what is already there.
    if (_seen == null || _scope != scope) {
      _scope = scope;
      _seen = ids;
      return;
    }
    final fresh = all
        .where((n) => !n.read && !_seen!.contains(n.id))
        .where(_announce)
        .toList();
    _seen = {..._seen!, ...ids};
    if (fresh.isEmpty || !(ref.read(settingsProvider)['banner'] ?? true)) {
      return;
    }
    fresh.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    DueHaptics.light();
    setState(() {
      _showing = fresh;
      _visible = true;
    });
    _hide?.cancel();
    _hide = Timer(LiveNotificationBanner.visibleFor, _dismiss);
  }

  /// Reminders always show. Activity shows only when it came from someone
  /// else, which with device storage it never does.
  bool _announce(DueNotification n) {
    if (reminderTypes.contains(n.type)) return true;
    if (ref.read(storageProvider).isDevice) return false;
    final local = ref.read(workspaceProvider.notifier).lastLocalAction;
    return local == null ||
        DateTime.now().difference(local) > const Duration(seconds: 15);
  }

  void _dismiss() {
    _hide?.cancel();
    if (mounted && _visible) setState(() => _visible = false);
  }

  Future<void> _open() async {
    final items = _showing;
    _dismiss();
    if (items.isEmpty) return;
    final router = ref.read(routerProvider);
    if (items.length > 1) {
      router.push('/notifications');
      return;
    }
    final n = items.single;
    router.push('/due/${Uri.encodeComponent(n.dueItemId)}');
    try {
      await ref
          .read(workspaceProvider.notifier)
          .act((r, a) => r.markRead(a, n.organisationId, id: n.id));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = _showing.isEmpty ? null : _showing.first;
    final many = _showing.length > 1;
    final style = first == null ? null : notificationStyle(context, first.type);
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        bottom: false,
        child: IgnorePointer(
          ignoring: !_visible,
          child: AnimatedSlide(
            offset: _visible ? Offset.zero : const Offset(0, -1.4),
            duration: const Duration(milliseconds: 420),
            curve: _visible ? Curves.easeOutBack : Curves.easeInCubic,
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: first == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: GestureDetector(
                          onVerticalDragEnd: (d) {
                            if ((d.primaryVelocity ?? 0) < 0) _dismiss();
                          },
                          child: Semantics(
                            liveRegion: true,
                            button: true,
                            label: many
                                ? '${_showing.length} new notifications'
                                : '${style!.title}. ${first.message}',
                            excludeSemantics: true,
                            child: FrostedPanel(
                              borderRadius: BorderRadius.circular(22),
                              child: InkWell(
                                key: const ValueKey('live-banner'),
                                onTap: _open,
                                borderRadius: BorderRadius.circular(22),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    11,
                                    14,
                                    12,
                                  ),
                                  child: Row(
                                    children: [
                                      NotificationIcon(type: first.type),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    many
                                                        ? '${_showing.length} new notifications'
                                                        : style!.title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 13.5,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  'now',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    color:
                                                        scheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              many
                                                  ? '${first.message} And ${_showing.length - 1} more.'
                                                  : first.message,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                height: 1.35,
                                                color: scheme.onSurface
                                                    .withValues(alpha: .82),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
