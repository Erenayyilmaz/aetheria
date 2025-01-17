from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from typing import Dict
from collections import defaultdict

app = FastAPI()

# Store WebSocket connections by room and client ID
rooms: Dict[str, Dict[str, WebSocket]] = defaultdict(dict)


@app.websocket("/ws/{room_id}/{client_id}")
async def websocket_endpoint(websocket: WebSocket, room_id: str, client_id: str):
    """
    WebSocket endpoint for signaling.
    Each client connects using a room ID and a unique client ID.
    """
    # Get and log the client's IP address
    client_ip = websocket.client.host
    print(f"Client connected: {client_id} to room {room_id}, IP: {client_ip}")

    await websocket.accept()
    rooms[room_id][client_id] = websocket

    try:
        for peer_id, connection in rooms[room_id].items():
            if peer_id != client_id:
                await websocket.send_json({"type": "create_offer",
                                           "client_id": peer_id})
                offer = await websocket.receive_json()
                offer["client_id"] = client_id
                await connection.send_json(offer)
        while True:
            data = await websocket.receive_json()
            for peer_id, connection in rooms[room_id].items():
                if "target_id" in data:
                    if peer_id == data["target_id"]:
                        await connection.send_json(data)
                else:
                    if peer_id != client_id:
                        await connection.send_json(data)

    except WebSocketDisconnect:
        print(f"Client disconnected: {client_id}, room: " +
              f"{room_id}, IP: {client_ip}")
    except Exception as e:
        print(f"Error with client {client_id} in room {room_id}: {e}")
    finally:
        # Remove the client from the room when they disconnect
        del rooms[room_id][client_id]
        # Remove the room if it's empty
        if not rooms[room_id]:
            del rooms[room_id]
        print(f"Client {client_id} disconnected from room {room_id}")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
