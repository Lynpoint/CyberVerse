<script setup lang="ts">
import { ref, computed, nextTick, onMounted, watch } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import AppHeader from '../components/AppHeader.vue'
import AvatarUpload from '../components/AvatarUpload.vue'
import CvSelect from '../components/CvSelect.vue'
import KnowledgeSourceManager from '../components/KnowledgeSourceManager.vue'
import { useCharacterStore } from '../stores/characters'
import type { AgentExtensionConfig, AvatarBackend, BaiduXilingCharacterConfig, CharacterComponents, CharacterForm, ComponentOption, ComponentsResponse, ImageInfo, XunfeiAvatarConfig } from '../types'
import { DOUBAO_TTS_VOICE_OPTIONS, GEMINI_LIVE_VOICE_OPTIONS, GROK_VOICE_OPTIONS, OPENAI_REALTIME_VOICE_OPTIONS, OPENAI_VOICE_OPTIONS, QWEN_OMNI_VOICE_OPTIONS, QWEN_TTS_MODEL_OPTIONS, QWEN_TTS_VOICE_OPTIONS, VOICE_OPTIONS } from '../types'
import { uploadAvatar, getCharacterImages, deleteCharacterImage, activateCharacterImage, testCharacterVoice, getComponents, getBaiduXilingFigure, getXunfeiAvatar } from '../services/api'
import {
  DEFAULT_COSYVOICE_V3_VOICE,
  DEFAULT_DOUBAO_TTS_VOICE,
  DEFAULT_GEMINI_LIVE_VOICE,
  DEFAULT_GROK_VOICE,
  DEFAULT_OPENAI_REALTIME_VOICE,
  DEFAULT_OFFICIAL_VOICE,
  DEFAULT_QWEN_OMNI_VOICE,
  DEFAULT_QWEN_TTS_VOICE,
  cosyVoiceBuiltinVoiceOptions,
  isCosyVoiceBuiltinModel,
  isCosyVoiceBuiltinVoice,
  isCosyVoiceCloneOnlyModel,
  isCosyVoiceKnownBuiltinVoice,
  isCosyVoiceTTSModel,
  isDoubaoTTSVoiceType,
  isGeminiLiveVoiceType,
  isGrokVoiceType,
  isOfficialVoiceType,
  isOpenAIRealtimeVoiceType,
  isOpenAIVoiceType,
  isQwenOmniVoiceType,
  isQwenTTSVoiceType,
  localizedVoiceOptions,
} from '../utils/voice'

const router = useRouter()
const route = useRoute()
const store = useCharacterStore()
const { t, locale } = useI18n()

const isEdit = computed(() => !!route.params.id)
const characterId = computed(() => route.params.id as string)

const DEFAULT_COMPONENTS: CharacterComponents = { llm: 'qwen', asr: 'qwen', tts: 'qwen' }

const form = ref<CharacterForm>({
  name: '',
  description: '',
  avatar_image: '',
  avatar_backend: 'local_image',
  baidu_xiling: null,
  xunfei: null,
  offline_video_tts: null,
  use_face_crop: false,
  image_mode: 'fixed',
  mode: 'standard',
  voice_provider: 'qwen',
  voice_type: DEFAULT_QWEN_TTS_VOICE,
  components: { ...DEFAULT_COMPONENTS },
  speaking_style: '',
  personality: '',
  welcome_message: '',
  system_prompt: '',
  tags: [],
  agent_extensions: [],
})

const saving = ref(false)
const pendingFiles = ref<File[]>([])
const images = ref<ImageInfo[]>([])
const deletedImageFilenames = ref<Set<string>>(new Set())
const voiceMode = ref<'official' | 'custom'>('official')
const cosyVoiceMode = ref<'official' | 'custom'>('official')
const customVoiceType = ref('')
const voiceError = ref('')
const testingVoice = ref(false)
const voiceTestStatus = ref<'success' | 'error' | null>(null)
const voiceTestMessage = ref('')
const showModeHelp = ref(false)
const hydratingCharacter = ref(false)
const baiduLookupLoading = ref(false)
const baiduLookupError = ref('')
const xunfeiLookupLoading = ref(false)
const xunfeiLookupError = ref('')
const OFFICIAL_VOICE_PREVIEW_URL = 'https://console.volcengine.com/speech/new/experience/call'
const CUSTOM_VOICE_CLONE_URL = 'https://console.volcengine.com/speech/new/experience/clone'
const DOUBAO_TTS_VOICE_LIST_URL = 'https://www.volcengine.com/docs/6561/1257544?lang=zh#%E8%B1%86%E5%8C%85%E8%AF%AD%E9%9F%B3%E5%90%88%E6%88%90%E6%A8%A1%E5%9E%8B2-0-%E9%9F%B3%E8%89%B2%E5%88%97%E8%A1%A8'
const QWEN_TTS_VOICE_PREVIEW_URL = 'https://help.aliyun.com/zh/model-studio/qwen-tts-voice-list'
const COSYVOICE_VOICE_LIST_URL = 'https://help.aliyun.com/zh/model-studio/cosyvoice-voice-list'
const QWEN_OMNI_VOICE_LIST_URL = 'https://help.aliyun.com/zh/model-studio/omni-voice-list'
const BAIDU_XILING_OVERVIEW_URL = 'https://xiling.cloud.baidu.com/open/overview'
const PI_PACKAGES_URL = 'https://pi.dev/packages'
const componentCatalog = ref<ComponentsResponse>({
  llm: [{ id: 'qwen', name: 'Qwen', model: 'qwen3.6-plus', default: true, available: true }],
  asr: [{ id: 'qwen', name: 'Qwen', model: 'qwen3-asr-flash-realtime', default: true, available: true }],
  tts: [{ id: 'qwen', name: 'Qwen', model: 'qwen3-tts-flash-realtime', default: true, available: true }],
})

const visibleImages = computed(() =>
  images.value.filter(img => !deletedImageFilenames.value.has(img.filename))
)

const isBaiduXilingAvatar = computed(() => form.value.avatar_backend === 'baidu_xiling')
const isLocalAvatar = computed(() => form.value.avatar_backend === 'local_image')
const isViduAvatar = computed(() => form.value.avatar_backend === 'vidu')
const usesUploadedAvatar = computed(() => isLocalAvatar.value || isViduAvatar.value)
const baiduFigureId = computed({
  get: () => form.value.baidu_xiling?.figure_id || '',
  set: (value: string) => {
    form.value.baidu_xiling = {
      ...(form.value.baidu_xiling || { figure_id: '' }),
      figure_id: value,
    }
    baiduLookupError.value = ''
  },
})
const baiduPreviewImage = computed(() =>
  form.value.baidu_xiling?.thumbnail_url
  || form.value.baidu_xiling?.source_image_url
  || ''
)
const baiduFigureLabel = computed(() =>
  form.value.baidu_xiling?.figure_name
  || form.value.baidu_xiling?.figure_id
  || ''
)
const xunfeiAvatarId = computed({
  get: () => form.value.xunfei?.avatar_id || '',
  set: (value: string) => {
    form.value.xunfei = {
      ...(form.value.xunfei || emptyXunfeiConfig()),
      avatar_id: value,
    }
    xunfeiLookupError.value = ''
  },
})
const xunfeiSceneId = computed({
  get: () => form.value.xunfei?.scene_id || '',
  set: (value: string) => {
    form.value.xunfei = {
      ...(form.value.xunfei || emptyXunfeiConfig()),
      scene_id: value,
    }
  },
})
const xunfeiVcn = computed({
  get: () => form.value.xunfei?.vcn || '',
  set: (value: string) => {
    form.value.xunfei = {
      ...(form.value.xunfei || emptyXunfeiConfig()),
      vcn: value,
    }
  },
})
const xunfeiPreviewImage = computed(() =>
  form.value.xunfei?.thumbnail_url
  || form.value.xunfei?.source_image_url
  || ''
)
const xunfeiAvatarLabel = computed(() =>
  form.value.xunfei?.avatar_name
  || form.value.xunfei?.avatar_id
  || ''
)
const hasRequiredAvatarConfig = computed(() => {
  if (form.value.avatar_backend === 'baidu_xiling') {
    return !!baiduFigureId.value.trim()
  }
  if (form.value.avatar_backend === 'xunfei') {
    return !!xunfeiAvatarId.value.trim()
  }
  if (form.value.avatar_backend === 'vidu') {
    return isEdit.value ? visibleImages.value.length > 0 : pendingFiles.value.length > 0
  }
  return true
})
const avatarBackendModel = computed({
  get: () => form.value.avatar_backend,
  set: (value: string) => selectAvatarBackend(normalizeAvatarBackend(value)),
})
const avatarBackendOptions = computed(() => [
  { label: t('characterEdit.localAvatar'), value: 'local_image' },
  { label: t('characterEdit.baiduDigitalHuman'), value: 'baidu_xiling' },
  { label: t('characterEdit.xunfeiDigitalHuman'), value: 'xunfei' },
  { label: t('characterEdit.viduS1'), value: 'vidu' },
])
const trimmedCustomVoiceType = computed(() => customVoiceType.value.trim())
const selectedTTS = computed(() => form.value.components?.tts || DEFAULT_COMPONENTS.tts)
const selectedTTSModel = computed(() => form.value.components?.tts_model || selectedComponent('tts')?.model || '')
const selectedOmniProvider = computed(() => form.value.voice_provider || 'doubao')
const usesDoubaoTTS = computed(() => form.value.mode !== 'omni' && selectedTTS.value === 'doubao')
const usesDoubaoOmniVoice = computed(() => form.value.mode === 'omni' && selectedOmniProvider.value === 'doubao')
const usesDoubaoVoice = computed(() => usesDoubaoTTS.value || usesDoubaoOmniVoice.value)
const usesCosyVoiceTTS = computed(() =>
  form.value.mode !== 'omni'
  && selectedTTS.value === 'qwen'
  && isCosyVoiceTTSModel(selectedTTSModel.value)
)
const usesCosyVoiceCloneOnlyTTS = computed(() =>
  usesCosyVoiceTTS.value && isCosyVoiceCloneOnlyModel(selectedTTSModel.value)
)
const usesCosyVoiceBuiltinTTS = computed(() =>
  usesCosyVoiceTTS.value && isCosyVoiceBuiltinModel(selectedTTSModel.value)
)
const usesQwenOmniVoice = computed(() =>
  form.value.mode === 'omni' && selectedOmniProvider.value === 'qwen_omni'
)
const usesGrokVoice = computed(() =>
  form.value.mode === 'omni' && selectedOmniProvider.value === 'grok'
)
const usesGeminiLiveVoice = computed(() =>
  form.value.mode === 'omni' && selectedOmniProvider.value === 'gemini'
)
const usesOpenAIRealtimeVoice = computed(() =>
  form.value.mode === 'omni' && selectedOmniProvider.value === 'openai_realtime'
)
const isOpenAIVoice = computed(() => !usesDoubaoVoice.value && selectedTTS.value === 'openai')
const omniProviderOptions = computed(() => [
  { label: t('settings.doubaoVoice'), value: 'doubao' },
  { label: 'Qwen Omni', value: 'qwen_omni' },
  { label: 'Grok Voice Think Fast 1.0', value: 'grok' },
  { label: 'Gemini 3.1 Flash Live', value: 'gemini' },
  { label: 'GPT Realtime 1.5', value: 'openai_realtime' },
])
const omniModelLabel = computed(() => {
  if (selectedOmniProvider.value === 'grok') return 'grok-voice-think-fast-1.0'
  if (selectedOmniProvider.value === 'gemini') return 'gemini-3.1-flash-live-preview'
  if (selectedOmniProvider.value === 'openai_realtime') return 'gpt-realtime-1.5'
  if (selectedOmniProvider.value === 'qwen_omni') return 'qwen3.5-omni-flash-realtime'
  return 'Doubao Realtime'
})
const providerSelectOptions = (items: ComponentOption[]) =>
  items.map(item => ({
    label: item.name,
    value: item.id,
  }))
