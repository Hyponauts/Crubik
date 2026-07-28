import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../cube/application/cube_connection_controller.dart';
import '../../../cube/domain/smart_cube_device.dart';
import '../../application/practice_controller.dart';

Future<void> showPracticeConnectionDialog(
  BuildContext context, {
  required PracticeController practice,
  required CubeConnectionController connection,
  required Future<void> Function() onUseDemoCube,
  required VoidCallback onExitDemo,
  required Future<void> Function(CubeDeviceCandidate) onConnect,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _PracticeConnectionDialog(
      practice: practice,
      connection: connection,
      onUseDemoCube: onUseDemoCube,
      onExitDemo: onExitDemo,
      onConnect: onConnect,
    ),
  );
}

class PracticeConnectionButton extends StatelessWidget {
  const PracticeConnectionButton({
    required this.practice,
    required this.connection,
    required this.onPressed,
    this.compact = false,
    super.key,
  });

  final PracticeController practice;
  final CubeConnectionController connection;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isConnected = connection.isConnected;
    final isDemo = practice.inputMode == PracticeInputMode.demo;
    final label = isDemo
        ? (compact ? 'DEMO' : 'Demo cube')
        : isConnected
        ? (compact ? 'LIVE' : connection.connectedCube!.name)
        : (compact ? 'CONNECT' : 'Connect cube');
    return OutlinedButton.icon(
      key: const Key('connect-cube-button'),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: isConnected
            ? CrubikColors.primaryAccent
            : CrubikColors.text,
        side: BorderSide(
          color: isConnected ? CrubikColors.primaryAccent : CrubikColors.border,
        ),
        backgroundColor: isConnected
            ? CrubikColors.accentStatusBackground
            : CrubikColors.surface,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: 11,
        ),
      ),
      icon: Icon(
        isDemo
            ? Icons.science_outlined
            : isConnected
            ? Icons.bluetooth_connected
            : Icons.bluetooth_searching,
        size: 18,
      ),
      label: Text(label),
    );
  }
}

class _PracticeConnectionDialog extends StatelessWidget {
  const _PracticeConnectionDialog({
    required this.practice,
    required this.connection,
    required this.onUseDemoCube,
    required this.onExitDemo,
    required this.onConnect,
  });

