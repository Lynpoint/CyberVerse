<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import AppHeader from '../components/AppHeader.vue'
import CvSelect from '../components/CvSelect.vue'
import { useCharacterStore } from '../stores/characters'
import { createOfflineVideo, deleteOfflineVideo, getComponents, getLaunchConfig, listOfflineVideos, renameOfflineVideo, updateOfflineVideoTTS } from '../services/api'
import { DOUBAO_TTS_VOICE_OPTIONS, OPENAI_VOICE_OPTIONS, QWEN_TTS_MODEL_OPTIONS, QWEN_TTS_VOICE_OPTIONS } from '../types'
import type { ComponentOption, ComponentsResponse, ConfigParam, OfflineVideoJob } from '../types'
import { saveLaunchWorkspaceMode } from '../utils/launchModePreference'
import {
  DEFAULT_COSYVOICE_V3_VOICE,
  DEFAULT_DOUBAO_TTS_VOICE,
  DEFAULT_QWEN_TTS_VOICE,
  cosyVoiceBuiltinVoiceOptions,
  formatVoiceTypeDisplay,
  isCosyVoiceBuiltinModel,
  isCosyVoiceBuiltinVoice,
  isCosyVoiceCloneOnlyModel,
  isCosyVoiceKnownBuiltinVoice,
  isCosyVoiceTTSModel,
  isDoubaoTTSVoiceType,
  isOfficialVoiceType,
  isOpenAIVoiceType,
  isQwenOmniVoiceType,
  isQwenTTSVoiceType,
  localizedVoiceOptions,
} from '../utils/voice'

const route = useRoute()
const router = useRouter()
const { t, locale } = useI18n()
const store = useCharacterStore()

const characterId = computed(() => route.params.id as string)
const pageTitle = computed(() => t('launch.workspaceTitle'))
const hasCurrentCharacter = computed(() => store.current?.id === characterId.value)
const showLoading = computed(() => loading.value && !hasCurrentCharacter.value)
const inputType = ref<'text' | 'audio'>('text')
const scriptText = ref(t('offlineVideo.defaultScript'))
const audioFile = ref<File | null>(null)
const audioFileError = ref('')
const inputAudioUrl = ref('')
const outputWidth = ref(1080)
const outputHeight = ref(1920)
const transparentBackground = ref(false)
const outputSettingsExpanded = ref(false)
const showLocalVideoOutputHelp = ref(false)
const ttsPerson = ref('')
const ttsLan = ref('auto')
const ttsSpeed = ref(5)
const ttsVolume = ref(5)
const ttsPitch = ref(5)
const offlineTTSProvider = ref('qwen')
const offlineTTSModel = ref(QWEN_TTS_MODEL_OPTIONS[0]?.value || 'qwen3-tts-flash-realtime')
const offlineTTSVoice = ref(DEFAULT_QWEN_TTS_VOICE)
const offlineCosyVoiceMode = ref<'official' | 'custom'>('official')
const offlineTTSSaveError = ref('')
const savingOfflineTTS = ref(false)
const backgroundImageUrl = ref('')
const autoAnimoji = ref(false)
const jobs = ref<OfflineVideoJob[]>([])
const localVideoOutputParams = ref<ConfigParam[]>([])
const loading = ref(true)
const submitting = ref(false)
const renaming = ref(false)
const editingJobId = ref('')
const editingTitle = ref('')
const highlightedJobId = ref('')
const currentJobPage = ref(1)
const failedReasonJob = ref<OfflineVideoJob | null>(null)
const playingVideoJob = ref<OfflineVideoJob | null>(null)
const videoPlayerRef = ref<HTMLVideoElement | null>(null)
const errorMessage = ref('')
let pollTimer: ReturnType<typeof setInterval> | null = null
let highlightTimer: ReturnType<typeof setTimeout> | null = null
let offlineTTSSaveTimer: ReturnType<typeof setTimeout> | null = null
let hydratingOfflineTTS = false

const JOBS_PER_PAGE = 9
const BAIDU_XILING_COMMON_ASSETS_URL = 'https://xiling.cloud.baidu.com/open/commonAssets/list'
const DEFAULT_COMPONENTS: ComponentsResponse = {
  llm: [{ id: 'qwen', name: 'Qwen', model: 'qwen3.6-plus', default: true, available: true }],
  asr: [{ id: 'qwen', name: 'Qwen', model: 'qwen3-asr-flash-realtime', default: true, available: true }],
  tts: [{ id: 'qwen', name: 'Qwen', model: 'qwen3-tts-flash-realtime', default: true, available: true }],
}
const componentCatalog = ref<ComponentsResponse>({ ...DEFAULT_COMPONENTS })

interface OfflineVideoSettings {
  inputType?: 'text' | 'audio'
  outputWidth?: number
  outputHeight?: number
  transparentBackground?: boolean
  ttsPerson?: string
  ttsLan?: string
  ttsSpeed?: number
  ttsVolume?: number
  ttsPitch?: number
  inputAudioUrl?: string
  backgroundImageUrl?: string
  autoAnimoji?: boolean
}

const ttsLanguageOptions = [
  'auto',
  'Chinese',
  'Chinese,Yue',
  'English',
  'Russian',
  'Spanish',
  'French',
  'Portuguese',
  'German',
  'Turkish',
  'Dutch',
  'Ukrainian',
  'Vietnamese',
  'Indonesian',
  'Japanese',
  'Italian',
  'Korean',
  'Thai',
  'Polish',
  'Romanian',
  'Greek',
  'Czech',
  'Finnish',
  'Hindi',
]

const providerSelectOptions = (items: ComponentOption[]) =>
  items.map(item => ({
    label: item.name,
    value: item.id,
  }))

