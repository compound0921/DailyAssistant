import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'lan_sync_snapshot.dart';

const _protocol = 'DA-LAN1';
const _transferTimeout = Duration(seconds: 45);

Uint8List _randomBytes(int count) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(count, (_) => random.nextInt(256)));
}

bool _localAddress(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4) return false;
  final bytes = address.rawAddress;
  return address.isLoopback ||
      bytes[0] == 10 ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
      (bytes[0] == 192 && bytes[1] == 168) ||
      (bytes[0] == 169 && bytes[1] == 254);
}

/// 连接码包含临时密钥，不写入日志、磁盘或公开链接。
class LanSyncConnection {
  LanSyncConnection(this.host, this.port, Uint8List key) : _key = key;
  final String host;
  final int port;
  final Uint8List _key;

  String encode() =>
      '$_protocol:${base64Url.encode(utf8.encode(jsonEncode({'host': host, 'port': port, 'key': base64Url.encode(_key)})))}';

  static LanSyncConnection parse(String code) {
    try {
      final trimmed = code.trim();
      if (!trimmed.startsWith('$_protocol:') || trimmed.length > 1024) {
        throw const FormatException();
      }
      final json =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(trimmed.substring(_protocol.length + 1)),
                ),
              )
              as Map<String, dynamic>;
      final host = json['host'] as String;
      final address = InternetAddress.tryParse(host);
      final port = json['port'] as int;
      final key = base64Url.decode(json['key'] as String);
      if (address == null ||
          !_localAddress(address) ||
          port < 1 ||
          port > 65535 ||
          key.length != 32) {
        throw const FormatException();
      }
      return LanSyncConnection(host, port, key);
    } catch (_) {
      throw const LanSyncException('连接码无效，请复制发送端显示的完整连接码');
    }
  }
}

Uint8List _seal(List<int> message, Uint8List key, String purpose) {
  final nonce = _randomBytes(12);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(
        KeyParameter(key),
        128,
        nonce,
        Uint8List.fromList(utf8.encode('$_protocol:$purpose')),
      ),
    );
  return Uint8List.fromList([
    ...nonce,
    ...cipher.process(Uint8List.fromList(message)),
  ]);
}

Uint8List _open(List<int> packet, Uint8List key, String purpose) {
  try {
    if (packet.length < 28) throw const FormatException();
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          128,
          Uint8List.fromList(packet.sublist(0, 12)),
          Uint8List.fromList(utf8.encode('$_protocol:$purpose')),
        ),
      );
    return cipher.process(Uint8List.fromList(packet.sublist(12)));
  } catch (_) {
    throw const LanSyncException('连接码不匹配或传输校验失败，未修改本机数据');
  }
}

/// 长度前缀分帧，避免 TCP 分包、提前断开或超大数据被当成完整快照。
class _Channel {
  _Channel(this.socket) : _reader = StreamIterator(socket);
  final Socket socket;
  final StreamIterator<Uint8List> _reader;
  List<int> _chunk = const [];
  int _offset = 0;

  Future<Uint8List> _read(int count) async {
    final buffer = BytesBuilder(copy: false);
    while (buffer.length < count) {
      if (_offset == _chunk.length) {
        if (!await _reader.moveNext()) {
          throw const LanSyncException('连接已中断，未修改本机数据');
        }
        _chunk = _reader.current;
        _offset = 0;
      }
      final size = min(count - buffer.length, _chunk.length - _offset);
      buffer.add(_chunk.sublist(_offset, _offset + size));
      _offset += size;
    }
    return buffer.takeBytes();
  }

  Future<Uint8List> readFrame({
    int limit = LanSyncSnapshot.maxBytes + 1024,
  }) async {
    final header = await _read(4);
    final size = ByteData.sublistView(header).getUint32(0);
    if (size < 28 || size > limit) {
      throw const LanSyncException('收到的数据大小异常，未修改本机数据');
    }
    return _read(size);
  }

  Future<void> send(List<int> packet) async {
    final header = ByteData(4)..setUint32(0, packet.length);
    socket.add(header.buffer.asUint8List());
    socket.add(packet);
    await socket.flush();
  }

  Future<void> close() async {
    socket.destroy();
    await _reader.cancel();
  }
}

class LanSyncShare {
  LanSyncShare._(
    this._server,
    this.addresses,
    this._key,
    this._data, {
    this.onSent,
    this.onExpired,
    required Duration lifetime,
  }) {
    _server.listen(_accept, onError: (_) => unawaited(close()));
    _expiry = Timer(lifetime, () {
      unawaited(close());
      onExpired?.call();
    });
  }