const llmProviderOptions = computed(() => providerSelectOptions(componentCatalog.value.llm))
const asrProviderOptions = computed(() => providerSelectOptions(componentCatalog.value.asr))
const ttsProviderOptions = computed(() => providerSelectOptions(componentCatalog.value.tts))
function selectedComponent(category: 'llm' | 'asr' | 'tts') {
  const selected = form.value.components?.[category] || DEFAULT_COMPONENTS[category]
  return componentCatalog.value[category].find(item => item.id === selected)
}
function modelOptions(category: 'llm' | 'asr' | 'tts') {
  if (category === 'tts' && selectedTTS.value === 'qwen') {
    const currentModel = selectedTTSModel.value
    const hasCurrent = QWEN_TTS_MODEL_OPTIONS.some(option => option.value === currentModel)
    return hasCurrent || !currentModel
      ? QWEN_TTS_MODEL_OPTIONS
      : [{ label: currentModel, value: currentModel }, ...QWEN_TTS_MODEL_OPTIONS]
  }
  const model = selectedComponent(category)?.model || ''
  return model ? [{ label: model, value: model }] : []
}
const llmModel = computed({
  get: () => selectedComponent('llm')?.model || '',
  set: () => {},
})
const asrModel = computed({
  get: () => selectedComponent('asr')?.model || '',
  set: () => {},
})
const ttsModel = computed({
  get: () => selectedTTSModel.value,
  set: (value: string) => {
    form.value.components.tts_model = value
  },
})
const llmModelOptions = computed(() => modelOptions('llm'))
const asrModelOptions = computed(() => modelOptions('asr'))
const ttsModelOptions = computed(() => modelOptions('tts'))
const qwenTTSVoiceOptions = computed(() => localizedVoiceOptions(QWEN_TTS_VOICE_OPTIONS, locale.value))
const cosyVoiceOfficialOptions = computed(() => localizedVoiceOptions(
  cosyVoiceBuiltinVoiceOptions(selectedTTSModel.value),
  locale.value,
))
const qwenOmniVoiceOptions = computed(() => localizedVoiceOptions(QWEN_OMNI_VOICE_OPTIONS, locale.value))
const grokVoiceOptions = computed(() => localizedVoiceOptions(GROK_VOICE_OPTIONS, locale.value))
const geminiLiveVoiceOptions = computed(() => localizedVoiceOptions(GEMINI_LIVE_VOICE_OPTIONS, locale.value))
const openAIRealtimeVoiceOptions = computed(() => localizedVoiceOptions(OPENAI_REALTIME_VOICE_OPTIONS, locale.value))
const officialVoiceOptions = computed(() => localizedVoiceOptions(
  usesDoubaoTTS.value ? DOUBAO_TTS_VOICE_OPTIONS : VOICE_OPTIONS,
  locale.value,
))
const openAIVoiceOptions = computed(() => localizedVoiceOptions(OPENAI_VOICE_OPTIONS, locale.value))
const canSave = computed(() =>
  !!form.value.name.trim() && hasRequiredAvatarConfig.value && (
    isViduAvatar.value
      ? isQwenOmniVoiceType(form.value.voice_type)
      : usesDoubaoVoice.value
      ? (voiceMode.value === 'official' || !!trimmedCustomVoiceType.value)
      : !!form.value.voice_type.trim()
  )
)
const canCheckVoice = computed(() =>
  (usesDoubaoVoice.value && (voiceMode.value === 'official' || !!trimmedCustomVoiceType.value))
  || ((usesQwenOmniVoice.value || usesGrokVoice.value || usesGeminiLiveVoice.value || usesOpenAIRealtimeVoice.value) && !!form.value.voice_type.trim())
  || (form.value.mode !== 'omni' && selectedTTS.value === 'qwen' && !!form.value.voice_type.trim())
  || (isOpenAIVoice.value && !!form.value.voice_type.trim())
)
const voiceCheckSucceeded = computed(() => voiceTestStatus.value === 'success')

function normalizeComponents(components?: Partial<CharacterComponents>): CharacterComponents {
  return {
    llm: components?.llm || DEFAULT_COMPONENTS.llm,
    asr: components?.asr || DEFAULT_COMPONENTS.asr,
    tts: components?.tts || DEFAULT_COMPONENTS.tts,
    tts_model: components?.tts_model || '',
  }
}

function normalizeAgentExtensionSource(value?: string): string {
  return (value || '').trim()
}

function normalizeAgentExtensions(extensions?: AgentExtensionConfig[]): AgentExtensionConfig[] {
  if (!Array.isArray(extensions)) return []
  return extensions
    .map(extension => ({
      name: (extension.name || '').trim(),
      url: normalizeAgentExtensionSource(extension.url),
      enabled: extension.enabled !== false,
    }))
    .filter(extension => extension.url)
}

function addAgentExtension() {
  form.value.agent_extensions = [
    ...(form.value.agent_extensions || []),
    { name: '', url: '', enabled: true },
  ]
}

function removeAgentExtension(index: number) {
  form.value.agent_extensions = (form.value.agent_extensions || []).filter((_, i) => i !== index)
}

function defaultModelForTTS(tts: string): string {
  if (tts === 'qwen') {
    return QWEN_TTS_MODEL_OPTIONS[0]?.value || selectedComponent('tts')?.model || ''
  }
  return selectedComponent('tts')?.model || ''
}

function isPresetVoice(value: string): boolean {
  return isQwenTTSVoiceType(value)
    || isOpenAIVoiceType(value)
    || isQwenOmniVoiceType(value)
    || isOfficialVoiceType(value)
    || isDoubaoTTSVoiceType(value)
    || isGeminiLiveVoiceType(value)
    || isOpenAIRealtimeVoiceType(value)
    || isCosyVoiceKnownBuiltinVoice(value)
}

function defaultDoubaoVoice() {
  return usesDoubaoTTS.value ? DEFAULT_DOUBAO_TTS_VOICE : DEFAULT_OFFICIAL_VOICE
}

function isCurrentDoubaoOfficialVoice(value: string): boolean {
  return usesDoubaoTTS.value ? isDoubaoTTSVoiceType(value) : isOfficialVoiceType(value)
}

function defaultVoiceForTTS(tts: string) {
  if (tts === 'openai') return 'nova'
  if (tts === 'doubao') return DEFAULT_DOUBAO_TTS_VOICE
  if (tts === 'qwen' && usesCosyVoiceCloneOnlyTTS.value) return ''
  if (tts === 'qwen' && usesCosyVoiceBuiltinTTS.value) return DEFAULT_COSYVOICE_V3_VOICE
  return DEFAULT_QWEN_TTS_VOICE
}

function defaultVoiceForOmni(provider: string) {
  if (provider === 'grok') return DEFAULT_GROK_VOICE
  if (provider === 'gemini') return DEFAULT_GEMINI_LIVE_VOICE
  if (provider === 'openai_realtime') return DEFAULT_OPENAI_REALTIME_VOICE
  return provider === 'qwen_omni' ? DEFAULT_QWEN_OMNI_VOICE : DEFAULT_OFFICIAL_VOICE
}

function normalizeOmniProvider(provider: string) {
  if (provider === 'qwen_omni' || provider === 'grok' || provider === 'gemini' || provider === 'openai_realtime') return provider
  return 'doubao'
}

function normalizeMode(mode?: string): CharacterForm['mode'] {
  return mode === 'omni' || mode === 'voice_llm' ? 'omni' : 'standard'
}

function normalizeAvatarBackend(backend?: string): AvatarBackend {
  if (backend === 'baidu_xiling') return 'baidu_xiling'
  if (backend === 'xunfei') return 'xunfei'
  if (backend === 'vidu') return 'vidu'
  return 'local_image'
}

function emptyBaiduXilingConfig(figureId = ''): BaiduXilingCharacterConfig {
  return { figure_id: figureId }
}

function emptyXunfeiConfig(): XunfeiAvatarConfig {
  return {
    avatar_id: '',
    avatar_name: '',
    scene_id: '',
    vcn: '',
    vcns: [],
    thumbnail_url: '',
    preview_video_url: '',
    source_image_url: '',
    status: '',
    protocol: 'flv',
    width: 720,
    height: 1280,
    fps: 25,
    bitrate: 2000,
    speed: 50,
    pitch: 50,
    volume: 50,
    air: 0,
  }
}

function selectAvatarBackend(backend: AvatarBackend) {
  form.value.avatar_backend = backend
  baiduLookupError.value = ''
  xunfeiLookupError.value = ''
  if (backend === 'vidu' && !isQwenOmniVoiceType(form.value.voice_type)) {
    form.value.voice_type = DEFAULT_QWEN_OMNI_VOICE
  }
  if (backend === 'baidu_xiling' && !form.value.baidu_xiling) {
    form.value.baidu_xiling = emptyBaiduXilingConfig()
  }
  if (backend === 'xunfei' && !form.value.xunfei) {
    form.value.xunfei = emptyXunfeiConfig()
  }
}

