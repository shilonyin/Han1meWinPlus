import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// 一次投屏推送过来的媒体（手机端 SetAVTransportURI 带的东西）。
class CastMediaItem {
  const CastMediaItem({required this.url, required this.title, this.metadata});

  final String url;
  final String title;

  /// 控制点附带的 DIDL-Lite 元数据，可能为空。
  final String? metadata;

  @override
  bool operator ==(Object other) => other is CastMediaItem && other.url == url && other.title == title;

  @override
  int get hashCode => Object.hash(url, title);
}

/// 接收端当前的真实播放进度：由界面层回填，用来响应 SOAP 的进度查询。
class CastPlaybackState {
  const CastPlaybackState({this.position = Duration.zero, this.duration = Duration.zero, this.playing = false});

  final Duration position;
  final Duration duration;
  final bool playing;
}

/// UPnP AVTransport 的传输状态；取值必须严格按规范拼写（控制点按字面比对）。
enum CastTransportState { stopped, playing, paused, transitioning, noMediaPresent }

/// 接收端把收到的指令交给界面层的通道。
///
/// 服务端只负责协议，不碰播放器：具体怎么播由实现了这个接口的对象决定。
abstract class CastRendererDelegate {
  void onSetMedia(CastMediaItem item);
  void onPlay();
  void onPause();
  void onStop();
  void onSeek(Duration position);
  void onVolume(int volume);
  void onMute(bool muted);

  /// 播放进度查询（GetPositionInfo / GetMediaInfo）要用的真实状态。
  CastPlaybackState get playbackState;
}

/// 接收端的运行状态（给设置页显示用）。
class CastRendererStatus {
  const CastRendererStatus({required this.running, required this.location, required this.addresses, this.detail});

  final bool running;

  /// 设备描述地址（LOCATION），未运行时为空串。
  final String location;
  final List<String> addresses;

  /// 启动失败的原因（端口被占、拿不到局域网地址等），正常运行时为 null。
  final String? detail;

  static const CastRendererStatus off = CastRendererStatus(running: false, location: '', addresses: <String>[]);
}

/// 一个极简的 DLNA / UPnP **MediaRenderer**（接收端）。
///
/// `dlna_dart` 只实现了控制点（发送端），接收端这里自己搭：
/// - SSDP：监听 `239.255.255.250:1900`，回应 `M-SEARCH *`，并周期性广播 `ssdp:alive`
/// - 描述：HTTP 提供 `device.xml` 与三个服务的 SCPD
/// - 控制：HTTP 提供 SOAP 端点（AVTransport / RenderingControl / ConnectionManager）
///
/// 手机上点「投屏」时，控制点会先 `SetAVTransportURI` 再 `Play`，
/// 这两条都会通过 [CastRendererDelegate] 转交给界面层。
class DlnaMediaRenderer {
  // 测试钩子：SSDP 端口固定 1900 会与本机其它服务/同机测试撞车，
  // 允许注入自定义端口（生产路径不传，仍是 1900）。
  DlnaMediaRenderer({required this.deviceName, this.delegate, String? uuid, int? ssdpPort})
      : _uuid = uuid ?? _generateUuid(),
        _ssdpPortOverride = ssdpPort;

  /// 设备在局域网里显示的名字。
  final String deviceName;

  /// 指令出口；由界面层的桥接对象实现。
  CastRendererDelegate? delegate;

  static const String _ssdpAddress = '239.255.255.250';
  static const int _ssdpPort = 1900;

  /// 测试注入的 SSDP 端口；null 时用标准 1900。
  final int? _ssdpPortOverride;

  /// 实际生效的 SSDP 端口。
  int get _ssdpPortEffective => _ssdpPortOverride ?? _ssdpPort;

  /// `ssdp:alive` 的宣告周期：`CACHE-CONTROL: max-age=1800`，所以在 10 分钟处续一次。
  static const Duration _aliveInterval = Duration(minutes: 10);

  final String _uuid;
  final math.Random _random = math.Random();
  final HtmlEscape _escape = const HtmlEscape();

  HttpServer? _server;
  RawDatagramSocket? _ssdpSocket;
  /// 1900 端口被独占时退而求其次的发送用 socket（只能发 NOTIFY，收不到 M-SEARCH）。
  RawDatagramSocket? _notifySocket;
  Timer? _aliveTimer;
  final List<Timer> _pendingReplies = <Timer>[];

  List<String> _addresses = const <String>[];
  var _running = false;
  String? _detail;

  CastMediaItem? _currentItem;
  CastTransportState _transportState = CastTransportState.noMediaPresent;
  var _volume = 80;
  var _muted = false;

  bool get isRunning => _running;
  int? get port => _server?.port;
  List<String> get addresses => _addresses;
  String get friendlyName => deviceName;

  String get _udn => 'uuid:$_uuid';