const isBaiduXilingCharacter = computed(() => store.current?.avatar_backend === 'baidu_xiling')
const showLocalTextTTSSettings = computed(() => !isBaiduXilingCharacter.value && inputType.value === 'text')
const localVideoOutputRows = computed(() => {
  const wanted = new Set(['size', 'fps'])
  return localVideoOutputParams.value
    .filter(param => wanted.has(param.name))
    .map(param => ({
      label: param.name === 'size' ? t('offlineVideo.outputResolution') : t('offlineVideo.outputFPS'),
      path: param.path,
      value: String(param.value === '' ? t('common.emptyDash') : param.value),
    }))
})
const showLocalVideoOutputSettings = computed(() => !isBaiduXilingCharacter.value && localVideoOutputRows.value.length > 0)
const showOutputSettings = computed(() => isBaiduXilingCharacter.value || showLocalTextTTSSettings.value || showLocalVideoOutputSettings.value)
const hasActiveJobs = computed(() => jobs.value.some(job => job.status === 'queued' || job.status === 'running'))
const totalJobPages = computed(() => Math.max(1, Math.ceil(jobs.value.length / JOBS_PER_PAGE)))
const pagedJobs = computed(() => {
  const start = (currentJobPage.value - 1) * JOBS_PER_PAGE
  return jobs.value.slice(start, start + JOBS_PER_PAGE)
})
const failedReasonText = computed(() =>
  failedReasonJob.value?.error?.trim()
    || failedReasonJob.value?.message?.trim()
    || t('offlineVideo.failureReasonUnavailable'),
)
const characterCoverImage = computed(() => {
  const character = store.current
  if (!character) return ''
  if (character.avatar_backend === 'baidu_xiling') {
    return character.baidu_xiling?.thumbnail_url || character.baidu_xiling?.source_image_url || ''
  }
  if (character.avatar_backend === 'xunfei') {
    return character.xunfei?.thumbnail_url || character.xunfei?.source_image_url || ''
  }
  return character.avatar_image || ''
})
const audioHint = computed(() =>
  isBaiduXilingCharacter.value ? t('offlineVideo.baiduAudioHint') : t('offlineVideo.audioHint'),
)
const selectedAudioFileName = computed(() => audioFile.value?.name || t('offlineVideo.audioFileEmpty'))
const selectedAudioFileMeta = computed(() => {
  const file = audioFile.value
  if (!file) return t('offlineVideo.audioFileEmptyHint')
  const fileType = file.type || t('offlineVideo.audioFileRawFormat')
  return `${formatFileSize(file.size)} · ${fileType}`
})
const ttsProviderOptions = computed(() => providerSelectOptions(componentCatalog.value.tts))
const selectedOfflineTTSComponent = computed(() =>
  componentCatalog.value.tts.find(item => item.id === offlineTTSProvider.value),
)
const offlineTTSModelOptions = computed(() => {
  if (offlineTTSProvider.value === 'qwen') {
    const hasCurrent = QWEN_TTS_MODEL_OPTIONS.some(option => option.value === offlineTTSModel.value)
    return hasCurrent || !offlineTTSModel.value
      ? QWEN_TTS_MODEL_OPTIONS
      : [{ label: offlineTTSModel.value, value: offlineTTSModel.value }, ...QWEN_TTS_MODEL_OPTIONS]
  }
  const model = selectedOfflineTTSComponent.value?.model || ''
  return model ? [{ label: model, value: model }] : []
})
const isOfflineCosyVoiceTTS = computed(() =>
  offlineTTSProvider.value === 'qwen' && isCosyVoiceTTSModel(offlineTTSModel.value)
)
const isOfflineCosyVoiceCloneOnlyTTS = computed(() =>
  isOfflineCosyVoiceTTS.value && isCosyVoiceCloneOnlyModel(offlineTTSModel.value)
)
const isOfflineCosyVoiceBuiltinTTS = computed(() =>
  isOfflineCosyVoiceTTS.value && isCosyVoiceBuiltinModel(offlineTTSModel.value)
)
const offlineTTSVoiceOptions = computed(() => {
  if (offlineTTSProvider.value === 'openai') {
    return localizedVoiceOptions(OPENAI_VOICE_OPTIONS, locale.value)
  }
  if (offlineTTSProvider.value === 'doubao') {
    return localizedVoiceOptions(DOUBAO_TTS_VOICE_OPTIONS, locale.value)
  }
  return localizedVoiceOptions(QWEN_TTS_VOICE_OPTIONS, locale.value)
})
const offlineCosyVoiceOfficialOptions = computed(() => localizedVoiceOptions(
  cosyVoiceBuiltinVoiceOptions(offlineTTSModel.value),
  locale.value,
))
const supportedAudioExtensions = new Set(['wav', 'pcm', 's16le'])
const audioAccept = '.wav,.pcm,.s16le,audio/wav,audio/wave,audio/x-wav'
const isTTSPersonRequired = computed(() => isBaiduXilingCharacter.value && inputType.value === 'text')
const isMissingTTSPerson = computed(() => isTTSPersonRequired.value && !ttsPerson.value.trim())
const canGenerate = computed(() => {
  if (submitting.value) return false
  if (isBaiduXilingCharacter.value && (!outputWidth.value || !outputHeight.value)) return false
  if (inputType.value === 'text') {
    if (isMissingTTSPerson.value) return false
    if (showLocalTextTTSSettings.value && !isOfflineTTSVoiceValid(offlineTTSProvider.value, offlineTTSVoice.value)) return false
    return scriptText.value.trim().length > 0
  }
  if (isBaiduXilingCharacter.value) {
    return inputAudioUrl.value.trim().length > 0
  }
  return !!audioFile.value
})

function offlineVideoSettingsKey(): string {
  return `cyberverse.offlineVideoSettings.v1:${characterId.value}`
}

function readOfflineVideoSettings(): OfflineVideoSettings {
  if (typeof window === 'undefined') return {}
  try {
    const raw = window.localStorage.getItem(offlineVideoSettingsKey())
    return raw ? JSON.parse(raw) as OfflineVideoSettings : {}
  } catch {
    return {}
  }
}

function saveOfflineVideoSettings() {
  if (typeof window === 'undefined') return
  const settings: OfflineVideoSettings = {
    inputType: inputType.value,
    outputWidth: outputWidth.value,
    outputHeight: outputHeight.value,
    transparentBackground: transparentBackground.value,
    ttsPerson: ttsPerson.value,
    ttsLan: ttsLan.value,
    ttsSpeed: ttsSpeed.value,
    ttsVolume: ttsVolume.value,
    ttsPitch: ttsPitch.value,
    inputAudioUrl: inputAudioUrl.value,
    backgroundImageUrl: backgroundImageUrl.value,
    autoAnimoji: autoAnimoji.value,
  }
  window.localStorage.setItem(offlineVideoSettingsKey(), JSON.stringify(settings))
}

function numberSetting(value: unknown, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback
}

function boolSetting(value: unknown, fallback: boolean): boolean {
  return typeof value === 'boolean' ? value : fallback
}

function stringSetting(value: unknown, fallback: string): string {
  return typeof value === 'string' ? value : fallback
}

function defaultOfflineTTSProvider(): string {
  return componentCatalog.value.tts.find(item => item.default)?.id
    || componentCatalog.value.tts[0]?.id
    || 'qwen'
}

function defaultOfflineTTSModel(provider: string): string {
  if (provider === 'qwen') return QWEN_TTS_MODEL_OPTIONS[0]?.value || selectedOfflineTTSComponent.value?.model || ''
  return selectedOfflineTTSComponent.value?.model || ''
}

function defaultOfflineTTSVoice(provider: string): string {
  if (provider === 'qwen' && isOfflineCosyVoiceCloneOnlyTTS.value) return ''
  if (provider === 'qwen' && isOfflineCosyVoiceBuiltinTTS.value) return DEFAULT_COSYVOICE_V3_VOICE
  if (provider === 'doubao') return DEFAULT_DOUBAO_TTS_VOICE
  return provider === 'openai' ? 'nova' : DEFAULT_QWEN_TTS_VOICE
}

function isOfflinePresetVoice(voice: string): boolean {
  return isQwenTTSVoiceType(voice)
    || isDoubaoTTSVoiceType(voice)
    || isOpenAIVoiceType(voice)
    || isQwenOmniVoiceType(voice)
    || isOfficialVoiceType(voice)
    || isCosyVoiceKnownBuiltinVoice(voice)
}

function isOfflineTTSVoiceValid(provider: string, voice: string): boolean {
  if (!voice.trim()) return false
  if (provider === 'openai') return isOpenAIVoiceType(voice)
  if (provider === 'doubao') return isDoubaoTTSVoiceType(voice)
  if (provider === 'qwen' && isOfflineCosyVoiceCloneOnlyTTS.value) return !isOfflinePresetVoice(voice)
  if (provider === 'qwen' && isOfflineCosyVoiceBuiltinTTS.value) {
    return offlineCosyVoiceMode.value === 'official'
      ? isCosyVoiceBuiltinVoice(offlineTTSModel.value, voice)
      : !isOfflinePresetVoice(voice)
  }
  if (provider === 'qwen') return isQwenTTSVoiceType(voice)
  return true
}

function normalizeOfflineTTSVoice(provider: string, voice: string): string {
  const trimmed = voice.trim()
  if (provider === 'qwen' && isOfflineCosyVoiceBuiltinTTS.value) {
    if (trimmed && isCosyVoiceBuiltinVoice(offlineTTSModel.value, trimmed)) {
      offlineCosyVoiceMode.value = 'official'
      return trimmed
    }
    if (trimmed && !isOfflinePresetVoice(trimmed)) {
      offlineCosyVoiceMode.value = 'custom'
      return trimmed
    }
    offlineCosyVoiceMode.value = 'official'
    return defaultOfflineTTSVoice(provider)
  }
  if (provider === 'qwen' && isOfflineCosyVoiceCloneOnlyTTS.value) {
    offlineCosyVoiceMode.value = 'custom'
    return trimmed && !isOfflinePresetVoice(trimmed) ? trimmed : ''
  }
  return isOfflineTTSVoiceValid(provider, trimmed) ? trimmed : defaultOfflineTTSVoice(provider)
}

function setOfflineCosyVoiceMode(mode: 'official' | 'custom') {
  offlineCosyVoiceMode.value = mode
  offlineTTSSaveError.value = ''
  if (mode === 'official') {
    if (!isCosyVoiceBuiltinVoice(offlineTTSModel.value, offlineTTSVoice.value)) {
      offlineTTSVoice.value = defaultOfflineTTSVoice(offlineTTSProvider.value)
    }
  } else if (isOfflinePresetVoice(offlineTTSVoice.value)) {
    offlineTTSVoice.value = ''
  }
  scheduleOfflineTTSSave()
}

function loadOfflineTTSPreference() {
  hydratingOfflineTTS = true
  try {
    const preference = store.current?.offline_video_tts
    const requestedProvider = preference?.provider || defaultOfflineTTSProvider()
    const provider = componentCatalog.value.tts.some(item => item.id === requestedProvider)
      ? requestedProvider
      : defaultOfflineTTSProvider()
    offlineTTSProvider.value = provider
    offlineTTSModel.value = preference?.model || defaultOfflineTTSModel(provider)
    offlineTTSVoice.value = normalizeOfflineTTSVoice(provider, preference?.voice || '')
    offlineTTSSaveError.value = ''
  } finally {
    hydratingOfflineTTS = false
  }
}

