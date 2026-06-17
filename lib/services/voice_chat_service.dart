import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ws_game_service.dart';

class VoiceChatService {
  VoiceChatService._();

  static const _nativeChannel = MethodChannel('com.laughroyale.app/voice');

  static RTCPeerConnection? _pc;
  static MediaStream? _localStream;
  static bool _isMuted = false;
  static bool _isActive = false;
  static String? _roomCode;
  static StreamSubscription? _voiceSubscription;
  static Timer? _iceTimeout;
  static final List<Map<String, dynamic>> _pendingSignals = [];
  static bool _remoteDescSet = false;
  static final List<RTCIceCandidate> _bufferedIceCandidates = [];

  static void _maybeSendIceCandidate(RTCIceCandidate candidate) {
    if (_remoteDescSet && _isActive) {
      WsGameService.sendVoiceSignal({
        'type': 'ice',
        'candidate': candidate.toMap(),
      });
    } else {
      _bufferedIceCandidates.add(candidate);
    }
  }

  static void _flushBufferedIceCandidates() {
    if (_bufferedIceCandidates.isEmpty) return;
    debugPrint('[VOICE] Flushing ${_bufferedIceCandidates.length} buffered ICE candidates');
    for (final c in _bufferedIceCandidates) {
      if (_isActive) {
        WsGameService.sendVoiceSignal({
          'type': 'ice',
          'candidate': c.toMap(),
        });
      }
    }
    _bufferedIceCandidates.clear();
  }

  static bool get isActive => _isActive;
  static bool get isMuted => _isMuted;

  static Future<bool> startVoiceChat({
    required String roomCode,
    required bool isHost,
  }) async {
    if (_isActive) {
      debugPrint('[VOICE] Already active in room $_roomCode — reusing');
      if (_roomCode != roomCode) {
        await stopVoiceChat();
      } else {
        return true;
      }
    }

    _roomCode = roomCode;
    _remoteDescSet = false;

    debugPrint('[VOICE] Requesting microphone permission...');
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      debugPrint('[VOICE] Microphone permission DENIED');
      return false;
    }
    debugPrint('[VOICE] Microphone permission GRANTED');

