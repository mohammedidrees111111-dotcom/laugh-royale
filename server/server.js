const http = require('http');
const WebSocket = require('ws');

const PORT = process.env.PORT || 3000;
const HOST = '0.0.0.0';

const rooms = new Map();
const matchmakingQueue = [];
const connStateMap = new Map();
const roomCleanupTimers = new Map();

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

function cancelCleanupTimer(roomCode) {
  const t = roomCleanupTimers.get(roomCode);
  if (t) { clearTimeout(t); roomCleanupTimers.delete(roomCode); }
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

  const roomCode = cs.roomCode;
  const other = (cs.role === 'host') ? room.guest : room.host;
  if (other && other.readyState === WebSocket.OPEN) {
    send(other, { type: 'opponent_disconnected' });
  }

  cancelCleanupTimer(roomCode);
  const timer = setTimeout(() => {
    const currentRoom = rooms.get(roomCode);
    if (!currentRoom) return;
    const hostAlive = currentRoom.host && currentRoom.host.readyState === WebSocket.OPEN;
    const guestAlive = currentRoom.guest && currentRoom.guest.readyState === WebSocket.OPEN;
    if (!hostAlive && !guestAlive) {
      const age = ((Date.now() - (currentRoom.createdAt || Date.now())) / 1000).toFixed(0);
      rooms.delete(roomCode);
      roomCleanupTimers.delete(roomCode);
      log('ROOM', `Room ${roomCode} expired (age: ${age}s, both left)`);
    }
  }, 30000);
  roomCleanupTimers.set(roomCode, timer);

  log('ROOM', `Player ${cs.role} left room ${roomCode} (reconnect window: 30s)`);
}

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

    send(p1, { type: 'matched', roomId: roomCode, opponentId: c2.playerId, opponentName: c2.playerName, role: 'host' });
    send(p2, { type: 'matched', roomId: roomCode, opponentId: c1.playerId, opponentName: c1.playerName, role: 'guest' });

    log('MATCH', `Paired ${c1.playerName}[${c1.playerId}] vs ${c2.playerName}[${c2.playerId}] in room ${roomCode}`);
    log('QUEUE', `Queue size: ${matchmakingQueue.length}`);
  }
}

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

const wss = new WebSocket.Server({ server: httpServer });

