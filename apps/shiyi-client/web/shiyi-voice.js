const $ = (id) => document.getElementById(id);
const copy = {
  zh: { brand: '时忆', integration: '独立语音联调', title: '时忆语音助手', disclosure: '内容由AI生成', start: '开始对话', resume: '播放声音', stop: '结束', mic: '麦克风', speaker: '扬声器', empty: '今天，有什么想聊的吗？', send: '发送', placeholder: '说点什么…', privacy: '语音与文字由云端 AI 服务处理。开启麦克风后才会采集声音；结束即停止。请勿输入敏感信息。', checking: '正在检查服务…', ready: '服务已就绪', connecting: '正在建立语音连接…', connected: '已连接', speaking: 'AI正在说话…', processing: 'AI正在思考…', ended: '对话已结束', reconnecting: '连接暂时中断，正在恢复…', failed: '连接失败，请结束后重试', unavailable: '联调服务未连接，请双击项目中的 open-voice-integration.bat', missing: '未找到语音助手，请检查联调环境的角色配置', denied: '麦克风不可用，仍可输入文字并听取AI回复', timeout: '连接超时，请结束后重试', greeting: '请用一句自然的普通话向我问好，介绍你是时忆的AI语音助手，然后问我今天过得怎么样。', you: '你', ai: 'AI · 内容由AI生成', error: '发生错误', portrait: 'AI助手示意形象' },
  en: { brand: 'Shiyi', integration: 'Voice integration', title: 'Shiyi Voice Assistant', disclosure: 'AI-generated content', start: 'Start conversation', resume: 'Play audio', stop: 'End', mic: 'Microphone', speaker: 'Speaker', empty: 'What is on your mind today?', send: 'Send', placeholder: 'Say something…', privacy: 'Cloud AI services process your messages and voice. Audio is captured only when the microphone is on and stops when you end the conversation. Do not share sensitive information.', checking: 'Checking services…', ready: 'Ready', connecting: 'Connecting voice…', connected: 'Connected', speaking: 'AI is speaking…', processing: 'AI is thinking…', ended: 'Conversation ended', reconnecting: 'Connection interrupted. Reconnecting…', failed: 'Connection failed. End and try again.', unavailable: 'Integration is offline. Open open-voice-integration.bat in the project.', missing: 'The voice assistant is missing from the integration configuration.', denied: 'Microphone unavailable. You can still type and hear AI replies.', timeout: 'Connection timed out. End and try again.', greeting: 'Greet me in one short English sentence, introduce yourself as the Shiyi AI voice assistant, and ask how my day is going.', you: 'You', ai: 'AI · AI-generated content', error: 'An error occurred', portrait: 'Illustrative AI assistant portrait' },
};
let language = new URLSearchParams(location.search).get('lang') === 'en' ? 'en' : 'zh';
const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(location.hostname);
const apiOrigin = location.port === '15173' || !loopback ? location.origin : 'http://127.0.0.1:18080';
let characterId = '';
let sessionId = '';
let socket = null;
let peer = null;
let micStream = null;
let iceServers = [];
let candidates = [];
let signalChain = Promise.resolve();
let generation = 0;
let active = false;
let greetingSent = false;
let statusKey = 'checking';
let statusError = false;
let connectionTimer = null;
let pendingCreate = false;
const drafts = new Map();
const text = (key) => copy[language][key] || key;
const audio = $('audio');