    try {
      await _setSpeakerOn();

      final config = {
        'iceServers': [
          {
            'urls': [
              'stun:stun.l.google.com:19302',
              'stun:stun1.l.google.com:19302',
              'stun:stun2.l.google.com:19302',
              'stun:stun3.l.google.com:19302',
              'stun:stun4.l.google.com:19302',
            ],
          },
          {
            'urls': [
              'turn:openrelay.metered.ca:80',
              'turn:openrelay.metered.ca:443',
              'turns:openrelay.metered.ca:443',
            ],
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
          {
            'urls': [
              'turn:relay1.expressturn.com:3478',
              'turn:relay1.expressturn.com:3478?transport=tcp',
            ],
            'username': 'efMYdMYglc8AJBNmzLvaV0apU6B8qGqO',
            'credential': 'DOogmNUqMX7Ewj3f7NNqYjpxf1aztCgO',
          },
        ],
        'iceTransportPolicy': 'all',
        'bundlePolicy': 'max-bundle',
        'rtcpMuxPolicy': 'require',
      };
      final constraints = {
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': false,
        },
        'optional': [
          {'DtlsSrtpKeyAgreement': true},
        ],
      };

      debugPrint('[VOICE] Creating peer connection...');
      _pc = await createPeerConnection(config, constraints);
      if (_pc == null) {
        debugPrint('[VOICE] FAILED to create peer connection');
        return false;
      }

      debugPrint('[VOICE] Getting user media (audio)...');
      try {
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': {
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
            'googEchoCancellation': true,
            'googNoiseSuppression': true,
            'googAutoGainControl': true,
            'googHighpassFilter': true,
          },
          'video': false,
        });
      } catch (e) {
        debugPrint('[VOICE] getUserMedia FAILED: $e');
        await _cleanupPc();
        return false;
      }

      final tracks = _localStream!.getAudioTracks();
      if (tracks.isEmpty) {
        debugPrint('[VOICE] No audio tracks returned');
        await _cleanupPc();
        return false;
      }
      debugPrint('[VOICE] Got ${tracks.length} audio track(s)');

      for (final track in tracks) {
        _pc!.addTrack(track, _localStream!);
      }

      _pc!.onIceCandidate = (candidate) {
        if (candidate != null && _isActive) {
          _maybeSendIceCandidate(candidate);
        }
      };

      _pc!.onTrack = (RTCTrackEvent event) {
        debugPrint('[VOICE] Remote audio track received — streams: ${event.streams.length}, tracks: ${event.trackIds?.length ?? 0}');
        if (event.streams.isNotEmpty) {
          final remoteStream = event.streams.first;
          final audioTracks = remoteStream.getAudioTracks();
          debugPrint('[VOICE] Remote stream audio tracks: ${audioTracks.length}');
          for (final t in audioTracks) {
            debugPrint('[VOICE] Remote track: ${t.id} enabled=${t.enabled} muted=${t.muted}');
          }

        }
        _setSpeakerOn();
      };

      _pc!.onIceConnectionState = (state) {
        debugPrint('[VOICE] ICE connection: $state');
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
          debugPrint('[VOICE] ✅ Voice peer-to-peer connected');
          _iceTimeout?.cancel();
          _iceTimeout = null;
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          debugPrint('[VOICE] ⚠ Voice peer disconnected');
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          debugPrint('[VOICE] ❌ Voice ICE failed');
          _iceTimeout?.cancel();
        }
      };

      _pc!.onIceGatheringState = _onIceGatheringStateChange;

      _pc!.onSignalingState = (state) {
        debugPrint('[VOICE] Signaling: $state');
      };

      _voiceSubscription?.cancel();
      _voiceSubscription = WsGameService.messages.listen(_onVoiceMessage);

      _isActive = true;

      _drainPendingSignals();

      if (isHost) {
        await _createAndSendOffer();
      }

      _iceTimeout = Timer(const Duration(seconds: 25), () {
        if (_isActive) {
          debugPrint('[VOICE] ⚠ ICE connection timeout (25s) — no peer connection established');
        }
      });

      debugPrint('[VOICE] Voice chat started | room=$roomCode | isHost=$isHost');
      return true;
    } catch (e) {
      debugPrint('[VOICE] Unexpected error starting voice: $e');
      await stopVoiceChat();
      return false;
    }
  }

  static void _onIceGatheringStateChange(RTCIceGatheringState state) {
    debugPrint('[VOICE] ICE gathering: $state');
    if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
      _iceGatheringCompleteCompleter?.complete();
      _iceGatheringCompleteCompleter = null;
    }
  }

  static Completer<void>? _iceGatheringCompleteCompleter;

  static Future<void> _createAndSendOffer() async {
    if (_pc == null || !_isActive) return;
    try {
      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await _pc!.setLocalDescription(offer);

      await _waitForIceGathering();

      _remoteDescSet = true;
      _flushBufferedIceCandidates();
      WsGameService.sendVoiceSignal({
        'type': 'offer',
        'sdp': offer.sdp,
      });
      debugPrint('[VOICE] Offer sent (SDP length: ${offer.sdp!.length})');
    } catch (e) {
      debugPrint('[VOICE] Error creating offer: $e');
    }
  }

  static Future<void> _waitForIceGathering() async {
    if (_pc == null) return;
    if (_pc!.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) return;

    final completer = Completer<void>();
    _iceGatheringCompleteCompleter = completer;
    try {
      await completer.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      debugPrint('[VOICE] ICE gathering timeout — sending offer anyway');
    }
    _iceGatheringCompleteCompleter = null;
  }

  static Future<void> _setSpeakerOn() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        try {
          await _nativeChannel.invokeMethod('enableSpeakerphone');
          debugPrint('[VOICE] Speakerphone enabled via native');
        } catch (e) {
          debugPrint('[VOICE] Native speakerphone call failed: $e');
        }
      }
    } catch (_) {}
  }

  static void _drainPendingSignals() {
    if (_pendingSignals.isEmpty) return;
    debugPrint('[VOICE] Draining ${_pendingSignals.length} pending signals');
    final toProcess = List<Map<String, dynamic>>.from(_pendingSignals);
    _pendingSignals.clear();
    for (final msg in toProcess) {
      _processVoiceMessage(msg);
    }
  }

  static void _onVoiceMessage(Map<String, dynamic> msg) {
    if (msg['type'] != 'voice') return;

    final signal = msg['signal'];
    if (signal == null || signal is! Map) return;

    if (!_isActive) {
      _pendingSignals.add(msg);
      debugPrint('[VOICE] Signal buffered (${signal['type']}), not yet active');
      return;
    }

    _processVoiceMessage(msg);
  }

  static void _processVoiceMessage(Map<String, dynamic> msg) {
    final signal = msg['signal'] as Map<String, dynamic>;
    final sigType = signal['type'] as String?;

    debugPrint('[VOICE] Received signal: $sigType');

    switch (sigType) {
      case 'offer':
        _handleOffer(signal);
        break;
      case 'answer':
        _handleAnswer(signal);
        break;
      case 'ice':
        _handleIce(signal);
        break;
      default:
        debugPrint('[VOICE] Unknown signal type: $sigType');
    }
  }

  static Future<void> _handleOffer(Map<String, dynamic> signal) async {
    if (_pc == null || !_isActive) return;
    try {
      final sdp = signal['sdp'] as String?;
      if (sdp == null) {
        debugPrint('[VOICE] Offer has no SDP');
        return;
      }
      debugPrint('[VOICE] Offer received (SDP length: ${sdp.length})');
      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      _remoteDescSet = true;
      _flushBufferedIceCandidates();

      final answer = await _pc!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await _pc!.setLocalDescription(answer);

      await _waitForIceGathering();

      WsGameService.sendVoiceSignal({
        'type': 'answer',
        'sdp': answer.sdp,
      });
      debugPrint('[VOICE] Answer sent');
    } catch (e) {
      debugPrint('[VOICE] Error handling offer: $e');
    }
  }

  static Future<void> _handleAnswer(Map<String, dynamic> signal) async {
    if (_pc == null || !_isActive) return;
    try {
      final sdp = signal['sdp'] as String?;
      if (sdp == null) return;
      debugPrint('[VOICE] Answer received');
      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      _remoteDescSet = true;
      _flushBufferedIceCandidates();
    } catch (e) {
      debugPrint('[VOICE] Error handling answer: $e');
    }
  }

  static Future<void> _handleIce(Map<String, dynamic> signal) async {
    if (_pc == null || !_isActive) return;
    try {
      final candidate = signal['candidate'] as Map<String, dynamic>?;
      if (candidate == null) return;
      await _pc!.addCandidate(
        RTCIceCandidate(
          candidate['candidate'] as String? ?? '',
          candidate['sdpMid'] as String? ?? '',
          (candidate['sdpMLineIndex'] as num?)?.toInt() ?? 0,
        ),
      );
    } catch (e) {
      debugPrint('[VOICE] Error adding ICE candidate: $e');
    }
  }

  static void toggleMute() {
    if (!_isActive || _localStream == null) return;
    _isMuted = !_isMuted;
    final audioTracks = _localStream!.getAudioTracks();
    for (final track in audioTracks) {
      track.enabled = !_isMuted;
    }
    debugPrint('[VOICE] ${_isMuted ? "MUTED" : "UNMUTED"}');
  }

  static Future<void> stopVoiceChat() async {
    if (!_isActive) return;
    debugPrint('[VOICE] Stopping voice chat...');
    _isActive = false;
    _remoteDescSet = false;

    _iceTimeout?.cancel();
    _iceTimeout = null;
    _voiceSubscription?.cancel();
    _voiceSubscription = null;
    _pendingSignals.clear();
    _bufferedIceCandidates.clear();
    _iceGatheringCompleteCompleter = null;

    if (_localStream != null) {
      try {
        final tracks = _localStream!.getAudioTracks();
        for (final track in tracks) {
          track.stop();
        }
      } catch (_) {}
      try {
        await _localStream!.dispose();
      } catch (_) {}
      _localStream = null;
    }

    if (_pc != null) {
      try {
        await _pc!.close();
      } catch (_) {}
      try {
        _pc!.dispose();
      } catch (_) {}
      _pc = null;
    }

    _isMuted = false;
    _roomCode = null;
    debugPrint('[VOICE] Voice chat stopped — all resources released');
  }

  static Future<void> _cleanupPc() async {
    if (_pc != null) {
      try { await _pc!.close(); } catch (_) {}
      try { _pc!.dispose(); } catch (_) {}
      _pc = null;
    }
    if (_localStream != null) {
      try { await _localStream!.dispose(); } catch (_) {}
      _localStream = null;
    }
  }
}