function applyBaiduFigure(figure: BaiduXilingCharacterConfig) {
  const figureName = figure.figure_name || ''
  form.value.baidu_xiling = {
    figure_id: figure.figure_id || baiduFigureId.value.trim(),
    figure_name: figureName,
    thumbnail_url: figure.thumbnail_url || '',
    preview_video_url: figure.preview_video_url || '',
    source_image_url: figure.source_image_url || '',
    status: figure.status || '',
    width: figure.width || 0,
    height: figure.height || 0,
  }
  if (figureName) {
    form.value.name = figureName
  }
}

async function lookupBaiduFigure() {
  const figureId = baiduFigureId.value.trim()
  baiduLookupError.value = ''
  if (!figureId) {
    baiduLookupError.value = t('characterEdit.baiduFigureRequired')
    return
  }
  baiduLookupLoading.value = true
  try {
    const figure = await getBaiduXilingFigure(figureId)
    applyBaiduFigure(figure)
  } catch (e) {
    form.value.baidu_xiling = {
      ...(form.value.baidu_xiling || emptyBaiduXilingConfig()),
      figure_id: figureId,
    }
    baiduLookupError.value = e instanceof Error ? e.message : String(e)
  } finally {
    baiduLookupLoading.value = false
  }
}

function applyXunfeiAvatar(avatar: XunfeiAvatarConfig) {
  const avatarName = avatar.avatar_name || ''
  form.value.xunfei = {
    ...emptyXunfeiConfig(),
    ...(form.value.xunfei || {}),
    avatar_id: avatar.avatar_id || xunfeiAvatarId.value.trim(),
    avatar_name: avatarName,
    scene_id: avatar.scene_id || xunfeiSceneId.value.trim(),
    vcn: xunfeiVcn.value.trim(),
    vcns: avatar.vcns || [],
    thumbnail_url: avatar.thumbnail_url || '',
    preview_video_url: avatar.preview_video_url || '',
    source_image_url: avatar.source_image_url || '',
    status: avatar.status || '',
    width: avatar.width || 720,
    height: avatar.height || 1280,
  }
  if (avatarName) {
    form.value.name = avatarName
  }
}

async function lookupXunfeiAvatar() {
  const avatarId = xunfeiAvatarId.value.trim()
  xunfeiLookupError.value = ''
  if (!avatarId) {
    xunfeiLookupError.value = t('characterEdit.xunfeiAvatarRequired')
    return
  }
  xunfeiLookupLoading.value = true
  try {
    const avatar = await getXunfeiAvatar(avatarId)
    applyXunfeiAvatar(avatar)
  } catch (e) {
    form.value.xunfei = {
      ...(form.value.xunfei || emptyXunfeiConfig()),
      avatar_id: avatarId,
    }
    xunfeiLookupError.value = e instanceof Error ? e.message : String(e)
  } finally {
    xunfeiLookupLoading.value = false
  }
}

function applyTTSVoiceDefault(tts: string, force = false) {
  if (form.value.mode === 'omni') {
    return
  }
  form.value.voice_provider = tts
  const current = form.value.voice_type.trim()
  if (tts === 'qwen' && usesCosyVoiceCloneOnlyTTS.value) {
    cosyVoiceMode.value = 'custom'
    if (!current || isPresetVoice(current)) {
      form.value.voice_type = ''
    }
    return
  }

  if (tts === 'qwen' && usesCosyVoiceBuiltinTTS.value) {
    if (cosyVoiceMode.value === 'custom') {
      if (!current || isPresetVoice(current)) {
        form.value.voice_type = ''
      }
      return
    }
    if (current && isCosyVoiceBuiltinVoice(selectedTTSModel.value, current)) {
      cosyVoiceMode.value = 'official'
      return
    }
    if (current && !isPresetVoice(current)) {
      cosyVoiceMode.value = 'custom'
      return
    }
    form.value.voice_type = defaultVoiceForTTS(tts)
    cosyVoiceMode.value = 'official'
    return
  }

  if (force || !current) {
    form.value.voice_type = defaultVoiceForTTS(tts)
    if (tts === 'doubao') syncVoiceInputs(form.value.voice_type)
    return
  }

  if (tts === 'qwen' && !isQwenTTSVoiceType(current)) {
    form.value.voice_type = DEFAULT_QWEN_TTS_VOICE
  } else if (tts === 'openai' && !isOpenAIVoiceType(current)) {
    form.value.voice_type = 'nova'
  } else if (tts === 'doubao') {
    const looksLikeOtherDoubaoModeVoice = usesDoubaoTTS.value
      ? isOfficialVoiceType(current)
      : isDoubaoTTSVoiceType(current)
    const looksLikeNonDoubaoVoice = isQwenTTSVoiceType(current)
      || isOpenAIVoiceType(current)
      || isQwenOmniVoiceType(current)
      || isGrokVoiceType(current)
      || isGeminiLiveVoiceType(current)
      || isOpenAIRealtimeVoiceType(current)
      || looksLikeOtherDoubaoModeVoice
    syncVoiceInputs(looksLikeNonDoubaoVoice ? defaultVoiceForTTS(tts) : current)
  }
}

function applyModeVoiceDefault(force = false) {
  if (form.value.mode !== 'omni') {
    applyTTSVoiceDefault(form.value.components.tts, force)
    return
  }

  form.value.voice_provider = normalizeOmniProvider(form.value.voice_provider)
  const current = form.value.voice_type.trim()
  const provider = form.value.voice_provider

  if (provider === 'qwen_omni') {
    if (force || !current || !isQwenOmniVoiceType(current)) {
      form.value.voice_type = DEFAULT_QWEN_OMNI_VOICE
    }
    voiceMode.value = 'official'
    customVoiceType.value = ''
    return
  }

  if (provider === 'grok') {
    if (force || !current || !isGrokVoiceType(current)) {
      form.value.voice_type = DEFAULT_GROK_VOICE
    }
    voiceMode.value = 'official'
    customVoiceType.value = ''
    return
  }

  if (provider === 'gemini') {
    if (force || !current || !isGeminiLiveVoiceType(current)) {
      form.value.voice_type = DEFAULT_GEMINI_LIVE_VOICE
    }
    voiceMode.value = 'official'
    customVoiceType.value = ''
    return
  }

  if (provider === 'openai_realtime') {
    if (force || !current || !isOpenAIRealtimeVoiceType(current)) {
      form.value.voice_type = DEFAULT_OPENAI_REALTIME_VOICE
    }
    voiceMode.value = 'official'
    customVoiceType.value = ''
    return
  }

  const looksLikeNonDoubaoVoice = isQwenTTSVoiceType(current)
    || isOpenAIVoiceType(current)
    || isQwenOmniVoiceType(current)
    || isGrokVoiceType(current)
    || isGeminiLiveVoiceType(current)
    || isOpenAIRealtimeVoiceType(current)
    || isDoubaoTTSVoiceType(current)
  if (force || !current || looksLikeNonDoubaoVoice) {
    form.value.voice_type = defaultVoiceForOmni(provider)
  }
  syncVoiceInputs(form.value.voice_type)
}

function toggleMode() {
  form.value.mode = form.value.mode === 'standard' ? 'omni' : 'standard'
  showModeHelp.value = false
}

function clearVoiceTestResult() {
  voiceTestStatus.value = null
  voiceTestMessage.value = ''
}

function syncVoiceInputs(voiceType: string) {
  const normalized = voiceType.trim()
  if (normalized && !isCurrentDoubaoOfficialVoice(normalized)) {
    voiceMode.value = 'custom'
    customVoiceType.value = normalized
    form.value.voice_type = normalized
    return
  }

  voiceMode.value = 'official'
  customVoiceType.value = ''
  form.value.voice_type = normalized || defaultDoubaoVoice()
}

function setVoiceMode(mode: 'official' | 'custom') {
  voiceMode.value = mode
  voiceError.value = ''

  if (mode === 'official') {
    if (!isCurrentDoubaoOfficialVoice(form.value.voice_type)) {
      form.value.voice_type = defaultDoubaoVoice()
    }
    return
  }

  if (!isCurrentDoubaoOfficialVoice(form.value.voice_type)) {
    customVoiceType.value = form.value.voice_type.trim()
  }
}

function setCosyVoiceMode(mode: 'official' | 'custom') {
  cosyVoiceMode.value = mode
  voiceError.value = ''
  if (mode === 'official') {
    if (!isCosyVoiceBuiltinVoice(selectedTTSModel.value, form.value.voice_type)) {
      form.value.voice_type = defaultVoiceForTTS(selectedTTS.value)
    }
  } else if (isPresetVoice(form.value.voice_type.trim())) {
    form.value.voice_type = ''
  }
}

function resolveVoiceType() {
  if (isViduAvatar.value) {
    const voice = form.value.voice_type.trim()
    form.value.voice_type = isQwenOmniVoiceType(voice) ? voice : DEFAULT_QWEN_OMNI_VOICE
    return form.value.voice_type
  }

  if (usesQwenOmniVoice.value) {
    const voice = form.value.voice_type.trim() || DEFAULT_QWEN_OMNI_VOICE
    form.value.voice_type = voice
    return voice
  }

  if (usesGrokVoice.value) {
    const voice = form.value.voice_type.trim() || DEFAULT_GROK_VOICE
    form.value.voice_type = isGrokVoiceType(voice) ? voice : DEFAULT_GROK_VOICE
    return form.value.voice_type
  }

  if (usesGeminiLiveVoice.value) {
    const voice = form.value.voice_type.trim() || DEFAULT_GEMINI_LIVE_VOICE
    form.value.voice_type = isGeminiLiveVoiceType(voice) ? voice : DEFAULT_GEMINI_LIVE_VOICE
    return form.value.voice_type
  }

  if (usesOpenAIRealtimeVoice.value) {
    const voice = form.value.voice_type.trim() || DEFAULT_OPENAI_REALTIME_VOICE
    form.value.voice_type = isOpenAIRealtimeVoiceType(voice) ? voice : DEFAULT_OPENAI_REALTIME_VOICE
    return form.value.voice_type
  }

  if (!usesDoubaoVoice.value) {
    applyTTSVoiceDefault(selectedTTS.value)
    const voice = form.value.voice_type.trim() || defaultVoiceForTTS(selectedTTS.value)
    if (usesCosyVoiceCloneOnlyTTS.value && !voice) {
      voiceError.value = t('characterEdit.cosyVoiceIdRequired')
      return null
    }
    if (usesCosyVoiceBuiltinTTS.value) {
      if (cosyVoiceMode.value === 'custom' && !voice) {
        voiceError.value = t('characterEdit.cosyVoiceIdRequired')
        return null
      }
      if (cosyVoiceMode.value === 'official' && !isCosyVoiceBuiltinVoice(selectedTTSModel.value, voice)) {
        form.value.voice_type = defaultVoiceForTTS(selectedTTS.value)
        return form.value.voice_type
      }
    }
    return voice
  }

  if (voiceMode.value === 'custom') {
    if (!trimmedCustomVoiceType.value) {
      voiceError.value = t('characterEdit.customSpeakerRequired')
      return null
    }
    return trimmedCustomVoiceType.value
  }

  return form.value.voice_type.trim() || defaultDoubaoVoice()
}

