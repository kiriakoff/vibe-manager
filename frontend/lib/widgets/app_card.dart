import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../models.dart';
import '../theme.dart';
import 'glass.dart';
import 'toasts.dart';

/// Dashboard tile: preview, FQDN, live status, Start/Stop + logs + open link.
class AppCard extends StatefulWidget {
  final AppInfo app;
  final ApiClient api;
  final VoidCallback onChanged;
  final void Function(String fqdn) onShowLogs;
  final Future<void> Function(AppInfo app) onRefreshPreview;

  const AppCard({
    super.key,
    required this.app,
    required this.api,
    required this.onChanged,
    required this.onShowLogs,
    required this.onRefreshPreview,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _busy = false;
  int _previewBuster = DateTime.now().millisecondsSinceEpoch;

  AppInfo get app => widget.app;

  Future<void> _togglePower() async {
    setState(() => _busy = true);
    try {
      final message = app.isRunning
          ? await widget.api.stopApp(app.fqdn)
          : await widget.api.startApp(app.fqdn);
      if (mounted) showVibeToast(context, message, success: true);
      widget.onChanged();
    } catch (e) {
      if (mounted) showVibeToast(context, e.toString(), success: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSite() async {
    final uri = Uri.parse('https://${app.fqdn}');
    final ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!ok && mounted) {
      showVibeToast(context, 'Could not open ${app.fqdn}', success: false);
    }
  }

  Future<void> _refreshPreview() async {
    await widget.onRefreshPreview(app);
    if (mounted) {
      setState(
          () => _previewBuster = DateTime.now().millisecondsSinceEpoch);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = statusColor(app.status);

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(18)),
            child: Container(
              height: 150,
              color: const Color(0xFF0B1120),
              child: app.hasPreview
                  ? Image.network(
                      widget.api.previewUrl(app.fqdn, cacheBuster: _previewBuster).toString(),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _PreviewFallback(),
                    )
                  : const _PreviewFallback(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.fqdn,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: VibeColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _StatusDot(color: color),
                    const SizedBox(width: 8),
                    Text(
                      statusLabel(app.status),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: color,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      app.owner,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: VibeColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _PowerButton(
                        running: app.isRunning,
                        busy: _busy,
                        onPressed: _togglePower,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _IconButton(
                      tooltip: 'Logs',
                      icon: Icons.receipt_long,
                      onPressed: () => widget.onShowLogs(app.fqdn),
                    ),
                    const SizedBox(width: 8),
                    _IconButton(
                      tooltip: 'Refresh preview',
                      icon: Icons.photo_camera_back,
                      onPressed: _refreshPreview,
                    ),
                    if (app.isRunning) ...[
                      const SizedBox(width: 8),
                      _IconButton(
                        tooltip: 'Open site',
                        icon: Icons.open_in_new,
                        onPressed: _openSite,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewFallback extends StatelessWidget {
  const _PreviewFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B1120),
      alignment: Alignment.center,
      child: Icon(
        Icons.language,
        size: 44,
        color: Colors.white.withValues(alpha: 0.12),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;

  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8),
        ],
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  final bool running;
  final bool busy;
  final VoidCallback onPressed;

  const _PowerButton({
    required this.running,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = running ? VibeColors.red : VibeColors.green;
    return SizedBox(
      height: 38,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.22),
              color.withValues(alpha: 0.12),
            ],
          ),
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: TextButton.icon(
          onPressed: busy ? null : onPressed,
          icon: busy
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  running ? Icons.stop : Icons.play_arrow,
                  size: 18,
                  color: color,
                ),
          label: Text(
            running ? 'Stop' : 'Start',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _IconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 38,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Colors.white.withValues(alpha: 0.05),
          border: Border.all(color: VibeColors.cardBorder),
        ),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, size: 18, color: VibeColors.textSecondary),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
