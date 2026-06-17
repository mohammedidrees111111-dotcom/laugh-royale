const http = require('http');
const WebSocket = require('ws');

const PORT = process.env.PORT || 3000;
const HOST = '0.0.0.0';
const HEARTBEAT_INTERVAL = 30000;
const HEARTBEAT_TIMEOUT = 10000;
const ROOM_SWEEP_INTERVAL = 60000;
const MAX_CONNECTIONS = 500;
const MAX_PAYLOAD = 65536;
const MAX_MSG_PER_SEC = 15;

const rooms = new Map();
const matchmakingQueue = [];
const connStateMap = new Map();
const roomCleanupTimers = new Map();
let shuttingDown = false;

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
  try { ws.send(JSON.stringify(obj)); } catch (e) {
    log('SEND_ERR', `Failed to send to ${connStateMap.get(ws)?.playerId || '?'}: ${e.message}`);
  }
}

function cancelCleanupTimer(roomCode) {
  const t = roomCleanupTimers.get(roomCode);
  if (t) { clearTimeout(t); roomCleanupTimers.delete(roomCode); }
}

function getOpponentName(ws, room) {
  if (!room) return 'Player';
  const cs = connStateMap.get(ws);
  if (!cs) return 'Player';
  if (cs.role === 'host') {
    const guestCs = connStateMap.get(room.guest);
    return guestCs?.playerName || 'Player';
  }
  const hostCs = connStateMap.get(room.host);
  return hostCs?.playerName || 'Player';
}

function getOpponent(ws, room) {
  if (!room) return null;
  if (ws === room.host) return room.guest;
  if (ws === room.guest) return room.host;
  const cs = connStateMap.get(ws);
  if (cs && cs.role === 'host') return room.guest;
  if (cs && cs.role === 'guest') return room.host;
  const target = ws === room.host ? room.guest : ws === room.guest ? room.host : null;
  return target && target.readyState === WebSocket.OPEN ? target : null;
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
  const other = getOpponent(ws, room);
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
      const age = currentRoom.createdAt
        ? ((Date.now() - currentRoom.createdAt) / 1000).toFixed(0)
        : '?';
      rooms.delete(roomCode);
      roomCleanupTimers.delete(roomCode);
      log('ROOM', `Room ${roomCode} expired (age: ${age}s, both left)`);
    }
  }, 30000);
  roomCleanupTimers.set(roomCode, timer);

  log('ROOM', `Player ${cs.role} left room ${roomCode} (reconnect window: 30s)`);
}

function sweepGhostRooms() {
  const now = Date.now();
  for (const [code, room] of rooms) {
    const hostAlive = room.host && room.host.readyState === WebSocket.OPEN;
    const guestAlive = room.guest && room.guest.readyState === WebSocket.OPEN;
    if (!hostAlive && !guestAlive) {
      rooms.delete(code);
      roomCleanupTimers.delete(code);
      log('SWEEP', `Ghost room ${code} removed (no live players)`);
    } else if (hostAlive && !guestAlive) {
      const age = (now - (room.createdAt || now)) / 1000;
      if (age > 120) {
        if (room.host) {
          connStateMap.delete(room.host);
          try { room.host.terminate(); } catch (_) {}
        }
        if (room.guest) {
          connStateMap.delete(room.guest);
          try { room.guest.terminate(); } catch (_) {}
        }
        rooms.delete(code);
        roomCleanupTimers.delete(code);
        log('SWEEP', `Stale room ${code} removed (age: ${age.toFixed(0)}s, only host alive)`);
      }
    } else if (guestAlive && !hostAlive) {
      const age = (now - (room.createdAt || now)) / 1000;
      if (age > 120) {
        if (room.host) {
          connStateMap.delete(room.host);
          try { room.host.terminate(); } catch (_) {}
        }
        if (room.guest) {
          connStateMap.delete(room.guest);
          try { room.guest.terminate(); } catch (_) {}
        }
        rooms.delete(code);
        roomCleanupTimers.delete(code);
        log('SWEEP', `Stale room ${code} removed (age: ${age.toFixed(0)}s, only guest alive)`);
      }
    }
  }
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
    if (!c1 || !c2) continue;

    if (c1.playerId === c2.playerId) {
      matchmakingQueue.unshift(p2);
      log('PAIR', 'Skipped same-player pairing');
      continue;
    }

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
      hostLaughTime: null,
      guestLaughTime: null,
      laughDecided: false,
    });

    send(p1, { type: 'matched', roomId: roomCode, opponentId: c2.playerId, opponentName: c2.playerName || 'Player', role: 'host' });
    send(p2, { type: 'matched', roomId: roomCode, opponentId: c1.playerId, opponentName: c1.playerName || 'Player', role: 'guest' });

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
    const wssReady = wss && wss.clients ? true : false;
    const memoryUsage = process.memoryUsage();
    res.writeHead(wssReady ? 200 : 503, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: wssReady && !shuttingDown ? 'ok' : 'degraded',
      uptime: process.uptime(),
      rooms: rooms.size,
      queue: matchmakingQueue.length,
      clients: connStateMap.size,
      shuttingDown: shuttingDown,
      memoryMB: Math.round(memoryUsage.heapUsed / 1048576),
      timestamp: new Date().toISOString(),
    }));
    return;
  }

  res.writeHead(404);
  res.end();
});