function scheduleOfflineTTSSave() {
  if (hydratingOfflineTTS || isBaiduXilingCharacter.value) return
  if (offlineTTSSaveTimer) clearTimeout(offlineTTSSaveTimer)
  offlineTTSSaveTimer = setTimeout(() => {
    saveOfflineTTSPreference().catch(() => {})
  }, 500)
}

async function saveOfflineTTSPreference() {
  if (isBaiduXilingCharacter.value || !characterId.value || !offlineTTSProvider.value) return
  if (!isOfflineTTSVoiceValid(offlineTTSProvider.value, offlineTTSVoice.value)) return
  savingOfflineTTS.value = true
  offlineTTSSaveError.value = ''
  try {
    const updated = await updateOfflineVideoTTS(characterId.value, {
      provider: offlineTTSProvider.value,
      model: offlineTTSModel.value,
      voice: offlineTTSVoice.value,
    })
    store.current = updated
  } catch (err) {
    offlineTTSSaveError.value = err instanceof Error ? err.message : t('offlineVideo.ttsPreferenceSaveFailed')
  } finally {
    savingOfflineTTS.value = false
  }
}

function clampProgress(job: OfflineVideoJob): number {
  return Math.min(100, Math.max(0, job.progress || 0))
}

function progressStyle(job: OfflineVideoJob) {
  return { width: `${clampProgress(job)}%` }
}

function statusLabel(job: OfflineVideoJob): string {
  return t(`offlineVideo.status.${job.status}`)
}

function isActiveJob(job: OfflineVideoJob): boolean {
  return job.status === 'queued' || job.status === 'running'
}

function formatDate(value?: string): string {
  if (!value) return t('common.emptyDash')
  const date = new Date(value)
  if (!Number.isFinite(date.getTime())) return value
  return date.toLocaleString()
}

