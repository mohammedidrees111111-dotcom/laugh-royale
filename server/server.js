const http = require('http');
const WebSocket = require('ws');

const PORT = process.env.PORT || 3000;
const HOST = '0.0.0.0';

// ── Game rooms (relay host↔guest messages) ─────────────────
const rooms = new Map();

// ── Matchmaking queue ──────────────────────────────────────
const matchmakingQueue = [];
const connStateMap = new Map(); // ws → { roomCode, role, playerId, playerName }

// ── Helpers ────────────────────────────────────────────────
function generateCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 6; i++) code += chars[Math.floor(Math.random() * chars.length)];
  return code;
}

function log(level, ...args) {
  const ts = new Date().toISOString().replace('T', ' ').substring(0, 19);
  console.log(`[${ts}] [${level}]`, ...args);
}

function send(ws, obj) {
  if (ws.readyState !== WebSocket.OPEN) return;
  try { ws.send(JSON.stringify(obj)); } catch (_) {}
}

function removeFromQueue(ws) {
  const idx = matchmakingQueue.indexOf(ws);
  if (idx !== -1) {
    const cs = connStateMap.get(ws);
    matchmakingQueue.splice(idx, 1);
    log('QUEUE', `- ${cs?.playerName || '?'} removed (size: ${matchmakingQueue.length})`);
    return true;
  }
  return false;
}

function cleanupRoom(ws) {
  const cs = connStateMap.get(ws);
  if (!cs || !cs.roomCode) return;
  const room = rooms.get(cs.roomCode);
  if (!room) return;

  const other = (cs.role === 'host') ? room.guest : room.host;
  if (other && other.readyState === WebSocket.OPEN) {
    send(other, { type: 'opponent_disconnected' });
  }

  setTimeout(() => {
    const currentRoom = rooms.get(cs.roomCode);
    if (!currentRoom) return;

    const hostAlive = currentRoom.host && currentRoom.host.readyState === WebSocket.OPEN;
    const guestAlive = currentRoom.guest && currentRoom.guest.readyState === WebSocket.OPEN;

    if (!hostAlive && !guestAlive) {
      const age = ((Date.now() - (currentRoom.createdAt || Date.now())) / 1000).toFixed(0);
      rooms.delete(cs.roomCode);
      log('ROOM', `Room ${cs.roomCode} expired (age: ${age}s, both left)`);
    }
  }, 30000);

  log('ROOM', `Player ${cs.role} left room ${cs.roomCode} (reconnect window: 30s)`);
}

// ── Pair two queued players into a room ────────────────────
function tryPair() {
  while (matchmakingQueue.length >= 2) {
    const p1 = matchmakingQueue.shift();
    const p2 = matchmakingQueue.shift();

    if (p1.readyState !== WebSocket.OPEN || p2.readyState !== WebSocket.OPEN) {
      if (p1.readyState === WebSocket.OPEN) matchmakingQueue.unshift(p1);
      if (p2.readyState === WebSocket.OPEN) matchmakingQueue.unshift(p2);
      log('PAIR', 'Skipped disconnected player(s)');
      continue;
    }

    const c1 = connStateMap.get(p1);
    const c2 = connStateMap.get(p2);

    const roomCode = generateCode();

    c1.roomCode = roomCode;
    c1.role = 'host';
    c2.roomCode = roomCode;
    c2.role = 'guest';

    rooms.set(roomCode, {
      host: p1,
      guest: p2,
      hostId: c1.playerId,
      guestId: c2.playerId,
      createdAt: Date.now(),
    });

    send(p1, {
      type: 'matched',
      roomId: roomCode,
      opponentId: c2.playerId,
      opponentName: c2.playerName,
      role: 'host',
    });

    send(p2, {
      type: 'matched',
      roomId: roomCode,
      opponentId: c1.playerId,
      opponentName: c1.playerName,
      role: 'guest',
    });

    log('MATCH', `Paired ${c1.playerName}[${c1.playerId}] vs ${c2.playerName}[${c2.playerId}] in room ${roomCode}`);
    log('QUEUE', `Queue size: ${matchmakingQueue.length}`);
  }
}

// ── HTTP health-check server ───────────────────────────────
const httpServer = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  if (req.method === 'GET' && (req.url === '/health' || req.url === '/')) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      uptime: process.uptime(),
      rooms: rooms.size,
      queue: matchmakingQueue.length,
      clients: connStateMap.size,
      timestamp: new Date().toISOString(),
    }));
    return;
  }

  res.writeHead(404);
  res.end();
});

// ── WebSocket server ───────────────────────────────────────
const wss = new WebSocket.Server({ server: httpServer });

