import 'package:flutter/material.dart';

import 'app_update_service.dart';

class AppUpdateBanner extends StatelessWidget {
  const AppUpdateBanner({
    super.key,
    required this.state,
    required this.onRetry,
    required this.onUpdate,
    required this.onLater,
    required this.onIgnore,
  });

  final AppUpdateState state;
  final VoidCallback onRetry;
  final VoidCallback onUpdate;
  final VoidCallback onLater;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final available = state.status == AppUpdateCheckStatus.available;
    final failed = state.status == AppUpdateCheckStatus.failed;
    final checking = state.status == AppUpdateCheckStatus.checking;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  available
                      ? Icons.system_update_alt
                      : failed
                          ? Icons.error_outline
                          : Icons.verified_outlined,
                  color: available
                      ? colorScheme.primary
                      : failed
                          ? colorScheme.error
                          : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'App version: ${state.installedVersion.isEmpty ? '...' : state.installedVersion}',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (checking)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_statusText(state)),
            if (available || failed) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (available)
                    FilledButton.icon(
                      onPressed: onUpdate,
                      icon: const Icon(Icons.download),
                      label: Text('Update to ${state.latestVersion}'),
                    ),
                  if (failed)
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  if (available)
                    TextButton(
                      onPressed: onLater,
                      child: const Text('Remind me later'),
                    ),
                  if (available)
                    TextButton(
                      onPressed: onIgnore,
                      child: const Text('Ignore this version'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusText(AppUpdateState state) {
    switch (state.status) {
      case AppUpdateCheckStatus.checking:
        return 'Checking for app updates.';
      case AppUpdateCheckStatus.available:
        return 'Update available: ${state.latestVersion}';
      case AppUpdateCheckStatus.upToDate:
        return 'Up to date';
      case AppUpdateCheckStatus.failed:
        return 'Update check failed';
      case AppUpdateCheckStatus.deferred:
        return 'Update deferred for now';
      case AppUpdateCheckStatus.ignored:
        return state.latestVersion.isEmpty
            ? 'Update ignored'
            : 'Ignored ${state.latestVersion}';
    }
  }
}