function downloadVideoFilename(job: OfflineVideoJob): string {
  const fallback = 'offline-video'
  const rawName = (job.video_filename || job.title || fallback).trim()
  const safeName = rawName.replace(/[\\/:*?"<>|]+/g, '-').trim() || fallback
  return /\.[a-z0-9]{2,5}$/i.test(safeName) ? safeName : `${safeName}.mp4`
}

async function refreshJobs() {
  if (!characterId.value) return
  const resp = await listOfflineVideos(characterId.value)
  const existingById = new Map(jobs.value.map(job => [job.id, job]))
  jobs.value = resp.videos.map(job => ({
    ...(existingById.get(job.id) || {}),
    ...job,
  }))
}

function markJobHighlighted(jobId: string) {
  highlightedJobId.value = jobId
  const index = jobs.value.findIndex(job => job.id === jobId)
  if (index >= 0) {
    currentJobPage.value = Math.floor(index / JOBS_PER_PAGE) + 1
  }
  if (highlightTimer) clearTimeout(highlightTimer)
  highlightTimer = setTimeout(() => {
    if (highlightedJobId.value === jobId) highlightedJobId.value = ''
  }, 6000)
}

function changeJobPage(nextPage: number) {
  currentJobPage.value = Math.min(totalJobPages.value, Math.max(1, nextPage))
}

function openFailedReason(job: OfflineVideoJob) {
  failedReasonJob.value = job
}

function closeFailedReason() {
  failedReasonJob.value = null
}

async function openVideoPlayer(job: OfflineVideoJob) {
  if (!job.video_url) return
  videoPlayerRef.value?.pause()
  playingVideoJob.value = job
  await nextTick()
  const video = videoPlayerRef.value
  if (!video) return
  try {
    video.currentTime = 0
  } catch {
    // Some remote videos may not be seekable before metadata is ready.
  }
  try {
    await video.play()
  } catch {
    // Browser autoplay policy can still require the user to press play.
  }
}

function closeVideoPlayer() {
  const video = videoPlayerRef.value
  if (video) {
    video.pause()
    try {
      video.currentTime = 0
    } catch {
      // Some remote videos may not be seekable after the source is removed.
    }
  }
  playingVideoJob.value = null
}

function handleModalKeydown(event: KeyboardEvent) {
  if (event.key !== 'Escape') return
  if (playingVideoJob.value) {
    closeVideoPlayer()
    return
  }
  if (failedReasonJob.value) {
    closeFailedReason()
  }
}

function closeLocalVideoOutputHelp() {
  showLocalVideoOutputHelp.value = false
}

function formatFileSize(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 KB'
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function isSupportedOfflineAudioFile(file: File | null): boolean {
  if (!file) return false
  const normalizedName = file.name.trim().toLowerCase()
  const dotIndex = normalizedName.lastIndexOf('.')
  const extension = dotIndex >= 0 ? normalizedName.slice(dotIndex + 1) : ''
  return supportedAudioExtensions.has(extension)
}

function handleAudioChange(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0] || null
  errorMessage.value = ''
  if (!file) {
    audioFile.value = null
    audioFileError.value = ''
    return
  }
  if (!isSupportedOfflineAudioFile(file)) {
    audioFile.value = null
    audioFileError.value = t('offlineVideo.audioFileUnsupported')
    input.value = ''
    return
  }
  audioFile.value = file
  audioFileError.value = ''
}

function loadOutputSettings() {
  const config = store.current?.baidu_xiling
  const settings = readOfflineVideoSettings()
  inputType.value = settings.inputType === 'audio' ? 'audio' : 'text'
  outputWidth.value = config?.width || 1080
  outputHeight.value = config?.height || 1920
  outputWidth.value = numberSetting(settings.outputWidth, outputWidth.value)
  outputHeight.value = numberSetting(settings.outputHeight, outputHeight.value)
  transparentBackground.value = boolSetting(settings.transparentBackground, false)
  outputSettingsExpanded.value = false
  ttsPerson.value = stringSetting(settings.ttsPerson, '')
  ttsLan.value = stringSetting(settings.ttsLan, 'auto')
  ttsSpeed.value = numberSetting(settings.ttsSpeed, 5)
  ttsVolume.value = numberSetting(settings.ttsVolume, 5)
  ttsPitch.value = numberSetting(settings.ttsPitch, 5)
  inputAudioUrl.value = stringSetting(settings.inputAudioUrl, '')
  backgroundImageUrl.value = stringSetting(settings.backgroundImageUrl, '')
  autoAnimoji.value = boolSetting(settings.autoAnimoji, false)
}

async function loadLocalVideoOutputSettings() {
  localVideoOutputParams.value = []
  if (isBaiduXilingCharacter.value) return
  try {
    const config = await getLaunchConfig()
    const section = config.sections.find(item => item.key === 'video_output')
    localVideoOutputParams.value = section?.params || []
  } catch (err) {
    console.warn('Failed to load local video output settings:', err)
  }
}

watch(
  [
    inputType,
    outputWidth,
    outputHeight,
    transparentBackground,
    ttsPerson,
    ttsLan,
    ttsSpeed,
    ttsVolume,
    ttsPitch,
    inputAudioUrl,
    backgroundImageUrl,
    autoAnimoji,
  ],
  saveOfflineVideoSettings,
)

watch(
  () => offlineTTSProvider.value,
  (provider) => {
    if (hydratingOfflineTTS) return
    offlineTTSModel.value = defaultOfflineTTSModel(provider)
    offlineCosyVoiceMode.value = 'official'
    offlineTTSVoice.value = defaultOfflineTTSVoice(provider)
    scheduleOfflineTTSSave()
  },
)

watch(
  () => offlineTTSModel.value,
  () => {
    if (hydratingOfflineTTS) return
    offlineTTSVoice.value = normalizeOfflineTTSVoice(offlineTTSProvider.value, offlineTTSVoice.value)
    scheduleOfflineTTSSave()
  },
)

watch(
  () => offlineTTSVoice.value,
  () => {
    scheduleOfflineTTSSave()
  },
)

watch(jobs, () => {
  if (currentJobPage.value > totalJobPages.value) {
    currentJobPage.value = totalJobPages.value
  }
})

async function submitJob() {
  if (!canGenerate.value) return
  if (inputType.value === 'audio' && !isBaiduXilingCharacter.value && !isSupportedOfflineAudioFile(audioFile.value)) {
    audioFile.value = null
    audioFileError.value = t('offlineVideo.audioFileUnsupported')
    return
  }
  submitting.value = true
  errorMessage.value = ''
  try {
    const createdJob = await createOfflineVideo(characterId.value, {
      inputType: inputType.value,
      text: scriptText.value.trim(),
      audio: isBaiduXilingCharacter.value ? null : audioFile.value,
      inputAudioUrl: isBaiduXilingCharacter.value ? inputAudioUrl.value.trim() : '',
      ttsProvider: showLocalTextTTSSettings.value ? offlineTTSProvider.value : '',
      ttsModel: showLocalTextTTSSettings.value ? offlineTTSModel.value : '',
      ttsVoice: showLocalTextTTSSettings.value ? offlineTTSVoice.value : '',
      width: outputWidth.value,
      height: outputHeight.value,
      transparent: transparentBackground.value,
      ttsPerson: ttsPerson.value.trim(),
      ttsLan: ttsLan.value,
      ttsSpeed: ttsSpeed.value,
      ttsVolume: ttsVolume.value,
      ttsPitch: ttsPitch.value,
      backgroundImageUrl: backgroundImageUrl.value.trim(),
      autoAnimoji: autoAnimoji.value,
    })
    await refreshJobs()
    markJobHighlighted(createdJob.id)
  } catch (err) {
    errorMessage.value = err instanceof Error ? err.message : t('offlineVideo.createFailed')
  } finally {
    submitting.value = false
  }
}

function startRename(job: OfflineVideoJob) {
  editingJobId.value = job.id
  editingTitle.value = job.title
  errorMessage.value = ''
}

function cancelRename() {
  editingJobId.value = ''
  editingTitle.value = ''
}

async function submitRename(job: OfflineVideoJob) {
  const nextTitle = editingTitle.value.trim()
  if (!nextTitle || renaming.value) return
  renaming.value = true
  errorMessage.value = ''
  try {
    await renameOfflineVideo(characterId.value, job.id, nextTitle)
    cancelRename()
    await refreshJobs()
  } catch (err) {
    errorMessage.value = err instanceof Error ? err.message : t('offlineVideo.renameFailed')
  } finally {
    renaming.value = false
  }
}

async function removeJob(job: OfflineVideoJob) {
  if (!window.confirm(t('offlineVideo.deleteConfirm'))) return
  await deleteOfflineVideo(characterId.value, job.id)
  await refreshJobs()
}

onMounted(async () => {
  window.addEventListener('keydown', handleModalKeydown)
  window.addEventListener('click', closeLocalVideoOutputHelp)
  saveLaunchWorkspaceMode('offline')
  try {
    componentCatalog.value = await getComponents()
  } catch (err) {
    console.warn('Failed to load components:', err)
  }
  await store.fetchOne(characterId.value).catch(() => {})
  if (store.current?.avatar_backend === 'vidu') {
    saveLaunchWorkspaceMode('live')
    await router.replace(`/launch/${characterId.value}/live`)
    return
  }
  loadOutputSettings()
  loadOfflineTTSPreference()
  await loadLocalVideoOutputSettings()
  await refreshJobs().catch((err) => {
    errorMessage.value = err instanceof Error ? err.message : t('offlineVideo.loadFailed')
  })
  loading.value = false
  pollTimer = setInterval(() => {
    if (hasActiveJobs.value) {
      refreshJobs().catch(() => {})
    }
  }, 4000)
})

onUnmounted(() => {
  if (pollTimer) clearInterval(pollTimer)
  if (highlightTimer) clearTimeout(highlightTimer)
  if (offlineTTSSaveTimer) clearTimeout(offlineTTSSaveTimer)
  window.removeEventListener('keydown', handleModalKeydown)
  window.removeEventListener('click', closeLocalVideoOutputHelp)
  closeVideoPlayer()
})
</script>

<template>
  <div class="offline-page flex min-h-screen flex-col bg-cv-base text-cv-text">
    <AppHeader showBack :title="pageTitle" />

    <div class="py-6 text-center">
      <div class="cv-pi-segment mx-auto h-11 w-[260px] grid-cols-2">
        <button class="cv-pi-segment-item cv-pi-segment-item--active" type="button">
          {{ t('offlineVideo.offlineMode') }}
        </button>
        <button
          class="cv-pi-segment-item"
          type="button"
          @click="router.push(`/launch/${characterId}/live`)"
        >
          {{ t('offlineVideo.liveMode') }}
        </button>
      </div>
    </div>

    <main class="mx-auto flex w-full max-w-[1100px] flex-1 flex-col gap-8 px-12 pb-24">
      <div v-if="showLoading" class="py-24 text-center text-cv-text-secondary">{{ t('common.loading') }}</div>

      <template v-else-if="store.current">
        <div class="grid gap-8 lg:grid-cols-[300px_minmax(0,1fr)]">
          <aside class="character-panel">
            <div class="avatar-shell">
              <img
                v-if="characterCoverImage"
                :src="characterCoverImage"
                :alt="store.current.name"
                class="h-full w-full object-cover"
              >
              <div v-else class="flex h-full items-center justify-center text-sm text-cv-text-muted">
                {{ t('offlineVideo.noAvatar') }}
              </div>
            </div>
            <div>
              <h2 class="truncate text-xl font-bold text-[#fbf6ef]">{{ store.current.name }}</h2>
              <p class="mt-2 text-sm leading-6 text-[#8d96a6]">{{ store.current.description || t('characterCard.noDescription') }}</p>
            </div>
            <div class="info-grid">
              <span>{{ t('launch.voice') }}</span>
              <strong>{{ formatVoiceTypeDisplay(store.current.voice_type, t, locale) }}</strong>
              <span>{{ t('offlineVideo.avatarSource') }}</span>
              <strong>{{ store.current.avatar_backend }}</strong>
            </div>
            <button
              class="cv-pi-button cv-pi-button--compact"
              type="button"
              @click="router.push(`/characters/${characterId}/edit`)"
            >
              {{ t('launch.editCharacter') }}
            </button>
          </aside>

          <section class="production-panel">
            <form class="generator-form" @submit.prevent="submitJob">
              <div v-if="errorMessage" class="notice error">{{ errorMessage }}</div>

              <div class="cv-pi-segment h-[42px] w-[260px] grid-cols-2" role="tablist" :aria-label="t('offlineVideo.inputMode')">
                <button
                  type="button"
                  class="cv-pi-segment-item"
                  :class="{ 'cv-pi-segment-item--active': inputType === 'text' }"
                  @click="inputType = 'text'"
                >
                  {{ t('offlineVideo.textInput') }}
                </button>
                <button
                  type="button"
                  class="cv-pi-segment-item"
                  :class="{ 'cv-pi-segment-item--active': inputType === 'audio' }"
                  @click="inputType = 'audio'"
                >
                  {{ t('offlineVideo.audioInput') }}
                </button>
              </div>

              <template v-if="inputType === 'text'">
                <label class="field-label" for="offline-script">{{ t('offlineVideo.script') }}</label>
                <textarea
                  id="offline-script"
                  v-model="scriptText"
                  class="script-input"
                  :placeholder="t('offlineVideo.scriptPlaceholder')"
                />
              </template>

              <template v-else-if="isBaiduXilingCharacter">
                <label class="field-label" for="offline-audio-url">{{ t('offlineVideo.inputAudioUrl') }}</label>
                <input
                  id="offline-audio-url"
                  v-model="inputAudioUrl"
                  class="number-input"
                  type="url"
                  :placeholder="t('offlineVideo.inputAudioUrlPlaceholder')"
                >
                <p class="field-hint">{{ audioHint }}</p>
              </template>

              <template v-else>
                <label class="field-label" for="offline-audio">{{ t('offlineVideo.audioFile') }}</label>
                <div class="audio-upload">
                  <input
                    id="offline-audio"
                    class="audio-upload-input"
                    type="file"
                    :accept="audioAccept"
                    @change="handleAudioChange"
                  >
                  <label class="audio-upload-control" for="offline-audio">
                    <span class="audio-upload-icon" aria-hidden="true">
                      <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
                        <path d="M9 12V3.75M9 3.75L5.75 7M9 3.75L12.25 7" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
                        <path d="M3.75 11.25V13.5C3.75 14.3284 4.42157 15 5.25 15H12.75C13.5784 15 14.25 14.3284 14.25 13.5V11.25" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" />
                      </svg>
                    </span>
                    <span class="audio-upload-copy">
                      <strong>{{ selectedAudioFileName }}</strong>
                      <small>{{ selectedAudioFileMeta }}</small>
                    </span>
                    <span class="audio-upload-action">
                      {{ audioFile ? t('offlineVideo.changeAudioFile') : t('offlineVideo.chooseAudioFile') }}
                    </span>
                  </label>
                </div>
                <p v-if="audioFileError" class="field-error">{{ audioFileError }}</p>
                <p class="field-hint">{{ audioHint }}</p>
              </template>

              <section v-if="showOutputSettings" class="output-settings">
                <div class="settings-header">
                  <button
                    class="settings-toggle"
                    type="button"
                    @click="outputSettingsExpanded = !outputSettingsExpanded; showLocalVideoOutputHelp = false"
                  >
                    <h3>{{ t('offlineVideo.outputSettings') }}</h3>
                    <span class="settings-chevron" :class="{ expanded: outputSettingsExpanded }" aria-hidden="true" />
                  </button>
                </div>
                <template v-if="outputSettingsExpanded">
                  <div v-if="showLocalVideoOutputSettings" class="settings-section local-video-output-section">
                    <div class="settings-section-title-row settings-section-title-row--compact">
                      <h4 class="settings-section-title">{{ t('offlineVideo.videoOutputSettings') }}</h4>
                      <span class="settings-help">
                        <button
                          class="field-help-button"
                          type="button"
                          :aria-label="t('offlineVideo.videoOutputHelpLabel')"
                          :aria-expanded="showLocalVideoOutputHelp"
                          @click.stop="showLocalVideoOutputHelp = !showLocalVideoOutputHelp"
                        >
                          ?
                        </button>
                        <span v-if="showLocalVideoOutputHelp" class="settings-help-popover" role="tooltip">
                          {{ t('offlineVideo.videoOutputHelp') }}
                        </span>
                      </span>
                    </div>
                    <div class="settings-grid">
                      <label v-for="row in localVideoOutputRows" :key="row.path" class="settings-field">
                        <span>{{ row.label }}</span>
                        <input
                          class="number-input readonly-input local-video-output-input"
                          type="text"
                          :value="row.value"
                          readonly
                        >
                      </label>
                    </div>
                  </div>

                  <div v-if="isBaiduXilingCharacter" class="settings-grid">
                    <label class="settings-field">
                      <span>{{ t('offlineVideo.outputWidth') }}</span>
                      <input v-model.number="outputWidth" class="number-input" type="number" min="1" max="3840" step="1">
                    </label>
                    <label class="settings-field">
                      <span>{{ t('offlineVideo.outputHeight') }}</span>
                      <input v-model.number="outputHeight" class="number-input" type="number" min="1" max="3840" step="1">
                    </label>
                    <label class="toggle-field">
                      <input v-model="transparentBackground" type="checkbox">
                      <span>{{ t('offlineVideo.transparentBackground') }}</span>
                    </label>
                    <label class="settings-field wide-field">
                      <span>{{ t('offlineVideo.backgroundImageUrl') }}</span>
                      <input
                        v-model="backgroundImageUrl"
                        class="number-input"
                        type="url"
                        :placeholder="t('offlineVideo.backgroundImageUrlPlaceholder')"
                      >
                    </label>
                  </div>

                  <div v-if="isBaiduXilingCharacter && inputType === 'text'" class="settings-section">
                    <h4 class="settings-section-title">{{ t('offlineVideo.ttsSettings') }}</h4>
                    <div class="settings-grid">
                      <div class="settings-field">
                        <div class="field-label-row">
                          <label for="offline-tts-person">{{ t('offlineVideo.ttsPerson') }}</label>
                          <span v-if="isTTSPersonRequired" class="required-mark" aria-hidden="true">*</span>
                          <span class="field-help">
                            <button
                              class="field-help-button"
                              type="button"
                              :aria-label="t('offlineVideo.ttsPersonHelpLabel')"
                            >
                              ?
                            </button>
                            <span class="field-tooltip" role="tooltip">
                              {{ t('offlineVideo.ttsPersonHelpPrefix') }}
                              <a :href="BAIDU_XILING_COMMON_ASSETS_URL" target="_blank" rel="noreferrer">
                                {{ t('offlineVideo.ttsPersonHelpLink') }}
                              </a>
                              {{ t('offlineVideo.ttsPersonHelpSuffix') }}
                            </span>
                          </span>
                        </div>
                        <input
                          id="offline-tts-person"
                          v-model="ttsPerson"
                          class="number-input"
                          type="text"
                          :required="isTTSPersonRequired"
                          :placeholder="t('offlineVideo.ttsPersonPlaceholder')"
                        >
                      </div>
                      <label class="settings-field">
                        <span>{{ t('offlineVideo.ttsLan') }}</span>
                        <select v-model="ttsLan" class="number-input">
                          <option v-for="lan in ttsLanguageOptions" :key="lan" :value="lan">{{ lan }}</option>
                        </select>
                      </label>
                      <label class="settings-field">
                        <span>{{ t('offlineVideo.ttsSpeed') }}</span>
                        <input v-model.number="ttsSpeed" class="number-input" type="number" min="0" max="15" step="1">
                      </label>
                      <label class="settings-field">
                        <span>{{ t('offlineVideo.ttsVolume') }}</span>
                        <input v-model.number="ttsVolume" class="number-input" type="number" min="0" max="15" step="1">
                      </label>
                      <label class="settings-field">
                        <span>{{ t('offlineVideo.ttsPitch') }}</span>
                        <input v-model.number="ttsPitch" class="number-input" type="number" min="0" max="15" step="1">
                      </label>
                      <label class="toggle-field">
                        <input v-model="autoAnimoji" type="checkbox">
                        <span>{{ t('offlineVideo.autoAnimoji') }}</span>
                      </label>
                    </div>
                  </div>

                  <div
                    v-if="showLocalTextTTSSettings"
                    class="settings-section local-tts-section"
                    :class="{ 'local-tts-section--separated': showLocalVideoOutputSettings }"
                  >
                    <div class="settings-section-title-row">
                      <h4 class="settings-section-title">{{ t('offlineVideo.ttsSettings') }}</h4>
                      <span v-if="savingOfflineTTS" class="local-tts-status">{{ t('common.saving') }}</span>
                    </div>
                    <div class="local-tts-grid">
                      <label class="settings-field">
                        <span>{{ t('common.provider') }}</span>
                        <CvSelect
                          v-model="offlineTTSProvider"
                          :options="ttsProviderOptions"
                        />
                      </label>
                      <label class="settings-field local-tts-field--model">
                        <span>{{ t('common.model') }}</span>
                        <CvSelect
                          v-model="offlineTTSModel"
                          :options="offlineTTSModelOptions"
                        />
                      </label>
                      <label class="settings-field">
                        <span>{{ t('common.voice') }}</span>
                        <input
                          v-if="isOfflineCosyVoiceCloneOnlyTTS"
                          v-model="offlineTTSVoice"
                          class="number-input"
                          type="text"
                          :placeholder="t('offlineVideo.cosyVoiceIdPlaceholder')"
                        >
                        <template v-else-if="isOfflineCosyVoiceBuiltinTTS">
                          <div class="cv-pi-segment h-[42px] w-[184px] grid-cols-2 text-[11px]">
                            <button
                              type="button"
                              class="cv-pi-segment-item cursor-pointer"
                              :class="{ 'cv-pi-segment-item--active': offlineCosyVoiceMode === 'official' }"
                              @click="setOfflineCosyVoiceMode('official')"
                            >
                              {{ t('characterEdit.officialVoice') }}
                            </button>
                            <button
                              type="button"
                              class="cv-pi-segment-item cursor-pointer"
                              :class="{ 'cv-pi-segment-item--active': offlineCosyVoiceMode === 'custom' }"
                              @click="setOfflineCosyVoiceMode('custom')"
                            >
                              {{ t('characterEdit.clonedVoice') }}
                            </button>
                          </div>
                          <CvSelect
                            v-if="offlineCosyVoiceMode === 'official'"
                            v-model="offlineTTSVoice"
                            :options="offlineCosyVoiceOfficialOptions"
                            class="mt-3"
                          />
                          <input
                            v-else
                            v-model="offlineTTSVoice"
                            class="number-input mt-3"
                            type="text"
                            :placeholder="t('offlineVideo.cosyVoiceIdPlaceholder')"
                          >
                        </template>
                        <CvSelect
                          v-else
                          v-model="offlineTTSVoice"
                          :options="offlineTTSVoiceOptions"
                          :searchable="offlineTTSProvider === 'doubao'"
                          :search-placeholder="t('common.search')"
                          :empty-label="t('common.noResults')"
                        />
                      </label>
                    </div>
                    <p v-if="isOfflineCosyVoiceCloneOnlyTTS" class="local-tts-hint">{{ t('offlineVideo.cosyVoiceIdHint') }}</p>
                    <p v-else-if="isOfflineCosyVoiceBuiltinTTS" class="local-tts-hint">{{ t('offlineVideo.cosyVoiceBuiltinHint') }}</p>
                    <p v-if="offlineTTSSaveError" class="field-error">{{ offlineTTSSaveError }}</p>
                  </div>
                </template>
              </section>

              <div class="flex justify-end">
                <button class="cv-pi-button cv-pi-button--primary" type="submit" :disabled="!canGenerate">
                  {{ submitting ? t('offlineVideo.submitting') : t('offlineVideo.generate') }}
                </button>
              </div>
            </form>
          </section>
        </div>

        <section class="jobs-section">
          <div class="jobs-header">
            <div class="jobs-title-block">
              <h2>{{ t('offlineVideo.library') }}</h2>
              <p>{{ t('offlineVideo.libraryCount', { count: jobs.length }) }}</p>
            </div>
          </div>
          <div v-if="jobs.length === 0" class="empty-jobs">{{ t('offlineVideo.empty') }}</div>
          <div v-else class="video-grid">
            <article
              v-for="job in pagedJobs"
              :key="job.id"
              class="video-card"
              :class="{
                'video-card--active': isActiveJob(job),
                'video-card--highlight': highlightedJobId === job.id,
              }"
            >
              <button
                v-if="job.status === 'completed' && job.video_url"
                class="video-preview video-preview--playable"
                :class="`video-preview--${job.status}`"
                type="button"
                :aria-label="t('offlineVideo.playVideoAria', { title: job.title })"
                @click="openVideoPlayer(job)"
              >
                <video
                  :src="job.video_url"
                  class="video-preview-media"
                  muted
                  playsinline
                  preload="metadata"
                />
                <span class="video-preview-play-overlay" aria-hidden="true">
                  <span class="video-preview-play-icon">▶</span>
                </span>
              </button>
              <div v-else class="video-preview" :class="`video-preview--${job.status}`">
                <div v-if="isActiveJob(job)" class="video-preview-state">
                  <span class="job-spinner" aria-hidden="true" />
                  <span>{{ statusLabel(job) }}</span>
                </div>
                <button
                  v-else-if="job.status === 'failed'"
                  class="video-preview-state video-preview-button"
                  type="button"
                  :aria-label="t('offlineVideo.viewFailureReason')"
                  @click="openFailedReason(job)"
                >
                  <span class="video-preview-mark">!</span>
                  <span>{{ t('offlineVideo.status.failed') }}</span>
                </button>
                <div v-else class="video-preview-state">
                  <span class="video-preview-mark">▶</span>
                  <span>{{ t('offlineVideo.status.completed') }}</span>
                </div>
              </div>

              <div class="video-card-body">
                <template v-if="editingJobId === job.id">
                  <input
                    v-model="editingTitle"
                    class="rename-input"
                    type="text"
                    :placeholder="t('offlineVideo.titlePlaceholder')"
                    @keydown.enter.prevent="submitRename(job)"
                    @keydown.esc.prevent="cancelRename"
                  >
                  <div class="video-card-actions">
                    <button
                      class="cv-pi-button cv-pi-button--primary cv-pi-button--compact"
                      type="button"
                      :disabled="renaming || !editingTitle.trim()"
                      @click="submitRename(job)"
                    >
                      {{ t('common.save') }}
                    </button>
                    <button class="cv-pi-button cv-pi-button--compact" type="button" @click="cancelRename">
                      {{ t('common.cancel') }}
                    </button>
                  </div>
                </template>
                <template v-else>
                  <button class="video-title" type="button" :title="job.title" @click="startRename(job)">
                    {{ job.title }}
                  </button>
                  <p class="video-date">{{ formatDate(job.created_at) }}</p>
                  <div v-if="isActiveJob(job)" class="video-progress">
                    <div class="progress-track">
                      <div class="progress-bar" :style="progressStyle(job)" />
                    </div>
                  </div>
                  <div class="video-card-actions">
                    <a
                      v-if="job.video_url"
                      class="cv-pi-button cv-pi-button--compact"
                      :href="job.video_url"
                      :download="downloadVideoFilename(job)"
                      :aria-label="t('offlineVideo.downloadVideoAria', { title: job.title })"
                    >
                      {{ t('offlineVideo.downloadVideo') }}
                    </a>
                    <button
                      class="cv-pi-button cv-pi-button--compact"
                      type="button"
                      :disabled="job.status === 'queued' || job.status === 'running'"
                      @click="removeJob(job)"
                    >
                      {{ t('common.delete') }}
                    </button>
                  </div>
                </template>
              </div>
            </article>
          </div>
          <div v-if="jobs.length > JOBS_PER_PAGE" class="video-pagination">
            <span>{{ t('offlineVideo.pagination', { page: currentJobPage, total: totalJobPages }) }}</span>
            <div class="video-pagination-actions">
              <button
                class="cv-pi-button cv-pi-button--compact"
                type="button"
                :disabled="currentJobPage <= 1"
                @click="changeJobPage(currentJobPage - 1)"
              >
                {{ t('offlineVideo.previousPage') }}
              </button>
              <button
                class="cv-pi-button cv-pi-button--compact"
                type="button"
                :disabled="currentJobPage >= totalJobPages"
                @click="changeJobPage(currentJobPage + 1)"
              >
                {{ t('offlineVideo.nextPage') }}
              </button>
            </div>
          </div>
        </section>
      </template>
    </main>

    <div v-if="failedReasonJob" class="failure-modal-backdrop" @click.self="closeFailedReason">
      <section class="failure-modal" role="dialog" aria-modal="true" :aria-label="t('offlineVideo.failureReason')">
        <div class="failure-modal-header">
          <button class="failure-modal-close" type="button" :aria-label="t('offlineVideo.closeFailureReason')" @click="closeFailedReason">
            ×
          </button>
        </div>
        <pre class="failure-modal-message">{{ failedReasonText }}</pre>
      </section>
    </div>

    <div v-if="playingVideoJob?.video_url" class="video-player-modal-backdrop" @click.self="closeVideoPlayer">
      <section class="video-player-modal" role="dialog" aria-modal="true" :aria-label="t('offlineVideo.videoPlayerTitle')">
        <div class="video-player-modal-header">
          <h2>{{ playingVideoJob.title }}</h2>
          <button class="failure-modal-close" type="button" :aria-label="t('offlineVideo.closeVideoPlayer')" @click="closeVideoPlayer">
            ×
          </button>
        </div>
        <video
          ref="videoPlayerRef"
          class="video-player-media"
          :src="playingVideoJob.video_url"
          controls
          playsinline
          preload="metadata"
        />
      </section>
    </div>
  </div>
</template>
<style scoped>
.character-panel,
.production-panel,
.jobs-section {
  border: 1px solid var(--color-cv-border);
  border-radius: 8px;
  background: var(--color-cv-surface);
}

.character-panel {
  display: flex;
  flex-direction: column;
  gap: 20px;
  padding: 22px;
}

.avatar-shell {
  aspect-ratio: 3 / 4;
  overflow: hidden;
  border: 1px solid #2b3542;
  background: #0b0d12;
}

.info-grid {
  display: grid;
  grid-template-columns: 96px minmax(0, 1fr);
  gap: 10px 14px;
  font-size: 13px;
}

.info-grid span {
  color: #798394;
}

.info-grid strong {
  min-width: 0;
  overflow: hidden;
  color: #f0f4f8;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.production-panel {
  padding: 22px;
}

.generator-form {
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.field-label {
  color: #c4ccd8;
  font-size: 12px;
  font-weight: 800;
  letter-spacing: 0;
}

.text-input,
.script-input {
  width: 100%;
  border: 1px solid #303a49;
  background: #0b0d12;
  color: #f4f7fb;
  font-size: 14px;
  outline: none;
}

.text-input {
  min-height: 44px;
  padding: 0 14px;
}

.script-input {
  min-height: 142px;
  resize: vertical;
  padding: 14px;
  line-height: 1.6;
}

.text-input:focus,
.script-input:focus {
  border-color: #34e6f3;
}

.field-hint {
  margin-top: -6px;
  color: #798394;
  font-size: 12px;
  line-height: 18px;
}

.output-settings {
  display: flex;
  flex-direction: column;
  gap: 14px;
  border: 1px solid #242b36;
  background: #0b0d12;
  padding: 16px;
}

.settings-header {
  display: flex;
  align-items: center;
}

.settings-toggle {
  display: flex;
  min-width: 0;
  width: 100%;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  text-align: left;
}

.settings-toggle h3 {
  color: #f4f7fb;
  font-size: 14px;
  font-weight: 800;
}

.settings-chevron {
  display: inline-flex;
  width: 18px;
  height: 18px;
  flex: 0 0 18px;
  align-items: center;
  justify-content: center;
  transform: rotate(180deg);
  transition: transform 160ms ease;
}

.settings-chevron::before {
  width: 8px;
  height: 8px;
  border-bottom: 2px solid #34e6f3;
  border-right: 2px solid #34e6f3;
  content: "";
  transform: rotate(-45deg);
}

.settings-chevron.expanded {
  transform: rotate(90deg);
}

.settings-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
}

.local-tts-status {
  flex: 0 0 auto;
  color: #8dcdd2;
  font-size: 12px;
  font-weight: 700;
}

.local-tts-grid {
  display: grid;
  align-items: start;
  gap: 12px;
  grid-template-columns: minmax(150px, 0.82fr) minmax(240px, 1.45fr) minmax(170px, 1fr);
}

.local-tts-field--model {
  min-width: 240px;
}

.local-tts-hint {
  color: #798394;
  font-size: 12px;
  line-height: 18px;
}

.settings-section {
  border-top: 1px solid #242b36;
  padding-top: 14px;
}

.local-tts-section {
  border-top: 0;
  padding-top: 0;
}

.local-video-output-section {
  border-top: 0;
  padding-top: 0;
}

.local-tts-section--separated {
  border-top: 1px solid #242b36;
  padding-top: 14px;
}

.settings-section-title {
  margin-bottom: 12px;
  color: #f4f7fb;
  font-size: 13px;
  font-weight: 800;
}

.settings-section-title-row {
  display: flex;
  min-width: 0;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.settings-section-title-row .settings-section-title {
  margin-bottom: 12px;
}

.settings-section-title-row--compact {
  position: relative;
  justify-content: flex-start;
  margin-bottom: 12px;
}

.settings-section-title-row--compact .settings-section-title {
  margin-bottom: 0;
}

.settings-help {
  position: relative;
  display: inline-flex;
}

.settings-help-popover {
  position: absolute;
  left: calc(100% + 8px);
  top: 50%;
  z-index: 30;
  width: min(260px, calc(100vw - 72px));
  padding: 10px 12px;
  border: 1px solid #303a49;
  background: #151920;
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.35);
  color: #c4ccd8;
  font-size: 12px;
  font-weight: 500;
  line-height: 18px;
  transform: translateY(-50%);
}

.wide-field {
  grid-column: 1 / -1;
}

.settings-field {
  display: flex;
  min-width: 0;
  position: relative;
  flex-direction: column;
  gap: 8px;
  color: #c4ccd8;
  font-size: 12px;
  font-weight: 800;
}

.field-label-row {
  display: inline-flex;
  min-width: 0;
  align-items: center;
  gap: 6px;
}

.required-mark {
  color: #fca5a5;
}

.field-help {
  position: relative;
  display: inline-flex;
}

.field-help-button {
  display: inline-flex;
  width: 18px;
  height: 18px;
  align-items: center;
  justify-content: center;
  border: 1px solid #303a49;
  border-radius: 999px;
  color: #c4ccd8;
  font-size: 11px;
  font-weight: 800;
  line-height: 1;
  transition: border-color 160ms ease, color 160ms ease, background 160ms ease;
}

.field-help-button:hover,
.field-help-button:focus-visible {
  border-color: #34e6f3;
  background: rgba(52, 230, 243, 0.08);
  color: #f4f7fb;
  outline: none;
}

.field-tooltip {
  position: absolute;
  left: 50%;
  bottom: calc(100% + 8px);
  z-index: 30;
  width: min(320px, calc(100vw - 48px));
  padding: 10px 12px;
  border: 1px solid #303a49;
  background: #151920;
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.35);
  color: #c4ccd8;
  font-size: 12px;
  font-weight: 500;
  line-height: 18px;
  opacity: 0;
  pointer-events: none;
  transform: translate(-50%, 4px);
  transition: opacity 120ms ease, transform 120ms ease;
}

