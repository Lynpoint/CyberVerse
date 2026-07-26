import type { CreateSessionResponse } from '../services/api'
import type { PipelineMode } from '../types'

export type SessionVisualInputConfig = NonNullable<CreateSessionResponse['visual_input']>
export type SessionAudioInputConfig = NonNullable<CreateSessionResponse['audio_input']>
export type AvatarIdleStrategy = NonNullable<CreateSessionResponse['idle_strategy']>
export type BaiduXilingSessionConfig = NonNullable<CreateSessionResponse['baidu_xiling']>
export type XunfeiSessionConfig = NonNullable<CreateSessionResponse['xunfei']>
export type ViduSessionConfig = NonNullable<CreateSessionResponse['vidu']>

export interface SessionLaunchState {
  session_id: string
  character_id: string
  mode: PipelineMode
  streaming_mode: string
  return_path?: string
  avatar_enabled?: boolean
  idle_strategy?: AvatarIdleStrategy
  audio_input?: SessionAudioInputConfig
  baidu_xiling?: BaiduXilingSessionConfig
  xunfei?: XunfeiSessionConfig
  vidu?: ViduSessionConfig
  livekit_url?: string
  livekit_token?: string
  idle_video_url?: string
  idle_video_urls?: string[]
  idle_image_url?: string
  visual_input?: SessionVisualInputConfig
}

const STORAGE_PREFIX = 'cyberverse.session.launch.'

function storageKey(sessionId: string): string {
  return `${STORAGE_PREFIX}${sessionId}`
}

function getSessionStorage(): Storage | null {
  try {
    return typeof window === 'undefined' ? null : window.sessionStorage
  } catch {
    return null
  }
}

function firstQueryValue(value: unknown): string {
  if (Array.isArray(value)) {
    return typeof value[0] === 'string' ? value[0] : ''
  }
  return typeof value === 'string' ? value : ''
}

function parseJSON<T>(raw: string): T | undefined {
  if (!raw) return undefined
  try {
    return JSON.parse(raw) as T
  } catch {
    return undefined
  }
}

function normalizeMode(mode: string, fallback: PipelineMode): PipelineMode {
  return mode === 'omni' || mode === 'standard' ? mode : fallback
}

function normalizeReturnPath(path: string): string | undefined {
  const trimmed = path.trim()
  if (!trimmed || !trimmed.startsWith('/') || trimmed.startsWith('//')) {
    return undefined
  }
  return trimmed
}

function normalizeIdleStrategy(strategy: string): AvatarIdleStrategy {
  return strategy === 'silent_inference' ? 'silent_inference' : 'cached_video'
}

export function buildSessionLaunchState(
  response: CreateSessionResponse,
  characterId: string,
  fallbackMode: PipelineMode,
  returnPath?: string,
): SessionLaunchState {
  return {
    session_id: response.session_id,
    character_id: characterId,
    mode: normalizeMode(response.mode, fallbackMode),
    streaming_mode: response.streaming_mode || 'direct',
    return_path: returnPath ? normalizeReturnPath(returnPath) : undefined,
    avatar_enabled: response.avatar_enabled,
    idle_strategy: normalizeIdleStrategy(response.idle_strategy || ''),
    audio_input: response.audio_input,
    baidu_xiling: response.baidu_xiling,
    xunfei: response.xunfei,
    vidu: response.vidu,
    livekit_url: response.livekit_url,
    livekit_token: response.livekit_token,
    idle_video_url: response.idle_video_url,
    idle_video_urls: response.idle_video_urls,
    idle_image_url: response.idle_image_url,
    visual_input: response.visual_input,
  }
}

export function saveSessionLaunchState(state: SessionLaunchState): void {
  const storage = getSessionStorage()
  if (!storage || !state.session_id) return
  storage.setItem(storageKey(state.session_id), JSON.stringify(state))
}

