import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:xterm/xterm.dart';

import '../models/ssh_credentials.dart';

class SshService {
  static const _storageKey = 'ssh_credentials';

  final FlutterSecureStorage _secureStorage;
  SSHClient? _client;
  SSHSession? _session;
  Terminal? _terminal;

  SshService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  bool get isConnected => _client != null && _session != null;

  Future<SshCredentials?> loadCredentials() async {
    final stored = await _secureStorage.read(key: _storageKey);
    if (stored == null) return null;
    try {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      return SshCredentials.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  Future<void> saveCredentials(SshCredentials credentials) async {
    final json = jsonEncode(credentials.toJson());
    await _secureStorage.write(key: _storageKey, value: json);
  }

  Future<void> clearCredentials() async {
    await _secureStorage.delete(key: _storageKey);
  }

  Future<bool> connect(SshCredentials credentials) async {
    try {
      _client = SSHClient(
        await SSHSocket.connect(credentials.host, credentials.port),
        username: credentials.username,
        onPasswordRequest: () => credentials.password,
      );

      _terminal = Terminal(
        maxLines: 10000,
      );

      _session = await _client!.shell(
        pty: SSHPtyConfig(
          width: _terminal!.viewWidth,
          height: _terminal!.viewHeight,
        ),
      );

      _terminal!.onResize = (width, height, pixelWidth, pixelHeight) {
        _session?.resizeTerminal(width, height, pixelWidth, pixelHeight);
      };

      if (credentials.workingDirectory.isNotEmpty) {
        _session!.stdin.add(utf8.encode('cd ${credentials.workingDirectory}\n'));
      }

      _session!.stdout.listen((data) {
        _terminal?.write(utf8.decode(data));
      });

      _session!.stderr.listen((data) {
        _terminal?.write(utf8.decode(data));
      });

      unawaited(_session!.done.then((_) async {
        final code = await _session!.exitCode;
        _terminal?.write('\r\n[Process exited with code $code]\r\n');
        disconnect();
      }));

      _terminal?.onOutput = (data) {
        _session?.stdin.add(utf8.encode(data));
      };

      return true;
    } catch (e) {
      _terminal?.write('\r\n[Connection error: $e]\r\n');
      disconnect();
      return false;
    }
  }

  Terminal? get terminal => _terminal;

  void resize(int width, int height) {
    if (_session != null) {
      _session!.resizeTerminal(width, height);
    }
  }

  void disconnect() {
    _session?.close();
    _session = null;
    _client?.close();
    _client = null;
    _terminal = null;
  }
}
