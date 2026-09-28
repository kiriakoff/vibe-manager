import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/app_card.dart';
import '../widgets/glass.dart';
import '../widgets/logs_sheet.dart';
import '../widgets/toasts.dart';

/// Main dashboard: header, responsive app grid, silent periodic refresh.
class DashboardPage extends StatefulWidget {
  final ApiClient api;
  final String user;
  final VoidCallback onLogout;

  const DashboardPage({
    super.key,
    required this.api,
    required this.user,
    required this.onLogout,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<AppInfo>? _apps;
  String? _error;
  Timer? _refreshTimer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _loadApps();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _loadApps(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadApps({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent && _apps == null) {
      setState(() {
        _error = null;
      });
    }
    try {
      final apps = await widget.api.listApps();
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.statusCode == 401) {
        widget.onLogout();
        return;
      }
      setState(() => _error = e.toString());
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshPreview(AppInfo app) async {
    try {
      final message = await widget.api.refreshPreview(app.fqdn);
      if (mounted) showVibeToast(context, message);
      await _loadApps(silent: true);
    } catch (e) {
      if (mounted) showVibeToast(context, e.toString(), success: false);
    }
  }

  void _showLogs(String fqdn) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: LogsSheet(
          fqdn: fqdn,
          connect: () => widget.api.streamLogs(fqdn),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final apps = _apps;
    final isAdmin = widget.user == 'admin';

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [VibeColors.bgTop, VibeColors.bgBottom, VibeColors.bgTop],
          ),
        ),
        child: RefreshIndicator(
          color: VibeColors.accent,
          backgroundColor: const Color(0xFF1E293B),
          onRefresh: () => _loadApps(),
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: const Color(0xCC0F172A),
                surfaceTintColor: Colors.transparent,
                toolbarHeight: 68,
                flexibleSpace: GlassCard(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  blur: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      const Icon(Icons.bolt, color: VibeColors.accent, size: 26),
                      const SizedBox(width: 10),
                      const Text(
                        'Vibe Manager',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const Spacer(),
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color:
                                      Colors.white.withValues(alpha: 0.06),
                                  border: Border.all(
                                      color: VibeColors.cardBorder),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isAdmin
                                          ? Icons.admin_panel_settings
                                          : Icons.person,
                                      size: 14,
                                      color: isAdmin
                                          ? VibeColors.accent
                                          : VibeColors.textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        widget.user,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          color: VibeColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Log out',
                              onPressed: widget.onLogout,
                              icon: const Icon(Icons.logout,
                                  size: 20, color: VibeColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                sliver: switch ((apps == null, _error)) {
                  (true, _) => const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: VibeColors.accent,
                        ),
                      ),
                    ),
                  (false, final String err) => SliverFillRemaining(
                      hasScrollBody: false,
                      child: _ErrorPane(
                        message: err,
                        onRetry: () => _loadApps(),
                      ),
                    ),
                  _ when apps!.isEmpty => SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyPane(
                        onRefresh: () => _loadApps(),
                      ),
                    ),
                  _ => SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.crossAxisExtent;
                        final columns = width < 620
                            ? 1
                            : width < 1040
                                ? 2
                                : width < 1460
                                    ? 3
                                    : 4;
                        const gap = 16.0;
                        return SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            crossAxisSpacing: gap,
                            mainAxisSpacing: gap,
                            mainAxisExtent: 150 + 8 + 130,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final app = apps[index];
                              return AppCard(
                                app: app,
                                api: widget.api,
                                onChanged: () => _loadApps(silent: true),
                                onShowLogs: _showLogs,
                                onRefreshPreview: _refreshPreview,
                              );
                            },
                            childCount: apps.length,
                          ),
                        );
                      },
                    ),
                },
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: apps == null || apps.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: VibeColors.accent.withValues(alpha: 0.15),
              foregroundColor: VibeColors.accent,
              elevation: 0,
              onPressed: () => _loadApps(),
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text('Refresh',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorPane({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassCard(
        padding: const EdgeInsets.all(28),
        margin: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: VibeColors.red, size: 40),
            const SizedBox(height: 14),
            const Text('Failed to load apps',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12.5, color: VibeColors.textSecondary),
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPane extends StatelessWidget {
  final VoidCallback onRefresh;

  const _EmptyPane({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open,
              size: 56, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          const Text(
            'No apps found',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Add a folder with index.html to the File Browser\n'
            'root and it will appear here automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: VibeColors.textSecondary),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}
