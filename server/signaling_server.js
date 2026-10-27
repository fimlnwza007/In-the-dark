/**
 * WebRTC Signaling Server for Alone in the Dusk
 * Supports Room Codes (e.g. 4-character codes like "K8M2")
 * Compatible with Node.js, Glitch, Render, Railway, Fly.io, and Localhost
 */

const http = require('http');
const { WebSocketServer, WebSocket } = require('ws');

const PORT = process.env.PORT || 9080;

// HTTP Server (provides health check for cloud hosts)
const server = http.createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Alone in the Dusk - WebRTC Signaling Server is RUNNING OK!\nActive Rooms: ' + rooms.size);
});

const wss = new WebSocketServer({ server });

// rooms: roomCode -> { hostWs, clients: Map(peerId -> ws), nextPeerId: 2 }
const rooms = new Map();

// Helper to generate readable 4-character room codes (avoids 0, O, 1, I)
const CODE_CHARS = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
function generateRoomCode() {
    let code = '';
    for (let i = 0; i < 4; i++) {
        code += CODE_CHARS.charAt(Math.floor(Math.random() * CODE_CHARS.length));
    }
    return code;
}

function send(ws, msg) {
    if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify(msg));
    }
}

wss.on('connection', (ws) => {
    let currentRoom = null;
    let myPeerId = 0;
    let isHost = false;

    ws.on('message', (message) => {
        let data;
        try {
            data = JSON.parse(message);
        } catch (e) {
            console.error('Invalid JSON received');
            return;
        }

        const action = data.action;

        // 1. Host creates a new room
        if (action === 'create_room') {
            let code = generateRoomCode();
            while (rooms.has(code)) {
                code = generateRoomCode();
            }

            currentRoom = code;
            myPeerId = 1; // Host is always Peer ID 1 in Godot
            isHost = true;

            const roomObj = {
                code: code,
                hostWs: ws,
                clients: new Map(),
                nextPeerId: 2,
                playerNames: new Map([[1, data.name || 'Host']])
            };
            rooms.set(code, roomObj);

            console.log(`[Room Created] Code: ${code} by Host '${data.name}'`);
            send(ws, {
                action: 'room_created',
                room_code: code,
                peer_id: 1,
                name: data.name || 'Host'
            });
            return;
        }

        // 2. Client joins an existing room by code
        if (action === 'join_room') {
            const code = (data.room_code || '').trim().toUpperCase();
            if (!rooms.has(code)) {
                send(ws, {
                    action: 'join_failed',
                    error: `ไม่พบห้องรหัส "${code}" กรุณาตรวจสอบรหัสห้องอีกครั้ง`
                });
                return;
            }

            const roomObj = rooms.get(code);
            if (roomObj.clients.size >= 7) { // Max 8 players total
                send(ws, {
                    action: 'join_failed',
                    error: `ห้อง "${code}" เต็มแล้ว (จำกัดสูงสุด 8 คน)`
                });
                return;
            }

            currentRoom = code;
            myPeerId = roomObj.nextPeerId++;
            isHost = false;

            roomObj.clients.set(myPeerId, ws);
            roomObj.playerNames.set(myPeerId, data.name || `Player_${myPeerId}`);

            console.log(`[Player Joined] Code: ${code}, PeerId: ${myPeerId}, Name: ${data.name}`);

            // Notify joiner that join succeeded
            send(ws, {
                action: 'joined_room',
                room_code: code,
                peer_id: myPeerId,
                name: data.name || `Player_${myPeerId}`
            });

            // Notify Host to initiate WebRTC connection with this joiner
            send(roomObj.hostWs, {
                action: 'peer_joined',
                peer_id: myPeerId,
                name: data.name || `Player_${myPeerId}`
            });

            // Broadcast updated player list to all in the room
            const playersList = Array.from(roomObj.playerNames.entries()).map(([id, name]) => ({
                id,
                name,
                is_host: id === 1
            }));

            send(roomObj.hostWs, { action: 'player_list', players: playersList });
            roomObj.clients.forEach((cWs) => {
                send(cWs, { action: 'player_list', players: playersList });
            });
            return;
        }

        // 3. WebRTC Signaling Relays (Offer, Answer, Candidate)
        if (action === 'offer' || action === 'answer' || action === 'candidate') {
            if (!currentRoom || !rooms.has(currentRoom)) return;
            const roomObj = rooms.get(currentRoom);
            const targetId = data.target;

            // Target is host
            if (targetId === 1) {
                data.sender = myPeerId;
                send(roomObj.hostWs, data);
            } else if (roomObj.clients.has(targetId)) {
                data.sender = myPeerId;
                send(roomObj.clients.get(targetId), data);
            }
            return;
        }

        // 4. Leave room explicitly
        if (action === 'leave_room') {
            handleDisconnect();
        }
    });

    ws.on('close', () => {
        handleDisconnect();
    });

    function handleDisconnect() {
        if (!currentRoom || !rooms.has(currentRoom)) return;
        const roomObj = rooms.get(currentRoom);

        if (isHost) {
            // If Host leaves, close room and inform all clients
            console.log(`[Room Closed] Host left room: ${currentRoom}`);
            roomObj.clients.forEach((cWs) => {
                send(cWs, {
                    action: 'host_disconnected',
                    message: 'Host ได้ปิดห้องแล้ว'
                });
            });
            rooms.delete(currentRoom);
        } else {
            // Client left
            console.log(`[Player Left] Peer ${myPeerId} left room: ${currentRoom}`);
            roomObj.clients.delete(myPeerId);
            roomObj.playerNames.delete(myPeerId);

            // Inform host
            send(roomObj.hostWs, {
                action: 'peer_left',
                peer_id: myPeerId
            });

            // Broadcast updated player list
            const playersList = Array.from(roomObj.playerNames.entries()).map(([id, name]) => ({
                id,
                name,
                is_host: id === 1
            }));
            send(roomObj.hostWs, { action: 'player_list', players: playersList });
            roomObj.clients.forEach((cWs) => {
                send(cWs, { action: 'player_list', players: playersList });
            });
        }
        currentRoom = null;
    }
});

server.listen(PORT, () => {
    console.log(`===============================================`);
    console.log(` WebRTC Signaling Server listening on port ${PORT}`);
    console.log(` Ready for Room Codes & P2P Matchmaking!`);
    console.log(`===============================================`);
});
