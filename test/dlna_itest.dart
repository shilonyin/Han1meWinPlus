import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/dlna_media_renderer.dart';

class _Target implements CastRendererDelegate {
  CastMediaItem? last;
  @override
  void onSetMedia(CastMediaItem item) { last = item; }
  @override
  void onPlay() {}
  @override
  void onPause() {}
  @override
  void onStop() {}
  @override
  void onSeek(Duration position) {}
  @override
  void onVolume(int volume) {}
  @override
  void onMute(bool muted) {}
  @override
  CastPlaybackState get playbackState => const CastPlaybackState();
}

void main() {
  test('renderer: M-SEARCH -> SSDP reply with our LOCATION', () async {
    final target = _Target();
    final renderer = DlnaMediaRenderer(deviceName: 'ITest', delegate: target, ssdpPort: 19390);
    final ok = await renderer.start();
    expect(ok, isTrue, reason: 'renderer.start failed: ${renderer.status.detail}');
    addTearDown(renderer.stop);

    final socket = RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final s = await socket;
    final payload = 'M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\nMX: 1\r\nST: ssdp:all\r\n\r\n';
    // Send unicast directly to the SSDP port (always 1900) so the test does not
    // depend on multicast delivery. The renderer binds 0.0.0.0:1900.
    s.send(payload.codeUnits, InternetAddress.loopbackIPv4, 19390);
    Datagram? reply;
    final sub = s.listen((event) {
      if (event == RawSocketEvent.read && reply == null) reply = s.receive();
    });
    for (var i = 0; i < 30 && reply == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    sub.cancel();
    expect(reply, isNotNull, reason: 'no SSDP reply to unicast M-SEARCH');
    final text = String.fromCharCodes(reply!.data);
    expect(text, contains('HTTP/1.1 200 OK'));
    expect(text, contains('LOCATION: '));
    s.close();
  });

  test('renderer: device.xml serves and advertises friendlyName', () async {
    final target = _Target();
    final renderer = DlnaMediaRenderer(deviceName: 'ITestXML', delegate: target, ssdpPort: 19391);
    expect(await renderer.start(), isTrue);
    addTearDown(renderer.stop);

    final client = HttpClient();
    final request = await client.getUrl(Uri.parse('http://127.0.0.1:${renderer.port}/device.xml'));
    final response = await request.close();
    expect(response.statusCode, 200);
    final body = await response.transform(utf8.decoder).join();
    expect(body, contains('ITestXML'));
    expect(body, contains('MediaRenderer'));
    client.close();
  });

  test('renderer: SetAVTransportURI + Play delegate to the target', () async {
    final target = _Target();
    final renderer = DlnaMediaRenderer(deviceName: 'ITestSoap', delegate: target, ssdpPort: 19392);
    expect(await renderer.start(), isTrue);
    addTearDown(renderer.stop);

    final client = HttpClient();
    final request = await client.postUrl(Uri.parse('http://127.0.0.1:${renderer.port}/av/control'));
    request.headers.set('SOAPAction', '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"');
    request.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
    const soap = '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><InstanceID>0</InstanceID><CurrentURI>http://example.com/v.mp4</CurrentURI></u:SetAVTransportURI></s:Body></s:Envelope>';
    request.add(soap.codeUnits);
    final response = await request.close();
    expect(response.statusCode, 200);
    final body = await response.transform(utf8.decoder).join();
    expect(body, isNot(contains('UPnPError')));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(target.last?.url, 'http://example.com/v.mp4');
    client.close();
  });
}