function resolveVoiceProviderForCheck() {
  if (form.value.mode === 'omni') return form.value.voice_provider.trim()
  return selectedTTS.value
}

watch(
  [
    () => form.value.voice_provider,
    () => form.value.voice_type,
    () => form.value.mode,
    () => form.value.components.tts,
    () => selectedTTSModel.value,
    () => voiceMode.value,
    () => cosyVoiceMode.value,
    () => customVoiceType.value,
  ],
  () => {
    clearVoiceTestResult()
  }
)

watch(
  () => form.value.components.tts,
  (tts) => {
    if (hydratingCharacter.value) return
    voiceError.value = ''
    form.value.components.tts_model = defaultModelForTTS(tts)
    applyTTSVoiceDefault(tts, true)
  }
)

watch(
  () => selectedTTSModel.value,
  () => {
    if (hydratingCharacter.value || form.value.mode === 'omni') return
    voiceError.value = ''
    applyTTSVoiceDefault(selectedTTS.value, true)
  }
)

watch(
  () => form.value.mode,
  () => {
    if (hydratingCharacter.value) return
    voiceError.value = ''
    applyModeVoiceDefault(true)
  }
)

watch(
  () => form.value.voice_provider,
  () => {
    if (hydratingCharacter.value) return
    if (form.value.mode === 'omni') {
      voiceError.value = ''
      applyModeVoiceDefault(true)
    }
  }
)

onMounted(async () => {
  try {
    componentCatalog.value = await getComponents()
  } catch (e) {
    console.warn('Failed to load components:', e)
  }

  if (isEdit.value) {
    await store.fetchOne(characterId.value)
    if (store.current) {
      const c = store.current
      hydratingCharacter.value = true
      try {
        form.value = {
          name: c.name,
          description: c.description,
          avatar_image: c.avatar_image,
          avatar_backend: normalizeAvatarBackend(c.avatar_backend),
          baidu_xiling: c.baidu_xiling ? { ...c.baidu_xiling } : null,
          xunfei: c.xunfei ? { ...emptyXunfeiConfig(), ...c.xunfei } : null,
          offline_video_tts: c.offline_video_tts ? { ...c.offline_video_tts } : null,
          use_face_crop: c.use_face_crop,
          image_mode: c.image_mode || 'fixed',
          mode: normalizeMode(c.mode),
          voice_provider: c.voice_provider,
          voice_type: c.voice_type,
          components: normalizeComponents(c.components),
          speaking_style: c.speaking_style,
          personality: c.personality,
          welcome_message: c.welcome_message,
          system_prompt: c.system_prompt,
          tags: [...c.tags],
          agent_extensions: normalizeAgentExtensions(c.agent_extensions),
        }
        if (isViduAvatar.value) {
          if (!isQwenOmniVoiceType(form.value.voice_type)) {
            form.value.voice_type = DEFAULT_QWEN_OMNI_VOICE
          }
        } else {
          applyModeVoiceDefault(!form.value.voice_type)
        }
        await nextTick()
      } finally {
        hydratingCharacter.value = false
      }
      await loadImages()
    }
  } else {
    applyModeVoiceDefault(true)
  }
})

async function loadImages() {
  if (!isEdit.value) return
  try {
    images.value = await getCharacterImages(characterId.value)
  } catch {
    images.value = []
  }
}

async function handleFileSelected(file: File, options?: { activate?: boolean }) {
  if (!usesUploadedAvatar.value) return
  if (isEdit.value) {
    // Edit mode: upload immediately
    try {
      const existingFilenames = new Set(images.value.map(img => img.filename))
      const uploaded = await uploadAvatar(characterId.value, file)
      await loadImages()
      const uploadedFilename = uploaded.filename || images.value.find(img => !existingFilenames.has(img.filename))?.filename
      if (options?.activate && uploadedFilename) {
        await activateCharacterImage(characterId.value, uploadedFilename)
        await loadImages()
      }
      await store.fetchOne(characterId.value)
      if (store.current) {
        form.value.avatar_image = store.current.avatar_image
      }
    } catch (e) {
      console.error('Upload failed:', e)
    }
  } else {
    // Create mode: queue for upload after save
    pendingFiles.value = [...pendingFiles.value, file]
  }
}

function handleReplacePending(index: number, file: File) {
  pendingFiles.value = pendingFiles.value.map((pendingFile, i) => i === index ? file : pendingFile)
}

function handleDeletePending(index: number) {
  pendingFiles.value = pendingFiles.value.filter((_, i) => i !== index)
}

const activeImage = computed(() => store.current?.active_image)

async function handleActivateImage(filename: string) {
  if (!isEdit.value) return
  try {
    await activateCharacterImage(characterId.value, filename)
    await loadImages()
    await store.fetchOne(characterId.value)
    if (store.current) {
      form.value.avatar_image = store.current.avatar_image
    }
  } catch (e) {
    console.error('Activate image failed:', e)
  }
}

function handleDeleteImage(filename: string) {
  deletedImageFilenames.value = new Set([...deletedImageFilenames.value, filename])
}

async function handleCheckVoice() {
  voiceError.value = ''
  clearVoiceTestResult()

  const voiceType = resolveVoiceType()
  if (!voiceType) return

  testingVoice.value = true
  try {
    await testCharacterVoice({
      voice_provider: resolveVoiceProviderForCheck(),
      voice_type: voiceType,
      model: ((form.value.mode !== 'omni' && selectedTTS.value === 'qwen') || usesDoubaoTTS.value) ? selectedTTSModel.value : undefined,
    })
    voiceTestStatus.value = 'success'
    voiceTestMessage.value = ''
  } catch (e) {
    voiceTestStatus.value = 'error'
    voiceTestMessage.value = e instanceof Error ? e.message : String(e)
  } finally {
    testingVoice.value = false
  }
}

async function save() {
  if (!form.value.name.trim()) return
  voiceError.value = ''
  saving.value = true
  try {
    const payload = { ...form.value }
    if (payload.avatar_image.startsWith('blob:')) {
      payload.avatar_image = ''
    }

    const voiceType = resolveVoiceType()
    if (!voiceType) {
      return
    }
    payload.voice_type = voiceType
    payload.components = normalizeComponents(payload.components)
    payload.agent_extensions = normalizeAgentExtensions(payload.agent_extensions)
    payload.avatar_backend = normalizeAvatarBackend(payload.avatar_backend)
    payload.voice_provider = payload.avatar_backend === 'vidu'
      ? 'qwen_omni'
      : payload.mode === 'omni'
        ? normalizeOmniProvider(payload.voice_provider)
        : payload.components.tts
    if (payload.avatar_backend === 'baidu_xiling') {
      payload.baidu_xiling = {
        ...(payload.baidu_xiling || emptyBaiduXilingConfig()),
        figure_id: (payload.baidu_xiling?.figure_id || '').trim(),
      }
      payload.xunfei = null
      payload.use_face_crop = false
      payload.image_mode = 'fixed'
    } else if (payload.avatar_backend === 'xunfei') {
      payload.xunfei = {
        ...emptyXunfeiConfig(),
        ...(payload.xunfei || {}),
        avatar_id: (payload.xunfei?.avatar_id || '').trim(),
        avatar_name: (payload.xunfei?.avatar_name || '').trim(),
        vcn: (payload.xunfei?.vcn || '').trim(),
        thumbnail_url: (payload.xunfei?.thumbnail_url || '').trim(),
        preview_video_url: (payload.xunfei?.preview_video_url || '').trim(),
        source_image_url: (payload.xunfei?.source_image_url || '').trim(),
        status: (payload.xunfei?.status || '').trim(),
      }
      payload.baidu_xiling = null
      payload.use_face_crop = false
      payload.image_mode = 'fixed'
    } else {
      payload.baidu_xiling = null
      payload.xunfei = null
    }

    let id: string
    if (isEdit.value) {
      await store.update(characterId.value, payload)
      id = characterId.value
    } else {
      const char = await store.create(payload)
      id = char.id
    }

    // Delete images marked for removal
    for (const filename of deletedImageFilenames.value) {
      await deleteCharacterImage(id, filename)
    }

    if (payload.avatar_backend === 'local_image' || payload.avatar_backend === 'vidu') {
      // Upload all pending files
      for (const file of pendingFiles.value) {
        await uploadAvatar(id, file)
      }
    }

    router.push('/characters')
  } catch (e) {
    console.error('Save failed:', e)
  } finally {
    saving.value = false
  }
}

async function handleDelete() {
  if (!confirm(t('characterEdit.deleteConfirm'))) return
  await store.remove(characterId.value)
  router.push('/characters')
}

const promptLength = computed(() => form.value.system_prompt.length)

const pageTitle = computed(() =>
  isEdit.value
    ? t('characterEdit.pageTitleEdit')
    : t('characterEdit.pageTitleCreate')
)
</script>