  final PracticeController practice;
  final CubeConnectionController connection;
  final Future<void> Function() onUseDemoCube;
  final VoidCallback onExitDemo;
  final Future<void> Function(CubeDeviceCandidate) onConnect;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([practice, connection]),
      builder: (context, _) {
        final scanning = connection.status == CubeConnectionStatus.scanning;
        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          backgroundColor: CrubikColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: CrubikColors.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: CrubikLayout.connectionDialogMaxWidth,
              maxHeight: CrubikLayout.connectionDialogMaxHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ConnectionDialogHeader(connection: connection),
                  const SizedBox(height: 20),
                  if (practice.inputMode == PracticeInputMode.demo)
                    _DemoInputCard(onExitDemo: onExitDemo)
                  else if (connection.isConnected)
                    _ConnectedCubeCard(connection: connection)
                  else
                    Flexible(
                      child: _DisconnectedCubeContent(
                        connection: connection,
                        scanning: scanning,
                        onUseDemoCube: onUseDemoCube,
                        onConnect: onConnect,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConnectionDialogHeader extends StatelessWidget {
  const _ConnectionDialogHeader({required this.connection});

  final CubeConnectionController connection;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: CrubikColors.accentIconBackground,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.bluetooth_searching,
            color: CrubikColors.primaryAccent,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connect a smart cube',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                'Supported protocols: ${_formatProtocolNames(connection.supportedProtocolDisplayNames)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _DisconnectedCubeContent extends StatelessWidget {
  const _DisconnectedCubeContent({
    required this.connection,
    required this.scanning,
    required this.onUseDemoCube,
    required this.onConnect,
  });

  final CubeConnectionController connection;
  final bool scanning;
  final Future<void> Function() onUseDemoCube;
  final Future<void> Function(CubeDeviceCandidate) onConnect;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DiscoveryControls(
          connection: connection,
          scanning: scanning,
          onUseDemoCube: onUseDemoCube,
        ),
        if (scanning) ...[
          const SizedBox(height: 14),
          const LinearProgressIndicator(minHeight: 2),
        ],
        if (connection.errorMessage != null) ...[
          const SizedBox(height: 14),
          _ConnectionError(connection: connection),
        ],
        const SizedBox(height: 16),
        Flexible(
          child: connection.discoveredDevices.isEmpty
              ? _EmptyDeviceSearch(scanning: scanning)
              : _DiscoveredDeviceList(
                  connection: connection,
                  onConnect: onConnect,
                ),
        ),
        const SizedBox(height: 14),
        Text(
          'Cube turns update the live model and timer. Use the demo cube to practice without hardware.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: CrubikColors.muted),
        ),
      ],
    );
  }
}

class _DiscoveryControls extends StatelessWidget {
  const _DiscoveryControls({
    required this.connection,
    required this.scanning,
    required this.onUseDemoCube,
  });

  final CubeConnectionController connection;
  final bool scanning;
  final Future<void> Function() onUseDemoCube;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: scanning ? connection.stopScan : connection.startScan,
            icon: Icon(scanning ? Icons.stop : Icons.bluetooth_searching),
            label: Text(scanning ? 'Stop scan' : 'Scan nearby'),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          key: const Key('use-demo-cube-dialog'),
          onPressed: () async {
            await onUseDemoCube();
            if (context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.science_outlined),
          label: const Text('Use demo'),
        ),
      ],
    );
  }
}

class _ConnectionError extends StatelessWidget {
  const _ConnectionError({required this.connection});

  final CubeConnectionController connection;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          connection.errorMessage!,
          style: const TextStyle(color: CrubikColors.danger),
        ),
        if (connection.hasDiagnostics) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('copy-bluetooth-diagnostics-button'),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: connection.diagnosticReport),
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Redacted Bluetooth diagnostics copied'),
                ),
              );
            },
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: const Text('Copy diagnostics'),
          ),
        ],
      ],
    );
  }
}

String _formatProtocolNames(List<String> names) => switch (names) {
  [] => 'none',
  [final name] => name,
  [final first, final second] => '$first and $second',
  _ => '${names.take(names.length - 1).join(', ')}, and ${names.last}',
};

class _ConnectedCubeCard extends StatelessWidget {
  const _ConnectedCubeCard({required this.connection});

  final CubeConnectionController connection;

  @override
  Widget build(BuildContext context) {
    final device = connection.connectedCube!;
    final batteryLevel = connection.batteryLevel;
    final connectionStatus = batteryLevel == null
        ? 'BLE link active'
        : 'BLE link active · $batteryLevel% battery';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CrubikColors.accentStatusBackground,
        border: Border.all(color: CrubikColors.activeInputBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.bluetooth_connected,
            color: CrubikColors.primaryAccent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  connectionStatus,
                  semanticsLabel: batteryLevel == null
                      ? connectionStatus
                      : 'BLE link active, battery $batteryLevel percent',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: connection.disconnect,
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }
}

class _DemoInputCard extends StatelessWidget {
  const _DemoInputCard({required this.onExitDemo});

  final VoidCallback onExitDemo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CrubikColors.accentStatusBackground,
        border: Border.all(color: CrubikColors.activeInputBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.science_outlined, color: CrubikColors.primaryAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Demo cube',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Manual timer and virtual cube controls active',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(onPressed: onExitDemo, child: const Text('Exit demo')),
        ],
      ),
    );
  }
}

class _EmptyDeviceSearch extends StatelessWidget {
  const _EmptyDeviceSearch({required this.scanning});

