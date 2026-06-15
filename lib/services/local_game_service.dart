import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LocalGameService {
  LocalGameService._();

  static ServerSocket? _server;
  static Socket? _client;
  static StreamSubscription? _serverSub;
  static StreamSubscription? _clientSub;
  static bool _hosting = false;
  static bool _connected = false;

  static bool get isHosting => _hosting;
  static bool get isConnected => _connected;

  static final _controller = StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get messages => _controller.stream;

  static Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.address.startsWith('127.')) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<int> startHosting({required String playerName, required String playerId}) async {
    _dispose();
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final port = _server!.port;
    _hosting = true;

    _server!.listen((Socket socket) {
      if (_connected) {
        socket.destroy();
        return;
      }
      _client = socket;
      _connected = true;

      socket.listen(
        (data) {
          try {
            final msg = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
            _controller.add(msg);
          } catch (_) {}
        },
        onDone: () => _connected = false,
        onError: (_) => _connected = false,
      );

      _send({'type': 'handshake', 'name': playerName, 'id': playerId});
    });

    return port;
  }

  static Future<bool> connectToHost({
    required String host,
    required int port,
    required String playerName,
    required String playerId,
  }) async {
    _dispose();
    try {
      _client = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      _connected = true;

      _client!.listen(
        (data) {
          try {
            final msg = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
            _controller.add(msg);
          } catch (_) {}
        },
        onDone: () => _connected = false,
        onError: (_) => _connected = false,
      );

      _send({'type': 'handshake', 'name': playerName, 'id': playerId});
      return true;
    } catch (_) {
      return false;
    }
  }

  static void _send(Map<String, dynamic> msg) {
    if (_client == null) return;
    try {
      final data = utf8.encode(jsonEncode(msg));
      _client!.add(data);
    } catch (_) {}
  }

  static void sendSmile(double value) {
    _send({'type': 'smile', 'value': value});
  }

  static void sendFace(String base64) {
    _send({'type': 'face', 'data': base64});
  }

  static void sendGameEvent(String event) {
    _send({'type': 'event', 'event': event});
  }

  static void dispose() {
    _dispose();
  }

  static void _dispose() {
    _hosting = false;
    _connected = false;
    _client?.destroy();
    _client = null;
    _server?.close();
    _server = null;
  }
}
