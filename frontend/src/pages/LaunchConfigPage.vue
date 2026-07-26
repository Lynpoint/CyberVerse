<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { useCharacterStore } from '../stores/characters'
import { createSession, getAvatarModelInfo, getLaunchConfig, updateLaunchConfig } from '../services/api'
import AppHeader from '../components/AppHeader.vue'
import CvSelect from '../components/CvSelect.vue'
import type { AvatarModelInfo, ConfigSection, ConfigParam } from '../types'
import { saveLaunchWorkspaceMode } from '../utils/launchModePreference'
import { formatVoiceTypeDisplay } from '../utils/voice'
import { buildSessionLaunchState, saveSessionLaunchState } from '../utils/sessionLaunchState'

const router = useRouter()
const route = useRoute()
const store = useCharacterStore()
const { t, locale } = useI18n()
const characterId = computed(() => route.params.id as string)
const pageTitle = computed(() => t('launch.workspaceTitle'))
const hasCurrentCharacter = computed(() => store.current?.id === characterId.value)
const showLoading = computed(() => loading.value && !hasCurrentCharacter.value)
const connecting = ref(false)

// Config state
const configSections = ref<ConfigSection[]>([])
const originalSections = ref<ConfigSection[]>([])
const loading = ref(true)
const saving = ref(false)
const saveMessage = ref('')
const errorMessage = ref('')
const avatarModelInfo = ref<AvatarModelInfo | null>(null)

const activeAvatarModel = computed(() => avatarModelInfo.value?.active_model || '')
const configuredDefaultModel = computed(() => avatarModelInfo.value?.configured_default_model || '')
const runtimeConfigMismatch = computed(() =>
  !!activeAvatarModel.value &&
  !!configuredDefaultModel.value &&
  activeAvatarModel.value !== configuredDefaultModel.value
)
const isBaiduXilingCharacter = computed(() => store.current?.avatar_backend === 'baidu_xiling')
const isXunfeiCharacter = computed(() => store.current?.avatar_backend === 'xunfei')
const isViduCharacter = computed(() => store.current?.avatar_backend === 'vidu')
const isExternalAvatarCharacter = computed(() => isBaiduXilingCharacter.value || isXunfeiCharacter.value || isViduCharacter.value)
const canLaunch = computed(() => {
  if (isBaiduXilingCharacter.value) {
    return !!store.current?.baidu_xiling?.figure_id
  }
  if (isXunfeiCharacter.value) {
    return !!store.current?.xunfei?.avatar_id
  }
  if (isViduCharacter.value) {
    return !!store.current?.active_image || !!store.current?.avatar_image
  }
  return !!activeAvatarModel.value
})
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
const baiduXilingConfig = computed(() => store.current?.baidu_xiling || null)
const baiduXilingResolution = computed(() => {
  const width = baiduXilingConfig.value?.width || 0
  const height = baiduXilingConfig.value?.height || 0
  if (width <= 0 || height <= 0) return t('common.emptyDash')
  return `${width} × ${height}`
})
const baiduXilingInfoRows = computed(() => {
  return [
    { label: t('launch.baiduResolution'), value: baiduXilingResolution.value },
  ]
})
const xunfeiInfoRows = computed(() => {
  const config = store.current?.xunfei
  return [
    { label: t('launch.xunfeiAvatarId'), value: config?.avatar_id || t('common.emptyDash') },
    { label: t('launch.xunfeiSceneId'), value: config?.scene_id || t('common.emptyDash') },
    { label: t('launch.xunfeiVcn'), value: config?.vcn || t('common.emptyDash') },
  ]
})

// Input width auto-sizing (in ch units)
const INPUT_MIN_WIDTH_CH = 16
const INPUT_MAX_WIDTH_CH = 48
const INPUT_PADDING_CH = 0

function inputWidth(value: string | number): string {
  const len = String(value).length + INPUT_PADDING_CH
  return Math.min(Math.max(len, INPUT_MIN_WIDTH_CH), INPUT_MAX_WIDTH_CH) + 'ch'
}

// Deep clone helper
function cloneSections(sections: ConfigSection[]): ConfigSection[] {
  return JSON.parse(JSON.stringify(sections))
}

function comparableSections(sections: ConfigSection[]): ConfigSection[] {
  return sections.map((section) => {
    const comparable = { ...section }
    delete comparable.collapsed
    return comparable
  })
}

