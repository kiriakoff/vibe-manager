class AppInfo {
  final String fqdn;
  final String status;
  final String owner;
  final bool hasPreview;

  const AppInfo({
    required this.fqdn,
    required this.status,
    required this.owner,
    required this.hasPreview,
  });

  factory AppInfo.fromJson(Map<String, dynamic> json) {
    return AppInfo(
      fqdn: json['fqdn'] as String? ?? '',
      status: json['status'] as String? ?? 'not found',
      owner: json['owner'] as String? ?? '',
      hasPreview: json['has_preview'] == true,
    );
  }

  bool get isRunning => status == 'running';
}

class LoginResult {
  final String accessToken;
  const LoginResult({required this.accessToken});

  factory LoginResult.fromJson(Map<String, dynamic> json) =>
      LoginResult(accessToken: json['access_token'] as String? ?? '');
}