.field-help:hover .field-tooltip,
.field-help:focus-within .field-tooltip {
  opacity: 1;
  pointer-events: auto;
  transform: translate(-50%, 0);
}

.field-tooltip a {
  color: #34e6f3;
  font-weight: 700;
  text-decoration: underline;
  text-underline-offset: 3px;
}

.number-input {
  min-height: 38px;
  width: 100%;
  border: 1px solid #303a49;
  background: #07080b;
  color: #f4f7fb;
  padding: 0 10px;
  font-size: 13px;
  outline: none;
}

.number-input:focus {
  border-color: #34e6f3;
}

.readonly-input {
  cursor: default;
  color: #d7dde8;
}

.local-video-output-input {
  border-color: #242b36;
  background: #151920;
  color: #8d96a6;
  cursor: not-allowed;
}

.audio-upload {
  min-width: 0;
}

.audio-upload-input {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  clip: rect(0 0 0 0);
  clip-path: inset(50%);
  white-space: nowrap;
}

.audio-upload-control {
  display: grid;
  min-height: 64px;
  width: 100%;
  grid-template-columns: 42px minmax(0, 1fr) auto;
  align-items: center;
  gap: 12px;
  border: 1px solid #303a49;
  background: #0b0d12;
  padding: 10px 12px;
  color: #f4f7fb;
  transition: border-color 160ms ease, background 160ms ease, box-shadow 160ms ease;
  cursor: pointer;
}

