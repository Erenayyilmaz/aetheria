import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:math';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aetheria',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: ChatScreen(),
      );
  }
}

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}


class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final String clientName = "client_${Random().nextInt(100000).toString()}";
  final String signalingServerUrl = "ws://altunel.online/ws/room/";

  late WebSocketChannel signalingChannel;
  Map<String, RTCPeerConnection> peers = {};
  Map<String, RTCDataChannel> dataChannels = {};
  List<String> chatLog = [];

  @override
  void initState() {
    super.initState();
    signalingChannel = WebSocketChannel.connect(Uri.parse(signalingServerUrl + clientName));
    signalingChannel.stream.listen(_handleSignalingMessage);
    signalingChannel.sink.add(jsonEncode({"type": "join", "client_id": clientName}));
  }

  void _handleSignalingMessage(dynamic message) async {
    final parsedMessage = jsonDecode(message);
    switch (parsedMessage['type']) {
      case 'create_offer':
        final peerConnection = await _createPeerConnection(parsedMessage['client_id']);
        final dataChannel = await peerConnection.createDataChannel("chat", RTCDataChannelInit());
        _setupDataChannel(parsedMessage['client_id'], dataChannel);

        final offer = await peerConnection.createOffer();
        await peerConnection.setLocalDescription(offer);
        signalingChannel.sink.add(jsonEncode({
          'type': 'offer',
          'offer': offer.toMap(),
          'client_id': clientName,
          'target_id': parsedMessage['client_id'],
        }));
        break;
      case 'offer':
        final peerConnection = await _createPeerConnection(parsedMessage['client_id']);
        await peerConnection.setRemoteDescription(RTCSessionDescription(parsedMessage['offer']['sdp'], parsedMessage['offer']['type']));

        final answer = await peerConnection.createAnswer();
        await peerConnection.setLocalDescription(answer);
        signalingChannel.sink.add(jsonEncode({
          'type': 'answer',
          'answer': answer.toMap(),
          'client_id': clientName,
          'target_id': parsedMessage['client_id'],
        }));
        break;
      case 'answer':
        final peerConnection = peers[parsedMessage['client_id']];
        if (peerConnection != null) {
          await peerConnection.setRemoteDescription(RTCSessionDescription(parsedMessage['answer']['sdp'], parsedMessage['answer']['type']));
        }
        break;
      case 'candidate':
        final peerConnection = peers[parsedMessage['client_id']];
        if (peerConnection != null) {
          await peerConnection.addCandidate(RTCIceCandidate(
              parsedMessage['candidate']['candidate'],
              parsedMessage['candidate']['sdpMid'],
              parsedMessage['candidate']['sdpMLineIndex']));
        }
        break;
    }
  }

  Future<RTCPeerConnection> _createPeerConnection(String clientId) async {
    final peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    });

    peerConnection.onIceCandidate = (candidate) {
      signalingChannel.sink.add(jsonEncode({
        'type': 'candidate',
        'candidate': candidate?.toMap(),
        'client_id': clientName,
        'target_id': clientId,
      }));
    };

    peerConnection.onDataChannel = (channel) {
      _setupDataChannel(clientId, channel);
    };

    peers[clientId] = peerConnection;
    return peerConnection;
  }

  void _setupDataChannel(String clientId, RTCDataChannel dataChannel) {
    dataChannels[clientId] = dataChannel;

    dataChannel.onMessage = (message) {
      setState(() {
        chatLog.add("$clientId: ${message.text}");
      });
      _scrollToBottom();
    };
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    if (message.isNotEmpty) {
      dataChannels.forEach((clientId, dataChannel) {
        if (dataChannel.state == RTCDataChannelState.RTCDataChannelOpen) {
          dataChannel.send(RTCDataChannelMessage(message));
        }
      });
      setState(() {
        chatLog.add("You: $message");
        _messageController.clear();
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Chat - $clientName")),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: chatLog.length,
              itemBuilder: (context, index) => ListTile(
                title: Text(chatLog[index]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(hintText: "Enter message"),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: _sendMessage,
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    signalingChannel.sink.close();
    peers.forEach((_, peer) => peer.close());
    super.dispose();
  }
}