export function loadSessionLaunchState(sessionId: string): SessionLaunchState | null {
  const storage = getSessionStorage()
  if (!storage || !sessionId) return null
  const raw = storage.getItem(storageKey(sessionId))
  if (!raw) return null

  const parsed = parseJSON<Partial<SessionLaunchState>>(raw)
  if (!parsed || parsed.session_id !== sessionId) return null

  return {
    session_id: sessionId,
    character_id: parsed.character_id || '',
    mode: normalizeMode(parsed.mode || '', 'standard'),
    streaming_mode: parsed.streaming_mode || 'direct',
    return_path: normalizeReturnPath(parsed.return_path || ''),
    avatar_enabled: parsed.avatar_enabled,
    idle_strategy: normalizeIdleStrategy(parsed.idle_strategy || ''),
    audio_input: parsed.audio_input,
    baidu_xiling: parsed.baidu_xiling,
    xunfei: parsed.xunfei,
    vidu: parsed.vidu,
    livekit_url: parsed.livekit_url,
    livekit_token: parsed.livekit_token,
    idle_video_url: parsed.idle_video_url,
    idle_video_urls: Array.isArray(parsed.idle_video_urls) ? parsed.idle_video_urls : undefined,
    idle_image_url: parsed.idle_image_url,
    visual_input: parsed.visual_input,
  }
}

export function clearSessionLaunchState(sessionId: string): void {
  const storage = getSessionStorage()
  if (!storage || !sessionId) return
  storage.removeItem(storageKey(sessionId))
}

export function sessionLaunchStateFromQuery(
  sessionId: string,
  query: Record<string, unknown>,
): SessionLaunchState | null {
  const streamingMode = firstQueryValue(query.streaming_mode)
  const mode = firstQueryValue(query.mode)
  const avatarEnabled = firstQueryValue(query.avatar_enabled)
  const idleStrategy = firstQueryValue(query.idle_strategy)
  const characterId = firstQueryValue(query.character_id)
  const livekitUrl = firstQueryValue(query.livekit_url)
  const livekitToken = firstQueryValue(query.livekit_token)
  const idleVideoUrl = firstQueryValue(query.idle_video_url)
  const idleVideoUrls = parseJSON<string[]>(firstQueryValue(query.idle_video_urls))
  const idleImageUrl = firstQueryValue(query.idle_image_url)
  const audioInput = parseJSON<SessionAudioInputConfig>(firstQueryValue(query.audio_input))
  const baiduXiling = parseJSON<BaiduXilingSessionConfig>(firstQueryValue(query.baidu_xiling))
  const xunfei = parseJSON<XunfeiSessionConfig>(firstQueryValue(query.xunfei))
  const vidu = parseJSON<ViduSessionConfig>(firstQueryValue(query.vidu))
  const visualInput = parseJSON<SessionVisualInputConfig>(firstQueryValue(query.visual_input))
  const returnPath = normalizeReturnPath(firstQueryValue(query.return_path))

  if (!streamingMode && !mode && !avatarEnabled && !idleStrategy && !characterId && !livekitUrl && !livekitToken && !idleVideoUrl && !idleVideoUrls && !idleImageUrl && !audioInput && !baiduXiling && !xunfei && !vidu && !visualInput && !returnPath) {
    return null
  }

  return {
    session_id: sessionId,
    character_id: characterId,
    mode: normalizeMode(mode, 'standard'),
    streaming_mode: streamingMode || 'direct',
    return_path: returnPath,
    avatar_enabled: avatarEnabled ? avatarEnabled === 'true' : undefined,
    idle_strategy: normalizeIdleStrategy(idleStrategy),
    baidu_xiling: baiduXiling,
    xunfei,
    vidu,
    livekit_url: livekitUrl || undefined,
    livekit_token: livekitToken || undefined,
    idle_video_url: idleVideoUrl || undefined,
    idle_video_urls: Array.isArray(idleVideoUrls) ? idleVideoUrls : undefined,
    idle_image_url: idleImageUrl || undefined,
    audio_input: audioInput,
    visual_input: visualInput,
  }
}