.audio-upload-control:hover {
  border-color: rgba(141, 205, 210, 0.68);
  background: #0f1218;
}

.audio-upload-input:focus-visible + .audio-upload-control {
  border-color: #34e6f3;
  box-shadow: 0 0 0 2px rgba(52, 230, 243, 0.14);
}

.audio-upload-icon {
  display: inline-flex;
  width: 42px;
  height: 42px;
  align-items: center;
  justify-content: center;
  border: 1px solid rgba(52, 230, 243, 0.24);
  background: rgba(52, 230, 243, 0.06);
  color: #8dcdd2;
}

.audio-upload-copy {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: 4px;
}

.audio-upload-copy strong,
.audio-upload-copy small {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.audio-upload-copy strong {
  color: #f4f7fb;
  font-size: 14px;
  font-weight: 800;
}

.audio-upload-copy small {
  color: #798394;
  font-size: 12px;
  font-weight: 500;
}

.audio-upload-action {
  display: inline-flex;
  min-height: 34px;
  align-items: center;
  justify-content: center;
  border: 1px solid rgba(104, 115, 132, 0.58);
  padding: 0 12px;
  color: rgba(221, 225, 231, 0.86);
  font-size: 12px;
  font-weight: 800;
  white-space: nowrap;
}

.field-error {
  color: #fca5a5;
  font-size: 12px;
  line-height: 1.5;
}

.toggle-field {
  display: inline-flex;
  min-height: 38px;
  align-items: center;
  gap: 10px;
  color: #c4ccd8;
  font-size: 13px;
  font-weight: 700;
}

.toggle-field input {
  width: 16px;
  height: 16px;
  accent-color: #34e6f3;
}

.notice {
  border: 1px solid;
  padding: 10px 12px;
  font-size: 13px;
  line-height: 20px;
}

.notice.warning {
  border-color: rgba(255, 179, 107, 0.3);
  background: rgba(255, 179, 107, 0.08);
  color: #ffca9a;
}

.notice.error,
.job-error {
  color: #fca5a5;
}

.notice.error {
  border-color: rgba(239, 68, 68, 0.35);
  background: rgba(239, 68, 68, 0.1);
}

.jobs-header,
.video-card-actions,
.video-pagination {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.jobs-section {
  padding: 22px;
}

.jobs-header {
  margin-bottom: 16px;
}

.jobs-title-block {
  min-width: 0;
}

.jobs-header h2 {
  color: #fbf6ef;
  font-size: 20px;
  font-weight: 800;
}

.jobs-title-block p {
  margin-top: 6px;
  color: #798394;
  font-size: 12px;
}

.empty-jobs {
  border: 1px dashed #303a49;
  padding: 40px;
  color: #798394;
  text-align: center;
}

.video-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 16px;
}

.video-card {
  display: flex;
  min-width: 0;
  flex-direction: column;
  border: 1px solid #242b36;
  background: #0b0d12;
  transition: border-color 160ms ease, background 160ms ease, box-shadow 160ms ease;
}

.video-card--active {
  border-color: rgba(52, 230, 243, 0.42);
}

.video-card--highlight {
  border-color: rgba(52, 230, 243, 0.76);
  background: rgba(52, 230, 243, 0.035);
  box-shadow: 0 0 0 1px rgba(52, 230, 243, 0.18), 0 0 24px rgba(52, 230, 243, 0.08);
}

.video-preview {
  position: relative;
  display: block;
  width: 100%;
  aspect-ratio: 16 / 9;
  overflow: hidden;
  border: 0;
  border-bottom: 1px solid #242b36;
  background: #07080b;
  padding: 0;
  text-align: left;
}

.video-preview-media {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.video-preview--playable {
  cursor: pointer;
  outline: none;
}

.video-preview--playable::after {
  position: absolute;
  inset: 0;
  background: linear-gradient(180deg, transparent 58%, rgba(0, 0, 0, 0.3));
  content: "";
  opacity: 0.72;
  pointer-events: none;
}

.video-preview-play-overlay {
  position: absolute;
  inset: 0;
  z-index: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.18);
  opacity: 0;
  transition: opacity 160ms ease, background 160ms ease;
}

.video-preview-play-icon {
  display: inline-flex;
  width: 46px;
  height: 46px;
  align-items: center;
  justify-content: center;
  border: 1px solid rgba(244, 247, 251, 0.62);
  background: rgba(7, 8, 11, 0.58);
  color: #f4f7fb;
  font-size: 16px;
  font-weight: 800;
}

.video-preview--playable:hover .video-preview-play-overlay,
.video-preview--playable:focus-visible .video-preview-play-overlay {
  background: rgba(0, 0, 0, 0.28);
  opacity: 1;
}

.video-preview--playable:focus-visible {
  box-shadow: inset 0 0 0 2px #34e6f3;
}

.video-preview-state {
  display: flex;
  width: 100%;
  height: 100%;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  color: #8d96a6;
  font-size: 12px;
  font-weight: 800;
}

.video-preview-button {
  border: 0;
  background: transparent;
  cursor: pointer;
  outline: none;
  transition: background 160ms ease, color 160ms ease;
}

.video-preview-button:hover,
.video-preview-button:focus-visible {
  background: rgba(239, 68, 68, 0.08);
  color: #f3b5b5;
}

.video-preview--queued,
.video-preview--running {
  background:
    linear-gradient(135deg, rgba(52, 230, 243, 0.1), transparent 42%),
    repeating-linear-gradient(135deg, rgba(52, 230, 243, 0.06) 0 1px, transparent 1px 11px),
    #07080b;
}

.video-preview--failed {
  border-color: #303a49;
  background:
    linear-gradient(135deg, rgba(255, 179, 107, 0.06), transparent 42%),
    #07080b;
}

.video-preview-mark {
  display: inline-flex;
  width: 32px;
  height: 32px;
  align-items: center;
  justify-content: center;
  border: 1px solid #303a49;
  color: #f4f7fb;
  font-size: 14px;
  font-weight: 800;
}

.job-spinner {
  width: 16px;
  height: 16px;
  flex: 0 0 16px;
  border: 2px solid rgba(52, 230, 243, 0.2);
  border-top-color: #34e6f3;
  border-radius: 999px;
  animation: job-spin 800ms linear infinite;
}

.rename-input {
  min-width: 0;
  height: 36px;
  width: 100%;
  border: 1px solid #303a49;
  background: #07080b;
  color: #f4f7fb;
  padding: 0 10px;
  font-size: 13px;
  outline: none;
}

.rename-input:focus {
  border-color: #34e6f3;
}

@keyframes job-spin {
  to {
    transform: rotate(360deg);
  }
}

.video-card-body {
  display: flex;
  min-width: 0;
  min-height: 116px;
  flex: 1 1 auto;
  flex-direction: column;
  padding: 12px;
}

.video-title {
  overflow: hidden;
  color: #f4f7fb;
  font-size: 15px;
  font-weight: 800;
  line-height: 21px;
  text-align: left;
  text-overflow: ellipsis;
  white-space: nowrap;
  transition: color 160ms ease;
}

.video-title:hover {
  color: #34e6f3;
}

.video-date {
  margin-top: 4px;
  color: #798394;
  font-size: 12px;
}

.video-progress {
  margin-top: 10px;
}

.progress-track {
  height: 5px;
  overflow: hidden;
  background: #1b222c;
}

.progress-bar {
  height: 100%;
  background: #34e6f3;
  transition: width 200ms ease;
}

.video-card-actions {
  margin-top: auto;
  justify-content: flex-start;
  flex-wrap: wrap;
  gap: 8px;
  padding-top: 12px;
}

.video-pagination {
  margin-top: 18px;
  border-top: 1px solid #242b36;
  padding-top: 16px;
  color: #798394;
  font-size: 12px;
}

.video-pagination-actions {
  display: flex;
  gap: 10px;
}

.failure-modal-backdrop,
.video-player-modal-backdrop {
  position: fixed;
  inset: 0;
  z-index: 80;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.68);
  padding: 24px;
}

