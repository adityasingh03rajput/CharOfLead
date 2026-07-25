// DiWall Cloud Relay Server (Node.js WebSocket Broker)
// Allows two players anywhere in the world to join using a 6-digit Room Code over public internet.

const { WebSocketServer } = require('ws');
const http = require('http');

const PORT = process.env.PORT || 8080;
const server = http.createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('DiWall Multiplayer Relay Server is Running!\n');
});

const wss = new WebSocketServer({ server });
const rooms = new Map(); // roomCode -> { hostWs, clientWs }

function generateRoomCode() {
    return Math.floor(100000 + Math.random() * 900000).toString();
}

wss.on('connection', (ws) => {
    let currentRoom = null;
    let isHost = false;

    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message.toString());
            
            if (data.type === 'create_room') {
                const code = generateRoomCode();
                rooms.set(code, { hostWs: ws, clientWs: null });
                currentRoom = code;
                isHost = true;
                ws.send(JSON.stringify({ type: 'room_created', code }));
                console.log(`Room ${code} created by host.`);
            } 
            else if (data.type === 'join_room') {
                const code = data.code;
                const room = rooms.get(code);
                if (room && !room.clientWs) {
                    room.clientWs = ws;
                    currentRoom = code;
                    isHost = false;
                    ws.send(JSON.stringify({ type: 'room_joined', code }));
                    room.hostWs.send(JSON.stringify({ type: 'peer_connected' }));
                    console.log(`Client joined room ${code}.`);
                } else {
                    ws.send(JSON.stringify({ type: 'error', message: 'Room not found or full' }));
                }
            } 
            else if (data.type === 'relay') {
                if (currentRoom) {
                    const room = rooms.get(currentRoom);
                    if (room) {
                        const target = isHost ? room.clientWs : room.hostWs;
                        if (target && target.readyState === 1) {
                            target.send(JSON.stringify({ type: 'relay', payload: data.payload }));
                        }
                    }
                }
            }
        } catch (e) {
            console.error('Error handling message:', e);
        }
    });

    ws.on('close', () => {
        if (currentRoom && rooms.has(currentRoom)) {
            const room = rooms.get(currentRoom);
            if (isHost) {
                if (room.clientWs && room.clientWs.readyState === 1) {
                    room.clientWs.send(JSON.stringify({ type: 'peer_disconnected' }));
                }
                rooms.delete(currentRoom);
            } else {
                room.clientWs = null;
                if (room.hostWs && room.hostWs.readyState === 1) {
                    room.hostWs.send(JSON.stringify({ type: 'peer_disconnected' }));
                }
            }
        }
    });
});

server.listen(PORT, () => {
    console.log(`DiWall Cloud Relay Server listening on port ${PORT}`);
});