wss.on('connection', (ws, req) => {
  const clientIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress || 'unknown';
  log('CONNECT', `Client connected from ${clientIp}`);

  const cs = { roomCode: null, role: null, playerId: null, playerName: null };
  connStateMap.set(ws, cs);

  send(ws, { type: 'connected', message: 'Welcome to Laugh Royale!', serverTime: Date.now() });

  ws.on('message', (raw) => {
    let msg;
    try { msg = JSON.parse(raw); } catch (e) {
      log('ERROR', 'Invalid JSON received');
      send(ws, { type: 'error', message: 'Invalid message format' });
      return;
    }

    log('MSG', `${cs.role || '?'} → ${msg.type}`);

    switch (msg.type) {

      case 'matchmaking_join':
        if (cs.roomCode || matchmakingQueue.includes(ws)) {
          send(ws, { type: 'error', message: 'Already in queue or room' });
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

      case 'reconnect':
        {
          const pid = msg.playerId;
          const rid = msg.roomCode;
          if (!pid || !rid) {
            send(ws, { type: 'error', message: 'Missing playerId or roomCode' });
            return;
          }

          if (cs.roomCode) {
            send(ws, { type: 'reconnected', roomId: cs.roomCode, role: cs.role,
              opponentId: cs.role === 'host' ? (rooms.get(cs.roomCode)?.guestId) : (rooms.get(cs.roomCode)?.hostId) });
            return;
          }

          const room = rooms.get(rid);
          if (!room) {
            send(ws, { type: 'error', message: 'Room expired' });
            log('RECONNECT', `Room ${rid} expired, ${pid} too late`);
            return;
          }

          cancelCleanupTimer(rid);
          removeFromQueue(ws);

          if (room.hostId === pid) {
            const oldWs = room.host;
            if (oldWs && oldWs !== ws && oldWs.readyState !== WebSocket.OPEN) {
              try { oldWs.terminate(); } catch (_) {}
              connStateMap.delete(oldWs);
            }
            room.host = ws;
            cs.role = 'host';
            cs.playerId = pid;
            cs.roomCode = rid;
            if (room.guest && room.guest.readyState === WebSocket.OPEN) {
              send(room.guest, { type: 'opponent_reconnected' });
            }
            send(ws, { type: 'reconnected', roomId: rid, role: 'host',
              opponentId: room.guestId, opponentName: room.guestId });
            log('RECONNECT', `Host ${pid} reconnected to room ${rid}`);
          } else if (room.guestId === pid) {
            const oldWs = room.guest;
            if (oldWs && oldWs !== ws && oldWs.readyState !== WebSocket.OPEN) {
              try { oldWs.terminate(); } catch (_) {}
              connStateMap.delete(oldWs);
            }
            room.guest = ws;
            cs.role = 'guest';
            cs.playerId = pid;
            cs.roomCode = rid;
            if (room.host && room.host.readyState === WebSocket.OPEN) {
              send(room.host, { type: 'opponent_reconnected' });
            }
            send(ws, { type: 'reconnected', roomId: rid, role: 'guest',
              opponentId: room.hostId, opponentName: room.hostId });
            log('RECONNECT', `Guest ${pid} reconnected to room ${rid}`);
          } else {
            send(ws, { type: 'error', message: 'Not a member of this room' });
          }
        }
        break;

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
          host: ws, guest: null, hostId: cs.playerId, guestId: null, createdAt: Date.now(),
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
        {
          const jc = msg.code;
          const jr = rooms.get(jc);
          if (!jr) { send(ws, { type: 'error', message: 'Room not found' }); return; }
          if (jr.guest) { send(ws, { type: 'error', message: 'Room is full' }); return; }
          cs.roomCode = jc;
          cs.role = 'guest';
          cs.playerId = msg.id || 'guest';
          cs.playerName = msg.name || 'Player';
          jr.guest = ws;
          jr.guestId = cs.playerId;
          send(jr.host, { type: 'player_joined', id: cs.playerId, name: cs.playerName });
          send(ws, { type: 'joined', id: jr.hostId, name: jr.hostId });
          log('JOIN', `Player ${cs.playerId} joined room ${jc}`);
        }
        break;

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
          if (!r) { send(ws, { type: 'error', message: 'Not in a room' }); return; }
          const target = cs.role === 'host' ? r.guest : r.host;
          if (msg.type === 'event' && msg.event === 'laughed') {
            log('LAUGH', `sender=${cs.role}[${cs.playerId}] target=${cs.role === 'host' ? 'guest' : 'host'}[${cs.role === 'host' ? r.guestId : r.hostId}] same=${target === ws} room=${cs.roomCode}`);
          }
          if (target && target.readyState === WebSocket.OPEN) send(target, msg);
        }
        break;

      default:
        {
          const r = rooms.get(cs.roomCode);
          if (!r) { send(ws, { type: 'error', message: 'Not in a room' }); return; }
          const target = cs.role === 'host' ? r.guest : r.host;
          if (target && target.readyState === WebSocket.OPEN) send(target, msg);
        }
    }
  });

  ws.on('close', () => {
    removeFromQueue(ws);
    cleanupRoom(ws);
    connStateMap.delete(ws);
    log('DISCONNECT', `Client disconnected (rooms: ${rooms.size}, queue: ${matchmakingQueue.length})`);
  });

  ws.on('error', (err) => {
    log('ERROR', `WebSocket error for ${cs.playerId || '?'}: ${err.message}`);
  });
});

httpServer.listen(PORT, HOST, () => {
  log('START', `Server running on http://${HOST}:${PORT}`);
  log('START', `Health check: http://${HOST}:${PORT}/health`);
  log('START', `Matchmaking: active (queue-based pairing)`);
});