function status(key, isError = false) {
  statusKey = key;
  statusError = isError;
  $('status').textContent = text(key);
  $('status').dataset.error = String(isError);
}
function translate() {
  document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en';
  document.title = `${text('brand')} · AI Voice`;
  document.querySelectorAll('[data-i18n]').forEach((el) => { el.textContent = text(el.dataset.i18n); });
  document.querySelectorAll('.message b').forEach((el) => { el.textContent = text(el.parentElement.dataset.role === 'user' ? 'you' : 'ai'); });
  $('language').textContent = language === 'zh' ? 'English' : '中文';
  $('prompt').placeholder = text('placeholder');
  $('prompt').ariaLabel = text('placeholder');
  $('portrait').alt = text('portrait');
  $('conversation').ariaLabel = text('title');
  status(statusKey, statusError);
}
async function request(path, options = {}) {
  const response = await fetch(`${apiOrigin}/api/v1${path}`, {
    ...options, headers: { 'Content-Type': 'application/json', ...options.headers },
    signal: AbortSignal.timeout(options.method === 'POST' ? 150000 : 12000),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.status === 204 ? null : response.json();
}
function send(message) {
  if (socket?.readyState !== WebSocket.OPEN) return false;
  socket.send(JSON.stringify(message));
  return true;
}
function addMessage(role, value, key) {
  if (!value) return;
  let el = drafts.get(key);
  if (!el) {
    $('messages').querySelector('.empty')?.remove();
    el = document.createElement('div');
    el.className = 'message';
    el.dataset.role = role;
    const label = document.createElement('b');
    label.textContent = text(role === 'user' ? 'you' : 'ai');
    el.append(label, document.createElement('span'));
    $('messages').append(el);
    if (key) drafts.set(key, el);
  }
  el.querySelector('span').textContent = value;
  $('messages').scrollTop = $('messages').scrollHeight;
}
async function play() {
  if (!audio.srcObject) return;
  try { await audio.play(); $('resume').hidden = true; }
  catch { $('resume').hidden = false; }
}
function enableInput(enabled) {
  $('prompt').disabled = !enabled;
  $('send').disabled = !enabled;
}
function clearConnectionTimer() { clearTimeout(connectionTimer); connectionTimer = null; }
function armConnectionTimer() {
  clearConnectionTimer();
  connectionTimer = setTimeout(() => { if (active && peer?.connectionState !== 'connected') { status('timeout', true); enableInput(false); } }, 40000);
}
async function handleSignal(data, currentGeneration) {
  if (!active || currentGeneration !== generation) return;
  if (data.type === 'webrtc_config') { iceServers = data.ice_servers || []; return; }
  if (data.type === 'webrtc_offer') {
    const old = peer;
    peer = null;
    old?.close();
    // The embedded TURN TCP service is forwarded through SSH. Direct UDP
    // candidates are unreliable across the two Windows/WSL networks.
    const connection = new RTCPeerConnection({ iceServers, iceTransportPolicy: 'relay' });
    peer = connection;
    connection.onicecandidate = ({ candidate }) => {
      if (candidate && peer === connection) send({ type: 'ice_candidate', candidate: candidate.candidate, sdp_mid: candidate.sdpMid, sdp_mline_index: candidate.sdpMLineIndex });
    };
    connection.ontrack = ({ track }) => {
      if (peer !== connection || track.kind !== 'audio') return;
      audio.srcObject = new MediaStream([track]);
      void play();
    };
    connection.onconnectionstatechange = () => {
      if (peer !== connection) return;
      if (connection.connectionState === 'connected') {
        clearConnectionTimer();
        status('connected');
        enableInput(true);
        if (!greetingSent) {
          greetingSent = true;
          // Trigger only after media is connected, so the first reply is audible.
          send({ type: 'text_input', text: text('greeting') });
        }
      } else if (connection.connectionState === 'failed') {
        clearConnectionTimer(); status('failed', true); enableInput(false);
      } else if (connection.connectionState === 'disconnected') {
        status('reconnecting'); enableInput(false); armConnectionTimer();
      }
    };
    if (micStream) micStream.getAudioTracks().forEach((track) => connection.addTrack(track, micStream));
    await connection.setRemoteDescription({ type: 'offer', sdp: data.sdp });
    for (const candidate of candidates.splice(0)) await connection.addIceCandidate(candidate);
    const answer = await connection.createAnswer();
    await connection.setLocalDescription(answer);
    if (currentGeneration === generation) send({ type: 'webrtc_answer', sdp: answer.sdp });
    return;
  }
  if (data.type === 'ice_candidate' && data.candidate) {
    const candidate = { candidate: data.candidate, sdpMid: data.sdp_mid ?? undefined, sdpMLineIndex: data.sdp_mline_index ?? undefined };
    if (!peer?.remoteDescription) candidates.push(candidate);
    else await peer.addIceCandidate(candidate);
  }
}
async function acquireMicrophone(expectedGeneration = generation) {
  if (micStream) return;
  const stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true }, video: false });
  if (!active || generation !== expectedGeneration || !$('mic').checked) {
    stream.getTracks().forEach((track) => track.stop());
    throw new DOMException('Conversation ended', 'AbortError');
  }
  micStream = stream;
}
async function endConversation(showEnded = true) {
  generation++;
  active = false;
  clearConnectionTimer();
  const oldSocket = socket; socket = null; oldSocket?.close();
  const oldPeer = peer; peer = null; oldPeer?.close();
  micStream?.getTracks().forEach((track) => track.stop()); micStream = null;
  $('mic').checked = false;
  audio.pause(); audio.srcObject = null;
  candidates = []; iceServers = []; signalChain = Promise.resolve();
  enableInput(false);
  $('stop').disabled = true; $('resume').hidden = true;
  const oldId = sessionId; sessionId = '';
  $('start').disabled = true;
  if (showEnded) status('ended');
  try { if (oldId) await request(`/sessions/${encodeURIComponent(oldId)}`, { method: 'DELETE' }); }
  catch { /* The upstream server also cleans sessions when the socket closes. */ }
  $('start').disabled = !characterId || pendingCreate;
}
async function startConversation() {
  if (active || pendingCreate) return;
  active = true; pendingCreate = true; greetingSent = false;
  drafts.clear();
  const currentGeneration = ++generation;
  $('start').disabled = true; $('stop').disabled = false; status('connecting');
  try {
    if ($('mic').checked) {
      try { await acquireMicrophone(); }
      catch { $('mic').checked = false; status('denied'); }
    }
    if (!active || generation !== currentGeneration) return;
    const result = await request('/sessions', { method: 'POST', body: JSON.stringify({ character_id: characterId, mode: 'omni' }) });
    pendingCreate = false;
    if (!active || generation !== currentGeneration) {
      await request(`/sessions/${encodeURIComponent(result.session_id)}`, { method: 'DELETE' }); return;
    }
    if (result.streaming_mode !== 'direct') throw new Error('Expected Direct WebRTC');
    sessionId = result.session_id;
    const url = new URL(`/ws/chat/${encodeURIComponent(sessionId)}`, apiOrigin);
    url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
    const ws = new WebSocket(url); socket = ws;
    ws.onopen = () => { if (socket === ws) { send({ type: 'webrtc_ready' }); armConnectionTimer(); } };
    ws.onmessage = (event) => {
      if (socket !== ws) return;
      let data; try { data = JSON.parse(event.data); } catch { return; }
      if (['webrtc_config', 'webrtc_offer', 'ice_candidate'].includes(data.type)) {
        signalChain = signalChain.then(() => handleSignal(data, currentGeneration)).catch(() => { status('failed', true); enableInput(false); });
      } else if (data.type === 'transcript' && data.text) {
        const role = data.speaker === 'assistant' ? 'assistant' : 'user';
        const key = `${role}-${data.turn_seq || 'current'}`;
        const previous = drafts.get(key)?.querySelector('span').textContent || '';
        addMessage(role, data.is_final || role === 'user' ? data.text : previous + data.text, key);
      } else if (data.type === 'avatar_status' && peer?.connectionState === 'connected') {
        status(data.status === 'speaking' ? 'speaking' : data.status === 'processing' ? 'processing' : 'connected');
      } else if (data.type === 'error') { status('error', true); }
    };
    ws.onerror = () => { if (socket === ws) { status('failed', true); enableInput(false); } };
    ws.onclose = () => { if (socket === ws && active) { status('failed', true); enableInput(false); } };
  } catch {
    pendingCreate = false; await endConversation(false); status('unavailable', true);
  } finally { pendingCreate = false; if (!active) $('start').disabled = !characterId; }
}
async function checkHealth() {
  try {
    const [health, characters] = await Promise.all([request('/health'), request('/characters')]);
    if (health.status !== 'ok' || !health.inference_connected) throw new Error('Inference unavailable');
    const requested = new URLSearchParams(location.search).get('character');
    const character = characters.find((item) => requested ? item.id === requested : item.name === '时忆语音助手');
    if (!character) { status('missing', true); return; }
    characterId = character.id; $('start').disabled = false; status('ready');
  } catch { status('unavailable', true); }
}
$('language').onclick = () => { language = language === 'zh' ? 'en' : 'zh'; translate(); };
$('start').onclick = () => { void startConversation(); };
$('stop').onclick = () => { void endConversation(); };
$('resume').onclick = () => { void play(); };
$('speaker').onchange = () => { audio.muted = !$('speaker').checked; if (!audio.muted) void play(); };
$('mic').onchange = async () => {
  if (!$('mic').checked) { micStream?.getAudioTracks().forEach((track) => { track.enabled = false; }); return; }
  if (!active) return;
  const currentGeneration = generation;
  try {
    const hadStream = !!micStream;
    await acquireMicrophone();
    if (generation !== currentGeneration || !active) { micStream?.getTracks().forEach((t) => t.stop()); micStream = null; return; }
    micStream.getAudioTracks().forEach((track) => { track.enabled = true; });
    if (!hadStream && peer) {
      candidates = []; status('connecting'); enableInput(false);
      const old = peer; peer = null; old.close();
      // StartNegotiation reuses its existing ICE credentials. A fresh browser
      // peer requires the upstream's explicit media-path reset instead.
      send({ type: 'direct_media_reset_request' }); armConnectionTimer();
    }
  } catch { $('mic').checked = false; status('denied', true); }
};
$('form').onsubmit = (event) => {
  event.preventDefault();
  const value = $('prompt').value.trim();
  if (!value || $('send').disabled) return;
  if (send({ type: 'text_input', text: value })) { addMessage('user', value); $('prompt').value = ''; status('processing'); }
};
window.addEventListener('pagehide', () => {
  micStream?.getTracks().forEach((track) => track.stop()); peer?.close(); socket?.close();
  if (sessionId) void fetch(`${apiOrigin}/api/v1/sessions/${encodeURIComponent(sessionId)}`, { method: 'DELETE', keepalive: true }).catch(() => {});
});
translate();
void checkHealth();