// Check if there are unsaved changes
const hasChanges = computed(() => {
  if (originalSections.value.length === 0) return false
  return JSON.stringify(comparableSections(configSections.value)) !== JSON.stringify(comparableSections(originalSections.value))
})

function sectionHasRestartPending(section: ConfigSection): boolean {
  const orig = originalSections.value.find(s => s.title === section.title)
  if (!orig) return false
  for (const param of section.params) {
    if (!param.requires_restart) continue
    const origParam = orig.params.find((p: ConfigParam) => p.path === param.path)
    if (origParam && origParam.value !== param.value) return true
  }
  return false
}

const restartBadgeHint = computed(() => t('launch.restartHint'))

function launchSectionTitle(section: ConfigSection): string {
  const key = section.key || ''
  return key ? t(`launch.sections.${key}`) : section.title
}

onMounted(async () => {
  saveLaunchWorkspaceMode('live')
  await store.fetchOne(characterId.value).catch(() => {})

  if (!isExternalAvatarCharacter.value) {
    // Fetch local avatar model config only for local-avatar characters.
    try {
      avatarModelInfo.value = await getAvatarModelInfo()
      const config = await getLaunchConfig()
      configSections.value = config.sections.map(s => ({ ...s, collapsed: false }))
      originalSections.value = cloneSections(configSections.value)
    } catch (e) {
      errorMessage.value = e instanceof Error ? e.message : t('launch.loadConfigFailed')
      console.error('Failed to load launch config:', e)
    }
  }
  loading.value = false
})

async function saveConfig() {
  saving.value = true
  saveMessage.value = ''
  errorMessage.value = ''

  // Collect changed non-readonly params
  const changedParams: Array<{ path: string; value: string | number }> = []
  for (const section of configSections.value) {
    for (const param of section.params) {
      if (param.readonly) continue
      // Find original value
      const origSection = originalSections.value.find(s => s.title === section.title)
      const origParam = origSection?.params.find(p => p.path === param.path)
      if (origParam && origParam.value !== param.value) {
        changedParams.push({ path: param.path, value: param.value })
      }
    }
  }

  if (changedParams.length === 0) {
    saving.value = false
    return
  }

  try {
    const resp = await updateLaunchConfig({
      model: activeAvatarModel.value,
      params: changedParams,
    })
    originalSections.value = cloneSections(configSections.value)
    if (resp.requires_restart) {
      saveMessage.value = t('launch.savedRequiresRestart')
    } else {
      saveMessage.value = t('launch.saved')
    }
  } catch (e) {
    errorMessage.value = t('launch.saveFailed')
    console.error('Failed to save launch config:', e)
  } finally {
    saving.value = false
  }
}

async function launch() {
  if (!canLaunch.value) return
  connecting.value = true
  try {
    const launchMode = store.current?.mode || 'standard'
    const resp = await createSession(characterId.value, launchMode)
    resp.warnings?.forEach((warning) => {
      console.warn('[CyberVerse]', warning)
    })
    saveSessionLaunchState(buildSessionLaunchState(resp, characterId.value, launchMode))
    router.push(`/session/${resp.session_id}`)
  } catch (e) {
    errorMessage.value = e instanceof Error ? e.message : t('launch.launchFailed')
    console.error('Failed to launch:', e)
  } finally {
    connecting.value = false
  }
}

</script>

