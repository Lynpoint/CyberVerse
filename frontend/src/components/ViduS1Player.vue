<script setup lang="ts">
import { onMounted, onUnmounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import artcSdk from 'aliyun-rtc-sdk'
import type { ViduSessionConfig } from '../utils/sessionLaunchState'

type PlayerStatus = 'joining' | 'waiting' | 'ready' | 'error'

interface ViduPlayerState {
  rtcReady: boolean
  streamReady: boolean
  audioReady: boolean
  autoplayBlocked: boolean
  microphoneEnabled: boolean
  cameraEnabled: boolean
  remoteSpeechDetected: boolean
}

const props = defineProps<{ config: ViduSessionConfig }>()
const emit = defineEmits<{
  stateChanged: [state: ViduPlayerState]
  rtcReady: []
  rtcFailed: [payload: { message: string }]
  renderError: [payload: { message: string }]
}>()

const { t } = useI18n()
const artc: any = artcSdk
const containerRef = ref<HTMLDivElement | null>(null)
const status = ref<PlayerStatus>('joining')
const errorMessage = ref('')
const state = ref<ViduPlayerState>({
  rtcReady: false,
  streamReady: false,
  audioReady: false,
  autoplayBlocked: false,
  microphoneEnabled: false,
  cameraEnabled: false,
  remoteSpeechDetected: false,
})

let engine: any = null
let joining = false
const remoteVideos = new Map<string, HTMLVideoElement>()

function publishState() {
  emit('stateChanged', { ...state.value })
}

function errorText(error: unknown): string {
  if (error instanceof DOMException && error.name === 'NotAllowedError') {
    return t('session.viduMicrophonePermissionRequired')
  }
  return error instanceof Error ? error.message : t('session.viduConnectionError')
}

function attachRemoteVideo(uid: string) {
  if (!engine || remoteVideos.has(uid)) return
  const video = document.createElement('video')
  video.autoplay = true
  video.muted = true
  video.setAttribute('playsinline', 'true')
  video.setAttribute('webkit-playsinline', 'true')
  video.className = 'vidu-s1-video'
  video.dataset.testid = 'vidu-video'
  containerRef.value?.appendChild(video)
  remoteVideos.set(uid, video)
  engine.setRemoteViewConfig(video, uid, 1)
}

function detachRemoteVideo(uid: string) {
  const video = remoteVideos.get(uid)
  if (!video) return
  try { engine?.setRemoteViewConfig(null, uid, 1) } catch {}
  try { video.pause() } catch {}
  video.remove()
  remoteVideos.delete(uid)
}

function cleanup() {
  for (const uid of [...remoteVideos.keys()]) detachRemoteVideo(uid)
  const activeEngine = engine
  engine = null
  joining = false
  if (activeEngine) {
    try { activeEngine.leaveChannel() } catch {}
    try { activeEngine.destroy() } catch {}
  }
  state.value = {
    rtcReady: false,
    streamReady: false,
    audioReady: false,
    autoplayBlocked: false,
    microphoneEnabled: false,
    cameraEnabled: false,
    remoteSpeechDetected: false,
  }
  publishState()
}

async function join() {
  if (joining || engine) return
  joining = true
  status.value = 'joining'
  errorMessage.value = ''
  try {
    const { app_id: appID, channel_id: channelID, user_id: userID, token, token_expire_at: tokenExpireAt } = props.config
    if (!appID || !channelID || !userID || !token || !Number.isFinite(tokenExpireAt)) {
      throw new Error(t('session.viduCredentialsIncomplete'))
    }
    if (tokenExpireAt <= Math.floor(Date.now() / 1000)) {
      throw new Error(t('session.viduCredentialsExpired'))
    }
    const support = await artc.isSupported('sendrecv')
    if (!support?.support) throw new Error(t('session.viduWebRTCUnsupported'))

    engine = artc.getInstance()
    try { artc.setLogLevel(0) } catch {}
    engine.on('videoSubscribeStateChanged', (uid: string, _oldState: number, newState: number) => {
      if (newState === 3) {
        attachRemoteVideo(uid)
        status.value = 'ready'
        state.value.streamReady = true
      } else if (newState === 1) {
        detachRemoteVideo(uid)
        state.value.streamReady = remoteVideos.size > 0
      }
      publishState()
    })
    engine.on('audioSubscribeStateChanged', (_uid: string, _oldState: number, newState: number) => {
      state.value.audioReady = newState === 3
      publishState()
    })
    const markAutoplayBlocked = () => {
      state.value.autoplayBlocked = true
      publishState()
    }
    engine.on('remoteAudioAutoPlayFail', markAutoplayBlocked)
    engine.on('remoteAudioPlayError', markAutoplayBlocked)
    engine.on('audioVolume', (speakers: Array<{ userId?: string; volume?: number }>) => {
      if (speakers.some(speaker => Boolean(speaker.userId) && Number(speaker.volume) > 0)) {
        state.value.remoteSpeechDetected = true
        publishState()
      }
    })
    engine.on('bye', () => {
      if (!engine) return
      const message = t('session.viduDisconnected')
      errorMessage.value = message
      status.value = 'error'
      state.value.rtcReady = false
      publishState()
      emit('renderError', { message })
    })

    engine.setChannelProfile('interactive_live')
    await engine.setClientRole('interactive')
    engine.setDefaultSubscribeAllRemoteAudioStreams(true)
    engine.setDefaultSubscribeAllRemoteVideoStreams(true)
    engine.muteAllRemoteAudioPlaying(false)
    engine.enableAudioVolumeIndication(300)
    await engine.publishLocalAudioStream(true)
    engine.muteLocalMic(false)
    state.value.microphoneEnabled = true
    await engine.publishLocalVideoStream(false)
    await engine.enableLocalVideo(false)
    status.value = 'waiting'
    await engine.joinChannel(token, userID)
    state.value.rtcReady = true
    publishState()
    emit('rtcReady')
  } catch (error) {
    const message = errorText(error)
    cleanup()
    errorMessage.value = message
    status.value = 'error'
    emit('rtcFailed', { message })
  } finally {
    joining = false
  }
}

function toggleMicrophone() {
  if (!engine) return
  const enabled = !state.value.microphoneEnabled
  engine.muteLocalMic(!enabled)
  state.value.microphoneEnabled = enabled
  publishState()
}

async function toggleCamera() {
  if (!engine) return
  const enabled = !state.value.cameraEnabled
  try {
    if (enabled) {
      await engine.enableLocalVideo(true)
      await engine.publishLocalVideoStream(true)
    } else {
      await engine.publishLocalVideoStream(false)
      await engine.enableLocalVideo(false)
    }
    state.value.cameraEnabled = enabled
    publishState()
  } catch (error) {
    const message = errorText(error)
    emit('renderError', { message })
  }
}

function muteAudio(muted: boolean) {
  if (!engine) return
  engine.muteAllRemoteAudioPlaying(muted)
  if (!muted) state.value.autoplayBlocked = false
  publishState()
}

function disconnect() {
  cleanup()
}

defineExpose({ toggleMicrophone, toggleCamera, muteAudio, disconnect })

onMounted(() => void join())
onUnmounted(cleanup)
</script>

<template>
  <div
    class="vidu-s1-player"
    data-testid="vidu-container"
    :data-rtc-ready="state.rtcReady"
    :data-stream-ready="state.streamReady"
    :data-audio-ready="state.audioReady"
    :data-remote-speech="state.remoteSpeechDetected"
  >
    <div ref="containerRef" class="vidu-s1-media" />
    <div v-if="status !== 'ready'" class="vidu-s1-status" :class="{ error: status === 'error' }" data-testid="vidu-status">
      <span v-if="status === 'joining'">{{ t('session.viduJoining') }}</span>
      <span v-else-if="status === 'waiting'">{{ t('session.viduGenerating') }}</span>
      <span v-else>{{ errorMessage || t('session.viduConnectionError') }}</span>
    </div>
    <button
      v-if="status === 'ready'"
      type="button"
      class="vidu-s1-audio-status"
      :disabled="!state.autoplayBlocked"
      data-testid="vidu-audio-status"
      @click="muteAudio(false)"
    >
      {{ state.autoplayBlocked
        ? t('session.viduEnableAudio')
        : state.remoteSpeechDetected
          ? t('session.viduSpeechReceived')
          : state.audioReady
            ? t('session.viduAudioReady')
            : t('session.viduAudioWaiting') }}
    </button>
  </div>
</template>

<style scoped>
.vidu-s1-player,
.vidu-s1-media {
  position: relative;
  width: 100%;
  height: 100%;
  min-height: 0;
  overflow: hidden;
  background: #000;
}

.vidu-s1-status {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
  background: linear-gradient(135deg, #172554, #05070a);
  color: #e5e7eb;
  text-align: center;
}

.vidu-s1-status.error {
  color: #fca5a5;
}

.vidu-s1-audio-status {
  position: absolute;
  top: 20px;
  right: 20px;
  z-index: 5;
  border-radius: 999px;
  background: rgb(0 0 0 / 65%);
  padding: 6px 10px;
  color: #f3f4f6;
  font-size: 12px;
}

.vidu-s1-audio-status:disabled {
  cursor: default;
}

:deep(.vidu-s1-video) {
  width: 100%;
  height: 100%;
  object-fit: contain;
}
</style>