wss.on('connection', (ws, req) => {
  const clientIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress || 'unknown';
  log('CONNECT', `Client connected from ${clientIp}`);

  const cs = { roomCode: null, role: null, playerId: null, playerName: null };
  connStateMap.set(ws, cs);

  send(ws, { type: 'connected', message: 'Welcome to Laugh Royale!', serverTime: Date.now() });

  ws.on('message', (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch (e) {
      log('ERROR', 'Invalid JSON received');
      send(ws, { type: 'error', message: 'Invalid message format' });
      return;
    }

    log('MSG', `${cs.role || '?'} → ${msg.type}`);

    switch (msg.type) {

      // ── Matchmaking ──────────────────────────────────────
      case 'matchmaking_join':
        if (cs.roomCode || matchmakingQueue.includes(ws)) {
          send(ws, { type: 'error', message: 'Already in queue or room' });
          log('QUEUE', `Rejected duplicate join from ${msg.name || '?'}`);
          return;
        }
        cs.playerId = msg.id || 'unknown';
        cs.playerName = msg.name || 'Player';
        matchmakingQueue.push(ws);
        log('QUEUE', `+ ${cs.playerName} joined queue (size: ${matchmakingQueue.length})`);
        send(ws, { type: 'queue_joined', queueSize: matchmakingQueue.length });
        tryPair();
        break;

      case 'matchmaking_leave':
        removeFromQueue(ws);
        send(ws, { type: 'queue_left' });
        break;

      // ── Session recovery ─────────────────────────────────
      case 'reconnect':
        {
          const pid = msg.playerId;
          const rid = msg.roomCode;

          if (!pid || !rid) {
            send(ws, { type: 'error', message: 'Missing playerId or roomCode' });
            return;
          }

          const room = rooms.get(rid);
          if (!room) {
            send(ws, { type: 'error', message: 'Room not found' });
            log('RECONNECT', `Room ${rid} not found for ${pid}`);
            return;
          }

          removeFromQueue(ws);

          if (room.hostId === pid) {
            room.host = ws;
            cs.role = 'host';
            cs.playerId = pid;
            cs.roomCode = rid;
            if (room.guest && room.guest.readyState === WebSocket.OPEN) {
              send(room.guest, { type: 'opponent_reconnected' });
            }
            send(ws, {
              type: 'reconnected',
              roomId: rid,
              role: 'host',
              opponentId: room.guestId,
              opponentName: room.guestId,
            });
            log('RECONNECT', `Host ${pid} reconnected to room ${rid}`);
          } else if (room.guestId === pid) {
            room.guest = ws;
            cs.role = 'guest';
            cs.playerId = pid;
            cs.roomCode = rid;
            if (room.host && room.host.readyState === WebSocket.OPEN) {
              send(room.host, { type: 'opponent_reconnected' });
            }
            send(ws, {
              type: 'reconnected',
              roomId: rid,
              role: 'guest',
              opponentId: room.hostId,
              opponentName: room.hostId,
            });
            log('RECONNECT', `Guest ${pid} reconnected to room ${rid}`);
          } else {
            send(ws, { type: 'error', message: 'Not a member of this room' });
          }
        }
        break;

      // ── Room hosting (manual code sharing) ──────────────
      case 'host':
        if (cs.roomCode) {
          send(ws, { type: 'error', message: 'Already in a room' });
          return;
        }
        removeFromQueue(ws);
        cs.roomCode = generateCode();
        cs.role = 'host';
        cs.playerId = msg.id || 'host';
        rooms.set(cs.roomCode, {
          host: ws,
          guest: null,
          hostId: cs.playerId,
          guestId: null,
          createdAt: Date.now(),
        });
        send(ws, { type: 'room_created', code: cs.roomCode });
        log('ROOM', `Created ${cs.roomCode} by host ${cs.playerId}`);
        break;

      case 'join':
        if (cs.roomCode) {
          send(ws, { type: 'error', message: 'Already in a room' });
          return;
        }
        removeFromQueue(ws);

        const joinCode = msg.code;
        const room = rooms.get(joinCode);
        if (!room) {
          send(ws, { type: 'error', message: 'Room not found' });
          log('JOIN', `Room ${joinCode} not found for ${msg.id || '?'}`);
          return;
        }
        if (room.guest) {
          send(ws, { type: 'error', message: 'Room is full' });
          log('JOIN', `Room ${joinCode} full, rejected ${msg.id || '?'}`);
          return;
        }

        cs.roomCode = joinCode;
        cs.role = 'guest';
        cs.playerId = msg.id || 'guest';
        cs.playerName = msg.name || 'Player';
        room.guest = ws;
        room.guestId = cs.playerId;

        send(room.host, { type: 'player_joined', id: cs.playerId, name: cs.playerName });
        send(ws, { type: 'joined', id: room.hostId, name: room.hostId });
        log('JOIN', `Player ${cs.playerId} joined room ${joinCode}`);
        break;

      // ── Game events (forward to opponent) ───────────────
      case 'start':
        {
          const r = rooms.get(cs.roomCode);
          if (r) {
            const target = cs.role === 'host' ? r.guest : r.host;
            if (target && target.readyState === WebSocket.OPEN) {
              send(target, { type: 'event', event: 'started' });
              log('GAME', `Game started in room ${cs.roomCode} by ${cs.role}`);
            }
          }
        }
        break;

      case 'smile':
      case 'face':
      case 'event':
        {
          const r = rooms.get(cs.roomCode);
          if (!r) {
            send(ws, { type: 'error', message: 'Not in a room' });
            return;
          }
          const target = cs.role === 'host' ? r.guest : r.host;
          if (target && target.readyState === WebSocket.OPEN) {
            send(target, msg);
          }
        }
        break;

      default:
        // Forward unknown types too (backward compatible)
        {
          const r = rooms.get(cs.roomCode);
          if (!r) {
            send(ws, { type: 'error', message: 'Not in a room' });
            return;
          }
          const target = cs.role === 'host' ? r.guest : r.host;
          if (target && target.readyState === WebSocket.OPEN) {
            send(target, msg);
          }
        }
    }
  });

  ws.on('close', () => {
    removeFromQueue(ws);
    cleanupRoom(ws);
    connStateMap.delete(ws);
    log('DISCONNECT', `Client from ${clientIp} disconnected (rooms: ${rooms.size}, queue: ${matchmakingQueue.length})`);
  });

  ws.on('error', (err) => {
    log('ERROR', `WebSocket error for ${cs.playerId || '?'}: ${err.message}`);
  });
});

httpServer.listen(PORT, HOST, () => {
  log('START', `Laugh Royale server running on http://${HOST}:${PORT}`);
  log('START', `WebSocket endpoint: ws://${HOST}:${PORT}`);
  log('START', `Health check:     http://${HOST}:${PORT}/health`);
  log('START', `Matchmaking:      active (queue-based pairing)`);
});