<template>
  <div class="launch-workspace flex min-h-screen flex-col bg-cv-base text-cv-text">
    <AppHeader showBack :title="pageTitle" />

    <div class="py-6 text-center">
      <div class="cv-pi-segment mx-auto h-11 w-[260px] grid-cols-2">
        <button
          class="cv-pi-segment-item"
          type="button"
          :disabled="isViduCharacter"
          :title="isViduCharacter ? t('offlineVideo.viduUnsupported') : ''"
          @click="router.push(`/launch/${characterId}/offline`)"
        >
          {{ t('offlineVideo.offlineMode') }}
        </button>
        <button class="cv-pi-segment-item cv-pi-segment-item--active" type="button">
          {{ t('offlineVideo.liveMode') }}
        </button>
      </div>
    </div>

    <main class="mx-auto flex w-full max-w-[1100px] flex-1 flex-col gap-8 px-12 pb-24">
      <div v-if="showLoading" class="py-24 text-center text-cv-text-secondary">{{ t('launch.loadingConfig') }}</div>

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
              <p class="mt-2 text-sm leading-6 text-[#8d96a6]">
                {{ store.current.description || t('characterCard.noDescription') }}
              </p>
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
            <div v-if="errorMessage" class="notice error">{{ errorMessage }}</div>
            <div v-if="runtimeConfigMismatch" class="notice warning">
              {{ t('launch.runtimeMismatch', { configured: configuredDefaultModel, active: activeAvatarModel }) }}
            </div>
            <div v-if="saveMessage" class="notice success">{{ saveMessage }}</div>

            <div v-if="isBaiduXilingCharacter" class="config-card">
              <div
                v-for="row in baiduXilingInfoRows"
                :key="row.label"
                class="config-row"
              >
                <p class="row-label">{{ row.label }}</p>
                <p class="row-value" :title="row.value">{{ row.value }}</p>
              </div>
            </div>

            <div v-else-if="isXunfeiCharacter" class="config-card">
              <div
                v-for="row in xunfeiInfoRows"
                :key="row.label"
                class="config-row"
              >
                <p class="row-label">{{ row.label }}</p>
                <p class="row-value" :title="row.value">{{ row.value }}</p>
              </div>
            </div>

            <div v-else-if="isViduCharacter" class="notice success">
              {{ t('launch.viduNativeRuntime') }}
            </div>

            <div v-for="section in configSections" :key="section.title" class="config-card">
              <button
                class="config-header"
                type="button"
                :aria-expanded="!section.collapsed"
                @click="section.collapsed = !section.collapsed"
              >
                <span class="config-header-main">
                  <span class="config-title">{{ launchSectionTitle(section) }}</span>
                  <span
                    v-if="sectionHasRestartPending(section)"
                    class="restart-indicator"
                  >
                    <span class="restart-badge">{{ t('launch.restartRequired') }}</span>
                    <span
                      class="restart-help"
                      aria-hidden="true"
                    >
                      ?
                    </span>
                    <span role="tooltip" class="restart-tooltip">
                      {{ restartBadgeHint }}
                    </span>
                  </span>
                </span>
                <span
                  class="config-chevron"
                  :class="{ expanded: !section.collapsed }"
                  aria-hidden="true"
                />
              </button>

              <div v-if="!section.collapsed">
                <div v-for="param in section.params" :key="param.name" class="config-row">
                  <div class="min-w-0">
                    <p class="row-label strong">{{ param.name }}</p>
                    <p class="row-path">{{ param.path }}</p>
                  </div>
                  <div class="param-control">
                    <span v-if="param.readonly" class="readonly-value">{{ param.value }}</span>
                    <CvSelect
                      v-else-if="param.options && param.options.length > 0"
                      :modelValue="String(param.value)"
                      :options="param.options"
                      class="w-[200px]"
                      @update:modelValue="param.value = $event"
                    />
                    <input
                      v-else-if="typeof param.value === 'number'"
                      type="text"
                      inputmode="numeric"
                      :value="param.value"
                      :style="{ width: inputWidth(param.value) }"
                      class="param-input"
                      @input="param.value = Number(($event.target as HTMLInputElement).value) || 0"
                    >
                    <input
                      v-else
                      v-model="param.value"
                      type="text"
                      :style="{ width: inputWidth(param.value) }"
                      class="param-input"
                    >
                    <span v-if="param.readonly && param.requires_restart" class="lock-icon">
                      <svg class="inline h-3.5 w-3" viewBox="0 0 9 11" fill="none">
                        <ellipse cx="4.5" cy="3.5" rx="3" ry="3" stroke="#73737d" stroke-width="1.2" />
                        <rect x="0" y="5" width="9" height="6" rx="1" fill="#73737d" />
                      </svg>
                    </span>
                  </div>
                </div>
              </div>
            </div>

            <div class="action-row">
              <button class="cv-pi-button" type="button" :disabled="!hasChanges || saving" @click="saveConfig">
                {{ saving ? t('common.saving') : t('launch.saveConfig') }}
              </button>
              <button class="cv-pi-button cv-pi-button--primary" type="button" :disabled="connecting || !canLaunch" @click="launch">
                {{ connecting ? t('launch.launching') : t('launch.launch') }}
              </button>
            </div>
          </section>
        </div>
      </template>
    </main>
  </div>
</template>

