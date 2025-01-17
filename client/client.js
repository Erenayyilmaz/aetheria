const chatLog = document.getElementById("chatLog");
const messageInput = document.getElementById("messageInput");
const sendButton = document.getElementById("sendButton");

const client_name = `client_${Math.random().toString(36).substring(2, 10)}`;
const signalingServerUrl = "ws://altunel.online/ws/room/" + client_name;
document.getElementById("name").innerHTML = client_name;
const signalingServer = new WebSocket(signalingServerUrl);

const peers = {};
const dataChannels = {};

function appendToChatLog(message, sender = "Peer") {
  chatLog.value += `${sender}: ${message}\n`;
  chatLog.scrollTop = chatLog.scrollHeight; // Auto-scroll to the latest message
}

function createPeerConnection(client_id) {
  const peerConnection = new RTCPeerConnection({
    iceServers: [{ urls: "stun:stun.l.google.com:19302" }],
  });

  peerConnection.onicecandidate = (event) => {
    if (event.candidate) {
      signalingServer.send(
        JSON.stringify({
          type: "candidate",
          candidate: event.candidate,
          client_id: client_name,
          target_id: client_id,
        })
      );
    }
  };

  peerConnection.ondatachannel = (event) => {
    const dataChannel = event.channel;
    setupDataChannel(client_id, dataChannel);
  };

  peerConnection.onconnectionstatechange = () => {
    if (
      peerConnection.connectionState === "disconnected" ||
      peerConnection.connectionState === "failed"
    ) {
      console.log(`Peer ${client_id} disconnected. Cleaning up.`);
      cleanupPeer(client_id);
    }
  };

  peers[client_id] = peerConnection;
  return peerConnection;
}

function setupDataChannel(client_id, dataChannel) {
  dataChannels[client_id] = dataChannel;

  dataChannel.onopen = () => {
    console.log(`DataChannel with ${client_id} is open!`);
  };

  dataChannel.onclose = () => {
    console.log(`DataChannel with ${client_id} is closed.`);
    delete dataChannels[client_id];
  };

  dataChannel.onmessage = (event) => {
    appendToChatLog(event.data, client_id);
  };
}

function cleanupPeer(client_id) {
  if (peers[client_id]) {
    peers[client_id].close();
    delete peers[client_id];
  }
  if (dataChannels[client_id]) {
    delete dataChannels[client_id];
  }
}

signalingServer.onmessage = async (event) => {
  try {
    const message = JSON.parse(event.data);
    console.log("Received signaling message:", message);

    if (message.type === "create_offer") {
      const peerConnection = createPeerConnection(message.client_id);
      const dataChannel = peerConnection.createDataChannel("chat");
      setupDataChannel(message.client_id, dataChannel);

      const offer = await peerConnection.createOffer();
      await peerConnection.setLocalDescription(offer);

      signalingServer.send(
        JSON.stringify({
          type: "offer",
          offer,
          client_id: client_name,
          target_id: message.client_id,
        })
      );
    } else if (message.type === "offer") {
      const peerConnection = createPeerConnection(message.client_id);
      await peerConnection.setRemoteDescription(
        new RTCSessionDescription(message.offer)
      );

      const answer = await peerConnection.createAnswer();
      await peerConnection.setLocalDescription(answer);

      signalingServer.send(
        JSON.stringify({
          type: "answer",
          answer,
          client_id: client_name,
          target_id: message.client_id,
        })
      );
    } else if (message.type === "answer") {
      const peerConnection = peers[message.client_id];
      if (peerConnection) {
        await peerConnection.setRemoteDescription(
          new RTCSessionDescription(message.answer)
        );
      } else {
        console.error("No peer connection found for answer");
      }
    } else if (message.type === "candidate") {
      const peerConnection = peers[message.client_id];
      if (peerConnection) {
        await peerConnection.addIceCandidate(
          new RTCIceCandidate(message.candidate)
        );
      } else {
        console.error("No peer connection found for candidate");
      }
    }
  } catch (error) {
    console.error("Error handling signaling message:", error);
  }
};

sendButton.onclick = () => {
  const message = messageInput.value.trim();
  if (message) {
    Object.entries(dataChannels).forEach(([peerId, dataChannel]) => {
      if (dataChannel.readyState === "open") {
        dataChannel.send(message);
      } else {
        console.error(`DataChannel to ${peerId} is not open`);
      }
    });
    appendToChatLog(message, "You");
    messageInput.value = "";
  }
};

signalingServer.onopen = () => {
  console.log("Connected to signaling server!");
};

signalingServer.onerror = (error) => {
  console.error("Signaling server error:", error);
};

signalingServer.onclose = () => {
  console.log("Signaling server connection closed.");
};