const wss = new WebSocket.Server({
  server: httpServer,
  maxPayload: MAX_PAYLOAD,
});

let connectCount = 0;

wss.on('connection', (ws, req) => {
  connectCount++;
  if (connectCount > MAX_CONNECTIONS) {
    ws.close(1013, 'Server full');
    connectCount--;
    log('REJECT', 'Connection refused: server full');
    return;
  }

  const clientIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress || 'unknown';
  log('CONNECT', `Client connected from ${clientIp} (total: ${connectCount})`);

  const cs = {
    roomCode: null,
    role: null,
    playerId: null,
    playerName: null,
    lastMsgTime: 0,
    msgCount: 0,
  };
  connStateMap.set(ws, cs);

  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });

  send(ws, { type: 'connected', message: 'Welcome to Laugh Royale!', serverTime: Date.now() });

  ws.on('message', (raw) => {
    const now = Date.now();
    if (now - cs.lastMsgTime > 1000) {
      cs.lastMsgTime = now;
      cs.msgCount = 0;
    }
    cs.msgCount++;
    if (cs.msgCount > MAX_MSG_PER_SEC) {
      log('RATE', `Rate limit hit for ${cs.playerId || '?'} (${cs.msgCount} msg/s)`);
      return;
    }

    let msg;
    try { msg = JSON.parse(raw); } catch (e) {
      log('ERROR', `Invalid JSON from ${cs.playerId || '?'}: ${e.message}`);
      send(ws, { type: 'error', message: 'Invalid message format' });
      return;
    }

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

          if (cs.roomCode && !shuttingDown) {
            const existingRoom = rooms.get(cs.roomCode);
            if (existingRoom) {
              if (existingRoom.hostId === pid) {
                const oldWs = existingRoom.host;
                if (oldWs && oldWs !== ws) {
                  connStateMap.delete(oldWs);
                  try { oldWs.terminate(); } catch (_) {}
                }
                existingRoom.host = ws;
              } else if (existingRoom.guestId === pid) {
                const oldWs = existingRoom.guest;
                if (oldWs && oldWs !== ws) {
                  connStateMap.delete(oldWs);
                  try { oldWs.terminate(); } catch (_) {}
                }
                existingRoom.guest = ws;
              }
              cancelCleanupTimer(cs.roomCode);
              cs.role = existingRoom.hostId === pid ? 'host' : 'guest';
              log('RECONNECT', `${cs.role} ${pid} rebinded WebSocket to room ${cs.roomCode}`);
            }
            const oppName = getOpponentName(ws, existingRoom);
            send(ws, { type: 'reconnected', roomId: cs.roomCode, role: cs.role,
              opponentId: existingRoom ? (existingRoom.hostId === pid ? existingRoom.guestId : existingRoom.hostId) : null,
              opponentName: oppName });
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
            if (oldWs && oldWs !== ws) {
              connStateMap.delete(oldWs);
              try { oldWs.terminate(); } catch (_) {}
            }
            room.host = ws;
            cs.role = 'host';
            cs.playerId = pid;
            cs.roomCode = rid;
            const nameMsg = msg.playerName;
            if (nameMsg) cs.playerName = nameMsg;
            if (room.guest && room.guest.readyState === WebSocket.OPEN) {
              send(room.guest, { type: 'opponent_reconnected' });
            }
            const oppName = getOpponentName(ws, room);
            send(ws, { type: 'reconnected', roomId: rid, role: 'host',
              opponentId: room.guestId, opponentName: oppName });
            log('RECONNECT', `Host ${pid} reconnected to room ${rid}`);
          } else if (room.guestId === pid) {
            const oldWs = room.guest;
            if (oldWs && oldWs !== ws) {
              connStateMap.delete(oldWs);
              try { oldWs.terminate(); } catch (_) {}
            }
            room.guest = ws;
            cs.role = 'guest';
            cs.playerId = pid;
            cs.roomCode = rid;
            const nameMsg = msg.playerName;
            if (nameMsg) cs.playerName = nameMsg;
            if (room.host && room.host.readyState === WebSocket.OPEN) {
              send(room.host, { type: 'opponent_reconnected' });
            }
            const oppName = getOpponentName(ws, room);
            send(ws, { type: 'reconnected', roomId: rid, role: 'guest',
              opponentId: room.hostId, opponentName: oppName });
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
        cs.playerName = msg.name || 'Host';
        rooms.set(cs.roomCode, {
          host: ws, guest: null, hostId: cs.playerId, guestId: null, createdAt: Date.now(),
          hostLaughTime: null, guestLaughTime: null, laughDecided: false,
        });
        send(ws, { type: 'room_created', code: cs.roomCode });
        log('ROOM', `Created ${cs.roomCode} by host ${cs.playerName}`);
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
          if (jr.guest && jr.guest.readyState === WebSocket.OPEN) {
            send(ws, { type: 'error', message: 'Room is full' });
            return;
          }
          cs.roomCode = jc;
          cs.role = 'guest';
          cs.playerId = msg.id || 'guest';
          cs.playerName = msg.name || 'Player';
          jr.guest = ws;
          jr.guestId = cs.playerId;
          const hostCs = connStateMap.get(jr.host);
          const hostName = hostCs?.playerName || 'Host';
          send(jr.host, { type: 'player_joined', id: cs.playerId, name: cs.playerName });
          send(ws, { type: 'joined', id: jr.hostId, name: hostName });
          log('JOIN', `Player ${cs.playerName} joined room ${jc}`);
        }
        break;

      case 'start':
        {
          const r = rooms.get(cs.roomCode);
          if (!r) { send(ws, { type: 'error', message: 'Not in a room' }); return; }
          const target = getOpponent(ws, r);
          if (target && target.readyState === WebSocket.OPEN) {
            send(target, { type: 'event', event: 'started' });
            log('GAME', `Game started in room ${cs.roomCode} by ${cs.role}`);
          } else {
            log('GAME', `Game start in room ${cs.roomCode} — opponent not available`);
          }
        }
        break;

      case 'voice':
      case 'voice_offer':
      case 'voice_answer':
      case 'voice_ice':
        {
          const r = rooms.get(cs.roomCode);
          if (!r) { send(ws, { type: 'error', message: 'Not in a room' }); return; }
          const target = getOpponent(ws, r);
          if (target && target.readyState === WebSocket.OPEN && target !== ws) {
            send(target, msg);
            log('VOICE', `Relayed ${msg.type} from ${cs.role || '?'}`);
          } else {
            log('VOICE', `Cannot relay ${msg.type} — opponent not open (${target ? 'exists but closed' : 'null'})`);
            send(ws, { type: 'error', message: 'Opponent not connected — voice signal not delivered' });
          }
        }
        break;

      case 'smile_laugh':
        {
          const r = rooms.get(cs.roomCode);
          if (!r) { send(ws, { type: 'error', message: 'Not in a room' }); return; }
          if (r.laughDecided) {
            log('LAUGH', `Laugh already decided for room ${cs.roomCode} — ignoring`);
            break;
          }

          const laughTime = msg.timestamp || Date.now();
          const isHost = cs.role === 'host';

          if (isHost) {
            if (r.hostLaughTime) break;
            r.hostLaughTime = laughTime;
            log('LAUGH', `Host ${cs.playerId} laughed at ${laughTime}`);
          } else {
            if (r.guestLaughTime) break;
            r.guestLaughTime = laughTime;
            log('LAUGH', `Guest ${cs.playerId} laughed at ${laughTime}`);
          }

          const target = getOpponent(ws, r);
          if (target && target.readyState === WebSocket.OPEN && target !== ws) {
            send(target, msg);
          }

          const hostTime = r.hostLaughTime;
          const guestTime = r.guestLaughTime;

          if (hostTime && guestTime) {
            const hostLost = hostTime < guestTime;
            log('LAUGH', `Both laughed — host:${hostTime} guest:${guestTime} → ${hostLost ? 'host' : 'guest'} loses`);
            if (r.host && r.host.readyState === WebSocket.OPEN) {
              send(r.host, { type: 'event', event: hostLost ? 'you_lost' : 'you_won' });
            }
            if (r.guest && r.guest.readyState === WebSocket.OPEN) {
              send(r.guest, { type: 'event', event: hostLost ? 'you_won' : 'you_lost' });
            }
            r.laughDecided = true;
          } else {
            const whoLaughed = hostTime ? 'host' : 'guest';
            log('LAUGH', `Only ${whoLaughed} laughed — they lose`);
            r.laughDecided = true;
            if (r.host && r.host.readyState === WebSocket.OPEN) {
              send(r.host, { type: 'event', event: hostTime ? 'you_lost' : 'you_won' });
            }
            if (r.guest && r.guest.readyState === WebSocket.OPEN) {
              send(r.guest, { type: 'event', event: guestTime ? 'you_lost' : 'you_won' });
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
          const target = getOpponent(ws, r);
          if (msg.type === 'event' && msg.event === 'laughed') {
            log('LAUGH', `sender=${cs.role || '?'}[${cs.playerId}] room=${cs.roomCode}`);
          }
          if (target && target.readyState === WebSocket.OPEN && target !== ws) {
            send(target, msg);
          } else {
            log('RELAY', `Cannot relay ${msg.type} from ${cs.role || '?'} — opponent not available`);
            send(ws, { type: 'error', message: `Opponent not available — ${msg.type} not delivered` });
          }
        }
        break;

      default:
        {
          const r = rooms.get(cs.roomCode);
          if (!r) { send(ws, { type: 'error', message: 'Not in a room' }); return; }
          const target = getOpponent(ws, r);
          if (target && target.readyState === WebSocket.OPEN && target !== ws) send(target, msg);
        }
    }
  });

  ws.on('close', (code, reason) => {
    connectCount = Math.max(0, connectCount - 1);
    const reasonStr = reason ? reason.toString().substring(0, 100) : '';
    log('DISCONNECT', `Client ${cs.playerId || '?'} disconnected (code: ${code}, reason: ${reasonStr}) (rooms: ${rooms.size}, queue: ${matchmakingQueue.length})`);
    removeFromQueue(ws);
    cleanupRoom(ws);
    connStateMap.delete(ws);
  });

  ws.on('error', (err) => {
    log('ERROR', `WebSocket error for ${cs.playerId || '?'}: ${err.message}`);
    removeFromQueue(ws);
    cleanupRoom(ws);
    connStateMap.delete(ws);
    try { ws.terminate(); } catch (_) {}
    connectCount = Math.max(0, connectCount - 1);
  });
});