<style scoped>
.character-panel,
.production-panel {
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
  display: flex;
  flex-direction: column;
  gap: 16px;
  padding: 22px;
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

.notice.error {
  border-color: rgba(239, 68, 68, 0.35);
  background: rgba(239, 68, 68, 0.1);
  color: #fca5a5;
}

.notice.success {
  border-color: rgba(52, 230, 243, 0.25);
  background: rgba(52, 230, 243, 0.08);
  color: #8fe8ef;
}

.config-card {
  overflow: hidden;
  border: 1px solid rgba(255, 255, 255, 0.06);
  background: #0b0d12;
}

.config-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.config-header {
  display: flex;
  min-width: 0;
  width: 100%;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
  background: #0b0e14;
  padding: 16px 20px;
  text-align: left;
  cursor: pointer;
  transition: background 160ms ease;
}

.config-header:hover {
  background: #0f131a;
}

.config-header:focus-visible {
  outline: 2px solid rgba(52, 230, 243, 0.45);
  outline-offset: -2px;
}

.config-row {
  min-width: 0;
  border-bottom: 1px solid rgba(255, 255, 255, 0.04);
  padding: 16px 20px;
}

.config-row:last-child {
  border-bottom: 0;
}

.config-header-main {
  position: relative;
  display: inline-flex;
  min-width: 0;
  align-items: center;
  gap: 10px;
}

.config-title {
  color: #c8d0dc;
  font-size: 14px;
  font-weight: 800;
}

.config-chevron {
  display: inline-flex;
  width: 18px;
  height: 18px;
  flex: 0 0 18px;
  align-items: center;
  justify-content: center;
  transform: rotate(180deg);
  transition: transform 160ms ease;
}

.config-chevron::before {
  width: 8px;
  height: 8px;
  border-bottom: 2px solid #34e6f3;
  border-right: 2px solid #34e6f3;
  content: "";
  transform: rotate(-45deg);
}

.config-chevron.expanded {
  transform: rotate(90deg);
}

.restart-indicator {
  position: relative;
  display: inline-flex;
  align-items: center;
  gap: 6px;
}

.restart-badge {
  border: 1px solid rgba(255, 147, 70, 0.4);
  background: rgba(255, 147, 70, 0.12);
  padding: 2px 8px;
  color: #ff9346;
  font-size: 11px;
}

.restart-help {
  display: inline-flex;
  height: 18px;
  min-width: 18px;
  align-items: center;
  justify-content: center;
  border: 1px solid rgba(255, 147, 70, 0.45);
  border-radius: 999px;
  background: rgba(255, 147, 70, 0.06);
  color: #ff9346;
  font-size: 11px;
  font-weight: 700;
}

.restart-tooltip {
  pointer-events: none;
  visibility: hidden;
  position: absolute;
  left: 0;
  top: calc(100% + 6px);
  z-index: 30;
  width: min(288px, calc(100vw - 3rem));
  border: 1px solid rgba(255, 255, 255, 0.1);
  background: #12161c;
  padding: 8px 12px;
  color: #b8c0cc;
  font-size: 11px;
  line-height: 1.6;
  opacity: 0;
  box-shadow: 0 18px 40px rgba(0, 0, 0, 0.3);
  transition: opacity 150ms ease;
}

.restart-indicator:hover .restart-tooltip,
.config-header:focus-visible .restart-tooltip {
  visibility: visible;
  opacity: 1;
}

.row-label {
  color: #505864;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0;
  text-transform: uppercase;
}

.row-label.strong {
  color: #c8d0dc;
  font-size: 13px;
  text-transform: none;
}

.row-path {
  margin-top: 4px;
  color: #505864;
  font-size: 11px;
}

.row-value,
.readonly-value {
  min-width: 0;
  overflow: hidden;
  color: #c8d0dc;
  font-size: 13px;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.param-control {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 10px;
}

.param-input {
  border: 1px solid rgba(72, 80, 92, 0.4);
  background: #0f1218;
  color: #a0a8b4;
  padding: 4px 8px;
  text-align: right;
  font-size: 13px;
  outline: none;
  transition: border-color 160ms ease;
}

.param-input:focus {
  border-color: rgba(52, 230, 243, 0.6);
}

.lock-icon {
  color: #505864;
  font-size: 12px;
}

.action-row {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  gap: 14px;
  padding-top: 4px;
}

@media (max-width: 860px) {
  .config-row {
    align-items: flex-start;
    flex-direction: column;
  }

  .param-control {
    width: 100%;
    justify-content: flex-start;
  }
}
</style>
