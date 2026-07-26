<script setup lang="ts">
import { ref, watch, watchEffect, unref, onUnmounted, computed, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import VideoPlayer from '../components/VideoPlayer.vue'
import BaiduXilingPlayer from '../components/BaiduXilingPlayer.vue'
import XunfeiAvatarPlayer from '../components/XunfeiAvatarPlayer.vue'
import ViduS1Player from '../components/ViduS1Player.vue'
import ChatPanel from '../components/ChatPanel.vue'
import { useWebRTC } from '../composables/useWebRTC'
import { useDirectWebRTC } from '../composables/useDirectWebRTC'
import { useChat, type BaiduXilingAudioEvent } from '../composables/useChat'
import { useVisualInput, type VisualInputConfig } from '../composables/useVisualInput'
import { deleteSession } from '../services/api'
import {
  clearSessionLaunchState,
  loadSessionLaunchState,
  saveSessionLaunchState,
  sessionLaunchStateFromQuery,
} from '../utils/sessionLaunchState'

const router = useRouter()
const route = useRoute()
const { t } = useI18n()
const sessionId = computed(() => route.params.id as string)

const videoPlayerRef = ref<InstanceType<typeof VideoPlayer> | null>(null)
const baiduPlayerRef = ref<InstanceType<typeof BaiduXilingPlayer> | null>(null)
const xunfeiPlayerRef = ref<InstanceType<typeof XunfeiAvatarPlayer> | null>(null)
const viduPlayerRef = ref<InstanceType<typeof ViduS1Player> | null>(null)
const pendingBaiduAudioEvents: BaiduXilingAudioEvent[] = []
const sessionVideoShellRef = ref<HTMLElement | null>(null)
const avatarFallbackBadgeRef = ref<HTMLElement | null>(null)
const avatarFallbackPopoverRef = ref<HTMLElement | null>(null)
const visualPreviewShellRef = ref<HTMLElement | null>(null)
const visualPreviewRef = ref<HTMLVideoElement | null>(null)
const visualPreviewPosition = ref<{ x: number; y: number } | null>(null)
const isVisualPreviewDragging = ref(false)
const elapsed = ref(0)
const clockMs = ref(Date.now())
let timer: ReturnType<typeof setInterval> | null = null
const showDiag = ref(false)
const isChatCollapsed = ref(false)
const isChatResizing = ref(false)
const chatSidebarRef = ref<HTMLElement | null>(null)
const chatSidebarWidth = ref<number | null>(null)

const CHAT_SIDEBAR_MIN_WIDTH = 320
const CHAT_SIDEBAR_DESKTOP_BASE_WIDTH = 360
const CHAT_SIDEBAR_DESKTOP_MAX_WIDTH = 560
const CHAT_SIDEBAR_DESKTOP_RATIO = 0.4
const CHAT_SIDEBAR_MOBILE_MAX_WIDTH = 420
const CHAT_SIDEBAR_MOBILE_RATIO = 0.82
const CHAT_SIDEBAR_COLLAPSE_RESISTANCE = 96

const queryLaunchState = sessionLaunchStateFromQuery(sessionId.value, route.query as Record<string, unknown>)
if (queryLaunchState) {
  saveSessionLaunchState(queryLaunchState)
}
const launchState = ref(loadSessionLaunchState(sessionId.value) || queryLaunchState)
const streamingMode = launchState.value?.streaming_mode || 'direct'
const baiduXilingConfig = computed(() => launchState.value?.baidu_xiling)
const xunfeiConfig = computed(() => launchState.value?.xunfei)
const viduConfig = computed(() => launchState.value?.vidu)
const isBaiduXilingSession = computed(() => !!baiduXilingConfig.value)
const isXunfeiSession = computed(() => !!xunfeiConfig.value)
const isViduSession = computed(() => !!viduConfig.value)
const isExternalAvatarSession = computed(() => isBaiduXilingSession.value || isXunfeiSession.value || isViduSession.value)
const audioInputConfig = computed(() => launchState.value?.audio_input)
const hasAudioInputCapability = computed(() => isViduSession.value || (audioInputConfig.value?.enabled ?? true))
const usesMediaPeerOutput = computed(() => !isExternalAvatarSession.value)
const shouldUseMediaPeer = computed(() => !isViduSession.value && (usesMediaPeerOutput.value || hasAudioInputCapability.value))

function truthyDebugFlag(value: unknown): boolean {
  const raw = Array.isArray(value) ? value[0] : value
  return raw === true || raw === '1' || raw === 'true' || raw === 'yes'
}

function readAVCalibrationEnabled(): boolean {
  if (truthyDebugFlag(route.query.avCalibration) || truthyDebugFlag(route.query.av_calibration)) {
    return true
  }
  try {
    return window.localStorage.getItem('cyberverse.avCalibration') === '1'
  } catch {
    return false
  }
}

const avCalibrationEnabled = readAVCalibrationEnabled()

function parseVisualInputConfig(): Partial<VisualInputConfig> | undefined {
  return launchState.value?.visual_input
}

const visualInputConfig = computed(() => parseVisualInputConfig())
const hasVisualInputCapability = computed(() => !!visualInputConfig.value)
const idleStrategy = computed(() => launchState.value?.idle_strategy || 'cached_video')

// Both composables are called unconditionally (Vue requirement),
// but only the active one is wired up.
const lk = useWebRTC()
const dp = useDirectWebRTC()
const isDirectMode = streamingMode === 'direct'

const videoElement = isDirectMode ? dp.videoElement : lk.videoElement
const connectionState = isDirectMode ? dp.connectionState : lk.connectionState
const debugState = isDirectMode ? dp.debugState : lk.debugState
const isMuted = isDirectMode ? dp.isMuted : lk.isMuted
const isOutputMuted = isDirectMode ? dp.isOutputMuted : lk.isOutputMuted
const micBarLevels = isDirectMode ? dp.micBarLevels : lk.micBarLevels
const toggleMute = isDirectMode ? dp.toggleMute : lk.toggleMute
const toggleOutputMute = isDirectMode ? dp.toggleOutputMute : lk.toggleOutputMute
const webrtcDisconnect = isDirectMode ? dp.disconnect : lk.disconnect
const setAVSyncLoggingEnabled = isDirectMode ? dp.setAVSyncLoggingEnabled : lk.setAVSyncLoggingEnabled

type BaiduXilingConnectionState = {
  rtcReady: boolean
  wsReady: boolean
  wsReadyState?: number
}

const baiduOutputMuted = ref(false)
const baiduXilingConnectionState = ref<BaiduXilingConnectionState>({ rtcReady: false, wsReady: false })
const baiduAvatarError = ref('')
const xunfeiConnectionState = ref({ streamReady: false, autoplayBlocked: false })
const xunfeiAvatarError = ref('')
const viduConnectionState = ref({
  rtcReady: false,
  streamReady: false,
  audioReady: false,
  autoplayBlocked: false,
  microphoneEnabled: false,
  cameraEnabled: false,
  remoteSpeechDetected: false,
})
const viduControlReady = ref(false)
const viduControlInitSent = ref(false)
const viduRTCJoined = ref(false)
const viduAvatarError = ref('')
const showAvatarFallbackDetails = ref(false)
const outputMutedVisual = computed(() => isExternalAvatarSession.value ? baiduOutputMuted.value : isOutputMuted.value)
const outputButtonTitle = computed(() => {
  if (isXunfeiSession.value && xunfeiConnectionState.value.autoplayBlocked) {
    return t('session.xunfeiAutoplayBlocked')
  }
  if (isViduSession.value && viduConnectionState.value.autoplayBlocked) {
    return t('session.viduEnableAudio')
  }
  return outputMutedVisual.value ? t('session.outputUnmute') : t('session.outputMute')
})
const baiduAvatarReady = computed(() =>
  isBaiduXilingSession.value
  && baiduXilingConnectionState.value.rtcReady
  && baiduXilingConnectionState.value.wsReady
  && !baiduAvatarError.value
)
const baiduVoiceFallbackActive = computed(() => isBaiduXilingSession.value && !!baiduAvatarError.value)
const xunfeiVoiceFallbackActive = computed(() => isXunfeiSession.value && !!xunfeiAvatarError.value)
const externalAvatarFallbackActive = computed(() => baiduVoiceFallbackActive.value || xunfeiVoiceFallbackActive.value)
const baiduAvatarNotice = computed(() => {
  if (!isBaiduXilingSession.value) return ''
  if (baiduAvatarError.value) return baiduAvatarError.value
  if (!baiduAvatarReady.value) return t('session.baiduConnecting')
  return ''
})
const mediaConnected = computed(() => {
  if (isViduSession.value) {
    return chatConnected.value
      && viduConnectionState.value.rtcReady
      && viduConnectionState.value.streamReady
      && viduControlReady.value
      && !viduAvatarError.value
  }
  if (isBaiduXilingSession.value) {
    const voiceReady = !shouldUseMediaPeer.value || connectionState.value === 'connected'
    return chatConnected.value && voiceReady && (baiduAvatarReady.value || baiduVoiceFallbackActive.value)
  }
  if (isXunfeiSession.value) {
    return chatConnected.value
      && (xunfeiConnectionState.value.streamReady || xunfeiVoiceFallbackActive.value)
      && (!shouldUseMediaPeer.value || connectionState.value === 'connected')
  }
  if (!shouldUseMediaPeer.value) return chatConnected.value
  return connectionState.value === 'connected'
})

watchEffect(() => {
  if (isExternalAvatarSession.value) {
    videoElement.value = null
    return
  }
  const inst = videoPlayerRef.value
  const inner = inst?.videoRef
  videoElement.value = inner ? unref(inner) : null
})

const characterId = computed(() => launchState.value?.character_id || '')

const {
  messages,
  currentTranscript,
  currentLLMResponse,
  avatarStatus,
  idleVideoUrl,
  idleVideoUrls,
  historyLoading,
  historyHasMore,
  sendText,
  connect: chatConnect,
  disconnect: chatDisconnect,
  loadHistory,
  registerSignalingHandler,
  registerBaiduXilingAudioHandler,
  registerViduControlHandler,
  sendSignaling,
  sendWSMessage,
  isConnected: chatConnected,
} = useChat(() => sessionId.value)

registerViduControlHandler((event) => {
  if (event.type === 'vidu_ready') {
    viduControlReady.value = true
    viduAvatarError.value = ''
    return
  }
  viduControlReady.value = false
  viduAvatarError.value = event.message || (event.type === 'vidu_hangup'
    ? t('session.viduDisconnected')
    : t('session.viduConnectionError'))
})

function notifyViduRTCReady() {
  if (!isViduSession.value || !chatConnected.value || !viduRTCJoined.value || viduControlInitSent.value) return
  if (sendWSMessage({ type: 'vidu_rtc_ready' })) {
    viduControlInitSent.value = true
  }
}

watch(chatConnected, notifyViduRTCReady)

registerBaiduXilingAudioHandler((event) => {
  if (baiduVoiceFallbackActive.value) {
    void playBaiduVoiceFallbackEvent(event)
    return
  }
  bufferBaiduVoiceFallbackEvent(event)
  const player = baiduPlayerRef.value
  if (!player) {
    pendingBaiduAudioEvents.push(event)
    return
  }
  player.sendAudioEvent(event)
})

watch(baiduPlayerRef, (player) => {
  if (!player || baiduAvatarError.value || pendingBaiduAudioEvents.length === 0) return
  const events = pendingBaiduAudioEvents.splice(0)
  for (const event of events) {
    player.sendAudioEvent(event)
  }
})

const visualInput = useVisualInput(
  (msg) => sendWSMessage(msg),
  () => visualInputConfig.value,
)
const startupGreetingReadySent = ref(false)
const canUseVisualInput = computed(() =>
  hasVisualInputCapability.value && chatConnected.value && (visualInputConfig.value?.enabled ?? false)
)
const visualPreviewStyle = computed(() => {
  const pos = visualPreviewPosition.value
  if (!pos) return undefined
  return {
    left: `${pos.x}px`,
    top: `${pos.y}px`,
    right: 'auto',
    bottom: 'auto',
  }
})

const VISUAL_PREVIEW_MARGIN = 12
const BAIDU_ACTIVE_SESSION_PREFIX = 'cyberverse.baidu_xiling.active.'
const BAIDU_AVATAR_READY_TIMEOUT_MS = 15000
const BAIDU_FALLBACK_AUDIO_SAMPLE_RATE = 16000

type VisualPreviewDragState = {
  pointerId: number
  offsetX: number
  offsetY: number
  previewEl: HTMLElement
}

let visualPreviewDragState: VisualPreviewDragState | null = null

type ChatSidebarResizeState = {
  pointerId: number
  rightEdge: number
  minWidth: number
  maxWidth: number
  minReachedClientX: number | null
  handleEl: HTMLElement
}

let chatSidebarResizeState: ChatSidebarResizeState | null = null
let baiduAvatarReadyTimer: ReturnType<typeof window.setTimeout> | null = null
let viduSessionTeardownRequested = false
const baiduVoiceFallbackEvents: BaiduXilingAudioEvent[] = []
let baiduVoiceAudioContext: AudioContext | null = null
let baiduVoiceGainNode: GainNode | null = null
let baiduVoiceNextPlayAt = 0
let baiduVoiceSources: AudioBufferSourceNode[] = []

const chatSidebarStyle = computed<Record<string, string> | undefined>(() => {
  if (chatSidebarWidth.value === null) return undefined
  return {
    '--chat-sidebar-width': `${chatSidebarWidth.value}px`,
  }
})

watch([chatConnected, connectionState], ([chatReady, mediaState]) => {
  if (!shouldUseMediaPeer.value || isExternalAvatarSession.value) return
  if (startupGreetingReadySent.value) return
  if (idleStrategy.value !== 'silent_inference') return
  if (!chatReady || mediaState !== 'connected') return
  if (sendWSMessage({ type: 'client_media_ready' })) {
    startupGreetingReadySent.value = true
  }
})

watch(baiduAvatarReady, (ready) => {
  if (ready) {
    clearBaiduAvatarReadyTimer()
  }
})

function baiduActiveSessionKey(): string {
  return `${BAIDU_ACTIVE_SESSION_PREFIX}${characterId.value}`
}

function clearBaiduAvatarReadyTimer() {
  if (!baiduAvatarReadyTimer) return
  window.clearTimeout(baiduAvatarReadyTimer)
  baiduAvatarReadyTimer = null
}

function markBaiduAvatarError(message: string) {
  baiduAvatarError.value = message
  pendingBaiduAudioEvents.splice(0)
  clearBaiduAvatarReadyTimer()
  void flushBaiduVoiceFallbackAudio()
}

function clearBaiduVoiceFallbackBuffer() {
  baiduVoiceFallbackEvents.splice(0)
}

function bufferBaiduVoiceFallbackEvent(event: BaiduXilingAudioEvent) {
  if (event.first) {
    clearBaiduVoiceFallbackBuffer()
  }
  if (event.audio) {
    baiduVoiceFallbackEvents.push(event)
  }
}

function resetBaiduVoiceFallbackPlayback(closeContext = false) {
  for (const source of baiduVoiceSources) {
    try {
      source.stop()
    } catch {}
  }
  baiduVoiceSources = []
  baiduVoiceNextPlayAt = 0
  if (closeContext && baiduVoiceAudioContext) {
    void baiduVoiceAudioContext.close()
    baiduVoiceAudioContext = null
    baiduVoiceGainNode = null
  }
}

function ensureBaiduVoiceAudioContext(): AudioContext | null {
  if (baiduVoiceAudioContext && baiduVoiceAudioContext.state !== 'closed') {
    applyBaiduVoiceOutputMuted()
    return baiduVoiceAudioContext
  }
  const AudioContextCtor = window.AudioContext || (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext
  if (!AudioContextCtor) return null
  const ctx = new AudioContextCtor()
  baiduVoiceAudioContext = ctx
  baiduVoiceGainNode = ctx.createGain()
  baiduVoiceGainNode.connect(ctx.destination)
  applyBaiduVoiceOutputMuted()
  return ctx
}

function applyBaiduVoiceOutputMuted() {
  if (!baiduVoiceGainNode) return
  baiduVoiceGainNode.gain.value = baiduOutputMuted.value ? 0 : 1
}

function decodeBase64PCM16(base64: string): Int16Array {
  const binary = window.atob(base64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i)
  }
  const length = Math.floor(bytes.byteLength / 2)
  const pcm = new Int16Array(length)
  const view = new DataView(bytes.buffer)
  for (let i = 0; i < length; i++) {
    pcm[i] = view.getInt16(i * 2, true)
  }
  return pcm
}

async function playBaiduVoiceFallbackEvent(event: BaiduXilingAudioEvent) {
  if (event.first) {
    resetBaiduVoiceFallbackPlayback(false)
  }
  if (!event.audio) return
  const ctx = ensureBaiduVoiceAudioContext()
  const output = baiduVoiceGainNode
  if (!ctx || !output) return
  if (ctx.state === 'suspended') {
    await ctx.resume().catch(() => {})
  }
  const pcm = decodeBase64PCM16(event.audio)
  if (pcm.length === 0) return
  const sampleRate = baiduXilingConfig.value?.audio_sample_rate || BAIDU_FALLBACK_AUDIO_SAMPLE_RATE
  const buffer = ctx.createBuffer(1, pcm.length, sampleRate)
  const channel = buffer.getChannelData(0)
  for (let i = 0; i < pcm.length; i++) {
    channel[i] = Math.max(-1, Math.min(1, pcm[i] / 32768))
  }
  const source = ctx.createBufferSource()
  source.buffer = buffer
  source.connect(output)
  const startAt = Math.max(ctx.currentTime + 0.02, baiduVoiceNextPlayAt || 0)
  source.start(startAt)
  baiduVoiceNextPlayAt = startAt + buffer.duration
  baiduVoiceSources.push(source)
  source.onended = () => {
    baiduVoiceSources = baiduVoiceSources.filter(item => item !== source)
  }
}

async function flushBaiduVoiceFallbackAudio() {
  if (!baiduVoiceFallbackEvents.length) return
  const events = baiduVoiceFallbackEvents.splice(0)
  for (const event of events) {
    await playBaiduVoiceFallbackEvent(event)
  }
}

function armBaiduAvatarReadyTimer() {
  clearBaiduAvatarReadyTimer()
  if (!isBaiduXilingSession.value) return
  baiduAvatarReadyTimer = window.setTimeout(() => {
    if (!baiduAvatarReady.value) {
      markBaiduAvatarError(t('session.baiduConnectionTimeout'))
    }
  }, BAIDU_AVATAR_READY_TIMEOUT_MS)
}

function readBaiduErrorDetail(body: unknown): string {
  if (!body) return ''
  if (typeof body === 'string') return body.trim()
  if (typeof body !== 'object') return ''
  const record = body as Record<string, unknown>
  for (const key of ['message', 'msg', 'error', 'reason']) {
    const value = record[key]
    if (typeof value === 'string' && value.trim()) return value.trim()
  }
  return ''
}

function withBaiduErrorDetail(message: string, detail: string): string {
  if (!detail) return message
  return t('session.baiduErrorWithDetail', { message, detail })
}

function handleBaiduStateChanged(state: BaiduXilingConnectionState) {
  baiduXilingConnectionState.value = state
  if (state.rtcReady && state.wsReady) {
    baiduAvatarError.value = ''
    clearBaiduVoiceFallbackBuffer()
    resetBaiduVoiceFallbackPlayback(true)
    clearBaiduAvatarReadyTimer()
    return
  }
  if (state.wsReadyState === WebSocket.CLOSED) {
    markBaiduAvatarError(t('session.baiduConnectionClosed'))
  }
}

function handleBaiduRenderError(payload: { code?: number; body?: unknown }) {
  const detail = readBaiduErrorDetail(payload.body) || (payload.code ? `code=${payload.code}` : '')
  markBaiduAvatarError(withBaiduErrorDetail(t('session.baiduRenderError'), detail))
}

function handleXunfeiStateChanged(state: { streamReady: boolean; autoplayBlocked: boolean }) {
  xunfeiConnectionState.value = state
  if (state.streamReady) {
    xunfeiAvatarError.value = ''
  }
}

function handleXunfeiRenderError(payload: { message?: string }) {
  xunfeiAvatarError.value = payload.message || t('session.xunfeiRenderError')
}

function handleViduStateChanged(state: typeof viduConnectionState.value) {
  viduConnectionState.value = state
}

function handleViduRTCReady() {
  viduRTCJoined.value = true
  notifyViduRTCReady()
}

function handleViduRTCFailed(payload: { message: string }) {
  viduAvatarError.value = payload.message || t('session.viduConnectionError')
  sendWSMessage({ type: 'vidu_rtc_failed' })
  void requestViduSessionTeardown(true)
}

function handleViduRenderError(payload: { message: string }) {
  viduAvatarError.value = payload.message || t('session.viduConnectionError')
}

function markBaiduSessionActive() {
  if (!isBaiduXilingSession.value || !characterId.value || !sessionId.value) return
  try {
    localStorage.setItem(baiduActiveSessionKey(), sessionId.value)
  } catch {}
}

function clearBaiduSessionActive() {
  if (!isBaiduXilingSession.value || !characterId.value || !sessionId.value) return
  try {
    const key = baiduActiveSessionKey()
    if (localStorage.getItem(key) === sessionId.value) {
      localStorage.removeItem(key)
    }
  } catch {}
}

function handleBaiduActiveSessionChange(event: StorageEvent) {
  if (!isBaiduXilingSession.value || !characterId.value || !sessionId.value) return
  if (event.key !== baiduActiveSessionKey()) return
  if (!event.newValue || event.newValue === sessionId.value) return
  void handleDisconnect()
}

function clampValue(value: number, min: number, max: number): number {
  if (max < min) return min
  return Math.min(Math.max(value, min), max)
}

function getChatSidebarMaxWidth(): number {
  const viewportWidth = window.innerWidth
  if (window.matchMedia('(max-width: 900px)').matches) {
    return Math.min(viewportWidth * CHAT_SIDEBAR_MOBILE_RATIO, CHAT_SIDEBAR_MOBILE_MAX_WIDTH)
  }
  return clampValue(
    viewportWidth * CHAT_SIDEBAR_DESKTOP_RATIO,
    CHAT_SIDEBAR_DESKTOP_BASE_WIDTH,
    CHAT_SIDEBAR_DESKTOP_MAX_WIDTH,
  )
}

function getChatSidebarMinWidth(maxWidth: number): number {
  return Math.min(CHAT_SIDEBAR_MIN_WIDTH, maxWidth)
}

function stopChatSidebarResize(event?: PointerEvent) {
  if (event && chatSidebarResizeState?.pointerId !== event.pointerId) return

  if (chatSidebarResizeState) {
    try {
      chatSidebarResizeState.handleEl.releasePointerCapture(chatSidebarResizeState.pointerId)
    } catch {}
  }

  chatSidebarResizeState = null
  isChatResizing.value = false
  window.removeEventListener('pointermove', handleChatSidebarPointerMove)
  window.removeEventListener('pointerup', stopChatSidebarResize)
  window.removeEventListener('pointercancel', stopChatSidebarResize)
}

function handleChatSidebarPointerMove(event: PointerEvent) {
  const resize = chatSidebarResizeState
  if (!resize || event.pointerId !== resize.pointerId) return

  const rawWidth = resize.rightEdge - event.clientX
  if (rawWidth <= resize.minWidth) {
    if (resize.minReachedClientX === null) {
      resize.minReachedClientX = event.clientX
    }

    chatSidebarWidth.value = resize.minWidth
    if (event.clientX - resize.minReachedClientX >= CHAT_SIDEBAR_COLLAPSE_RESISTANCE) {
      isChatCollapsed.value = true
      event.preventDefault()
      stopChatSidebarResize(event)
      return
    }

    event.preventDefault()
    return
  }

  resize.minReachedClientX = null
  chatSidebarWidth.value = clampValue(rawWidth, resize.minWidth, resize.maxWidth)
  event.preventDefault()
}

function handleChatSidebarPointerDown(event: PointerEvent) {
  if (event.button !== 0 || isChatCollapsed.value) return

  const sidebar = chatSidebarRef.value
  const handleEl = event.currentTarget as HTMLElement | null
  if (!sidebar || !handleEl) return

  const rect = sidebar.getBoundingClientRect()
  const maxWidth = getChatSidebarMaxWidth()
  const minWidth = getChatSidebarMinWidth(maxWidth)
  const currentWidth = clampValue(rect.width || maxWidth, minWidth, maxWidth)

  chatSidebarWidth.value = currentWidth
  chatSidebarResizeState = {
    pointerId: event.pointerId,
    rightEdge: rect.right,
    minWidth,
    maxWidth,
    minReachedClientX: currentWidth <= minWidth + 1 ? event.clientX : null,
    handleEl,
  }
  isChatResizing.value = true

  handleEl.setPointerCapture(event.pointerId)
  window.addEventListener('pointermove', handleChatSidebarPointerMove)
  window.addEventListener('pointerup', stopChatSidebarResize)
  window.addEventListener('pointercancel', stopChatSidebarResize)
  event.preventDefault()
}

function keepChatSidebarWidthInBounds() {
  if (chatSidebarWidth.value === null) return
  const maxWidth = getChatSidebarMaxWidth()
  const minWidth = getChatSidebarMinWidth(maxWidth)
  chatSidebarWidth.value = clampValue(chatSidebarWidth.value, minWidth, maxWidth)
}

function clampVisualPreviewPosition(x: number, y: number, previewEl: HTMLElement): { x: number; y: number } {
  const shell = sessionVideoShellRef.value
  if (!shell) return { x, y }

  const shellRect = shell.getBoundingClientRect()
  const previewRect = previewEl.getBoundingClientRect()
  const maxX = shellRect.width - previewRect.width - VISUAL_PREVIEW_MARGIN
  const maxY = shellRect.height - previewRect.height - VISUAL_PREVIEW_MARGIN

  return {
    x: clampValue(x, VISUAL_PREVIEW_MARGIN, maxX),
    y: clampValue(y, VISUAL_PREVIEW_MARGIN, maxY),
  }
}

function updateVisualPreviewPosition(clientX: number, clientY: number) {
  const drag = visualPreviewDragState
  const shell = sessionVideoShellRef.value
  if (!drag || !shell) return

  const shellRect = shell.getBoundingClientRect()
  visualPreviewPosition.value = clampVisualPreviewPosition(
    clientX - shellRect.left - drag.offsetX,
    clientY - shellRect.top - drag.offsetY,
    drag.previewEl,
  )
}

function handleVisualPreviewPointerMove(event: PointerEvent) {
  if (!visualPreviewDragState || event.pointerId !== visualPreviewDragState.pointerId) return
  updateVisualPreviewPosition(event.clientX, event.clientY)
  event.preventDefault()
}

function stopVisualPreviewDragging(event?: PointerEvent) {
  if (event && visualPreviewDragState?.pointerId !== event.pointerId) return

  if (visualPreviewDragState) {
    try {
      visualPreviewDragState.previewEl.releasePointerCapture(visualPreviewDragState.pointerId)
    } catch {}
  }

  visualPreviewDragState = null
  isVisualPreviewDragging.value = false
  window.removeEventListener('pointermove', handleVisualPreviewPointerMove)
  window.removeEventListener('pointerup', stopVisualPreviewDragging)
  window.removeEventListener('pointercancel', stopVisualPreviewDragging)
}

function handleVisualPreviewPointerDown(event: PointerEvent) {
  if (event.button !== 0) return

  const shell = sessionVideoShellRef.value
  const previewEl = event.currentTarget as HTMLElement | null
  if (!shell || !previewEl) return

  const shellRect = shell.getBoundingClientRect()
  const previewRect = previewEl.getBoundingClientRect()
  visualPreviewDragState = {
    pointerId: event.pointerId,
    offsetX: event.clientX - previewRect.left,
    offsetY: event.clientY - previewRect.top,
    previewEl,
  }
  visualPreviewPosition.value = clampVisualPreviewPosition(
    previewRect.left - shellRect.left,
    previewRect.top - shellRect.top,
    previewEl,
  )
  isVisualPreviewDragging.value = true

  previewEl.setPointerCapture(event.pointerId)
  window.addEventListener('pointermove', handleVisualPreviewPointerMove)
  window.addEventListener('pointerup', stopVisualPreviewDragging)
  window.addEventListener('pointercancel', stopVisualPreviewDragging)
  event.preventDefault()
}

function keepVisualPreviewInBounds() {
  const pos = visualPreviewPosition.value
  const previewEl = visualPreviewShellRef.value
  if (!pos || !previewEl) return

  visualPreviewPosition.value = clampVisualPreviewPosition(pos.x, pos.y, previewEl)
}

watchEffect(() => {
  const el = visualPreviewRef.value
  if (!el) return
  const stream = visualInput.previewStream.value
  if (el.srcObject !== stream) {
    el.srcObject = stream
  }
  if (stream) {
    void el.play().catch(() => {})
  }
})

// Initialize idle video URLs from route query (if already cached at session creation)
const launchIdleUrls = launchState.value?.idle_video_urls
const launchIdleUrl = launchState.value?.idle_video_url || ''
const idleImageUrl = ref(launchState.value?.idle_image_url || '')
const voiceAgentVisualImage = computed(() => idleImageUrl.value.trim())
if (idleStrategy.value === 'cached_video' && launchIdleUrls && launchIdleUrls.length > 0) {
  idleVideoUrls.value = launchIdleUrls
} else if (idleStrategy.value === 'cached_video' && launchIdleUrl) {
  idleVideoUrls.value = [launchIdleUrl]
}

// Standby MP4 failed to decode (404/HTML, corrupt file, etc.) — do not keep black layer over WebRTC.
const standbyDecodeFailed = ref(false)
watch(idleVideoUrls, () => {
  standbyDecodeFailed.value = false
}, { deep: true })

function onStandbyMp4Failed() {
  standbyDecodeFailed.value = true
}

// Switch to webrtc only when fresh frames are actually arriving.
// The backend now delays avatar_status=speaking until the first video frame is
// about to be published, so we no longer need the "frozen last frame" fallback
// that previously showed a stale frame for seconds.
let _prevDisplayMode = ''
const displayMode = computed<'webrtc' | 'standby' | 'placeholder'>(() => {
  const lastFrameAt = debugState.value.lastVideoFrameAtMs
  const hasFreshRealtimeFrame = !!lastFrameAt && clockMs.value - lastFrameAt < 3000
  const hasRealtimeSize = !!videoElement.value?.videoWidth || !!debugState.value.network?.frameWidth
  const hasStandbyVisual = !standbyDecodeFailed.value && (!!idleVideoUrl.value || !!idleImageUrl.value)

  if (idleStrategy.value === 'silent_inference') {
    const result = connectionState.value === 'connected' && (hasFreshRealtimeFrame || hasRealtimeSize)
      ? 'webrtc'
      : 'placeholder'
    if (result !== _prevDisplayMode) {
      const reason = result === 'webrtc' ? 'silent inference realtime stream' : 'silent inference waiting for media'
      console.log(`[switch] ${_prevDisplayMode || 'init'} → ${result} | reason: ${reason}`)
      _prevDisplayMode = result
    }
    return result
  }

  let result: 'webrtc' | 'standby' | 'placeholder'
  let reason = ''
  if (hasStandbyVisual && avatarStatus.value !== 'speaking') {
    result = 'standby'
    reason = `avatarStatus=${avatarStatus.value}`
  } else if (hasFreshRealtimeFrame) {
    result = 'webrtc'
    reason = `fresh frame (${lastFrameAt ? (Date.now() - lastFrameAt) + 'ms ago' : ''})`
  } else if (hasStandbyVisual) {
    result = 'standby'
    reason = `fallback (speaking but no fresh frame yet)`
  } else if (standbyDecodeFailed.value && connectionState.value === 'connected') {
    result = 'webrtc'
    reason = 'standby MP4 decode failed, WebRTC layer'
  } else {
    result = 'placeholder'
    reason = 'no idle video'
  }
  if (result !== _prevDisplayMode) {
    console.log(`[switch] ${_prevDisplayMode || 'init'} → ${result} | reason: ${reason}`)
    _prevDisplayMode = result
  }
  return result
})
const isLocalVoiceAgentVisualActive = computed(() =>
  !isExternalAvatarSession.value
  && (launchState.value?.avatar_enabled === false || displayMode.value === 'placeholder')
)
const shouldShowVoiceAgentVisual = computed(() =>
  !!voiceAgentVisualImage.value && (isLocalVoiceAgentVisualActive.value || externalAvatarFallbackActive.value)
)
const shouldShowAvatarFallbackBadge = computed(() => externalAvatarFallbackActive.value && shouldShowVoiceAgentVisual.value)

watch(shouldShowAvatarFallbackBadge, (visible) => {
  if (!visible) {
    showAvatarFallbackDetails.value = false
  }
})

watchEffect(() => {
  setAVSyncLoggingEnabled(avatarStatus.value === 'speaking' && displayMode.value === 'webrtc')
})

watch(displayMode, (mode, previousMode) => {
  if (!isDirectMode || previousMode !== 'webrtc' || mode !== 'standby') return
  dp.requestMediaResetIfNeeded('standby')
})

function handleAvatarFallbackGlobalPointerDown(event: PointerEvent) {
  if (!showAvatarFallbackDetails.value) return
  const target = event.target
  if (!(target instanceof Node)) {
    showAvatarFallbackDetails.value = false
    return
  }
  if (avatarFallbackBadgeRef.value?.contains(target) || avatarFallbackPopoverRef.value?.contains(target)) {
    return
  }
  showAvatarFallbackDetails.value = false
}

// Auto-connect on mount using session params from query
onMounted(async () => {
  if (queryLaunchState && Object.keys(route.query).length > 0) {
    void router.replace({ path: route.path })
  }

  if (isBaiduXilingSession.value) {
    window.addEventListener('storage', handleBaiduActiveSessionChange)
    markBaiduSessionActive()
    armBaiduAvatarReadyTimer()
  }

  window.addEventListener('resize', keepVisualPreviewInBounds)
  window.addEventListener('resize', keepChatSidebarWidthInBounds)
  window.addEventListener('pointerdown', handleAvatarFallbackGlobalPointerDown)
  if (isViduSession.value) {
    window.addEventListener('pagehide', handleViduPageHide)
  }

  const startedAt = Date.now()

  await chatConnect()
  notifyViduRTCReady()

  // Load conversation history for this character
  if (characterId.value) {
    loadHistory(characterId.value)
  }

  if (!shouldUseMediaPeer.value) {
    // Sessions without media peer use chat WS only.
  } else if (isDirectMode) {
    // Direct P2P WebRTC: register signaling handler then connect
    registerSignalingHandler((data: any) => dp.handleSignaling(data))
    await dp.connect(
      (msg: any) => sendSignaling(msg),
      {
        dedicatedAudioOutput: launchState.value?.avatar_enabled === false,
        avCalibration: avCalibrationEnabled,
      },
    )
  } else {
    // LiveKit mode
    const url = launchState.value?.livekit_url || ''
    const token = launchState.value?.livekit_token || ''
    if (url && token) {
      await lk.connect(url, token)
    }
  }

  timer = setInterval(() => {
    const now = Date.now()
    clockMs.value = now
    elapsed.value = Math.floor((now - startedAt) / 1000)
  }, 500)
})

onUnmounted(() => {
  if (timer) clearInterval(timer)
  stopVisualPreviewDragging()
  stopChatSidebarResize()
  clearBaiduSessionActive()
  clearBaiduAvatarReadyTimer()
  resetBaiduVoiceFallbackPlayback(true)
  window.removeEventListener('storage', handleBaiduActiveSessionChange)
  window.removeEventListener('resize', keepVisualPreviewInBounds)
  window.removeEventListener('resize', keepChatSidebarWidthInBounds)
  window.removeEventListener('pointerdown', handleAvatarFallbackGlobalPointerDown)
  window.removeEventListener('pagehide', handleViduPageHide)
  if (isViduSession.value) {
    viduPlayerRef.value?.disconnect()
    void requestViduSessionTeardown(true)
  }
  visualInput.stop(undefined, true)
})

function requestViduSessionTeardown(keepalive: boolean): Promise<void> {
  if (!isViduSession.value || !sessionId.value || viduSessionTeardownRequested) return Promise.resolve()
  viduSessionTeardownRequested = true
  clearSessionLaunchState(sessionId.value)
  return deleteSession(sessionId.value, keepalive).catch(() => {})
}

function handleViduPageHide() {
  viduPlayerRef.value?.disconnect()
  void requestViduSessionTeardown(true)
}

async function handleDisconnect() {
  visualInput.stop(undefined, true)
  if (shouldUseMediaPeer.value) {
    webrtcDisconnect()
  }
  chatDisconnect()
  if (isViduSession.value) {
    viduPlayerRef.value?.disconnect()
  }
  const returnPath = launchState.value?.return_path || '/characters'
  if (sessionId.value) {
    if (isViduSession.value) {
      await requestViduSessionTeardown(false)
    } else {
      await deleteSession(sessionId.value).catch(() => {})
    }
    clearSessionLaunchState(sessionId.value)
  }
  router.push(returnPath)
}

function handleLoadMore() {
  if (characterId.value) {
    loadHistory(characterId.value)
  }
}

function toggleChatPanel() {
  isChatCollapsed.value = !isChatCollapsed.value
}

async function handleOutputButtonClick() {
  if (isViduSession.value) {
    baiduOutputMuted.value = !baiduOutputMuted.value
    viduPlayerRef.value?.muteAudio(baiduOutputMuted.value)
    return
  }
  if (isBaiduXilingSession.value) {
    baiduOutputMuted.value = !baiduOutputMuted.value
    applyBaiduVoiceOutputMuted()
    if (!baiduOutputMuted.value && baiduVoiceAudioContext?.state === 'suspended') {
      await baiduVoiceAudioContext.resume().catch(() => {})
    }
    baiduPlayerRef.value?.muteAudio(baiduOutputMuted.value)
    return
  }
  if (isXunfeiSession.value) {
    if (!xunfeiConnectionState.value.streamReady || xunfeiConnectionState.value.autoplayBlocked) {
      await xunfeiPlayerRef.value?.playVideo(true)
      return
    }
    baiduOutputMuted.value = !baiduOutputMuted.value
    xunfeiPlayerRef.value?.muteAudio(baiduOutputMuted.value)
    return
  }
  await toggleOutputMute()
}

function handleMicrophoneClick() {
  if (isViduSession.value) {
    viduPlayerRef.value?.toggleMicrophone()
    return
  }
  toggleMute()
}

function handleViduCameraClick() {
  void viduPlayerRef.value?.toggleCamera()
}

const microphoneMutedVisual = computed(() =>
  isViduSession.value ? !viduConnectionState.value.microphoneEnabled : isMuted.value
)

function formatTime(s: number): string {
  const m = Math.floor(s / 60)
  const sec = s % 60
  return `${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}`
}

function micDockBarHeight(level: number): string {
  if (isMuted.value) return '1px'
  return `${2 + Math.min(1, Math.max(0, level || 0)) * 14}px`
}
</script>

<template>
  <div class="session-page" :class="{ 'chat-collapsed': isChatCollapsed, 'chat-resizing': isChatResizing }">
    <!-- Left: Video area (60%) -->
    <div ref="sessionVideoShellRef" class="session-video-shell">
      <BaiduXilingPlayer
        v-if="isBaiduXilingSession && baiduXilingConfig"
        ref="baiduPlayerRef"
        :config="baiduXilingConfig"
        class="w-full flex-1 min-h-0"
        @state-changed="handleBaiduStateChanged"
        @render-error="handleBaiduRenderError"
      />
      <XunfeiAvatarPlayer
        v-else-if="isXunfeiSession && xunfeiConfig"
        ref="xunfeiPlayerRef"
        :config="xunfeiConfig"
        class="w-full flex-1 min-h-0"
        @state-changed="handleXunfeiStateChanged"
        @render-error="handleXunfeiRenderError"
      />
      <ViduS1Player
        v-else-if="isViduSession && viduConfig"
        ref="viduPlayerRef"
        :config="viduConfig"
        class="w-full flex-1 min-h-0"
        @state-changed="handleViduStateChanged"
        @rtc-ready="handleViduRTCReady"
        @rtc-failed="handleViduRTCFailed"
        @render-error="handleViduRenderError"
      />
      <VideoPlayer
        v-else
        ref="videoPlayerRef"
        :display-mode="displayMode"
        :standby-src="idleVideoUrl"
        :standby-sources="idleVideoUrls"
        :standby-image-src="idleImageUrl"
        class="w-full flex-1 min-h-0"
        @standby-failed="onStandbyMp4Failed"
      />

      <div
        v-if="shouldShowVoiceAgentVisual"
        class="voice-agent-visual"
        aria-hidden="true"
      >
        <img class="voice-agent-visual-bg" :src="voiceAgentVisualImage" alt="" />
        <div class="voice-agent-portrait">
          <img :src="voiceAgentVisualImage" alt="" />
        </div>
      </div>

      <!-- Back button (top-left, glass) -->
      <button @click="handleDisconnect"
              class="absolute top-5 left-5 px-3 py-2 bg-black/70 backdrop-blur-sm rounded-cv-md text-sm text-cv-text hover:bg-black/90 transition-colors cursor-pointer z-10">
        {{ t('session.back') }}
      </button>

      <!-- FPS indicator (top-right, glass) — click to toggle diagnostics -->
      <button v-if="!isExternalAvatarSession && connectionState === 'connected'"
              @click="showDiag = !showDiag"
              class="absolute top-5 right-5 px-2.5 py-1.5 bg-black/70 backdrop-blur-sm rounded-cv-md text-xs font-mono text-cv-text z-10 cursor-pointer hover:bg-black/90 transition-colors">
        {{ debugState.fps }} FPS
        <span v-if="debugState.jitter.stutterCount > 0" class="ml-1 text-yellow-400">
          {{ debugState.jitter.stutterCount }} stutters
        </span>
      </button>

      <button
        v-if="shouldShowAvatarFallbackBadge"
        ref="avatarFallbackBadgeRef"
        type="button"
        class="avatar-fallback-badge"
        :title="t('session.avatarFallbackDetail')"
        :aria-label="t('session.avatarFallbackTitle')"
        :aria-expanded="showAvatarFallbackDetails"
        @click="showAvatarFallbackDetails = !showAvatarFallbackDetails"
      >
        <span>Voice Agent</span>
      </button>

      <button
        v-if="isChatCollapsed"
        type="button"
        class="chat-expand-button"
        :title="t('session.expandChat')"
        :aria-label="t('session.expandChat')"
        @click="toggleChatPanel"
      >
        <svg class="w-4 h-4" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8">
          <path d="M10 3 5 8l5 5" stroke-linecap="round" stroke-linejoin="round" />
        </svg>
      </button>

      <!-- Diagnostics panel -->
      <div v-if="!isExternalAvatarSession && showDiag && connectionState === 'connected'"
           class="absolute top-14 right-5 w-80 max-h-[70vh] overflow-y-auto bg-black/85 backdrop-blur-md rounded-lg border border-white/10 p-3 text-[11px] font-mono text-cv-text z-20 space-y-2">
        <div class="text-xs font-semibold text-cv-accent mb-1">{{ t('session.frameJitter') }}</div>
        <div class="grid grid-cols-2 gap-x-3 gap-y-0.5">
          <span class="text-cv-text-muted">{{ t('session.meanInterval') }}</span>
          <span>{{ debugState.jitter.meanIntervalMs }} ms</span>
          <span class="text-cv-text-muted">{{ t('session.stddev') }}</span>
          <span :class="debugState.jitter.stddevMs > 15 ? 'text-yellow-400' : ''">
            {{ debugState.jitter.stddevMs }} ms
          </span>
          <span class="text-cv-text-muted">{{ t('session.p95') }}</span>
          <span :class="debugState.jitter.p95IntervalMs > 80 ? 'text-red-400' : ''">
            {{ debugState.jitter.p95IntervalMs }} ms
          </span>
          <span class="text-cv-text-muted">{{ t('session.max') }}</span>
          <span :class="debugState.jitter.maxIntervalMs > 100 ? 'text-red-400' : ''">
            {{ debugState.jitter.maxIntervalMs }} ms
          </span>
          <span class="text-cv-text-muted">{{ t('session.stutters') }}</span>
          <span :class="debugState.jitter.stutterCount > 0 ? 'text-yellow-400' : ''">
            {{ debugState.jitter.stutterCount }} / {{ debugState.jitter.windowSize }} frames
          </span>
        </div>

        <div class="text-xs font-semibold text-cv-accent mt-2 mb-1">{{ t('session.playback') }}</div>
        <div class="grid grid-cols-2 gap-x-3 gap-y-0.5">
          <span class="text-cv-text-muted">FPS</span>
          <span>{{ debugState.fps }}</span>
          <span class="text-cv-text-muted">{{ t('session.decoded') }}</span>
          <span>{{ debugState.decodedFrames }}</span>
          <span class="text-cv-text-muted">{{ t('session.dropped') }}</span>
          <span :class="debugState.droppedFrames > 0 ? 'text-red-400' : ''">
            {{ debugState.droppedFrames }}
          </span>
          <span class="text-cv-text-muted">{{ t('session.readyState') }}</span>
          <span>{{ debugState.readyState }}</span>
          <span class="text-cv-text-muted">{{ t('session.displayMode') }}</span>
          <span>{{ displayMode }}</span>
        </div>

        <template v-if="debugState.network">
          <div class="text-xs font-semibold text-cv-accent mt-2 mb-1">{{ t('session.network') }}</div>
          <div class="grid grid-cols-2 gap-x-3 gap-y-0.5">
            <span class="text-cv-text-muted">RTT</span>
            <span>{{ debugState.network.roundTripTimeMs ?? '—' }} ms</span>
            <span class="text-cv-text-muted">{{ t('session.jitterRTP') }}</span>
            <span>{{ debugState.network.jitterMs ?? '—' }} ms</span>
            <span class="text-cv-text-muted">{{ t('session.packetLoss') }}</span>
            <span :class="debugState.network.lossRate > 0.01 ? 'text-red-400' : ''">
              {{ debugState.network.packetsLost }} ({{ (debugState.network.lossRate * 100).toFixed(2) }}%)
            </span>
            <span class="text-cv-text-muted">{{ t('session.nackPliFir') }}</span>
            <span>{{ debugState.network.nackCount }} / {{ debugState.network.pliCount }} / {{ debugState.network.firCount }}</span>
            <span class="text-cv-text-muted">{{ t('session.jitterBuffer') }}</span>
            <span>{{ debugState.network.jitterBufferDelayMs ?? '—' }} ms</span>
            <span class="text-cv-text-muted">{{ t('session.resolution') }}</span>
            <span>{{ debugState.network.frameWidth }}x{{ debugState.network.frameHeight }}</span>
            <span class="text-cv-text-muted">{{ t('session.codec') }}</span>
            <span>{{ debugState.network.codec || '—' }}</span>
          </div>
        </template>

        <div class="text-xs font-semibold text-cv-accent mt-2 mb-1">{{ t('session.notes') }}</div>
        <div class="text-[10px] text-cv-text-muted space-y-0.5 max-h-24 overflow-y-auto">
          <div v-for="(note, i) in debugState.notes" :key="i">{{ note }}</div>
          <div v-if="!debugState.notes.length" class="italic">{{ t('session.noEvents') }}</div>
        </div>
      </div>

      <div
        v-if="baiduAvatarNotice && !shouldShowVoiceAgentVisual"
        class="baidu-avatar-status"
        :class="{ error: !!baiduAvatarError }"
      >
        {{ baiduAvatarNotice }}
      </div>

      <div v-if="isViduSession && viduAvatarError" class="baidu-avatar-status error">
        {{ viduAvatarError }}
      </div>

      <div
        v-if="hasVisualInputCapability && visualInput.error.value"
        class="absolute bottom-24 left-1/2 -translate-x-1/2 z-10 max-w-[min(90vw,28rem)] px-3 py-2 bg-black/80 border border-red-400/30 text-red-100 text-xs rounded-cv-md"
      >
        {{ visualInput.error.value }}
      </div>

      <div
        v-if="visualInput.previewStream.value"
        class="visual-preview"
        :class="{ dragging: isVisualPreviewDragging }"
        :style="visualPreviewStyle"
        ref="visualPreviewShellRef"
        @pointerdown="handleVisualPreviewPointerDown"
      >
        <video
          ref="visualPreviewRef"
          class="visual-preview-video"
          :class="{ 'visual-preview-mirror': visualInput.isCameraActive.value }"
          autoplay
          muted
          playsinline
        />
        <button
          type="button"
          class="visual-preview-close"
          :title="t('session.closeVisualInput')"
          :aria-label="t('session.closeVisualInput')"
          @pointerdown.stop
          @click.stop="visualInput.stop()"
        >
          <svg class="w-3.5 h-3.5" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M4 4l8 8M12 4l-8 8" stroke-linecap="round" />
          </svg>
        </button>
      </div>

      <div
        v-if="shouldShowAvatarFallbackBadge && showAvatarFallbackDetails"
        ref="avatarFallbackPopoverRef"
        class="avatar-fallback-popover"
        role="status"
        @click="showAvatarFallbackDetails = false"
      >
        <div class="avatar-fallback-popover-title">{{ t('session.avatarFallbackTitle') }}</div>
        <div class="avatar-fallback-popover-detail">{{ t('session.avatarFallbackDetail') }}</div>
      </div>

      <!-- Control bar (bottom center, floating) -->
      <div class="absolute bottom-6 left-1/2 -translate-x-1/2 flex items-center gap-4 px-6 py-2.5 bg-black/70 backdrop-blur-xl rounded-2xl border border-white/10 shadow-[0_4px_16px_rgba(0,0,0,0.3)] z-10 overflow-hidden">
        <div v-if="hasAudioInputCapability && !isViduSession" class="dock-waveform-background" aria-hidden="true">
          <span
            v-for="(level, index) in micBarLevels"
            :key="index"
            class="dock-waveform-bar"
            :style="{ height: micDockBarHeight(level) }"
          />
        </div>

        <!-- User video input (standard and qwen_omni voice sessions) -->
        <button
          v-if="hasVisualInputCapability"
          type="button"
          :disabled="!canUseVisualInput || visualInput.isStarting.value"
          :title="visualInput.isCameraActive.value ? t('session.cameraOff') : t('session.cameraOn')"
          :aria-label="visualInput.isCameraActive.value ? t('session.cameraOff') : t('session.cameraOn')"
          class="relative z-10 w-12 h-12 rounded-full flex items-center justify-center transition-colors cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
          :class="visualInput.isCameraActive.value ? 'bg-cv-accent text-white' : 'bg-white/10 text-cv-text hover:bg-white/16'"
          @click="visualInput.toggleCamera()"
        >
          <svg class="w-5 h-5" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6">
            <path d="M3.5 6.5A2.5 2.5 0 0 1 6 4h5a2.5 2.5 0 0 1 2.5 2.5v7A2.5 2.5 0 0 1 11 16H6a2.5 2.5 0 0 1-2.5-2.5v-7Z" />
            <path d="m13.5 8 3-2v8l-3-2" stroke-linecap="round" stroke-linejoin="round" />
            <path v-if="!visualInput.isCameraActive.value" d="M3 3l14 14" stroke="currentColor" stroke-width="2" stroke-linecap="round" />
          </svg>
        </button>

        <button
          v-if="isViduSession"
          type="button"
          :title="viduConnectionState.cameraEnabled ? t('session.cameraOff') : t('session.cameraOn')"
          :aria-label="viduConnectionState.cameraEnabled ? t('session.cameraOff') : t('session.cameraOn')"
          class="relative z-10 w-12 h-12 rounded-full flex items-center justify-center transition-colors cursor-pointer"
          :class="viduConnectionState.cameraEnabled ? 'bg-cv-accent text-white' : 'bg-white/10 text-cv-text hover:bg-white/16'"
          @click="handleViduCameraClick"
        >
          <svg class="w-5 h-5" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6">
            <path d="M3.5 6.5A2.5 2.5 0 0 1 6 4h5a2.5 2.5 0 0 1 2.5 2.5v7A2.5 2.5 0 0 1 11 16H6a2.5 2.5 0 0 1-2.5-2.5v-7Z" />
            <path d="m13.5 8 3-2v8l-3-2" stroke-linecap="round" stroke-linejoin="round" />
            <path v-if="!viduConnectionState.cameraEnabled" d="M3 3l14 14" stroke="currentColor" stroke-width="2" stroke-linecap="round" />
          </svg>
        </button>

        <!-- Digital human output mute; also unlocks browser audio when needed. -->
        <button
          type="button"
          :title="outputButtonTitle"
          :aria-label="outputButtonTitle"
          class="relative z-10 w-12 h-12 rounded-full flex items-center justify-center transition-colors cursor-pointer"
          :class="outputMutedVisual ? 'bg-cv-danger text-white' : 'bg-white/10 text-cv-text hover:bg-white/16'"
          @click="handleOutputButtonClick"
        >
          <svg class="w-5 h-5" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7">
            <path d="M3 8.2v3.6h3l4 3.2V5L6 8.2H3Z" stroke-linejoin="round" />
            <path d="M13 7.2a4 4 0 0 1 0 5.6M15.5 5a7.5 7.5 0 0 1 0 10" stroke-linecap="round" />
            <path v-if="outputMutedVisual" d="M3 3l14 14" stroke="currentColor" stroke-width="2" stroke-linecap="round" />
          </svg>
        </button>

        <!-- Mic button -->
        <button v-if="hasAudioInputCapability"
                @click="handleMicrophoneClick"
                class="relative z-10 w-12 h-12 rounded-full flex items-center justify-center transition-colors cursor-pointer"
                :class="microphoneMutedVisual ? 'bg-cv-danger' : 'bg-cv-accent shadow-[0_2px_8px_rgba(59,130,246,0.3)]'">
          <svg class="w-5 h-5 text-white" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5">
            <rect x="7" y="2" width="6" height="10" rx="3" />
            <path d="M4 10a6 6 0 0012 0M10 16v2M7 18h6" stroke-linecap="round" />
            <path v-if="microphoneMutedVisual" d="M3 3l14 14" stroke="currentColor" stroke-width="2" stroke-linecap="round" />
          </svg>
        </button>

        <!-- Timer -->
        <div class="relative z-10 flex items-center gap-2">
          <span class="w-1.5 h-1.5 rounded-full" :class="mediaConnected ? 'bg-cv-success' : 'bg-cv-danger'" />
          <span class="text-[11px] text-cv-text-muted font-mono">{{ formatTime(elapsed) }}</span>
        </div>

        <!-- Disconnect -->
        <button @click="handleDisconnect"
                class="relative z-10 w-10 h-10 rounded-full bg-cv-danger flex items-center justify-center text-white hover:bg-red-600 transition-colors cursor-pointer">
          <svg class="w-4 h-4" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M4 4l8 8M12 4l-8 8" stroke-linecap="round" />
          </svg>
        </button>
      </div>
    </div>

    <!-- Right: Chat panel (40%) -->
    <div
      ref="chatSidebarRef"
      class="session-chat-sidebar"
      :style="chatSidebarStyle"
      :aria-hidden="isChatCollapsed"
      :inert="isChatCollapsed"
    >
      <div
        class="chat-resize-handle"
        role="separator"
        aria-orientation="vertical"
        :title="t('session.resizeChat')"
        :aria-label="t('session.resizeChat')"
        @pointerdown="handleChatSidebarPointerDown"
      />
      <div class="session-chat-inner">
        <!-- Chat header -->
        <div class="h-[52px] shrink-0 flex items-center justify-between px-5 border-b border-cv-border-subtle">
          <div class="flex items-center gap-3 min-w-0">
            <button
              type="button"
              class="chat-toggle-button"
              :title="t('session.collapseChat')"
              :aria-label="t('session.collapseChat')"
              :aria-expanded="!isChatCollapsed"
              @click="toggleChatPanel"
            >
              <svg class="w-4 h-4" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8">
                <path d="M6 3l5 5-5 5" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
            </button>
            <span class="text-base font-semibold text-cv-text truncate">{{ t('session.chatTitle') }}</span>
          </div>
          <button class="text-[13px] text-cv-text-muted hover:text-cv-text transition-colors cursor-pointer">{{ t('session.clear') }}</button>
        </div>

        <!-- Messages (reuse ChatPanel) -->
        <ChatPanel
          :messages="messages"
          :current-transcript="currentTranscript"
          :current-l-l-m-response="currentLLMResponse"
          :avatar-status="avatarStatus"
          :history-loading="historyLoading"
          :history-has-more="historyHasMore"
          @send-text="sendText"
          @load-more="handleLoadMore"
          class="flex-1"
        />

        <!-- Footer hint -->
        <div class="h-6 flex items-center justify-center shrink-0">
          <span class="text-[11px] text-cv-text-muted">{{ t('session.footerHint') }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.session-page {
  position: relative;
  display: flex;
  width: 100%;
  height: 100vh;
  overflow: hidden;
  background: #000;
}

.session-page.chat-resizing {
  cursor: col-resize;
  user-select: none;
}

.session-video-shell {
  position: relative;
  flex: 1 1 auto;
  min-width: 0;
  min-height: 0;
  display: flex;
  flex-direction: column;
  background: #000;
}

.voice-agent-visual {
  position: absolute;
  inset: 0;
  z-index: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  padding: 64px clamp(16px, 3vw, 48px) 124px;
  background: #05070a;
  pointer-events: none;
}

.voice-agent-visual::before,
.voice-agent-visual::after {
  content: "";
  position: absolute;
  top: 0;
  bottom: 0;
  z-index: 1;
  width: clamp(76px, 18vw, 260px);
  border-color: rgba(255, 255, 255, 0.12);
  background: linear-gradient(90deg, rgba(255, 255, 255, 0.1), rgba(255, 255, 255, 0.025));
  backdrop-filter: blur(22px) saturate(1.18);
  -webkit-backdrop-filter: blur(22px) saturate(1.18);
}

.voice-agent-visual::before {
  left: 0;
  border-right: 1px solid rgba(255, 255, 255, 0.1);
}

.voice-agent-visual::after {
  right: 0;
  border-left: 1px solid rgba(255, 255, 255, 0.1);
  transform: scaleX(-1);
}

.voice-agent-visual-bg {
  position: absolute;
  inset: -44px;
  width: calc(100% + 88px);
  height: calc(100% + 88px);
  object-fit: cover;
  object-position: center;
  filter: blur(34px) saturate(0.92) brightness(0.48);
  transform: scale(1.06);
  opacity: 0.72;
}

.voice-agent-portrait {
  position: relative;
  z-index: 2;
  width: min(44vw, 58vh, 640px);
  max-width: calc(100% - 32px);
  max-height: 100%;
  aspect-ratio: 3 / 4;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  border-radius: 8px;
}

.voice-agent-portrait img {
  width: 100%;
  height: 100%;
  object-fit: contain;
  object-position: center;
}

.session-chat-sidebar {
  position: relative;
  flex: 0 0 var(--chat-sidebar-width, clamp(360px, 40vw, 560px));
  width: var(--chat-sidebar-width, clamp(360px, 40vw, 560px));
  min-width: 0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  background: var(--color-cv-surface);
  border-left: 1px solid var(--color-cv-border-subtle);
  opacity: 1;
  transition:
    flex-basis 220ms ease,
    width 220ms ease,
    opacity 160ms ease,
    border-color 220ms ease;
}

.chat-resizing .session-chat-sidebar {
  transition:
    opacity 160ms ease,
    border-color 220ms ease;
}

.session-chat-inner {
  width: 100%;
  min-width: 0;
  height: 100%;
  display: flex;
  flex-direction: column;
}

.chat-collapsed .session-chat-sidebar {
  flex-basis: 0;
  width: 0;
  border-left-width: 0;
  border-left-color: transparent;
  opacity: 0;
  pointer-events: none;
}

.chat-resize-handle {
  position: absolute;
  top: 0;
  bottom: 0;
  left: -6px;
  z-index: 6;
  width: 12px;
  cursor: col-resize;
  touch-action: none;
}

.chat-resize-handle::before,
.chat-resize-handle::after {
  content: "";
  position: absolute;
  pointer-events: none;
}

.chat-resize-handle::before {
  top: 0;
  bottom: 0;
  left: 0;
  right: 0;
  background: rgba(37, 99, 235, 0);
  transition: background-color 120ms ease;
}

.chat-resize-handle::after {
  top: 0;
  bottom: 0;
  left: 5px;
  width: 2px;
  background: transparent;
  transition: background-color 120ms ease;
}

.chat-resize-handle:hover::before,
.chat-resizing .chat-resize-handle::before {
  background: rgba(37, 99, 235, 0.14);
}

.chat-resize-handle:hover::after,
.chat-resizing .chat-resize-handle::after {
  background: var(--color-cv-accent);
}

.chat-toggle-button,
.chat-expand-button {
  width: 32px;
  height: 32px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  flex: 0 0 auto;
  border-radius: 8px;
  color: var(--color-cv-text-secondary);
  background: transparent;
  transition:
    color 160ms ease,
    background-color 160ms ease;
  cursor: pointer;
}

.chat-toggle-button:hover,
.chat-expand-button:hover {
  color: var(--color-cv-text);
  background: var(--color-cv-hover);
}

.chat-expand-button {
  position: absolute;
  top: 64px;
  right: 20px;
  z-index: 10;
  color: var(--color-cv-text);
  background: rgba(0, 0, 0, 0.7);
  border: 1px solid rgba(255, 255, 255, 0.1);
  backdrop-filter: blur(10px);
}

.chat-expand-button:hover {
  background: rgba(0, 0, 0, 0.9);
}

.baidu-avatar-status {
  position: absolute;
  top: 50%;
  left: 50%;
  z-index: 11;
  width: min(90vw, 460px);
  transform: translate(-50%, -50%);
  padding: 14px 16px;
  border: 1px solid rgba(96, 165, 250, 0.36);
  border-radius: 8px;
  background: rgba(5, 7, 12, 0.86);
  color: var(--color-cv-text);
  text-align: center;
  line-height: 1.6;
  font-size: 13px;
  box-shadow: 0 18px 48px rgba(0, 0, 0, 0.46);
}

.baidu-avatar-status.error {
  border-color: rgba(248, 113, 113, 0.45);
  color: #fecaca;
}

.avatar-fallback-popover {
  position: absolute;
  top: 64px;
  right: 20px;
  z-index: 12;
  width: min(86vw, 360px);
  padding: 12px 14px;
  border: 1px solid rgba(125, 211, 252, 0.24);
  border-radius: 8px;
  background: rgba(7, 13, 20, 0.78);
  color: var(--color-cv-text);
  box-shadow: 0 18px 48px rgba(0, 0, 0, 0.4);
  backdrop-filter: blur(18px);
  -webkit-backdrop-filter: blur(18px);
  cursor: pointer;
}

.avatar-fallback-popover-title {
  margin-bottom: 4px;
  color: #dbeafe;
  font-size: 12px;
  font-weight: 600;
}

.avatar-fallback-popover-detail {
  color: var(--color-cv-text-secondary);
  font-size: 12px;
  line-height: 1.55;
}

.avatar-fallback-badge {
  position: absolute;
  top: 20px;
  right: 20px;
  z-index: 10;
  height: 30px;
  display: inline-flex;
  align-items: center;
  flex: 0 0 auto;
  padding: 0 12px;
  border: 1px solid rgba(125, 211, 252, 0.28);
  border-radius: 999px;
  background: rgba(14, 31, 45, 0.58);
  color: #dbeafe;
  font-size: 11px;
  font-weight: 600;
  line-height: 1;
  cursor: pointer;
  transition:
    border-color 160ms ease,
    background-color 160ms ease,
    color 160ms ease;
}

.avatar-fallback-badge:hover,
.avatar-fallback-badge[aria-expanded="true"] {
  border-color: rgba(125, 211, 252, 0.42);
  background: rgba(23, 47, 68, 0.72);
  color: #eff6ff;
}

.dock-waveform-background {
  position: absolute;
  right: 0;
  bottom: 7px;
  left: 0;
  z-index: 0;
  display: flex;
  height: 18px;
  align-items: flex-end;
  justify-content: center;
  gap: 3px;
  pointer-events: none;
  opacity: 0.28;
  -webkit-mask-image: linear-gradient(90deg, transparent, #000 12%, #000 88%, transparent);
  mask-image: linear-gradient(90deg, transparent, #000 12%, #000 88%, transparent);
}

.dock-waveform-bar {
  width: 3px;
  max-height: 16px;
  border-radius: 999px;
  background: var(--color-cv-success);
  box-shadow: 0 0 8px rgba(34, 197, 94, 0.32);
  transition: height 75ms ease;
}

.visual-preview {
  position: absolute;
  right: 20px;
  bottom: 88px;
  z-index: 12;
  width: clamp(132px, 18vw, 220px);
  aspect-ratio: 16 / 10;
  overflow: hidden;
  border-radius: 8px;
  border: 1px solid rgba(255, 255, 255, 0.16);
  background: #05070a;
  box-shadow: 0 14px 42px rgba(0, 0, 0, 0.46);
  cursor: grab;
  touch-action: none;
  user-select: none;
}

.visual-preview.dragging {
  cursor: grabbing;
}

.visual-preview-video {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

.visual-preview-mirror {
  transform: scaleX(-1);
}

.visual-preview-close {
  position: absolute;
  top: 8px;
  right: 8px;
  width: 26px;
  height: 26px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  background: rgba(0, 0, 0, 0.58);
  border: 1px solid rgba(255, 255, 255, 0.16);
  border-radius: 999px;
  cursor: pointer;
  transition: background-color 160ms ease;
}

.visual-preview-close:hover {
  background: rgba(0, 0, 0, 0.82);
}

@media (max-width: 900px) {
  .session-chat-sidebar {
    flex-basis: var(--chat-sidebar-width, min(82vw, 420px));
    width: var(--chat-sidebar-width, min(82vw, 420px));
  }

  .voice-agent-visual {
    padding: 72px 12px 124px;
  }

  .voice-agent-visual::before,
  .voice-agent-visual::after {
    width: clamp(52px, 16vw, 120px);
  }

  .voice-agent-portrait {
    width: min(78vw, 54vh, 420px);
    max-width: calc(100% - 24px);
  }

  .avatar-fallback-popover {
    top: 60px;
    right: 14px;
    width: min(88vw, 340px);
  }

  .visual-preview {
    right: 14px;
    bottom: 94px;
    width: min(42vw, 170px);
  }
}
</style>
