import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/cli_device.dart';
import 'app_logger.dart';
import 'preferences_service.dart';

class LanDiscoveryService {
  final PreferencesService _preferencesService;
  final HttpClient _httpClient;

  LanDiscoveryService(this._preferencesService, {HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  Stream<List<DiscoveredCliDevice>> scanStream({
    int port = 4058,
    Duration timeout = const Duration(milliseconds: 350),
  }) {
    late final StreamController<List<DiscoveredCliDevice>> controller;
    controller = StreamController<List<DiscoveredCliDevice>>(
      onCancel: () async {
        if (!controller.isClosed) {
          await controller.close();
        }
      },
    );
    unawaited(_runScan(controller, port: port, timeout: timeout));
    return controller.stream;
  }

  Future<List<DiscoveredCliDevice>> scan({
    int port = 4058,
    Duration timeout = const Duration(milliseconds: 350),
  }) async {
    var latest = const <DiscoveredCliDevice>[];
    await for (final devices in scanStream(port: port, timeout: timeout)) {
      latest = devices;
    }
    return latest;
  }

  Future<void> _runScan(
    StreamController<List<DiscoveredCliDevice>> controller, {
    required int port,
    required Duration timeout,
  }) async {
    AppLogger.instance.info(
      'LAN discovery scan started',
      scope: 'discovery',
      data: {'port': port, 'timeoutMs': timeout.inMilliseconds},
    );
    try {
      final paired = await _preferencesService.getPairedCliDevices();
      final pairedByHost = <String, Map<String, dynamic>>{
        for (final device in paired)
          '${device['host']}:${device['port']}': device,
      };

      final preferredHosts = paired
          .map((device) => device['host']?.toString() ?? '')
          .where((host) => host.isNotEmpty);
      final hosts = await _candidateHosts(preferredHosts: preferredHosts);
      final devicesByHost = <String, DiscoveredCliDevice>{};

      await Future.wait(
        hosts.map((host) async {
          final device = await _probeHost(host, port, timeout, pairedByHost);
          if (device == null || controller.isClosed) {
            return;
          }

          devicesByHost['${device.host}:${device.port}'] = device;
          controller.add(_sortDevices(devicesByHost.values));
        }),
      );

      final devices = _sortDevices(devicesByHost.values);
      AppLogger.instance.info(
        'LAN discovery scan completed',
        scope: 'discovery',
        data: {
          'count': devices.length,
          'devices': devices
              .map((device) => device.toStored())
              .toList(growable: false),
        },
      );
      if (!controller.isClosed) {
        await controller.close();
      }
    } catch (error, stackTrace) {
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
        await controller.close();
      }
    }
  }

  Future<DiscoveredCliDevice> redeemPairing({
    required DiscoveredCliDevice device,
    required String code,
  }) async {
    AppLogger.instance.info(
      'Redeeming CLI pairing code',
      scope: 'discovery',
      data: {
        'host': device.host,
        'port': device.port,
        'isPaired': device.isPaired,
      },
    );
    final uri = Uri.parse('${device.baseUrl}/v1/pairing/code/redeem');
    final request = await _httpClient
        .postUrl(uri)
        .timeout(const Duration(seconds: 3));
    final phoneName =
        'moCODE ${Platform.operatingSystem[0].toUpperCase()}${Platform.operatingSystem.substring(1)}';
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'code': code, 'deviceName': phoneName}));
    final response = await request.close().timeout(const Duration(seconds: 4));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body.isEmpty ? 'Pairing failed.' : body);
    }
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final paired = device.copyWith(
      isPaired: true,
      token: decoded['token'] as String?,
      pairedDeviceId: (decoded['device'] as Map?)?['id']?.toString(),
    );
    await _preferencesService.savePairedCliDevice(paired.toStored());
    AppLogger.instance.info(
      'CLI pairing succeeded',
      scope: 'discovery',
      data: paired.toStored(),
    );
    return paired;
  }

  List<DiscoveredCliDevice> _sortDevices(
    Iterable<DiscoveredCliDevice> devices,
  ) {
    final sorted = devices.toList(growable: false);
    sorted.sort((left, right) {
      if (left.isPaired != right.isPaired) {
        return left.isPaired ? -1 : 1;
      }
      return left.deviceName.toLowerCase().compareTo(
        right.deviceName.toLowerCase(),
      );
    });
    return sorted;
  }

  Future<List<String>> _candidateHosts({
    Iterable<String> preferredHosts = const <String>[],
  }) async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: true,
      type: InternetAddressType.IPv4,
    );
    final discoveredHosts = <String>{'127.0.0.1'};

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final parts = address.address.split('.');
        if (parts.length != 4) {
          continue;
        }
        final first = int.tryParse(parts[0]) ?? 0;
        final second = int.tryParse(parts[1]) ?? 0;
        if (!_isPrivate(first, second)) {
          continue;
        }
        final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
        for (var i = 1; i <= 254; i++) {
          discoveredHosts.add('$prefix.$i');
        }
      }
    }

    final orderedHosts = <String>[];
    final seen = <String>{};

    void addHost(String host) {
      if (host.isEmpty || seen.contains(host)) {
        return;
      }
      seen.add(host);
      orderedHosts.add(host);
    }

    addHost('127.0.0.1');
    for (final host in preferredHosts) {
      addHost(host);
    }

    final remainingHosts = discoveredHosts.toList()..sort();
    for (final host in remainingHosts) {
      addHost(host);
    }

    return orderedHosts;
  }

  bool _isPrivate(int first, int second) {
    if (first == 10) {
      return true;
    }
    if (first == 172 && second >= 16 && second <= 31) {
      return true;
    }
    return first == 192 && second == 168;
  }

  Future<DiscoveredCliDevice?> _probeHost(
    String host,
    int port,
    Duration timeout,
    Map<String, Map<String, dynamic>> pairedByHost,
  ) async {
    final uri = Uri.parse('http://$host:$port/v1/discovery');
    try {
      final request = await _httpClient.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final key = '$host:$port';
      final paired = pairedByHost[key];
      final device = DiscoveredCliDevice(
        host: host,
        port: port,
        deviceName:
            decoded['deviceName'] as String? ??
            decoded['hostname'] as String? ??
            host,
        deviceModel: decoded['deviceModel'] as String?,
        platform: decoded['platform'] as String?,
        isPaired: paired != null,
        token: paired?['token'] as String?,
        pairedDeviceId: paired?['deviceId'] as String?,
      );
      AppLogger.instance.debug(
        'Discovered CLI device',
        scope: 'discovery',
        data: device.toStored(),
      );
      return device;
    } catch (_) {
      return null;
    }
  }
}