.failure-modal {
  position: relative;
  width: min(560px, 100%);
  border: 1px solid #303a49;
  background: #11141b;
  box-shadow: 0 24px 80px rgba(0, 0, 0, 0.38);
  padding: 24px 54px 24px 24px;
}

.failure-modal-header {
  position: absolute;
  top: 12px;
  right: 12px;
}

.failure-modal-close {
  display: inline-flex;
  width: 24px;
  height: 24px;
  flex: 0 0 24px;
  align-items: center;
  justify-content: center;
  border: 1px solid transparent;
  color: #c4ccd8;
  font-size: 18px;
  line-height: 1;
}

.failure-modal-close:hover {
  border-color: #303a49;
  color: #34e6f3;
}

.failure-modal-close:focus-visible {
  border-color: #34e6f3;
  color: #34e6f3;
  outline: none;
}

.failure-modal-message {
  max-height: 260px;
  margin-top: 0;
  overflow: auto;
  color: #d7dde8;
  padding: 0;
  font-family: inherit;
  font-size: 14px;
  line-height: 1.65;
  white-space: pre-wrap;
  word-break: break-word;
}

.video-player-modal {
  display: flex;
  width: min(920px, 100%);
  max-height: calc(100vh - 48px);
  flex-direction: column;
  gap: 14px;
  border: 1px solid #303a49;
  background: #11141b;
  box-shadow: 0 24px 80px rgba(0, 0, 0, 0.38);
  padding: 18px;
}