  final bool scanning;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: CrubikColors.elevated,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(scanning ? Icons.radar : Icons.bluetooth_disabled, size: 30),
          const SizedBox(height: 10),
          Text(
            scanning
                ? 'Looking for nearby Bluetooth devices…'
                : 'No Bluetooth devices found yet',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: CrubikColors.text),
          ),
          const SizedBox(height: 4),
          Text(
            'Wake your cube with a turn and keep nearby devices in range.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _DiscoveredDeviceList extends StatelessWidget {
  const _DiscoveredDeviceList({
    required this.connection,
    required this.onConnect,
  });

  final CubeConnectionController connection;
  final Future<void> Function(CubeDeviceCandidate) onConnect;

  @override
  Widget build(BuildContext context) {
    final cubes = connection.discoveredCubes;
    final otherDevices = connection.otherDiscoveredDevices;
    final connectionBusy = connection.status == CubeConnectionStatus.connecting;

    return ListView(
      key: const Key('discovered-device-list'),
      shrinkWrap: true,
      children: [
        _DeviceGroupHeader(title: 'Cubes', count: cubes.length),
        const SizedBox(height: 8),
        if (cubes.isEmpty)
          const _NoIdentifiedCubes()
        else
          for (var index = 0; index < cubes.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            _DeviceResult(
              device: cubes[index],
              connecting: connection.connectingDeviceId == cubes[index].id,
              connectionBusy: connectionBusy,
              onConnect: cubes[index].canConnect
                  ? () async {
                      await onConnect(cubes[index]);
                      if (context.mounted && connection.isConnected) {
                        Navigator.of(context).pop();
                      }
                    }
                  : null,
            ),
          ],
        if (otherDevices.isNotEmpty) ...[
          const SizedBox(height: 18),
          _DeviceGroupHeader(
            title: 'Other available devices',
            count: otherDevices.length,
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < otherDevices.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            _DeviceResult(
              device: otherDevices[index],
              connecting: false,
              connectionBusy: connectionBusy,
              onConnect: null,
            ),
          ],
        ],
      ],
    );
  }
}

class _DeviceGroupHeader extends StatelessWidget {
  const _DeviceGroupHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        Text(
          '$count',
          semanticsLabel: '$count devices',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: CrubikColors.muted),
        ),
      ],
    );
  }
}

class _NoIdentifiedCubes extends StatelessWidget {
  const _NoIdentifiedCubes();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: CrubikColors.elevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CrubikColors.border),
      ),
      child: Text(
        'No identified cubes found yet.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _DeviceResult extends StatelessWidget {
  const _DeviceResult({
    required this.device,
    required this.connecting,
    required this.connectionBusy,
    required this.onConnect,
  });

  final CubeDeviceCandidate device;
  final bool connecting;
  final bool connectionBusy;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    final isOtherDevice = !device.isIdentifiedCube;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: CrubikColors.elevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CrubikColors.border),
      ),
      child: Row(
        children: [
          Icon(isOtherDevice ? Icons.bluetooth : Icons.view_in_ar_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: CrubikColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isOtherDevice)
                  Text(
                    '${device.rssi ?? '—'} dBm · Not identified as a smart cube',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else if (device.isSupported)
                  Text(
                    '${device.vendor.name.toUpperCase()} · ${device.rssi ?? '—'} dBm',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else ...[
                  Text(
                    '${device.vendor.name.toUpperCase()} · Detected, not supported yet',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: CrubikColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    device.supportMessage ??
                        'This smart-cube protocol is not supported yet.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (device.canConnect)
            FilledButton(
              key: Key('connect-device-${device.id}'),
              onPressed: connectionBusy ? null : onConnect,
              child: Text(connecting ? 'Connecting…' : 'Connect'),
            )
          else if (device.isIdentifiedCube)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(
                Icons.info_outline,
                semanticLabel: 'Protocol not supported',
              ),
            ),
        ],
      ),
    );
  }
}
