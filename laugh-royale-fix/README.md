# Laugh Royale - Fix Guide

## Problems Found & Solutions

### Problem 1: Game doesn't detect who laughed first ❌

**Root Cause:**
- The smile detection was working but the game wasn't comparing WHO laughed first
- Each player sent their smile value to the opponent, but there was no timestamp comparison
- Server only relayed smile events without determining the winner

**Solution:**
- Added timestamp tracking when a player crosses the laugh threshold
- Added `laugh_event` message type with timestamps
- Server now compares timestamps and determines the winner

---

### Problem 2: Voice chat audio not playing ❌

**Root Cause:**
- The `onTrack` handler was empty - it only printed a message but didn't play the audio
- No audio renderer was created to play remote audio
- Remote audio tracks weren't properly enabled

**Solution:**
- Added audio renderer initialization
- Properly handle `onTrack` to add audio tracks to remote stream
- Enable audio tracks and start playback

---

## Files to Update

Copy these fixed files to your project:

### 1. `lib/screens/game/game_screen.dart`
- Added `_myLaughTime` and `_opponentLaughTime` tracking
- Added `_checkForLaugh()` method to detect when player laughs
- Added `_handleOpponentLaugh()` to handle opponent's laugh
- Added `_determineWinner()` to compare timestamps
- Added `_laughEventSent` to prevent duplicate laugh events

### 2. `lib/services/ws_game_service.dart`
- Added `sendLaughEvent()` method to send laugh timestamp
- Added handling for `laugh_event` message type

### 3. `lib/services/voice_chat_service.dart`
- Added `_initAudioRenderer()` to initialize audio playback
- Added `_startRemoteAudioPlayback()` to play remote audio
- Fixed `onTrack` handler to properly enable and play audio tracks
- Added `_remoteStream` for receiving remote audio

### 4. `server/server.js`
- Added `handleLaughEvent()` function to process laugh events
- Added laugh tracking fields to room data (`hostLaughed`, `guestLaughed`, `hostLaughTime`, `guestLaughTime`)
- Added winner determination logic when both players have laughed
- Added `game_result` message type

---

## How to Apply

### Step 1: Backup your files
```bash
cp lib/screens/game/game_screen.dart lib/screens/game/game_screen.dart.bak
cp lib/services/ws_game_service.dart lib/services/ws_game_service.dart.bak
cp lib/services/voice_chat_service.dart lib/services/voice_chat_service.dart.bak
cp server/server.js server/server.js.bak
```

### Step 2: Replace files
Copy the fixed files from this folder to your project.

### Step 3: Update server
Push the new `server/server.js` to your Render deployment.

### Step 4: Test
1. Rebuild the Flutter app
2. Deploy the updated server
3. Test with two devices

---

## How it Works Now

1. When a player's smile crosses the threshold (`0.35`):
   - Record the timestamp
   - Send `laugh_event` to server with timestamp

2. Server receives laugh event:
   - Records the laugh in room data
   - Relays to opponent
   - If BOTH have laughed, compares timestamps

3. Winner determination:
   - Player who laughed FIRST loses
   - Player who laughed SECOND wins
   - If only one laughs within 3 seconds, they win

4. Audio:
   - Remote audio tracks are now properly added and enabled
   - Audio should play through the device speaker

---

## Testing Tips

### Test smile detection:
```dart
// In game_screen.dart, you can add debug logs:
debugPrint('[GAME] My smile: $_mySmile');
debugPrint('[GAME] Opponent smile: $_oppSmile');
debugPrint('[GAME] My laugh time: $_myLaughTime');
debugPrint('[GAME] Opponent laugh time: $_opponentLaughTime');
```

### Test voice:
```dart
// Check if remote audio is playing:
VoiceChatService.startVoiceChat(roomCode: 'test', isHost: true)
  .then((success) => debugPrint('[TEST] Voice chat: $success'));
```

---

## Security Note

⚠️ The original `voice_chat_service.dart` had hardcoded TURN server credentials. The fixed version removes these. For production, use environment variables or a secure credential management system.

```dart
// ❌ REMOVED from fixed version:
// 'username': 'efMYdMYglc8AJBNmzLvaV0apU6B8qGqO',
// 'credential': 'DOogmNUqMX7Ewj3f7NNqYjpxf1aztCgO',
```