.video-player-modal-header {
  display: flex;
  min-width: 0;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
}

.video-player-modal-header h2 {
  min-width: 0;
  overflow: hidden;
  color: #f4f7fb;
  font-size: 16px;
  font-weight: 800;
  line-height: 24px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.video-player-media {
  width: 100%;
  max-height: calc(100vh - 146px);
  border: 1px solid #242b36;
  background: #07080b;
  object-fit: contain;
}

@media (max-width: 860px) {
  .settings-grid {
    grid-template-columns: 1fr;
  }

  .local-tts-grid {
    grid-template-columns: 1fr;
  }

  .local-tts-field--model {
    min-width: 0;
  }

  .audio-upload-control {
    grid-template-columns: 38px minmax(0, 1fr);
  }

  .audio-upload-action {
    grid-column: 2;
    justify-self: start;
  }

  .jobs-header {
    align-items: flex-start;
    flex-direction: column;
  }

  .video-grid {
    grid-template-columns: 1fr;
  }

  .video-pagination {
    align-items: flex-start;
    flex-direction: column;
  }

  .video-player-modal {
    padding: 14px;
  }

  .video-player-modal-header h2 {
    font-size: 14px;
    line-height: 20px;
  }
}

@media (max-width: 1180px) and (min-width: 861px) {
  .video-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (max-width: 960px) and (min-width: 681px) {
  .video-grid {
    grid-template-columns: 1fr;
  }
}
</style>