  /// 设备描述地址；未启动时为空串。
  String get location {
    if (_server == null || _addresses.isEmpty) return '';
    return 'http://${_addresses.first}:${_server!.port}/device.xml';
  }

  CastRendererStatus get status => CastRendererStatus(running: _running, location: location, addresses: _addresses, detail: _detail);

  /// SSDP 宣告 + HTTP 描述 / 控制服务。
  ///
  /// [port] 传 0 由系统分配（默认）。失败时不会抛，原因写在 [status.detail] 里。
  Future<bool> start({int port = 0}) async {
    if (_running) return true;
    _detail = '';
    _addresses = await _localAddresses();
    if (_addresses.isEmpty) {
      _detail = 'noLocalAddress';
      return false;
    }
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    } catch (error) {
      _detail = 'bindHttpFailed';
      _server = null;
      return false;
    }
    _server!.listen(_handleRequest, onError: (_) {}, cancelOnError: false);

    await _bindSsdpSocket();
    _announceAlive();
    _aliveTimer?.cancel();
    _aliveTimer = Timer.periodic(_aliveInterval, (_) => _announceAlive());
    _running = true;
    return true;
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _aliveTimer?.cancel();
    _aliveTimer = null;
    for (final timer in _pendingReplies) {
      timer.cancel();
    }
    _pendingReplies.clear();
    _announceByeBye();
    _ssdpSocket?.close();
    _ssdpSocket = null;
    _notifySocket?.close();
    _notifySocket = null;
    final server = _server;
    _server = null;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }
    _transportState = CastTransportState.noMediaPresent;
  }

  /// 界面层告知「已停止播放」时同步一下传输状态（比如用户关掉了投屏页）。
  void reportStopped() {
    _transportState = CastTransportState.stopped;
  }

  // ---------------------------------------------------------------- 网络与 SSDP

  /// 取本机局域网 IPv4 地址：私网段优先（LOCATION 要能被手机访问到）。
  Future<List<String>> _localAddresses() async {
    final all = <String>[];
    final preferred = <String>[];
    try {
      for (final interface in await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false, includeLinkLocal: false)) {
        for (final address in interface.addresses) {
          if (address.type != InternetAddressType.IPv4) continue;
          final ip = address.address;
          all.add(ip);
          if (_isPrivateAddress(ip)) preferred.add(ip);
        }
      }
    } catch (_) {
      return const <String>[];
    }
    preferred.sort();
    all.sort();
    return preferred.isNotEmpty ? preferred : all;
  }

  static bool _isPrivateAddress(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) return false;
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }

  Future<void> _bindSsdpSocket() async {
    try {
      // Windows 不支持 reusePort（Dart 会直接抛 SocketException，见
      // socket_win.cc 的 reusePort 报错），1900 端口在 Windows 上本就允许
      // 与系统服务（WS-Discovery 等）按 SO_REUSEADDR 共存，所以只有
      // POSIX 平台才传 reusePort。
      final reusePort = !Platform.isWindows;
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _ssdpPortEffective, reusePort: reusePort);
      socket.joinMulticast(InternetAddress(_ssdpAddress));
      socket.listen(_onSocketEvent, onError: (_) {}, cancelOnError: false);
      _ssdpSocket = socket;
      return;
    } catch (_) {
      // 1900 被别的程序独占（比如某些投屏软件）：至少还能广播 alive，
      // 控制点一般会缓存宣告结果，仍有机会被搜到。
      _detail = 'ssdpPortBusy';
    }
    try {
      _notifySocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    } catch (_) {}
  }

  void _onSocketEvent(RawSocketEvent event) {
    final socket = _ssdpSocket;
    if (socket == null || event != RawSocketEvent.read) return;
    Datagram? datagram;
    do {
      datagram = socket.receive();
      if (datagram != null) _handleSsdpPacket(datagram);
    } while (datagram != null);
  }

  void _handleSsdpPacket(Datagram datagram) {
    final message = String.fromCharCodes(datagram.data);
    final lines = message.split('\n');
    if (lines.isEmpty) return;
    if (!lines.first.trim().toUpperCase().startsWith('M-SEARCH')) return;
    final headers = _parseHeaders(message);
    final searchTarget = headers['ST'];
    if (searchTarget == null) return;
    final matched = _matchSearchTarget(searchTarget);
    if (matched == null) return;
    // 按 MX（秒）稍作随机延迟再回，避免和局域网里其它设备撞在一起。
    final mx = int.tryParse(headers['MX'] ?? '1') ?? 1;
    final delay = mx <= 1 ? _random.nextInt(120) : _random.nextInt(math.min(mx * 200, 500));
    // 先声明再赋值：闭包里要引用 timer 自己，初始化器里引用不到自身。
    Timer? timer;
    timer = Timer(Duration(milliseconds: delay), () {
      _pendingReplies.remove(timer);
      _sendSearchResponse(datagram.address, datagram.port, matched);
    });
    _pendingReplies.add(timer);
  }

  /// 把搜索目标翻译成要回的 NT；不认识的目标（电视、打印机等）返回 null。
  String? _matchSearchTarget(String searchTarget) {
    const servicePrefix = 'urn:schemas-upnp-org:service:';
    const supportedServices = <String>{
      '${servicePrefix}AVTransport:1',
      '${servicePrefix}RenderingControl:1',
      '${servicePrefix}ConnectionManager:1',
    };
    final st = searchTarget.trim();
    if (st == 'ssdp:all') return 'upnp:rootdevice';
    if (st == 'upnp:rootdevice') return st;
    if (st == _udn || st == _uuid) return _udn;
    if (st == 'urn:schemas-upnp-org:device:MediaRenderer:1') return st;
    if (supportedServices.contains(st)) return st;
    return null;
  }

  void _sendSearchResponse(InternetAddress address, int port, String notificationType) {
    final socket = _ssdpSocket ?? _notifySocket;
    final location = this.location;
    if (socket == null || location.isEmpty) return;
    final usn = notificationType == _udn ? _udn : '$_udn::$notificationType';
    final body = <String>[
      'HTTP/1.1 200 OK',
      'CACHE-CONTROL: max-age=1800',
      'DATE: ${HttpDate.format(DateTime.now())}',
      'EXT:',
      'LOCATION: $location',
      'SERVER: $_serverToken',
      'ST: $notificationType',
      'USN: $usn',
      '',
      '',
    ].join('\r\n');
    try {
      socket.send(body.codeUnits, address, port);
    } catch (_) {}
  }

  static const String _serverToken = 'Windows/10.0 UPnP/1.0 Han1meWinPlus/1.0';

  void _announceAlive() {
    for (final address in _addresses) {
      for (final notificationType in _notificationTypes) {
        _sendNotify(address, notificationType, 'ssdp:alive');
      }
    }
  }

  void _announceByeBye() {
    for (final address in _addresses) {
      for (final notificationType in _notificationTypes) {
        _sendNotify(address, notificationType, 'ssdp:byebye');
      }
    }
  }

  List<String> get _notificationTypes => <String>[
        'upnp:rootdevice',
        _udn,
        'urn:schemas-upnp-org:device:MediaRenderer:1',
        'urn:schemas-upnp-org:service:AVTransport:1',
        'urn:schemas-upnp-org:service:RenderingControl:1',
        'urn:schemas-upnp-org:service:ConnectionManager:1',
      ];

  void _sendNotify(String address, String notificationType, String subtype) {
    final socket = _ssdpSocket ?? _notifySocket;
    final location = this.location;
    if (socket == null || location.isEmpty) return;
    final usn = notificationType == _udn ? _udn : '$_udn::$notificationType';
    final body = <String>[
      'NOTIFY * HTTP/1.1',
      'HOST: $_ssdpAddress:$_ssdpPortEffective',
      'CACHE-CONTROL: max-age=1800',
      'LOCATION: $location',
      'NT: $notificationType',
      'NTS: $subtype',
      'SERVER: $_serverToken',
      'USN: $usn',
      '',
      '',
    ].join('\r\n');
    try {
      socket.send(body.codeUnits, InternetAddress(_ssdpAddress), _ssdpPortEffective);
    } catch (_) {}
  }

  static Map<String, String> _parseHeaders(String message) {
    final headers = <String, String>{};
    for (final line in message.split('\n')) {
      final index = line.indexOf(':');
      if (index <= 0) continue;
      headers[line.substring(0, index).trim().toUpperCase()] = line.substring(index + 1).trim();
    }
    return headers;
  }

  // ---------------------------------------------------------------- HTTP 端点

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    response.headers.set('SERVER', _serverToken);
    try {
      final path = request.uri.path;
      switch (request.method) {
        case 'GET':
          _handleGet(request, path);
        case 'POST':
          await _handlePost(request, path);
        case 'SUBSCRIBE':
          _handleSubscribe(request, path);
        case 'UNSUBSCRIBE':
          _handleUnsubscribe(request);
        default:
          _respond(request, HttpStatus.methodNotAllowed, '');
      }
    } catch (_) {
      _respond(request, HttpStatus.internalServerError, '');
    }
    try {
      await response.close();
    } catch (_) {}
  }

  void _handleGet(HttpRequest request, String path) {
    switch (path) {
      case '/device.xml':
      case '/':
        _respond(request, HttpStatus.ok, _deviceDescription(), contentType: 'text/xml; charset="utf-8"');
      case '/av/scpd.xml':
        _respond(request, HttpStatus.ok, _avTransportScpd(), contentType: 'text/xml; charset="utf-8"');
      case '/rc/scpd.xml':
        _respond(request, HttpStatus.ok, _renderingControlScpd(), contentType: 'text/xml; charset="utf-8"');
      case '/cm/scpd.xml':
        _respond(request, HttpStatus.ok, _connectionManagerScpd(), contentType: 'text/xml; charset="utf-8"');
      default:
        _respond(request, HttpStatus.notFound, '');
    }
  }

  Future<void> _handlePost(HttpRequest request, String path) async {
    // utf8.decoder 的静态类型与 Stream<Uint8List>.transform 的形参不匹配，直接用 decodeStream。
    final body = await utf8.decodeStream(request);
    final action = _soapAction(request, body);
    if (action == null) {
      _respond(request, HttpStatus.badRequest, '');
      return;
    }
    final payload = switch (path) {
      '/av/control' => _avTransportAction(action, body),
      '/rc/control' => _renderingControlAction(action, body),
      '/cm/control' => _connectionManagerAction(action, body),
      _ => null,
    };
    if (payload == null) {
      _soapFault(request, action);
      return;
    }
    _respond(request, HttpStatus.ok, payload, contentType: 'text/xml; charset="utf-8"');
  }

  void _handleSubscribe(HttpRequest request, String path) {
    if (path != '/av/event' && path != '/rc/event' && path != '/cm/event') {
      _respond(request, HttpStatus.notFound, '');
      return;
    }
    final response = request.response;
    response.headers.set('SID', 'uuid:${_generateUuid()}');
    response.headers.set('TIMEOUT', 'Second-1800');
    response.statusCode = HttpStatus.ok;
    response.write('');
  }

  void _handleUnsubscribe(HttpRequest request) {
    request.response.statusCode = HttpStatus.ok;
    request.response.write('');
  }

  /// 控制点可能把动作放在 SOAPAction 头里，也可能只在 body 里；两处都认。
  String? _soapAction(HttpRequest request, String body) {
    final header = request.headers.value('SOAPAction')?.trim();
    if (header != null && header.isNotEmpty) {
      final value = header.replaceAll('"', '');
      final hash = value.indexOf('#');
      if (hash >= 0 && hash + 1 < value.length) return value.substring(hash + 1);
    }
    final match = RegExp(r'<u:([A-Za-z]+)\s+xmlns:u=').firstMatch(body);
    return match?.group(1);
  }

  void _respond(HttpRequest request, int status, String body, {String contentType = 'text/plain'}) {
    final response = request.response;
    response.statusCode = status;
    if (body.isNotEmpty) {
      response.headers.set('Content-Type', contentType);
      response.write(body);
    } else {
      response.headers.set('Content-Length', '0');
    }
  }

  void _soapFault(HttpRequest request, String action) {
    final body = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
<s:Body>
<s:Fault>
<faultcode>s:Client</faultcode>
<faultstring>UPnPError</faultstring>
<detail>
<UPnPError xmlns="urn:schemas-upnp-org:control-1-0">
<errorCode>401</errorCode>
<errorDescription>Invalid Action</errorDescription>
</UPnPError>
</detail>
</s:Fault>
</s:Body>
</s:Envelope>''';
    _respond(request, HttpStatus.internalServerError, body, contentType: 'text/xml; charset="utf-8"');
  }

  // ---------------------------------------------------------------- 控制动作

  String _avTransportAction(String action, String body) {
    final delegate = this.delegate;
    switch (action) {
      case 'SetAVTransportURI':
        final url = _tag(body, 'CurrentURI') ?? '';
        final metadata = _tag(body, 'CurrentURIMetaData');
        final title = _titleFromMetadata(metadata) ?? _titleFromUrl(url);
        _currentItem = CastMediaItem(url: _unescape(url), title: title, metadata: metadata);
        _transportState = CastTransportState.stopped;
        delegate?.onSetMedia(_currentItem!);
        return _soap('AVTransport', 'SetAVTransportURIResponse', '');
      case 'Play':
        _transportState = CastTransportState.playing;
        delegate?.onPlay();
        return _soap('AVTransport', 'PlayResponse', '');
      case 'Pause':
        _transportState = CastTransportState.paused;
        delegate?.onPause();
        return _soap('AVTransport', 'PauseResponse', '');
      case 'Stop':
        _transportState = CastTransportState.stopped;
        delegate?.onStop();
        return _soap('AVTransport', 'StopResponse', '');
      case 'Seek':
        final target = _tag(body, 'Target') ?? '';
        final position = _parseClock(target);
        delegate?.onSeek(position);
        return _soap('AVTransport', 'SeekResponse', '');
      case 'GetPositionInfo':
        final state = delegate?.playbackState ?? const CastPlaybackState();
        return _soap(
          'AVTransport',
          'GetPositionInfoResponse',
          '<Track>1</Track><TrackDuration>${_clock(state.duration)}</TrackDuration><TrackMetaData></TrackMetaData>'
              '<TrackURI>${_escape.convert(_currentItem?.url ?? '')}</TrackURI>'
              '<RelTime>${_clock(state.position)}</RelTime><AbsTime>${_clock(state.position)}</AbsTime>'
              '<RelCount>2147483647</RelCount><AbsCount>2147483647</AbsCount>',
        );
      case 'GetTransportInfo':
        return _soap(
          'AVTransport',
          'GetTransportInfoResponse',
          '<CurrentTransportState>${_transportStateName(_transportState)}</CurrentTransportState>'
              '<CurrentTransportStatus>OK</CurrentTransportStatus><CurrentSpeed>1</CurrentSpeed>',
        );
      case 'GetMediaInfo':
        final state = delegate?.playbackState ?? const CastPlaybackState();
        final url = _escape.convert(_currentItem?.url ?? '');
        return _soap(
          'AVTransport',
          'GetMediaInfoResponse',
          '<NrTracks>1</NrTracks><MediaDuration>${_clock(state.duration)}</MediaDuration>'
              '<CurrentURI>$url</CurrentURI><CurrentURIMetaData></CurrentURIMetaData>'
              '<NextURI>NOT_IMPLEMENTED</NextURI><NextURIMetaData></NextURIMetaData>'
              '<PlayMedium>NETWORK</PlayMedium><RecordMedium>NOT_IMPLEMENTED</RecordMedium><WriteStatus>NOT_IMPLEMENTED</WriteStatus>',
        );
      case 'GetCurrentTransportActions':
        return _soap('AVTransport', 'GetCurrentTransportActionsResponse', '<Actions>Play,Pause,Stop,Seek</Actions>');
      case 'GetDeviceCapabilities':
        return _soap(
          'AVTransport',
          'GetDeviceCapabilitiesResponse',
          '<PlayMedia>NETWORK</PlayMedia><RecMedia>NOT_IMPLEMENTED</RecMedia><RecQualityModes>NOT_IMPLEMENTED</RecQualityModes>',
        );
      case 'SetPlayMode':
        return _soap('AVTransport', 'SetPlayModeResponse', '');
      case 'Next':
      case 'Previous':
        // 单条投屏没有上下集概念，认下这个动作即可（否则控制点会报 401）。
        return _soap('AVTransport', '${action}Response', '');
      default:
        return _soap('AVTransport', '${action}Response', '');
    }
  }

  String _renderingControlAction(String action, String body) {
    final delegate = this.delegate;
    switch (action) {
      case 'SetVolume':
        final value = int.tryParse(_tag(body, 'DesiredVolume') ?? '');
        if (value != null) {
          _volume = value.clamp(0, 100);
          delegate?.onVolume(_volume);
        }
        return _soap('RenderingControl', 'SetVolumeResponse', '');
      case 'GetVolume':
        return _soap('RenderingControl', 'GetVolumeResponse', '<CurrentVolume>$_volume</CurrentVolume>');
      case 'SetMute':
        final raw = _tag(body, 'DesiredMute') ?? '0';
        _muted = raw == '1' || raw.toLowerCase() == 'true';
        delegate?.onMute(_muted);
        return _soap('RenderingControl', 'SetMuteResponse', '');
      case 'GetMute':
        return _soap('RenderingControl', 'GetMuteResponse', '<CurrentMute>${_muted ? 1 : 0}</CurrentMute>');
      default:
        return _soap('RenderingControl', '${action}Response', '');
    }
  }

  String _connectionManagerAction(String action, String body) {
    switch (action) {
      case 'GetProtocolInfo':
        return _soap(
          'ConnectionManager',
          'GetProtocolInfoResponse',
          '<Source></Source><Sink>http-get:*:video/mp4:*,http-get:*:video/x-matroska:*,'
              'http-get:*:video/webm:*,http-get:*:video/*:*,http-get:*:audio/mpeg:*,http-get:*:audio/*:*,http-get:*:image/*:*</Sink>',
        );
      case 'GetCurrentConnectionIDs':
        return _soap('ConnectionManager', 'GetCurrentConnectionIDsResponse', '<ConnectionIDs>0</ConnectionIDs>');
      case 'GetCurrentConnectionInfo':
        return _soap(
          'ConnectionManager',
          'GetCurrentConnectionInfoResponse',
          '<RcsID>-1</RcsID><AVTransportID>0</AVTransportID><ProtocolInfo>http-get:*:video/*:*</ProtocolInfo>'
              '<PeerConnectionManager></PeerConnectionManager><PeerConnectionID>-1</PeerConnectionID>'
              '<Direction>Input</Direction><Status>OK</Status>',
        );
      default:
        return _soap('ConnectionManager', '${action}Response', '');
    }
  }

  /// 规范里的状态名和枚举名不一致（`paused` → `PAUSED_PLAYBACK`），单独映射。
  static String _transportStateName(CastTransportState state) => switch (state) {
        CastTransportState.stopped => 'STOPPED',
        CastTransportState.playing => 'PLAYING',
        CastTransportState.paused => 'PAUSED_PLAYBACK',
        CastTransportState.transitioning => 'TRANSITIONING',
        CastTransportState.noMediaPresent => 'NO_MEDIA_PRESENT',
      };

  static String _soap(String service, String responseName, String payload) {
    return '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
<s:Body>
<u:$responseName xmlns:u="urn:schemas-upnp-org:service:$service:1">$payload</u:$responseName>
</s:Body>
</s:Envelope>''';
  }

  static String? _tag(String body, String tag) {
    final match = RegExp('<$tag[^>]*>(.*?)</$tag>', caseSensitive: false, dotAll: true).firstMatch(body);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// 标题藏在 DIDL-Lite 里（还被整体转义过一次），取不到就退回 URL 末段。
  String? _titleFromMetadata(String? metadata) {
    if (metadata == null) return null;
    final title = _tag(metadata, 'dc:title');
    if (title == null) return null;
    final value = _unescape(title).trim();
    return value.isEmpty ? null : value;
  }

  static String _titleFromUrl(String url) {
    final escaped = url;
    final path = Uri.tryParse(escaped)?.pathSegments;
    if (path != null && path.isNotEmpty) {
      final last = path.last;
      if (last.isNotEmpty) return Uri.decodeComponent(last);
    }
    return escaped;
  }

  static String _unescape(String value) {
    var result = value;
    for (var i = 0; i < 2; i++) {
      final decoded = result
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .replaceAll('&apos;', "'");
      if (decoded == result) break;
      result = decoded;
    }
    return result;
  }

  /// `H:MM:SS`（UPnP 的 REL_TIME 格式）。
  static String _clock(Duration duration) {
    final total = duration.inSeconds.clamp(0, 86399);
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 反向解析 REL_TIME：同时接受 `H:MM:SS` 与裸秒数（部分控制点直接给秒）。
  static Duration _parseClock(String value) {
    final trimmed = value.trim();
    final parts = trimmed.split(':');
    if (parts.length >= 3) {
      final hours = int.tryParse(parts[0]) ?? 0;
      final minutes = int.tryParse(parts[1]) ?? 0;
      final seconds = double.tryParse(parts[2]) ?? 0;
      return Duration(seconds: hours * 3600 + minutes * 60 + seconds.round());
    }
    final seconds = double.tryParse(trimmed);
    return Duration(seconds: seconds?.round() ?? 0);
  }

  // ---------------------------------------------------------------- 描述文档

  String _deviceDescription() {
    final location = this.location;
    return '''<?xml version="1.0" encoding="utf-8"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
<specVersion><major>1</major><minor>0</minor></specVersion>
<URLBase>$location</URLBase>
<device>
<deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
<friendlyName>${_escape.convert(deviceName)}</friendlyName>
<manufacturer>Han1meWinPlus</manufacturer>
<manufacturerURL>https://github.com/shilonyin/Han1meWinPlus</manufacturerURL>
<modelDescription>Han1meWinPlus DLNA MediaRenderer</modelDescription>
<modelName>Han1meWinPlus</modelName>
<modelNumber>1.0</modelNumber>
<modelURL>https://github.com/shilonyin/Han1meWinPlus</modelURL>
<serialNumber>1</serialNumber>
<UDN>$_udn</UDN>
<serviceList>
<service>
<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
<serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
<SCPDURL>/av/scpd.xml</SCPDURL>
<controlURL>/av/control</controlURL>
<eventSubURL>/av/event</eventSubURL>
</service>
<service>
<serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
<serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId>
<SCPDURL>/rc/scpd.xml</SCPDURL>
<controlURL>/rc/control</controlURL>
<eventSubURL>/rc/event</eventSubURL>
</service>
<service>
<serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
<serviceId>urn:upnp-org:serviceId:ConnectionManager</serviceId>
<SCPDURL>/cm/scpd.xml</SCPDURL>
<controlURL>/cm/control</controlURL>
<eventSubURL>/cm/event</eventSubURL>
</service>
</serviceList>
</device>
</root>''';
  }

  static String _avTransportScpd() {
    return '''<?xml version="1.0" encoding="utf-8"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
<specVersion><major>1</major><minor>0</minor></specVersion>
<actionList>
<action><name>SetAVTransportURI</name><argumentList>
<argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
<argument><name>CurrentURI</name><direction>in</direction><relatedStateVariable>AVTransportURI</relatedStateVariable></argument>
<argument><name>CurrentURIMetaData</name><direction>in</direction><relatedStateVariable>AVTransportURIMetaData</relatedStateVariable></argument>
</argumentList></action>
<action><name>Play</name><argumentList>
<argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
<argument><name>Speed</name><direction>in</direction><relatedStateVariable>TransportPlaySpeed</relatedStateVariable></argument>
</argumentList></action>
<action><name>Pause</name><argumentList>
<argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
</argumentList></action>
<action><name>Stop</name><argumentList>
<argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
</argumentList></action>
<action><name>Seek</name><argumentList>
<argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
<argument><name>Unit</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_SeekMode</relatedStateVariable></argument>
<argument><name>Target</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_SeekTarget</relatedStateVariable></argument>
</argumentList></action>
<action><name>GetPositionInfo</name><argumentList>
<argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
<argument><name>Track</name><direction>out</direction><relatedStateVariable>NumberOfTracks</relatedStateVariable></argument>
<argument><name>TrackDuration</name><direction>out</direction><relatedStateVariable>CurrentTrackDuration</relatedStateVariable></argument>
<argument><name>RelTime</name><direction>out</direction><relatedStateVariable>RelativeTimePosition</relatedStateVariable></argument>
<argument><name>AbsTime</name><direction>out</direction><relatedStateVariable>AbsoluteTimePosition</relatedStateVariable></argument>
</argumentList></action>
<action><name>GetTransportInfo</name><argumentList>
<argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
<argument><name>CurrentTransportState</name><direction>out</direction><relatedStateVariable>TransportState</relatedStateVariable></argument>
<argument><name>CurrentTransportStatus</name><direction>out</direction><relatedStateVariable>TransportStatus</relatedStateVariable></argument>
<argument><name>CurrentSpeed</name><direction>out</direction><relatedStateVariable>TransportPlaySpeed</relatedStateVariable></argument>
</argumentList></action>
<action><name>GetMediaInfo</name><argumentList>
<argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
<argument><name>NrTracks</name><direction>out</direction><relatedStateVariable>NumberOfTracks</relatedStateVariable></argument>
<argument><name>MediaDuration</name><direction>out</direction><relatedStateVariable>CurrentMediaDuration</relatedStateVariable></argument>
<argument><name>CurrentURI</name><direction>out</direction><relatedStateVariable>AVTransportURI</relatedStateVariable></argument>
</argumentList></action>
<action><name>GetCurrentTransportActions</name><argumentList>
<argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
<argument><name>Actions</name><direction>out</direction><relatedStateVariable>CurrentTransportActions</relatedStateVariable></argument>
</argumentList></action>
<action><name>GetDeviceCapabilities</name><argumentList>
<argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
<argument><name>PlayMedia</name><direction>out</direction><relatedStateVariable>PossiblePlaybackStorageMedia</relatedStateVariable></argument>
</argumentList></action>
<action><name>SetPlayMode</name><argumentList>
<argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
<argument><name>NewPlayMode</name><direction>in</direction><relatedStateVariable>CurrentPlayMode</relatedStateVariable></argument>
</argumentList></action>
</actionList>
<serviceStateTable>
<stateVariable sendEvents="no"><name>TransportState</name><dataType>string</dataType>
<allowedValueList><allowedValue>STOPPED</allowedValue><allowedValue>PLAYING</allowedValue>
<allowedValue>PAUSED_PLAYBACK</allowedValue><allowedValue>TRANSITIONING</allowedValue>
<allowedValue>NO_MEDIA_PRESENT</allowedValue></allowedValueList></stateVariable>
<stateVariable sendEvents="no"><name>TransportStatus</name><dataType>string</dataType></stateVariable>
<stateVariable sendEvents="no"><name>TransportPlaySpeed</name><dataType>string</dataType></stateVariable>
<stateVariable sendEvents="no"><name>NumberOfTracks</name><dataType>ui4</dataType></stateVariable>
<stateVariable sendEvents="no"><name>CurrentTrackDuration</name><dataType>string</dataType></stateVariable>
<stateVariable sendEvents="no"><name>CurrentMediaDuration</name><dataType>string</dataType></stateVariable>
<stateVariable sendEvents="no"><name>RelativeTimePosition</name><dataType>string</dataType></stateVariable>
<stateVariable sendEvents="no"><name>AbsoluteTimePosition</name><dataType>string</dataType></stateVariable>
<stateVariable sendEvents="no"><name>CurrentTransportActions</name><dataType>string</dataType></stateVariable>
<stateVariable sendEvents="no"><name>PossiblePlaybackStorageMedia</name><dataType>string</dataType></stateVariable>
<stateVariable sendEvents="no"><name>CurrentPlayMode</name><dataType>string</dataType></stateVariable>
<stateVariable sendEvents="no"><name>AVTransportURI</name><dataType>string</dataType></stateVariable>
<stateVariable sendEvents="no"><name>AVTransportURIMetaData</name><dataType>string</dataType></stateVariable>
<stateVariable sendEvents="no"><name>A_ARG_TYPE_InstanceID</name><dataType>ui4</dataType></stateVariable>
<stateVariable sendEvents="no"><name>A_ARG_TYPE_SeekMode</name><dataType>string</dataType></stateVariable>
<stateVariable sendEvents="no"><name>A_ARG_TYPE_SeekTarget</name><dataType>string</dataType></stateVariable>
</serviceStateTable>
</scpd>''';
  }

  static String _renderingControlScpd() {
    return '''<?xml version="1.0" encoding="utf-8"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
<specVersion><major>1</major><minor>0</minor></specVersion>
<actionList>
<action><name>SetVolume</name><argumentList>
<argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
<argument><name>Channel</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_Channel</relatedStateVariable></argument>
<argument><name>DesiredVolume</name><direction>in</direction><relatedStateVariable>Volume</relatedStateVariable></argument>
</argumentList></action>
<action><name>GetVolume</name><argumentList>
<argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
<argument><name>Channel</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_Channel</relatedStateVariable></argument>
<argument><name>CurrentVolume</name><direction>out</direction><relatedStateVariable>Volume</relatedStateVariable></argument>
</argumentList></action>
<action><name>SetMute</name><argumentList>
<argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
<argument><name>Channel</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_Channel</relatedStateVariable></argument>
<argument><name>DesiredMute</name><direction>in</direction><relatedStateVariable>Mute</relatedStateVariable></argument>
</argumentList></action>
<action><name>GetMute</name><argumentList>
<argument><name>InstanceID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_InstanceID</relatedStateVariable></argument>
<argument><name>Channel</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_Channel</relatedStateVariable></argument>
<argument><name>CurrentMute</name><direction>out</direction><relatedStateVariable>Mute</relatedStateVariable></argument>
</argumentList></action>
</actionList>
<serviceStateTable>
<stateVariable sendEvents="yes"><name>Volume</name><dataType>ui2</dataType>
<allowedValueRange><minimum>0</minimum><maximum>100</maximum><step>1</step></allowedValueRange></stateVariable>
<stateVariable sendEvents="yes"><name>Mute</name><dataType>boolean</dataType></stateVariable>
<stateVariable sendEvents="no"><name>A_ARG_TYPE_InstanceID</name><dataType>ui4</dataType></stateVariable>
<stateVariable sendEvents="no"><name>A_ARG_TYPE_Channel</name><dataType>string</dataType></stateVariable>
</serviceStateTable>
</scpd>''';
  }

  static String _connectionManagerScpd() {
    return '''<?xml version="1.0" encoding="utf-8"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
<specVersion><major>1</major><minor>0</minor></specVersion>
<actionList>
<action><name>GetProtocolInfo</name><argumentList>
<argument><name>Source</name><direction>out</direction><relatedStateVariable>SourceProtocolInfo</relatedStateVariable></argument>
<argument><name>Sink</name><direction>out</direction><relatedStateVariable>SinkProtocolInfo</relatedStateVariable></argument>
</argumentList></action>
<action><name>GetCurrentConnectionIDs</name><argumentList>
<argument><name>ConnectionIDs</name><direction>out</direction><relatedStateVariable>CurrentConnectionIDs</relatedStateVariable></argument>
</argumentList></action>
<action><name>GetCurrentConnectionInfo</name><argumentList>
<argument><name>ConnectionID</name><direction>in</direction><relatedStateVariable>A_ARG_TYPE_ConnectionID</relatedStateVariable></argument>
<argument><name>RcsID</name><direction>out</direction><relatedStateVariable>RcsID</relatedStateVariable></argument>
<argument><name>AVTransportID</name><direction>out</direction><relatedStateVariable>AVTransportID</relatedStateVariable></argument>
<argument><name>ProtocolInfo</name><direction>out</direction><relatedStateVariable>ProtocolInfo</relatedStateVariable></argument>
<argument><name>Direction</name><direction>out</direction><relatedStateVariable>Direction</relatedStateVariable></argument>
<argument><name>Status</name><direction>out</direction><relatedStateVariable>ConnectionStatus</relatedStateVariable></argument>
</argumentList></action>
</actionList>
<serviceStateTable>
<stateVariable sendEvents="no"><name>SourceProtocolInfo</name><dataType>string</dataType></stateVariable>
<stateVariable sendEvents="no"><name>SinkProtocolInfo</name><dataType>string</dataType></stateVariable>
<stateVariable sendEvents="yes"><name>CurrentConnectionIDs</name><dataType>string</dataType></stateVariable>
<stateVariable sendEvents="no"><name>A_ARG_TYPE_ConnectionID</name><dataType>i4</dataType></stateVariable>
<stateVariable sendEvents="no"><name>RcsID</name><dataType>i4</dataType></stateVariable>
<stateVariable sendEvents="no"><name>AVTransportID</name><dataType>i4</dataType></stateVariable>
<stateVariable sendEvents="no"><name>ProtocolInfo</name><dataType>string</dataType></stateVariable>
<stateVariable sendEvents="no"><name>Direction</name><dataType>string</dataType></stateVariable>
<stateVariable sendEvents="no"><name>ConnectionStatus</name><dataType>string</dataType></stateVariable>
</serviceStateTable>
</scpd>''';
  }

  static String _generateUuid() {
    final random = math.Random();
    String block(int length) => List<String>.generate(length, (_) => random.nextInt(16).toRadixString(16)).join();
    return '${block(8)}-${block(4)}-4${block(3)}-a${block(3)}-${block(12)}';
  }
}