  final ServerSocket _server;
  final List<String> addresses;
  final Uint8List _key;
  final List<int> _data;
  final void Function()? onSent;
  final void Function()? onExpired;
  final Set<Socket> _connections = {};
  late final Timer _expiry;
  bool _closed = false;
  int get port => _server.port;
  String codeFor(String address) =>
      LanSyncConnection(address, port, _key).encode();

  void _accept(Socket socket) {
    if (_closed ||
        !_localAddress(socket.remoteAddress) ||
        _connections.length >= 3) {
      socket.destroy();
      return;
    }
    _connections.add(socket);
    unawaited(_send(socket));
  }

  Future<void> _send(Socket socket) async {
    final channel = _Channel(socket);
    try {
      final packet = await channel
          .readFrame(limit: 1024)
          .timeout(const Duration(seconds: 8));
      final challenge = _open(packet, _key, 'request');
      if (challenge.length != 32) throw const FormatException();
      // 绑定本次请求，旧响应不能被重放成一次新同步。
      final response = _seal([...challenge, ..._data], _key, 'snapshot');
      await channel.send(response).timeout(_transferTimeout);
      if (!_closed) onSent?.call();
    } catch (_) {
      // 无效密钥或中断只关闭该连接，不输出连接码及数据内容。
    } finally {
      _connections.remove(socket);
      await channel.close();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _expiry.cancel();
    for (final socket in _connections.toList()) {
      socket.destroy();
    }
    await _server.close();
  }
}

class LanSyncTransport {
  Socket? _receiving;
  bool _disposed = false;

  Future<LanSyncShare> share(
    LanSyncSnapshot snapshot, {
    void Function()? onSent,
    void Function()? onExpired,
    Duration lifetime = const Duration(minutes: 10),
    InternetAddress? bindAddress,
  }) async {
    final data = snapshot.encode();
    LanSyncSnapshot.decode(data);
    final addresses = bindAddress == null
        ? (await NetworkInterface.list(type: InternetAddressType.IPv4))
              .expand((interface) => interface.addresses)
              .where((address) => _localAddress(address) && !address.isLoopback)
              .map((address) => address.address)
              .toSet()
              .toList()
        : [bindAddress.address];
    if (addresses.isEmpty) {
      throw const LanSyncException('未找到局域网地址，请先连接 Wi-Fi、网线或手机热点');
    }
    final server = await ServerSocket.bind(
      bindAddress ?? InternetAddress.anyIPv4,
      0,
    );
    if (_disposed) {
      await server.close();
      throw const LanSyncException('同步页面已关闭');
    }
    return LanSyncShare._(
      server,
      addresses,
      _randomBytes(32),
      data,
      onSent: onSent,
      onExpired: onExpired,
      lifetime: lifetime,
    );
  }

  Future<LanSyncSnapshot> receive(String code) async {
    final connection = LanSyncConnection.parse(code);
    _Channel? channel;
    try {
      final socket = await Socket.connect(
        connection.host,
        connection.port,
        timeout: const Duration(seconds: 8),
      );
      if (_disposed) {
        socket.destroy();
        throw const LanSyncException('同步页面已关闭');
      }
      _receiving = socket;
      channel = _Channel(socket);
      final challenge = _randomBytes(32);
      await channel
          .send(_seal(challenge, connection._key, 'request'))
          .timeout(_transferTimeout);
      final packet = await channel.readFrame().timeout(_transferTimeout);
      final data = _open(packet, connection._key, 'snapshot');
      if (data.length < challenge.length) throw const FormatException();
      for (var i = 0; i < challenge.length; i++) {
        if (challenge[i] != data[i]) throw const FormatException();
      }
      return LanSyncSnapshot.decode(data.sublist(challenge.length));
    } on LanSyncException {
      rethrow;
    } on TimeoutException {
      throw const LanSyncException('连接超时，请保持两端同步页面打开，并检查防火墙及校园网设备隔离');
    } on SocketException {
      throw const LanSyncException('无法连接发送端，请确认同一局域网、连接码仍有效且防火墙允许连接');
    } catch (_) {
      throw const LanSyncException('传输未完成或校验失败，未修改本机数据');
    } finally {
      _receiving = null;
      await channel?.close();
    }
  }

  void cancelReceive() => _receiving?.destroy();
  void dispose() {
    _disposed = true;
    cancelReceive();
  }
}
