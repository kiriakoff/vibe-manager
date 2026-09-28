import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Live log viewer shown in a modal sheet. Connects to the SSE stream and
/// auto-scrolls; supports copy and cancel (kills the docker logs process
/// server-side when the stream is closed).
class LogsSheet extends StatefulWidget {
  final String fqdn;
  final Stream<String> Function() connect;

  const LogsSheet({super.key, required this.fqdn, required this.connect});

  @override
  State<LogsSheet> createState() => _LogsSheetState();
}

class _LogsSheetState extends State<LogsSheet> {
  final ScrollController _scroll = ScrollController();
  final List<String> _lines = [];
  Stream<String>? _stream;
  bool _done = false;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    setState(() {
      _done = false;
      _stream = widget.connect();
    });
    _stream!.listen(
      (line) {
        setState(() => _lines.add(line));
        _scrollToBottom();
      },
      onError: (Object e) {
        setState(() {
          _lines.add('--- Stream error: $e ---');
          _done = true;
        });
      },
      onDone: () => setState(() => _done = true),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _lines.join('\n')));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xF30D1424)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: VibeColors.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.fqdn,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: VibeColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy logs',
                  onPressed: _lines.isEmpty ? null : _copy,
                  icon: Icon(
                    _copied ? Icons.check : Icons.copy,
                    size: 18,
                    color: _copied ? VibeColors.green : VibeColors.textSecondary,
                  ),
                ),
                IconButton(
                  tooltip: 'Reconnect',
                  onPressed: _subscribe,
                  icon: const Icon(Icons.refresh,
                      size: 18, color: VibeColors.textSecondary),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close,
                      size: 18, color: VibeColors.textSecondary),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: VibeColors.cardBorder),
          Expanded(
            child: StreamBuilder<String>(
              stream: _stream,
              builder: (context, snapshot) {
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  itemCount: _lines.length + (_done ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_done && index == _lines.length) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          '--- Connection closed ---',
                          style: TextStyle(
                            color: VibeColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      );
                    }
                    return SelectableText(
                      _lines[index],
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono, Fira Code, monospace',
                        fontSize: 12.5,
                        height: 1.45,
                        color: _lines[index].contains('error')
                            ? VibeColors.red
                            : VibeColors.textPrimary,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
