import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:xterm/xterm.dart';

import '../models/ssh_credentials.dart';
import 'connection_manager.dart';
import 'foreground_service.dart';

class SshService {
  static const _storageKey = 'ssh_credentials';

  String _safeUtf8Decode(List<int> data) {
    try {
      return utf8.decode(data, allowMalformed: true);
    } catch (e) {
      return String.fromCharCodes(data);
    }
  }

  final FlutterSecureStorage _secureStorage;
  SSHClient? _client;
  SSHSession? _session;
  Terminal? _terminal;
  SftpClient? _sftp;

  SshCredentials? _lastCredentials;
  ConnectionStateMachine? _connectionStateMachine;

  final _connectionStateController =
      StreamController<SshConnectionState>.broadcast();
  Stream<SshConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  final _reconnectAttemptController =
      StreamController<ReconnectAttempt>.broadcast();
  Stream<ReconnectAttempt> get reconnectAttemptStream =>
      _reconnectAttemptController.stream;

  SshService({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  bool get isConnected =>
      _client != null &&
      _session != null &&
      _connectionStateMachine?.state == SshConnectionState.connected;

  SshConnectionState get connectionState =>
      _connectionStateMachine?.state ?? SshConnectionState.disconnected;

  int get currentRetryAttempt =>
      _connectionStateMachine?.currentRetryAttempt ?? 0;

  SSHClient? get client => _client;

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

  Future<bool> connect(
    SshCredentials credentials, {
    bool remember = false,
    void Function(String error)? onError,
  }) async {
    _lastCredentials = credentials;

    _connectionStateMachine = ConnectionStateMachine(
      onStateChanged: (oldState, newState) {
        _connectionStateController.add(newState);
      },
      onRetry: (attempt, delay) {
        _reconnectAttemptController.add(
          ReconnectAttempt(attempt: attempt, delay: delay),
        );
      },
      onMaxRetriesReached: () {
        _terminal?.write(
          '\r\n[Connection failed: Maximum retries reached]\r\n',
        );
      },
    );

    final success = await _connectionStateMachine!.connect(
      () => _establishConnection(credentials, onError: onError),
    );

    if (success) {
      _startKeepalive();
      _startForegroundService();
    }

    return success;
  }

  Future<bool> _establishConnection(
    SshCredentials credentials, {
    void Function(String error)? onError,
  }) async {
    try {
      _client = SSHClient(
        await SSHSocket.connect(credentials.host, credentials.port),
        username: credentials.username,
        onPasswordRequest: () => credentials.password,
      );

      _terminal = Terminal(maxLines: 10000);

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
        _session!.stdin.add(
          utf8.encode('cd ${credentials.workingDirectory}\n'),
        );
      }

      _session!.stdout.listen((data) {
        _terminal?.write(_safeUtf8Decode(data));
      });

      _session!.stderr.listen((data) {
        _terminal?.write(_safeUtf8Decode(data));
      });

      unawaited(
        _session!.done.then((_) async {
          if (_session == null) return;
          final code = await _session!.exitCode;
          _terminal?.write('\r\n[Process exited with code $code]\r\n');
          handleConnectionLost();
        }),
      );

      _terminal?.onOutput = (data) {
        _session?.stdin.add(utf8.encode(data));
      };

      return true;
    } catch (e) {
      final errorMsg = _formatConnectionError(e);
      _terminal?.write('\r\n[Connection error: $errorMsg]\r\n');
      onError?.call(errorMsg);
      _cleanupConnection();
      return false;
    }
  }

  String _formatConnectionError(dynamic e) {
    final errorStr = e.toString();
    if (errorStr.contains('Connection refused')) {
      return 'Connection refused. Please check if the SSH server is running.';
    } else if (errorStr.contains('Connection timed out') ||
        errorStr.contains('Timeout')) {
      return 'Connection timed out. Please check if the host is reachable.';
    } else if (errorStr.contains('Host not found') ||
        errorStr.contains('Name or service not known') ||
        errorStr.contains('getAddressInfo')) {
      return 'Host not found. Please check the hostname.';
    } else if (errorStr.contains('Authentication failed') ||
        errorStr.contains('Auth')) {
      return 'Authentication failed. Please check your username and password.';
    } else if (errorStr.contains('SocketException')) {
      return 'Unable to connect. Please check the host and port.';
    }
    return errorStr;
  }

  Future<bool> reconnect() async {
    if (_lastCredentials == null) {
      return false;
    }

    if (_connectionStateMachine == null) {
      _connectionStateMachine = ConnectionStateMachine(
        onStateChanged: (oldState, newState) {
          _connectionStateController.add(newState);
        },
        onRetry: (attempt, delay) {
          _reconnectAttemptController.add(
            ReconnectAttempt(attempt: attempt, delay: delay),
          );
        },
        onMaxRetriesReached: () {
          _terminal?.write(
            '\r\n[Reconnection failed: Maximum retries reached]\r\n',
          );
        },
      );
    }

    _terminal?.write('\r\n[Attempting to reconnect...]\r\n');

    String? lastError;
    final success = await _connectionStateMachine!.reconnect(
      () => _reestablishConnection(
        _lastCredentials!,
        onError: (e) => lastError = e,
      ),
    );

    if (success) {
      _startKeepalive();
      _terminal?.write('\r\n[Connection restored]\r\n');
    }

    return success;
  }

  Future<bool> _reestablishConnection(
    SshCredentials credentials, {
    void Function(String error)? onError,
  }) async {
    try {
      _cleanupConnection();

      _client = SSHClient(
        await SSHSocket.connect(credentials.host, credentials.port),
        username: credentials.username,
        onPasswordRequest: () => credentials.password,
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
        _session!.stdin.add(
          utf8.encode('cd ${credentials.workingDirectory}\n'),
        );
      }

      _session!.stdout.listen((data) {
        _terminal?.write(_safeUtf8Decode(data));
      });

      _session!.stderr.listen((data) {
        _terminal?.write(_safeUtf8Decode(data));
      });

      unawaited(
        _session!.done.then((_) async {
          if (_session == null) return;
          final code = await _session!.exitCode;
          _terminal?.write('\r\n[Process exited with code $code]\r\n');
          handleConnectionLost();
        }),
      );

      _terminal?.onOutput = (data) {
        _session?.stdin.add(utf8.encode(data));
      };

      _sftp = null;

      return true;
    } catch (e) {
      final errorMsg = _formatConnectionError(e);
      _terminal?.write('\r\n[Reconnection error: $errorMsg]\r\n');
      onError?.call(errorMsg);
      _cleanupConnection();
      return false;
    }
  }

  void handleConnectionLost() {
    _connectionStateMachine?.onConnectionLost();
    _connectionStateController.add(SshConnectionState.disconnected);
  }

  void _startKeepalive() {
    _connectionStateMachine?.startKeepalive(
      checkConnection: () async {
        try {
          if (_client == null) return false;
          await _client!.authenticated;
          return true;
        } catch (e) {
          return false;
        }
      },
      interval: const Duration(seconds: 15),
    );
  }

  void _startForegroundService() {
    if (Platform.isAndroid) {
      ForegroundServiceManager().startService();
    }
  }

  void _stopForegroundService() {
    if (Platform.isAndroid) {
      ForegroundServiceManager().stopService();
    }
  }

  Terminal? get terminal => _terminal;

  void resize(int width, int height) {
    if (_session != null) {
      _session!.resizeTerminal(width, height);
    }
  }

  void disconnect() {
    _connectionStateMachine?.stopKeepalive();
    _connectionStateMachine?.disconnect();
    _cleanupConnection();
    _connectionStateController.add(SshConnectionState.disconnected);
    _stopForegroundService();
  }

  void _cleanupConnection() {
    _session?.close();
    _session = null;
    _sftp?.close();
    _sftp = null;
    _client?.close();
    _client = null;
  }

  Future<SftpClient> getSftp() async {
    if (_sftp != null) return _sftp!;
    if (_client == null) {
      throw Exception('Not connected to SSH server');
    }
    _sftp = await _client!.sftp();
    return _sftp!;
  }

  Future<bool> checkSftpConnection() async {
    try {
      final sftp = await getSftp();
      await sftp.listdir('.');
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> checkSshConnection() async {
    try {
      if (_client == null || _session == null) return false;
      await _client!.authenticated;
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<List<SftpName>> listDirectory(String path) async {
    final sftp = await getSftp();
    return await sftp.listdir(path);
  }

  Future<void> createDirectory(String path) async {
    final sftp = await getSftp();
    await sftp.mkdir(path);
  }

  Future<void> delete(String path, {bool recursive = false}) async {
    final sftp = await getSftp();
    final stat = await sftp.stat(path);
    if (stat.isDirectory) {
      if (recursive) {
        final items = await sftp.listdir(path);
        for (final item in items) {
          if (item.filename == '.' || item.filename == '..') continue;
          final itemPath = '$path/${item.filename}';
          await delete(itemPath, recursive: true);
        }
      }
      await sftp.rmdir(path);
    } else {
      await sftp.remove(path);
    }
  }

  Future<void> rename(String oldPath, String newPath) async {
    final sftp = await getSftp();
    await sftp.rename(oldPath, newPath);
  }

  Future<void> downloadFile(
    String remotePath,
    String localPath, {
    void Function(int received, int total)? onProgress,
    int? resumeOffset,
  }) async {
    final sftp = await getSftp();
    final stat = await sftp.stat(remotePath);
    final total = stat.size ?? 0;

    int startOffset = 0;
    FileMode fileMode = FileMode.writeOnly;

    if (resumeOffset != null && resumeOffset > 0) {
      final partFile = File('$localPath.part');
      if (await partFile.exists()) {
        final partStat = await partFile.stat();
        startOffset = partStat.size;
        fileMode = FileMode.writeOnlyAppend;
      }
    }

    final localFile = File('$localPath.part');
    final raf = await localFile.open(mode: fileMode);

    try {
      final remoteFile = await sftp.open(
        remotePath,
        mode: SftpFileOpenMode.read,
      );

      final stream = remoteFile.read(offset: startOffset);

      await for (final chunk in stream) {
        await raf.writeFrom(chunk);

        await Future.delayed(Duration.zero);

        onProgress?.call(startOffset + chunk.length, total);
        startOffset += chunk.length;
      }

      await raf.close();
      await remoteFile.close();

      await localFile.rename(localPath);
    } catch (e) {
      await raf.close();
      rethrow;
    }
  }

  Future<RemoteFileInfo> getRemoteFileInfo(String remotePath) async {
    final sftp = await getSftp();
    final stat = await sftp.stat(remotePath);
    return RemoteFileInfo(
      size: stat.size ?? 0,
      modified: stat.modifyTime != null
          ? DateTime.fromMillisecondsSinceEpoch(stat.modifyTime! * 1000)
          : null,
    );
  }

  Future<void> uploadFile(
    String localPath,
    String remotePath, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final sftp = await getSftp();
    final localFile = File(localPath);
    final total = await localFile.length();

    final remoteFile = await sftp.open(
      remotePath,
      mode:
          SftpFileOpenMode.create |
          SftpFileOpenMode.write |
          SftpFileOpenMode.truncate,
    );

    final bytes = await localFile.readAsBytes();
    await remoteFile.write(Stream.value(bytes));
    await remoteFile.close();
    onProgress?.call(total, total);
  }

  Future<String> getHomeDirectory() async {
    final sftp = await getSftp();
    return await sftp.absolute('.');
  }

  void dispose() {
    _connectionStateMachine?.dispose();
    _connectionStateController.close();
    _reconnectAttemptController.close();
  }
}

class RemoteFileInfo {
  final int size;
  final DateTime? modified;

  RemoteFileInfo({required this.size, this.modified});
}

class ReconnectAttempt {
  final int attempt;
  final Duration delay;

  ReconnectAttempt({required this.attempt, required this.delay});
}

void unawaited(Future<void> future) {}