<template>
  <div class="min-h-screen bg-cv-base flex flex-col">
    <AppHeader showBack :title="pageTitle" />

    <!-- Content -->
    <main class="flex-1 max-w-[1100px] mx-auto w-full px-12 pt-8 pb-24 flex gap-8">
      <!-- Left column: Avatar -->
      <div class="w-[300px] shrink-0">
        <div class="mb-4 rounded-cv-lg border border-cv-border bg-cv-surface p-3">
          <div class="mb-2 text-[12px] font-medium text-cv-text-muted">{{ t('characterEdit.avatarBackend') }}</div>
          <CvSelect
            v-model="avatarBackendModel"
            :options="avatarBackendOptions"
          />
          <p v-if="isLocalAvatar" class="mt-2 text-[11px] leading-5 text-cv-text-muted">
            {{ t('characterEdit.localAvatarBackendHint') }}
          </p>
          <p v-else-if="isViduAvatar" class="mt-2 text-[11px] leading-5 text-cv-text-muted">
            {{ t('characterEdit.viduAvatarBackendHint') }}
          </p>
          <p v-else-if="isBaiduXilingAvatar" class="mt-2 text-[11px] leading-5 text-cv-text-muted">
            <span>{{ t('characterEdit.baiduAvatarBackendHint') }}</span>
            <a
              :href="BAIDU_XILING_OVERVIEW_URL"
              target="_blank"
              rel="noopener noreferrer"
              class="ml-1 inline-flex h-5 w-5 items-center justify-center rounded-cv-sm align-[-4px] text-cv-accent transition-colors hover:bg-cv-accent/10 focus:outline-none focus:ring-2 focus:ring-cv-accent/30"
              :aria-label="t('characterEdit.baiduXilingLinkLabel')"
              :title="t('characterEdit.baiduXilingLinkLabel')"
            >
              <svg aria-hidden="true" width="12" height="12" viewBox="0 0 24 24" fill="none">
                <path d="M7 17L17 7" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
                <path d="M9 7h8v8" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
            </a>
          </p>
          <p v-else class="mt-2 text-[11px] leading-5 text-cv-text-muted">
            {{ t('characterEdit.xunfeiAvatarBackendHint') }}
          </p>
        </div>

        <AvatarUpload
          v-if="usesUploadedAvatar"
          :use-face-crop="form.use_face_crop"
          :images="visibleImages"
          :character-id="isEdit ? characterId : undefined"
          :pending-files="pendingFiles"
          :active-image="activeImage"
          :image-mode="form.image_mode"
          @update:use-face-crop="v => form.use_face_crop = v"
          @file-selected="handleFileSelected"
          @replace-pending="handleReplacePending"
          @delete-image="handleDeleteImage"
          @delete-pending="handleDeletePending"
          @activate-image="handleActivateImage"
        />

        <div v-else-if="isBaiduXilingAvatar" class="rounded-cv-lg border border-cv-border bg-cv-surface p-4">
          <div class="grid grid-cols-[minmax(0,1fr)_82px] gap-2">
            <label class="flex h-11 overflow-hidden rounded-cv-md border border-cv-border bg-cv-elevated transition-all focus-within:border-cv-accent focus-within:shadow-[0_0_0_2px_rgba(59,130,246,0.15)]">
              <span class="flex h-full w-[74px] shrink-0 items-center border-r border-cv-border px-3 text-[13px] font-medium text-cv-text-secondary">{{ t('characterEdit.baiduFigureId') }}</span>
              <input
                id="baidu-figure-id-input"
                v-model="baiduFigureId"
                type="text"
                :placeholder="t('characterEdit.baiduFigureIdPlaceholder')"
                class="h-full min-w-0 flex-1 border-0 bg-transparent px-3 text-sm text-cv-text placeholder:text-cv-text-muted focus:outline-none"
              />
            </label>
            <button
              type="button"
              @click="lookupBaiduFigure"
              :disabled="baiduLookupLoading || !baiduFigureId.trim()"
              class="cv-pi-button cv-pi-button--compact h-11"
            >
              {{ baiduLookupLoading ? t('characterEdit.baiduFigureChecking') : t('characterEdit.baiduFigureLookup') }}
            </button>
          </div>
          <p v-if="baiduLookupError" class="mt-2 break-words text-[11px] leading-5 text-cv-danger">
            {{ baiduLookupError }}
          </p>

          <div class="mt-4 overflow-hidden rounded-cv-md border border-cv-border bg-cv-elevated">
            <img
              v-if="baiduPreviewImage"
              :src="baiduPreviewImage"
              :alt="baiduFigureLabel"
              class="block h-auto w-full"
            />
            <div v-else class="flex h-[180px] flex-col items-center justify-center px-4 text-center">
              <svg aria-hidden="true" width="28" height="28" viewBox="0 0 24 24" fill="none" class="text-cv-text-muted">
                <path d="M4 6.5A2.5 2.5 0 0 1 6.5 4h11A2.5 2.5 0 0 1 20 6.5v11a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 17.5v-11Z" stroke="currentColor" stroke-width="1.6" />
                <path d="m5 16 4.2-4.2a1.2 1.2 0 0 1 1.7 0L14 15l1.2-1.2a1.2 1.2 0 0 1 1.7 0L20 17" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
                <path d="M15.5 8.5h.01" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" />
              </svg>
            </div>
          </div>
        </div>

        <div v-else class="rounded-cv-lg border border-cv-border bg-cv-surface p-4">
          <div class="space-y-3">
            <div>
              <div class="grid grid-cols-[minmax(0,1fr)_82px] gap-2">
                <label class="flex h-11 overflow-hidden rounded-cv-md border border-cv-border bg-cv-elevated transition-all focus-within:border-cv-accent focus-within:shadow-[0_0_0_2px_rgba(59,130,246,0.15)]">
                  <span class="flex h-full w-[74px] shrink-0 items-center border-r border-cv-border px-3 text-[13px] font-medium text-cv-text-secondary">{{ t('characterEdit.xunfeiAvatarId') }}</span>
                  <input
                    id="xunfei-avatar-id-input"
                    v-model="xunfeiAvatarId"
                    type="text"
                    :placeholder="t('characterEdit.xunfeiAvatarIdPlaceholder')"
                    class="h-full min-w-0 flex-1 border-0 bg-transparent px-3 text-sm text-cv-text placeholder:text-cv-text-muted focus:outline-none"
                  />
                </label>
                <button
                  type="button"
                  @click="lookupXunfeiAvatar"
                  :disabled="xunfeiLookupLoading || !xunfeiAvatarId.trim()"
                  class="cv-pi-button cv-pi-button--compact h-11"
                >
                  {{ xunfeiLookupLoading ? t('characterEdit.xunfeiAvatarChecking') : t('characterEdit.xunfeiAvatarLookup') }}
                </button>
              </div>
              <p v-if="xunfeiLookupError" class="mt-2 break-words text-[11px] leading-5 text-cv-danger">
                {{ xunfeiLookupError }}
              </p>
            </div>
          </div>
          <div class="mt-4 overflow-hidden rounded-cv-md border border-cv-border bg-cv-elevated">
            <img
              v-if="xunfeiPreviewImage"
              :src="xunfeiPreviewImage"
              :alt="xunfeiAvatarLabel"
              class="block h-auto w-full"
            />
            <div v-else class="flex h-[180px] flex-col items-center justify-center px-4 text-center">
              <svg aria-hidden="true" width="28" height="28" viewBox="0 0 24 24" fill="none" class="text-cv-text-muted">
                <path d="M4 6.5A2.5 2.5 0 0 1 6.5 4h11A2.5 2.5 0 0 1 20 6.5v11a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 17.5v-11Z" stroke="currentColor" stroke-width="1.6" />
                <path d="m5 16 4.2-4.2a1.2 1.2 0 0 1 1.7 0L14 15l1.2-1.2a1.2 1.2 0 0 1 1.7 0L20 17" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
                <path d="M15.5 8.5h.01" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" />
              </svg>
              <p class="mt-3 text-[13px] font-medium text-cv-text-secondary">{{ t('characterEdit.xunfeiPreviewPlaceholderTitle') }}</p>
              <p class="mt-1 text-[12px] leading-5 text-cv-text-muted">{{ t('characterEdit.xunfeiPreviewPlaceholderBody') }}</p>
            </div>
          </div>
        </div>

        <button
          v-if="isEdit"
          type="button"
          class="cv-pi-button cv-pi-button--compact mt-4 w-full"
          @click="router.push(isViduAvatar ? `/launch/${characterId}/live` : `/launch/${characterId}`)"
        >
          {{ t('characterEdit.openWorkspace') }}
        </button>

        <!-- Image mode toggle -->
        <div v-if="isLocalAvatar && isEdit && visibleImages.length > 1"
             class="mt-4 bg-cv-surface border border-cv-border rounded-cv-lg p-4">
          <div class="flex items-center justify-between">
            <div>
              <span class="text-[13px] font-medium text-cv-text-secondary">{{ t('characterEdit.randomAvatar') }}</span>
              <p class="text-[11px] text-cv-text-muted mt-1">{{ t('characterEdit.randomAvatarHint') }}</p>
            </div>
            <button @click="form.image_mode = form.image_mode === 'random' ? 'fixed' : 'random'"
                    class="relative w-11 h-6 rounded-full transition-colors cursor-pointer"
                    :class="form.image_mode === 'random' ? 'bg-cv-text-secondary' : 'bg-cv-elevated'">
              <span class="absolute top-0.5 left-0.5 w-5 h-5 rounded-full transition-transform duration-200"
                    :class="form.image_mode === 'random' ? 'translate-x-5 bg-cv-text' : 'translate-x-0 bg-cv-text-muted'" />
            </button>
          </div>
        </div>
      </div>

      <!-- Right column: Form -->
      <div class="flex-1 flex flex-col gap-6">
        <!-- Section 1: Basic info -->
        <section class="bg-cv-surface border border-cv-border rounded-cv-lg p-6">
          <h2 class="text-base font-semibold text-cv-text mb-5">{{ t('characterEdit.basicInfo') }}</h2>

          <label class="block mb-4">
            <span class="text-[13px] font-medium text-cv-text-secondary">{{ t('characterEdit.name') }} <span class="text-cv-danger">*</span></span>
            <input v-model="form.name" type="text" :placeholder="t('characterEdit.namePlaceholder')"
                   class="mt-1.5 w-full h-[42px] bg-cv-elevated border border-cv-border rounded-cv-md px-4 text-sm text-cv-text placeholder:text-cv-text-muted focus:border-cv-accent focus:outline-none focus:shadow-[0_0_0_2px_rgba(59,130,246,0.15)] transition-all" />
          </label>

          <label class="block">
            <span class="text-[13px] font-medium text-cv-text-secondary">{{ t('characterEdit.description') }}</span>
            <textarea v-model="form.description" :placeholder="t('characterEdit.descriptionPlaceholder')"
                      class="mt-1.5 w-full h-20 bg-cv-elevated border border-cv-border rounded-cv-md px-4 py-3 text-sm text-cv-text placeholder:text-cv-text-muted resize-y focus:border-cv-accent focus:outline-none focus:shadow-[0_0_0_2px_rgba(59,130,246,0.15)] transition-all" />
          </label>
        </section>

        <!-- Section 2: Component configuration -->
        <section class="bg-cv-surface border border-cv-border rounded-cv-lg p-6">
          <template v-if="isViduAvatar">
            <h2 class="text-base font-semibold text-cv-text mb-5">{{ t('characterEdit.viduVoiceConfig') }}</h2>
            <label class="block">
              <span class="text-[13px] font-medium text-cv-text-secondary">{{ t('characterEdit.lineVoice') }}</span>
              <CvSelect
                v-model="form.voice_type"
                :options="qwenOmniVoiceOptions"
                :searchable="true"
                :search-placeholder="t('common.search')"
                :empty-label="t('common.noResults')"
                class="mt-1.5"
              />
              <p class="mt-2 text-[11px] leading-5 text-cv-text-muted">
                {{ t('characterEdit.viduVoiceHint') }}
                <a
                  :href="QWEN_OMNI_VOICE_LIST_URL"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="underline underline-offset-2 transition-colors hover:text-cv-text"
                >
                  {{ t('characterEdit.qwenOmniVoiceList') }}
                </a>
              </p>
            </label>
          </template>
          <template v-else>
          <div class="mb-5 flex flex-wrap items-center gap-3">
            <h2 class="text-base font-semibold text-cv-text">{{ t('characterEdit.components') }}</h2>
            <div class="relative flex items-center gap-2">
              <button
                type="button"
                @click="toggleMode"
                class="cv-pi-segment h-9 w-[280px] max-w-[calc(100vw-120px)] grid-cols-2 cursor-pointer"
                :aria-label="t('characterEdit.modeToggleLabel', { mode: form.mode })"
              >
                <span
                  class="cv-pi-segment-item"
                  :class="{ 'cv-pi-segment-item--active': form.mode === 'standard' }"
                >
                  standard
                </span>
                <span
                  class="cv-pi-segment-item"
                  :class="{ 'cv-pi-segment-item--active': form.mode === 'omni' }"
                >
                  {{ t('characterEdit.omniMode') }}
                </span>
              </button>
              <button
                type="button"
                @click="showModeHelp = !showModeHelp"
                class="flex h-7 w-7 items-center justify-center rounded-full border border-cv-border text-sm font-medium text-cv-text-muted transition-colors hover:bg-cv-hover hover:text-cv-text cursor-pointer"
                :aria-expanded="showModeHelp"
                :aria-label="t('characterEdit.modeHelpLabel')"
              >
                ?
              </button>
              <div
                v-if="showModeHelp"
                class="absolute right-0 top-[calc(100%+8px)] z-20 w-[340px] max-w-[calc(100vw-64px)] rounded-cv-md border border-cv-border bg-cv-elevated p-4 shadow-lg"
              >
                <div class="mb-3">
                  <div class="text-[13px] font-semibold text-cv-text">standard</div>
                  <p class="mt-1 text-[12px] leading-5 text-cv-text-secondary">
                    {{ t('characterEdit.standardHelp') }}
                  </p>
                </div>
                <div>
                  <div class="text-[13px] font-semibold text-cv-text">{{ t('characterEdit.omniMode') }}</div>
                  <p class="mt-1 text-[12px] leading-5 text-cv-text-secondary">
                    {{ t('characterEdit.omniHelp') }}
                  </p>
                </div>
              </div>
            </div>
          </div>

          <div v-if="form.mode === 'standard'" class="flex flex-col gap-4">
            <div class="grid gap-3 md:grid-cols-[90px_minmax(0,1fr)_minmax(0,1fr)] md:items-end">
              <span class="text-[13px] font-medium text-cv-text-secondary md:pb-3">LLM</span>
              <label class="block">
                <span class="text-[12px] font-medium text-cv-text-muted">Provider</span>
                <CvSelect
                  v-model="form.components.llm"
                  :options="llmProviderOptions"
                  class="mt-1.5"
                />
              </label>
              <label class="block">
                <span class="text-[12px] font-medium text-cv-text-muted">{{ t('common.model') }}</span>
                <CvSelect
                  v-model="llmModel"
                  :options="llmModelOptions"
                  class="mt-1.5"
                />
              </label>
            </div>

            <div class="grid gap-3 md:grid-cols-[90px_minmax(0,1fr)_minmax(0,1fr)] md:items-end">
              <span class="text-[13px] font-medium text-cv-text-secondary md:pb-3">ASR</span>
              <label class="block">
                <span class="text-[12px] font-medium text-cv-text-muted">Provider</span>
                <CvSelect
                  v-model="form.components.asr"
                  :options="asrProviderOptions"
                  class="mt-1.5"
                />
              </label>
              <label class="block">
                <span class="text-[12px] font-medium text-cv-text-muted">{{ t('common.model') }}</span>
                <CvSelect
                  v-model="asrModel"
                  :options="asrModelOptions"
                  class="mt-1.5"
                />
              </label>
            </div>

            <div class="grid gap-3 md:grid-cols-[90px_minmax(0,1fr)_minmax(0,1fr)] md:items-start">
              <span class="text-[13px] font-medium text-cv-text-secondary md:pt-[31px]">TTS</span>
              <label class="block">
                <span class="text-[12px] font-medium text-cv-text-muted">Provider</span>
                <CvSelect
                  v-model="form.components.tts"
                  :options="ttsProviderOptions"
                  class="mt-1.5"
                />
              </label>
              <label class="block">
                <span class="text-[12px] font-medium text-cv-text-muted">{{ t('common.model') }}</span>
                <CvSelect
                  v-model="ttsModel"
                  :options="ttsModelOptions"
                  class="mt-1.5"
                />
              </label>
              <template v-if="!usesDoubaoVoice && selectedTTS === 'qwen'">
                <label class="block md:col-span-2 md:col-start-2">
                  <span class="text-[12px] font-medium text-cv-text-muted">{{ t('common.voice') }}</span>
                  <div v-if="usesCosyVoiceCloneOnlyTTS" class="mt-1.5 flex items-start gap-3">
                    <div class="relative min-w-0 flex-1">
                      <input
                        v-model="form.voice_type"
                        type="text"
                        :placeholder="t('characterEdit.cosyVoiceIdPlaceholder')"
                        class="h-[42px] w-full bg-cv-elevated border border-cv-border rounded-cv-md px-4 text-sm text-cv-text placeholder:text-cv-text-muted focus:outline-none transition-all"
                        :class="voiceCheckSucceeded
                          ? 'pr-11 border-cv-success focus:border-cv-success focus:shadow-[0_0_0_2px_rgba(34,197,94,0.15)]'
                          : 'focus:border-cv-accent focus:shadow-[0_0_0_2px_rgba(59,130,246,0.15)]'"
                      />
                      <span
                        v-if="voiceCheckSucceeded"
                        class="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-cv-success"
                      >
                        <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
                          <path d="M3.5 8.5l3 3 6-6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" />
                        </svg>
                      </span>
                    </div>
                    <button
                      type="button"
                      @click="handleCheckVoice"
                      :disabled="testingVoice || !canCheckVoice"
                      :class="{ 'opacity-40 cursor-not-allowed': testingVoice || !canCheckVoice }"
                      class="cv-pi-button cv-pi-button--compact h-[42px] w-[96px] shrink-0 px-2 disabled:opacity-40 disabled:cursor-not-allowed"
                    >
                      {{ t('common.check') }}
                    </button>
                  </div>
                  <template v-else-if="usesCosyVoiceBuiltinTTS">
                    <div class="mt-1.5 grid gap-3 lg:grid-cols-[184px_minmax(0,1fr)_96px]">
                      <div class="cv-pi-segment h-[42px] min-w-0 grid-cols-2 text-[11px]">
                        <button
                          type="button"
                          @click="setCosyVoiceMode('official')"
                          class="cv-pi-segment-item cursor-pointer"
                          :class="{ 'cv-pi-segment-item--active': cosyVoiceMode === 'official' }"
                        >
                          {{ t('characterEdit.officialVoice') }}
                        </button>
                        <button
                          type="button"
                          @click="setCosyVoiceMode('custom')"
                          class="cv-pi-segment-item cursor-pointer"
                          :class="{ 'cv-pi-segment-item--active': cosyVoiceMode === 'custom' }"
                        >
                          {{ t('characterEdit.clonedVoice') }}
                        </button>
                      </div>
                      <CvSelect
                        v-if="cosyVoiceMode === 'official'"
                        v-model="form.voice_type"
                        :options="cosyVoiceOfficialOptions"
                        :success="voiceCheckSucceeded"
                        class="min-w-0"
                      />
                      <div v-else class="relative min-w-0">
                        <input
                          v-model="form.voice_type"
                          type="text"
                          :placeholder="t('characterEdit.cosyVoiceIdPlaceholder')"
                          class="h-[42px] w-full bg-cv-elevated border border-cv-border rounded-cv-md px-4 text-sm text-cv-text placeholder:text-cv-text-muted focus:outline-none transition-all"
                          :class="voiceCheckSucceeded
                            ? 'pr-11 border-cv-success focus:border-cv-success focus:shadow-[0_0_0_2px_rgba(34,197,94,0.15)]'
                            : 'focus:border-cv-accent focus:shadow-[0_0_0_2px_rgba(59,130,246,0.15)]'"
                        />
                        <span
                          v-if="voiceCheckSucceeded"
                          class="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-cv-success"
                        >
                          <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
                            <path d="M3.5 8.5l3 3 6-6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" />
                          </svg>
                        </span>
                      </div>
                      <button
                        type="button"
                        @click="handleCheckVoice"
                        :disabled="testingVoice || !canCheckVoice"
                        :class="{ 'opacity-40 cursor-not-allowed': testingVoice || !canCheckVoice }"
                        class="cv-pi-button cv-pi-button--compact h-[42px] w-full min-w-0 px-2 disabled:opacity-40 disabled:cursor-not-allowed"
                      >
                        {{ t('common.check') }}
                      </button>
                    </div>
                  </template>
                  <div v-else class="mt-1.5 grid gap-3 lg:grid-cols-[minmax(0,1fr)_96px]">
                    <CvSelect
                      v-model="form.voice_type"
                      :options="qwenTTSVoiceOptions"
                      :success="voiceCheckSucceeded"
                      class="min-w-0"
                    />
                    <button
                      type="button"
                      @click="handleCheckVoice"
                      :disabled="testingVoice || !canCheckVoice"
                      :class="{ 'opacity-40 cursor-not-allowed': testingVoice || !canCheckVoice }"
                      class="cv-pi-button cv-pi-button--compact h-[42px] w-full min-w-0 px-2 disabled:opacity-40 disabled:cursor-not-allowed"
                    >
                      {{ t('common.check') }}
                    </button>
                  </div>
                </label>
                <p
                  v-if="usesCosyVoiceCloneOnlyTTS"
                  class="text-[11px] leading-5 text-cv-text-muted md:col-span-2 md:col-start-2 md:-mt-1"
                >
                  {{ t('characterEdit.cosyVoiceIdHint') }}
                </p>
                <p
                  v-else-if="usesCosyVoiceBuiltinTTS"
                  class="text-[11px] leading-5 text-cv-text-muted md:col-span-2 md:col-start-2 md:-mt-1"
                >
                  {{ t('characterEdit.cosyVoiceBuiltinHint') }}
                  <a
                    :href="COSYVOICE_VOICE_LIST_URL"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="underline underline-offset-2 transition-colors hover:text-cv-text"
                  >
                    {{ t('characterEdit.cosyVoiceVoiceList') }}
                  </a>
                </p>
                <p
                  v-else
                  class="text-[11px] leading-5 text-cv-text-muted md:col-span-2 md:col-start-2 md:-mt-1"
                >
                  {{ t('characterEdit.canPreviewAt') }}
                  <a
                    :href="QWEN_TTS_VOICE_PREVIEW_URL"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="underline underline-offset-2 transition-colors hover:text-cv-text"
                  >
                    {{ t('characterEdit.qwenTTSVoiceList') }}
                  </a>
                  {{ t('characterEdit.previewVoice') }}
                </p>
                <p
                  v-if="usesCosyVoiceTTS && voiceError"
                  class="text-[11px] leading-5 text-cv-danger md:col-span-2 md:col-start-2 md:-mt-1"
                >
                  {{ voiceError }}
                </p>
                <p
                  v-if="voiceTestStatus === 'error' && voiceTestMessage"
                  class="text-[11px] leading-5 text-cv-danger whitespace-pre-wrap break-all md:col-span-2 md:col-start-2 md:-mt-1"
                >
                  {{ voiceTestMessage }}
                </p>
              </template>
              <div v-else-if="isOpenAIVoice" class="block md:col-span-2 md:col-start-2">
                <span class="text-[12px] font-medium text-cv-text-muted">{{ t('common.voice') }}</span>
                <div class="mt-1.5 grid gap-3 lg:grid-cols-[minmax(0,1fr)_96px]">
                  <CvSelect
                    v-model="form.voice_type"
                    :options="openAIVoiceOptions"
                    :success="voiceCheckSucceeded"
                    class="min-w-0"
                  />
                  <button
                    type="button"
                    @click="handleCheckVoice"
                    :disabled="testingVoice || !canCheckVoice"
                    :class="{ 'opacity-40 cursor-not-allowed': testingVoice || !canCheckVoice }"
                    class="cv-pi-button cv-pi-button--compact h-[42px] w-full min-w-0 px-2 disabled:opacity-40 disabled:cursor-not-allowed"
                  >
                    {{ t('common.check') }}
                  </button>
                </div>
                <p
                  v-if="voiceTestStatus === 'error' && voiceTestMessage"
                  class="mt-2 text-[11px] leading-5 text-cv-danger whitespace-pre-wrap break-all"
                >
                  {{ voiceTestMessage }}
                </p>
              </div>
              <div v-else class="block md:col-span-2 md:col-start-2">
                <span class="text-[12px] font-medium text-cv-text-muted">{{ t('common.voice') }}</span>
                <div class="mt-1.5 grid gap-3 lg:grid-cols-[184px_minmax(0,1fr)_96px]">
                  <div class="cv-pi-segment h-[42px] min-w-0 grid-cols-2">
                    <button
                      type="button"
                      @click="setVoiceMode('official')"
                      class="cv-pi-segment-item cursor-pointer"
                      :class="{ 'cv-pi-segment-item--active': voiceMode === 'official' }"
                    >
                      {{ t('characterEdit.officialVoice') }}
                    </button>
                    <button
                      type="button"
                      @click="setVoiceMode('custom')"
                      class="cv-pi-segment-item cursor-pointer"
                      :class="{ 'cv-pi-segment-item--active': voiceMode === 'custom' }"
                    >
                      {{ t('characterEdit.clonedVoice') }}
                    </button>
                  </div>
                  <CvSelect
                    v-if="voiceMode === 'official'"
                    v-model="form.voice_type"
                    :options="officialVoiceOptions"
                    :success="voiceCheckSucceeded"
                    :searchable="usesDoubaoTTS"
                    :search-placeholder="t('common.search')"
                    :empty-label="t('common.noResults')"
                    class="min-w-0"
                  />
                  <div v-else class="relative min-w-0">
                    <input
                      v-model="customVoiceType"
                      type="text"
                      :placeholder="t('characterEdit.customSpeakerPlaceholder')"
                      class="h-[42px] w-full bg-cv-elevated border border-cv-border rounded-cv-md px-4 text-sm text-cv-text placeholder:text-cv-text-muted focus:outline-none transition-all"
                      :class="voiceCheckSucceeded
                        ? 'pr-11 border-cv-success focus:border-cv-success focus:shadow-[0_0_0_2px_rgba(34,197,94,0.15)]'
                        : 'focus:border-cv-accent focus:shadow-[0_0_0_2px_rgba(59,130,246,0.15)]'"
                    />
                    <span
                      v-if="voiceCheckSucceeded"
                      class="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-cv-success"
                    >
                      <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
                        <path d="M3.5 8.5l3 3 6-6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" />
                      </svg>
                    </span>
                  </div>
                  <button
                    type="button"
                    @click="handleCheckVoice"
                    :disabled="testingVoice || !canCheckVoice"
                    :class="{ 'opacity-40 cursor-not-allowed': testingVoice || !canCheckVoice }"
                    class="cv-pi-button cv-pi-button--compact h-[42px] w-full min-w-0 disabled:opacity-40 disabled:cursor-not-allowed"
                  >
                    {{ t('common.check') }}
                  </button>
                </div>
                <p v-if="usesDoubaoTTS && voiceMode === 'official'" class="mt-2 text-[11px] leading-5 text-cv-text-muted">
                  {{ t('characterEdit.canPreviewAt') }}
                  <a
                    :href="DOUBAO_TTS_VOICE_LIST_URL"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="underline underline-offset-2 transition-colors hover:text-cv-text"
                  >
                    {{ t('characterEdit.doubaoTTSVoiceList') }}
                  </a>
                  {{ t('characterEdit.previewVoice') }}
                </p>
                <p v-if="voiceError" class="mt-2 text-[11px] text-cv-danger">{{ voiceError }}</p>
                <p
                  v-if="voiceTestStatus === 'error' && voiceTestMessage"
                  class="mt-2 text-[11px] leading-5 text-cv-danger whitespace-pre-wrap break-all"
                >
                  {{ voiceTestMessage }}
                </p>
              </div>
            </div>
          </div>

          <div v-else class="flex flex-col gap-4">
            <div class="grid gap-3 md:grid-cols-[90px_minmax(0,1fr)_minmax(0,1fr)] md:items-end">
              <span class="text-[13px] font-medium text-cv-text-secondary md:pb-3">{{ t('characterEdit.omniModel') }}</span>
              <label class="block">
                <span class="text-[12px] font-medium text-cv-text-muted">Provider</span>
                <CvSelect
                  v-model="form.voice_provider"
                  :options="omniProviderOptions"
                  class="mt-1.5"
                />
              </label>
              <div v-if="usesDoubaoVoice" class="block">
                <span class="text-[12px] font-medium text-cv-text-muted">{{ t('characterEdit.voiceType') }}</span>
                <div class="cv-pi-segment mt-1.5 h-[42px] grid-cols-2">
                  <button
                    type="button"
                    @click="setVoiceMode('official')"
                    class="cv-pi-segment-item cursor-pointer"
                    :class="{ 'cv-pi-segment-item--active': voiceMode === 'official' }"
                  >
                    {{ t('characterEdit.officialVoice') }}
                  </button>
                  <button
                    type="button"
                    @click="setVoiceMode('custom')"
                    class="cv-pi-segment-item cursor-pointer"
                    :class="{ 'cv-pi-segment-item--active': voiceMode === 'custom' }"
                  >
                    {{ t('characterEdit.clonedVoice') }}
                  </button>
                </div>
              </div>
              <label v-else class="block">
                <span class="text-[12px] font-medium text-cv-text-muted">{{ t('common.model') }}</span>
                <input
                  type="text"
                  :value="omniModelLabel"
                  readonly
                  class="mt-1.5 h-[42px] w-full bg-cv-elevated border border-cv-border rounded-cv-md px-4 text-sm text-cv-text-secondary focus:outline-none"
                />
              </label>
            </div>

            <div class="grid gap-3 md:grid-cols-[90px_minmax(0,1fr)] md:items-start">
              <span class="text-[13px] font-medium text-cv-text-secondary md:pt-3">{{ t('characterEdit.lineVoice') }}</span>
              <label class="block">
                <div class="flex items-start gap-3">
                  <CvSelect
                    v-if="usesQwenOmniVoice"
                    v-model="form.voice_type"
                    :options="qwenOmniVoiceOptions"
                    :success="voiceCheckSucceeded"
                    class="min-w-0 flex-1"
                  />
                  <CvSelect
                    v-else-if="usesGrokVoice"
                    v-model="form.voice_type"
                    :options="grokVoiceOptions"
                    :success="voiceCheckSucceeded"
                    class="min-w-0 flex-1"
                  />
                  <CvSelect
                    v-else-if="usesGeminiLiveVoice"
                    v-model="form.voice_type"
                    :options="geminiLiveVoiceOptions"
                    :success="voiceCheckSucceeded"
                    class="min-w-0 flex-1"
                  />
                  <CvSelect
                    v-else-if="usesOpenAIRealtimeVoice"
                    v-model="form.voice_type"
                    :options="openAIRealtimeVoiceOptions"
                    :success="voiceCheckSucceeded"
                    class="min-w-0 flex-1"
                  />
                  <CvSelect
                    v-else-if="voiceMode === 'official'"
                    v-model="form.voice_type"
                    :options="officialVoiceOptions"
                    :success="voiceCheckSucceeded"
                    :searchable="usesDoubaoTTS"
                    :search-placeholder="t('common.search')"
                    :empty-label="t('common.noResults')"
                    class="min-w-0 flex-1"
                  />
                  <div v-else class="relative min-w-0 flex-1">
                    <input
                      v-model="customVoiceType"
                      type="text"
                      :placeholder="t('characterEdit.registeredSpeakerPlaceholder')"
                      class="h-[42px] w-full bg-cv-elevated border border-cv-border rounded-cv-md px-4 text-sm text-cv-text placeholder:text-cv-text-muted focus:outline-none transition-all"
                      :class="voiceCheckSucceeded
                        ? 'pr-11 border-cv-success focus:border-cv-success focus:shadow-[0_0_0_2px_rgba(34,197,94,0.15)]'
                        : 'focus:border-cv-accent focus:shadow-[0_0_0_2px_rgba(59,130,246,0.15)]'"
                    />
                    <span
                      v-if="voiceCheckSucceeded"
                      class="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-cv-success"
                    >
                      <svg width="14" height="14" viewBox="0 0 16 16" fill="none">
                        <path d="M3.5 8.5l3 3 6-6" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" />
                      </svg>
                    </span>
                  </div>
                  <button
                    type="button"
                    @click="handleCheckVoice"
                    :disabled="testingVoice || !canCheckVoice"
                    :class="{ 'opacity-40 cursor-not-allowed': testingVoice || !canCheckVoice }"
                    class="cv-pi-button cv-pi-button--compact h-[42px] shrink-0 disabled:opacity-40 disabled:cursor-not-allowed"
                  >
                    {{ t('common.check') }}
                  </button>
                </div>
                <p v-if="usesDoubaoVoice && voiceMode === 'official'" class="mt-2 text-[11px] leading-5 text-cv-text-muted">
                  {{ t('characterEdit.canPreviewAt') }}
                  <a
                    :href="OFFICIAL_VOICE_PREVIEW_URL"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="underline underline-offset-2 transition-colors hover:text-cv-text"
                  >
                    {{ t('characterEdit.doubaoVoiceConsole') }}
                  </a>
                  {{ t('characterEdit.previewVoice') }}
                </p>
                <p v-if="usesQwenOmniVoice" class="mt-2 text-[11px] leading-5 text-cv-text-muted">
                  {{ t('characterEdit.canPreviewAt') }}
                  <a
                    :href="QWEN_OMNI_VOICE_LIST_URL"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="underline underline-offset-2 transition-colors hover:text-cv-text"
                  >
                    {{ t('characterEdit.qwenOmniVoiceList') }}
                  </a>
                  {{ t('characterEdit.previewVoice') }}
                </p>
                <p v-if="usesDoubaoVoice && voiceMode === 'custom'" class="mt-2 text-[11px] leading-5 text-cv-text-muted">
                  {{ t('characterEdit.clonePrerequisitePrefix') }}
                  <a
                    :href="CUSTOM_VOICE_CLONE_URL"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="underline underline-offset-2 transition-colors hover:text-cv-text"
                  >
                    {{ t('characterEdit.doubaoVoiceConsole') }}
                  </a>
                  {{ t('characterEdit.clonePrerequisiteSuffix') }}
                </p>
                <p v-if="voiceError" class="mt-2 text-[11px] text-cv-danger">{{ voiceError }}</p>
                <p
                  v-if="voiceTestStatus === 'error' && voiceTestMessage"
                  class="mt-2 text-[11px] leading-5 text-cv-danger whitespace-pre-wrap break-all"
                >
                  {{ voiceTestMessage }}
                </p>
              </label>
            </div>
          </div>
          </template>
        </section>

        <!-- Section 3: Persona and style -->
        <section class="bg-cv-surface border border-cv-border rounded-cv-lg p-6">
          <h2 class="text-base font-semibold text-cv-text mb-5">{{ t('characterEdit.personaStyle') }}</h2>

          <label class="block mb-4">
            <span class="text-[13px] font-medium text-cv-text-secondary">{{ t('characterEdit.speakingStyle') }}</span>
            <input v-model="form.speaking_style" type="text" :placeholder="t('characterEdit.speakingStylePlaceholder')"
                   class="mt-1.5 w-full h-[42px] bg-cv-elevated border border-cv-border rounded-cv-md px-4 text-sm text-cv-text placeholder:text-cv-text-muted focus:border-cv-accent focus:outline-none focus:shadow-[0_0_0_2px_rgba(59,130,246,0.15)] transition-all" />
            <p class="text-[11px] text-cv-text-muted mt-1">{{ t('characterEdit.speakingStyleHint') }}</p>
          </label>

          <label class="block mb-4">
            <span class="text-[13px] font-medium text-cv-text-secondary">{{ t('characterEdit.personality') }}</span>
            <textarea v-model="form.personality" :placeholder="t('characterEdit.personalityPlaceholder')"
                      class="mt-1.5 w-full h-20 bg-cv-elevated border border-cv-border rounded-cv-md px-4 py-3 text-sm text-cv-text placeholder:text-cv-text-muted resize-y focus:border-cv-accent focus:outline-none focus:shadow-[0_0_0_2px_rgba(59,130,246,0.15)] transition-all" />
            <p class="text-[11px] text-cv-text-muted mt-1">{{ t('characterEdit.personalityHint') }}</p>
          </label>

          <label class="block">
            <span class="text-[13px] font-medium text-cv-text-secondary">{{ t('characterEdit.welcomeMessage') }}</span>
            <textarea v-model="form.welcome_message" :placeholder="t('characterEdit.welcomeMessagePlaceholder')"
                      class="mt-1.5 w-full h-[60px] bg-cv-elevated border border-cv-border rounded-cv-md px-4 py-3 text-sm text-cv-text placeholder:text-cv-text-muted resize-y focus:border-cv-accent focus:outline-none focus:shadow-[0_0_0_2px_rgba(59,130,246,0.15)] transition-all" />
            <p class="text-[11px] text-cv-text-muted mt-1">{{ t('characterEdit.welcomeMessageHint') }}</p>
          </label>
        </section>

        <!-- Section 4: Agent extensions -->
        <section class="bg-cv-surface border border-cv-border rounded-cv-lg p-6">
          <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
            <div>
              <h2 class="text-base font-semibold text-cv-text">{{ t('characterEdit.agentExtensions') }}</h2>
              <p class="mt-1 text-[11px] leading-5 text-cv-text-muted">{{ t('characterEdit.agentExtensionsHint') }}</p>
            </div>
            <a
              :href="PI_PACKAGES_URL"
              target="_blank"
              rel="noopener noreferrer"
              class="text-[12px] font-medium text-cv-accent hover:underline"
            >
              {{ t('characterEdit.piPackageGallery') }}
            </a>
          </div>

          <div v-if="form.agent_extensions?.length" class="divide-y divide-cv-border-subtle border-y border-cv-border-subtle">
            <div
              v-for="(extension, index) in form.agent_extensions"
              :key="`${extension.url}-${index}`"
              class="py-4"
            >
              <div class="grid gap-3 md:grid-cols-[minmax(120px,180px)_1fr_auto] md:items-end">
                <label class="block">
                  <span class="text-[12px] font-medium text-cv-text-muted">{{ t('characterEdit.agentExtensionName') }}</span>
                  <input
                    v-model="extension.name"
                    type="text"
                    :placeholder="t('characterEdit.agentExtensionNamePlaceholder')"
                    class="mt-1.5 h-[38px] w-full rounded-cv-md border border-cv-border bg-cv-elevated px-3 text-[13px] text-cv-text placeholder:text-cv-text-muted focus:border-cv-accent focus:outline-none focus:shadow-[0_0_0_2px_rgba(59,130,246,0.15)]"
                  />
                </label>
                <label class="block">
                  <span class="text-[12px] font-medium text-cv-text-muted">{{ t('characterEdit.agentExtensionUrl') }}</span>
                  <input
                    v-model="extension.url"
                    type="text"
                    :placeholder="t('characterEdit.agentExtensionUrlPlaceholder')"
                    class="mt-1.5 h-[38px] w-full rounded-cv-md border border-cv-border bg-cv-elevated px-3 text-[13px] text-cv-text placeholder:text-cv-text-muted focus:border-cv-accent focus:outline-none focus:shadow-[0_0_0_2px_rgba(59,130,246,0.15)]"
                  />
                </label>
                <div class="flex h-[38px] items-center gap-3 md:mb-0.5">
                  <label class="inline-flex items-center gap-2 text-[13px] font-medium text-cv-text-secondary">
                    <input v-model="extension.enabled" type="checkbox" class="h-4 w-4 rounded border-cv-border text-cv-accent focus:ring-cv-accent/30" />
                    {{ t('characterEdit.agentExtensionEnabled') }}
                  </label>
                  <button
                    type="button"
                    class="cv-pi-button cv-pi-button--compact h-[38px]"
                    @click="removeAgentExtension(index)"
                  >
                    {{ t('characterEdit.removeAgentExtension') }}
                  </button>
                </div>
              </div>
            </div>
          </div>

          <button
            type="button"
            class="cv-pi-button cv-pi-button--compact mt-4"
            @click="addAgentExtension"
          >
            {{ t('characterEdit.addAgentExtension') }}
          </button>
        </section>

        <!-- Section 5: Role prompt -->
        <section class="bg-cv-surface border border-cv-border rounded-cv-lg p-6">
          <h2 class="text-base font-semibold text-cv-text mb-5">{{ t('characterEdit.systemPrompt') }}</h2>

          <textarea v-model="form.system_prompt"
                    :placeholder="t('characterEdit.systemPromptPlaceholder')"
                    class="w-full h-40 bg-cv-elevated border border-cv-border rounded-cv-md px-4 py-3 text-[13px] text-cv-text placeholder:text-cv-text-muted resize-y leading-[22px] focus:border-cv-accent focus:outline-none focus:shadow-[0_0_0_2px_rgba(59,130,246,0.15)] transition-all" />
          <p class="text-right text-[11px] text-cv-text-muted mt-1">{{ promptLength }} / 2000</p>
        </section>

        <KnowledgeSourceManager v-if="isEdit" :character-id="characterId" />
      </div>
    </main>

    <!-- Bottom action bar -->
    <div class="fixed bottom-0 left-0 right-0 bg-cv-surface border-t border-cv-border-subtle px-12 py-4 z-20">
      <div class="max-w-[1100px] mx-auto flex items-center justify-between">
        <button v-if="isEdit" @click="handleDelete"
                class="cv-pi-button cv-pi-button--danger cv-pi-button--compact">
          {{ t('characterEdit.deleteCharacter') }}
        </button>
        <div v-else />
        <div class="flex items-center gap-3">
          <button @click="router.back()"
                  class="cv-pi-button">
            {{ t('common.cancel') }}
          </button>
          <button @click="save" :disabled="saving || !canSave"
                  :class="{ 'opacity-40 cursor-not-allowed': saving || !canSave }"
                  class="cv-pi-button cv-pi-button--primary disabled:opacity-40 disabled:cursor-not-allowed">
            {{ saving ? t('common.saving') : t('characterEdit.saveCharacter') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