const heartbeatTimer = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (ws.isAlive === false) {
      log('HEARTBEAT', `Terminating zombie connection for ${connStateMap.get(ws)?.playerId || '?'}`);
      removeFromQueue(ws);
      cleanupRoom(ws);
      connStateMap.delete(ws);
      return ws.terminate();
    }
    ws.isAlive = false;
    try { ws.ping(); } catch (_) {}
  });
}, HEARTBEAT_INTERVAL);

const sweepTimer = setInterval(sweepGhostRooms, ROOM_SWEEP_INTERVAL);

process.on('SIGTERM', () => {
  shuttingDown = true;
  log('SHUTDOWN', 'SIGTERM received — graceful shutdown');

  wss.clients.forEach((ws) => {
    send(ws, { type: 'server_shutdown', message: 'Server is restarting. Please reconnect in a few seconds.' });
  });

  clearInterval(heartbeatTimer);
  clearInterval(sweepTimer);

  setTimeout(() => {
    wss.clients.forEach((ws) => { try { ws.terminate(); } catch (_) {} });
    wss.close(() => {
      httpServer.close(() => {
        log('SHUTDOWN', 'Server closed');
        process.exit(0);
      });
    });
  }, 3000);
});

process.on('SIGINT', () => {
  shuttingDown = true;
  log('SHUTDOWN', 'SIGINT received — graceful shutdown');

  wss.clients.forEach((ws) => {
    send(ws, { type: 'server_shutdown', message: 'Server is shutting down.' });
  });

  clearInterval(heartbeatTimer);
  clearInterval(sweepTimer);

  setTimeout(() => {
    wss.clients.forEach((ws) => { try { ws.terminate(); } catch (_) {} });
    wss.close(() => {
      httpServer.close(() => {
        log('SHUTDOWN', 'Server closed');
        process.exit(0);
      });
    });
  }, 2000);
});

httpServer.listen(PORT, HOST, () => {
  log('START', `Server running on http://${HOST}:${PORT}`);
  log('START', `Health check: http://${HOST}:${PORT}/health`);
  log('START', `Matchmaking: active | Heartbeat: ${HEARTBEAT_INTERVAL/1000}s | Room sweep: ${ROOM_SWEEP_INTERVAL/1000}s`);
  log('START', `Max connections: ${MAX_CONNECTIONS} | Max payload: ${MAX_PAYLOAD} bytes | Rate limit: ${MAX_MSG_PER_SEC} msg/s`);
});
