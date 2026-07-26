// Character image info
export type PipelineMode = 'standard' | 'omni'

export interface ImageInfo {
  filename: string
  orig_name: string
  added_at: string
  url?: string
}

export type KnowledgeSourceStatus = 'indexing' | 'ready' | 'failed'

export interface KnowledgeSource {
  id: string
  title: string
  filename: string
  mime_type: string
  relative_path?: string
  stored_path?: string
  indexable: boolean
  status: KnowledgeSourceStatus
  chunk_count: number
  error?: string
  created_at: string
  updated_at: string
  indexed_at?: string
}

export interface KnowledgeUploadSkippedFile {
  filename: string
  reason: string
}

// Character data model
export type AvatarBackend = 'local_image' | 'baidu_xiling' | 'xunfei' | 'vidu'

export interface BaiduXilingCharacterConfig {
  figure_id: string
  figure_name?: string
  camera_id?: string
  thumbnail_url?: string
  preview_video_url?: string
  source_image_url?: string
  status?: string
  width?: number
  height?: number
}

export interface XunfeiAvatarConfig {
  avatar_id: string
  avatar_name?: string
  scene_id?: string
  vcn: string
  vcns?: string[]
  thumbnail_url?: string
  preview_video_url?: string
  source_image_url?: string
  status?: string
  protocol?: 'xrtc' | 'rtmp' | 'webrtc' | 'flv'
  width?: number
  height?: number
  fps?: number
  bitrate?: number
  speed?: number
  pitch?: number
  volume?: number
  air?: number
}

export interface OfflineVideoTTSConfig {
  provider: string
  model?: string
  voice: string
}

export interface AgentExtensionConfig {
  name?: string
  url: string
  enabled: boolean
}

export interface Character {
  id: string
  name: string
  description: string
  avatar_image: string
  avatar_backend: AvatarBackend
  baidu_xiling?: BaiduXilingCharacterConfig | null
  xunfei?: XunfeiAvatarConfig | null
  offline_video_tts?: OfflineVideoTTSConfig | null
  idle_video_url?: string
  idle_video_urls?: string[]
  use_face_crop: boolean
  mode: PipelineMode
  voice_provider: string
  voice_type: string
  components: CharacterComponents
  speaking_style: string
  personality: string
  welcome_message: string
  system_prompt: string
  tags: string[]
  images: ImageInfo[]
  agent_extensions?: AgentExtensionConfig[]
  active_image: string
  image_mode: string
  created_at: string
  updated_at: string
}

export type CharacterForm = Omit<Character, 'id' | 'created_at' | 'updated_at' | 'images' | 'active_image'>

export interface CharacterComponents {
  llm: string
  asr: string
  tts: string
  tts_model?: string
}

export interface ComponentOption {
  id: string
  name: string
  model: string
  default: boolean
  available: boolean
}

export interface ComponentsResponse {
  llm: ComponentOption[]
  asr: ComponentOption[]
  tts: ComponentOption[]
}

export type OfflineVideoStatus = 'queued' | 'running' | 'completed' | 'failed'

export interface OfflineVideoJob {
  id: string
  character_id: string
  title: string
  provider?: string
  input_type: 'text' | 'audio'
  text?: string
  status: OfflineVideoStatus
  stage?: string
  message?: string
  progress: number
  error?: string
  audio_filename?: string
  video_filename?: string
  video_url?: string
  remote_video_url?: string
  baidu_task_id?: string
  duration_ms?: number
  width?: number
  height?: number
  fps?: number
  frame_count?: number
  audio_sample_rate?: number
  created_at: string
  updated_at: string
  finished_at?: string
}

// Settings
export interface DoubaoSettings {
  access_token: string
  app_id: string
  api_key: string
}

export interface LiveKitSettings {
  url: string
  api_key: string
  api_secret: string
}

export interface ModelProviderSettings {
  dashscope_api_key: string
  openai_api_key: string
}

export interface InferenceSettings {
  grpc_addr: string
}

export interface Settings {
  doubao: DoubaoSettings
  livekit: LiveKitSettings
  model_providers: ModelProviderSettings
  inference: InferenceSettings
}

// Launch config
export interface ConfigParam {
  name: string
  path: string
  value: string | number
  readonly: boolean
  requires_restart: boolean
  options?: string[]
}

export interface ConfigSection {
  key: 'avatar' | 'video_output' | 'gpu' | string
  title: string
  badge: 'restart' | 'configurable'
  params: ConfigParam[]
  collapsed?: boolean
}

export interface LaunchConfig {
  active_model: string
  configured_default_model: string
  avatar_enabled: boolean
  config_status: AvatarModelConfigStatus
  sections: ConfigSection[]
}

export interface LaunchConfigUpdate {
  model: string
  params: Array<{ path: string; value: string | number }>
}

export interface AvatarModelConfigStatus {
  has_infer_params: boolean
  config_sections_available: string[]
}

export interface AvatarModelDescriptor {
  name: string
  display_name: string
  is_active: boolean
  is_configured_default: boolean
  config_status: AvatarModelConfigStatus
}

export interface AvatarModelInfo {
  active_model: string
  configured_default_model: string
  avatar_enabled: boolean
  models: AvatarModelDescriptor[]
  config_status: AvatarModelConfigStatus
}

// Voice types
export interface VoiceOption {
  label: string
  value: string
  labelEn?: string
}

export const QWEN_TTS_MODEL_OPTIONS: VoiceOption[] = [
  { label: 'qwen3-tts-flash-realtime', value: 'qwen3-tts-flash-realtime' },
  { label: 'cosyvoice-v3-plus', value: 'cosyvoice-v3-plus' },
  { label: 'cosyvoice-v3-flash', value: 'cosyvoice-v3-flash' },
  { label: 'cosyvoice-v3.5-plus', value: 'cosyvoice-v3.5-plus' },
  { label: 'cosyvoice-v3.5-flash', value: 'cosyvoice-v3.5-flash' },
]

// Doubao-TTS 2.0 official voices. Values match Volcengine voice_type.
export const DOUBAO_TTS_VOICE_OPTIONS: VoiceOption[] = [
  { label: 'Vivi 2.0', value: 'zh_female_vv_uranus_bigtts', labelEn: 'Vivi 2.0' },
  { label: '小何 2.0', value: 'zh_female_xiaohe_uranus_bigtts', labelEn: 'Xiaohe 2.0' },
  { label: '云舟 2.0', value: 'zh_male_m191_uranus_bigtts', labelEn: 'Yunzhou 2.0' },
  { label: '小天 2.0', value: 'zh_male_taocheng_uranus_bigtts', labelEn: 'Xiaotian 2.0' },
  { label: '刘飞 2.0', value: 'zh_male_liufei_uranus_bigtts', labelEn: 'Liu Fei 2.0' },
  { label: '魅力苏菲 2.0', value: 'zh_female_sophie_uranus_bigtts', labelEn: 'Sophie 2.0' },
  { label: '清新女声 2.0', value: 'zh_female_qingxinnvsheng_uranus_bigtts', labelEn: 'Fresh female 2.0' },
  { label: '知性灿灿 2.0', value: 'zh_female_cancan_uranus_bigtts', labelEn: 'Cancan 2.0' },
  { label: '撒娇学妹 2.0', value: 'zh_female_sajiaoxuemei_uranus_bigtts', labelEn: 'Playful junior 2.0' },
  { label: '甜美小源 2.0', value: 'zh_female_tianmeixiaoyuan_uranus_bigtts', labelEn: 'Sweet Xiaoyuan 2.0' },
  { label: '甜美桃子 2.0', value: 'zh_female_tianmeitaozi_uranus_bigtts', labelEn: 'Sweet Taozi 2.0' },
  { label: '爽快思思 2.0', value: 'zh_female_shuangkuaisisi_uranus_bigtts', labelEn: 'Sisi 2.0' },
  { label: '佩奇猪 2.0', value: 'zh_female_peiqi_uranus_bigtts' },
  { label: '邻家女孩 2.0', value: 'zh_female_linjianvhai_uranus_bigtts', labelEn: 'Neighbor girl 2.0' },
  { label: '少年梓辛/Brayan 2.0', value: 'zh_male_shaonianzixin_uranus_bigtts', labelEn: 'Brayan 2.0' },
  { label: '猴哥 2.0', value: 'zh_male_sunwukong_uranus_bigtts' },
  { label: 'Tina老师 2.0', value: 'zh_female_yingyujiaoxue_uranus_bigtts', labelEn: 'Teacher Tina 2.0' },
  { label: '暖阳女声 2.0', value: 'zh_female_kefunvsheng_uranus_bigtts', labelEn: 'Warm female 2.0' },
  { label: '儿童绘本 2.0', value: 'zh_female_xiaoxue_uranus_bigtts' },
  { label: '大壹 2.0', value: 'zh_male_dayi_uranus_bigtts' },
  { label: '黑猫侦探社咪仔 2.0', value: 'zh_female_mizai_uranus_bigtts' },
  { label: '鸡汤女 2.0', value: 'zh_female_jitangnv_uranus_bigtts' },
  { label: '魅力女友 2.0', value: 'zh_female_meilinvyou_uranus_bigtts' },
  { label: '流畅女声 2.0', value: 'zh_female_liuchangnv_uranus_bigtts' },
  { label: '儒雅逸辰 2.0', value: 'zh_male_ruyayichen_uranus_bigtts' },
  { label: 'Tim', value: 'en_male_tim_uranus_bigtts', labelEn: 'Tim' },
  { label: 'Dacey', value: 'en_female_dacey_uranus_bigtts', labelEn: 'Dacey' },
  { label: 'Stokie', value: 'en_female_stokie_uranus_bigtts', labelEn: 'Stokie' },
  { label: '温柔妈妈 2.0', value: 'zh_female_wenroumama_uranus_bigtts', labelEn: 'Gentle mother 2.0' },
  { label: '解说小明 2.0', value: 'zh_male_jieshuoxiaoming_uranus_bigtts' },
  { label: 'TVB女声 2.0', value: 'zh_female_tvbnv_uranus_bigtts' },
  { label: '译制片男 2.0', value: 'zh_male_yizhipiannan_uranus_bigtts' },
  { label: '俏皮女声 2.0', value: 'zh_female_qiaopinv_uranus_bigtts' },
  { label: '直率英子 2.0', value: 'zh_female_zhishuaiyingzi_uranus_bigtts' },
  { label: '邻家男孩 2.0', value: 'zh_male_linjiananhai_uranus_bigtts' },
  { label: '四郎 2.0', value: 'zh_male_silang_uranus_bigtts' },
  { label: '儒雅青年 2.0', value: 'zh_male_ruyaqingnian_uranus_bigtts' },
  { label: '擎苍 2.0', value: 'zh_male_qingcang_uranus_bigtts' },
  { label: '熊二 2.0', value: 'zh_male_xionger_uranus_bigtts' },
  { label: '樱桃丸子 2.0', value: 'zh_female_yingtaowanzi_uranus_bigtts' },
  { label: '温暖阿虎/Alvin 2.0', value: 'zh_male_wennuanahu_uranus_bigtts' },
  { label: '奶气萌娃 2.0', value: 'zh_male_naiqimengwa_uranus_bigtts' },
  { label: '婆婆 2.0', value: 'zh_female_popo_uranus_bigtts' },
  { label: '高冷御姐 2.0', value: 'zh_female_gaolengyujie_uranus_bigtts', labelEn: 'Cool mature woman 2.0' },
  { label: '傲娇霸总 2.0', value: 'zh_male_aojiaobazong_uranus_bigtts' },
  { label: '懒音绵宝 2.0', value: 'zh_male_lanyinmianbao_uranus_bigtts' },
  { label: '反卷青年 2.0', value: 'zh_male_fanjuanqingnian_uranus_bigtts' },
  { label: '温柔淑女 2.0', value: 'zh_female_wenroushunv_uranus_bigtts', labelEn: 'Gentle lady 2.0' },
  { label: '古风少御 2.0', value: 'zh_female_gufengshaoyu_uranus_bigtts' },
  { label: '活力小哥 2.0', value: 'zh_male_huolixiaoge_uranus_bigtts' },
  { label: '霸气青叔 2.0', value: 'zh_male_baqiqingshu_uranus_bigtts' },
  { label: '悬疑解说 2.0', value: 'zh_male_xuanyijieshuo_uranus_bigtts' },
  { label: '萌丫头/Cutey 2.0', value: 'zh_female_mengyatou_uranus_bigtts' },
  { label: '贴心女声/Candy 2.0', value: 'zh_female_tiexinnvsheng_uranus_bigtts' },
  { label: '鸡汤妹妹/Hope 2.0', value: 'zh_female_jitangmei_uranus_bigtts' },
  { label: '磁性解说男声/Morgan 2.0', value: 'zh_male_cixingjieshuonan_uranus_bigtts' },
  { label: '亮嗓萌仔 2.0', value: 'zh_male_liangsangmengzai_uranus_bigtts' },
  { label: '开朗姐姐 2.0', value: 'zh_female_kailangjiejie_uranus_bigtts' },
  { label: '高冷沉稳 2.0', value: 'zh_male_gaolengchenwen_uranus_bigtts' },
  { label: '深夜播客 2.0', value: 'zh_male_shenyeboke_uranus_bigtts' },
  { label: '鲁班七号 2.0', value: 'zh_male_lubanqihao_uranus_bigtts' },
  { label: '娇喘女声 2.0', value: 'zh_female_jiaochuannv_uranus_bigtts' },
  { label: '林潇 2.0', value: 'zh_female_linxiao_uranus_bigtts' },
  { label: '玲玲姐姐 2.0', value: 'zh_female_lingling_uranus_bigtts' },
  { label: '春日部姐姐 2.0', value: 'zh_female_chunribu_uranus_bigtts' },
  { label: '唐僧 2.0', value: 'zh_male_tangseng_uranus_bigtts' },
  { label: '庄周 2.0', value: 'zh_male_zhuangzhou_uranus_bigtts' },
  { label: '开朗弟弟 2.0', value: 'zh_male_kailangdidi_uranus_bigtts' },
  { label: '猪八戒 2.0', value: 'zh_male_zhubajie_uranus_bigtts' },
  { label: '感冒电音姐姐 2.0', value: 'zh_female_ganmaodianyin_uranus_bigtts' },
  { label: '谄媚女声 2.0', value: 'zh_female_chanmeinv_uranus_bigtts' },
  { label: '女雷神 2.0', value: 'zh_female_nvleishen_uranus_bigtts' },
  { label: '亲切女声 2.0', value: 'zh_female_qinqienv_uranus_bigtts' },
  { label: '快乐小东 2.0', value: 'zh_male_kuailexiaodong_uranus_bigtts' },
  { label: '开朗学长 2.0', value: 'zh_male_kailangxuezhang_uranus_bigtts' },
  { label: '悠悠君子 2.0', value: 'zh_male_youyoujunzi_uranus_bigtts' },
  { label: '文静毛毛 2.0', value: 'zh_female_wenjingmaomao_uranus_bigtts' },
  { label: '知性女声 2.0', value: 'zh_female_zhixingnv_uranus_bigtts' },
  { label: '清爽男大 2.0', value: 'zh_male_qingshuangnanda_uranus_bigtts' },
  { label: '渊博小叔 2.0', value: 'zh_male_yuanboxiaoshu_uranus_bigtts' },
  { label: '阳光青年 2.0', value: 'zh_male_yangguangqingnian_uranus_bigtts' },
  { label: '清澈梓梓 2.0', value: 'zh_female_qingchezizi_uranus_bigtts' },
  { label: '甜美悦悦 2.0', value: 'zh_female_tianmeiyueyue_uranus_bigtts' },
  { label: '心灵鸡汤 2.0', value: 'zh_female_xinlingjitang_uranus_bigtts' },
  { label: '温柔小哥 2.0', value: 'zh_male_wenrouxiaoge_uranus_bigtts' },
  { label: '柔美女友 2.0', value: 'zh_female_roumeinvyou_uranus_bigtts' },
  { label: '东方浩然 2.0', value: 'zh_male_dongfanghaoran_uranus_bigtts' },
  { label: '温柔小雅 2.0', value: 'zh_female_wenrouxiaoya_uranus_bigtts' },
  { label: '天才童声 2.0', value: 'zh_male_tiancaitongsheng_uranus_bigtts' },
  { label: '武则天 2.0', value: 'zh_female_wuzetian_uranus_bigtts' },
  { label: '顾姐 2.0', value: 'zh_female_gujie_uranus_bigtts' },
  { label: '广告解说 2.0', value: 'zh_male_guanggaojieshuo_uranus_bigtts' },
  { label: '少儿故事 2.0', value: 'zh_female_shaoergushi_uranus_bigtts' },
]

export const COSYVOICE_V3_FLASH_VOICE_OPTIONS: VoiceOption[] = [
  { label: '龙安洋 (longanyang)', value: 'longanyang' },
  { label: '龙安欢（V3） (longanhuan_v3)', value: 'longanhuan_v3' },
  { label: '龙安欢 (longanhuan)', value: 'longanhuan' },
  { label: '龙呼呼 (longhuhu_v3)', value: 'longhuhu_v3' },
  { label: '龙泡泡 (longpaopao_v3)', value: 'longpaopao_v3' },
  { label: '龙杰力豆 (longjielidou_v3)', value: 'longjielidou_v3' },
  { label: '龙仙 (longxian_v3)', value: 'longxian_v3' },
  { label: '龙铃 (longling_v3)', value: 'longling_v3' },
  { label: '龙闪闪 (longshanshan_v3)', value: 'longshanshan_v3' },
  { label: '龙牛牛 (longniuniu_v3)', value: 'longniuniu_v3' },
  { label: '龙嘉欣 (longjiaxin_v3)', value: 'longjiaxin_v3' },
  { label: '龙嘉怡 (longjiayi_v3)', value: 'longjiayi_v3' },
  { label: '龙安粤 (longanyue_v3)', value: 'longanyue_v3' },
  { label: '龙老铁 (longlaotie_v3)', value: 'longlaotie_v3' },
  { label: '龙陕哥 (longshange_v3)', value: 'longshange_v3' },
  { label: '龙安闽 (longanmin_v3)', value: 'longanmin_v3' },
  { label: 'loongkyong (loongkyong_v3)', value: 'loongkyong_v3' },
  { label: 'Riko (loongriko_v3)', value: 'loongriko_v3' },
  { label: 'loongtomoka (loongtomoka_v3)', value: 'loongtomoka_v3' },
  { label: 'loongabby (loongabby_v3)', value: 'loongabby_v3' },
  { label: 'loongandy (loongandy_v3)', value: 'loongandy_v3' },
  { label: 'loongannie (loongannie_v3)', value: 'loongannie_v3' },
  { label: 'loongava (loongava_v3)', value: 'loongava_v3' },
  { label: 'loongbeth (loongbeth_v3)', value: 'loongbeth_v3' },
  { label: 'loongbetty (loongbetty_v3)', value: 'loongbetty_v3' },
  { label: 'loongcally (loongcally_v3)', value: 'loongcally_v3' },
  { label: 'loongcindy (loongcindy_v3)', value: 'loongcindy_v3' },
  { label: 'loongdavid (loongdavid_v3)', value: 'loongdavid_v3' },
  { label: 'loongdonna (loongdonna_v3)', value: 'loongdonna_v3' },
  { label: 'loongemily (loongemily_v3)', value: 'loongemily_v3' },
  { label: 'loongeric (loongeric_v3)', value: 'loongeric_v3' },
  { label: 'loongluna (loongluna_v3)', value: 'loongluna_v3' },
  { label: 'loongluca (loongluca_v3)', value: 'loongluca_v3' },
  { label: 'loongtomoya (loongtomoya_v3)', value: 'loongtomoya_v3' },
  { label: 'Yuuna (loongyuuna_v3)', value: 'loongyuuna_v3' },
  { label: 'Yuuma (loongyuuma_v3)', value: 'loongyuuma_v3' },
  { label: 'Jihun (loongjihun_v3)', value: 'loongjihun_v3' },
  { label: 'loongindah (loongindah_v3)', value: 'loongindah_v3' },
  { label: '龙飞 (longfei_v3)', value: 'longfei_v3' },
  { label: '龙应笑 (longyingxiao_v3)', value: 'longyingxiao_v3' },
  { label: '龙应询 (longyingxun_v3)', value: 'longyingxun_v3' },
  { label: '龙应静 (longyingjing_v3)', value: 'longyingjing_v3' },
  { label: '龙应聆 (longyingling_v3)', value: 'longyingling_v3' },
  { label: '龙应桃 (longyingtao_v3)', value: 'longyingtao_v3' },
  { label: '龙小淳 (longxiaochun_v3)', value: 'longxiaochun_v3' },
  { label: '龙小夏 (longxiaoxia_v3)', value: 'longxiaoxia_v3' },
  { label: 'YUMI (longyumi_v3)', value: 'longyumi_v3' },
  { label: '龙安昀 (longanyun_v3)', value: 'longanyun_v3' },
  { label: '龙安温 (longanwen_v3)', value: 'longanwen_v3' },
  { label: '龙安莉 (longanli_v3)', value: 'longanli_v3' },
  { label: '龙安朗 (longanlang_v3)', value: 'longanlang_v3' },
  { label: '龙应沐 (longyingmu_v3)', value: 'longyingmu_v3' },
  { label: '龙安台 (longantai_v3)', value: 'longantai_v3' },
  { label: '龙华 (longhua_v3)', value: 'longhua_v3' },
  { label: '龙橙 (longcheng_v3)', value: 'longcheng_v3' },
  { label: '龙泽 (longze_v3)', value: 'longze_v3' },
  { label: '龙哲 (longzhe_v3)', value: 'longzhe_v3' },
  { label: '龙颜 (longyan_v3)', value: 'longyan_v3' },
  { label: '龙星 (longxing_v3)', value: 'longxing_v3' },
  { label: '龙天 (longtian_v3)', value: 'longtian_v3' },
  { label: '龙婉 (longwan_v3)', value: 'longwan_v3' },
  { label: '龙嫱 (longqiang_v3)', value: 'longqiang_v3' },
  { label: '龙菲菲 (longfeifei_v3)', value: 'longfeifei_v3' },
  { label: '龙浩 (longhao_v3)', value: 'longhao_v3' },
  { label: '龙安柔 (longanrou_v3)', value: 'longanrou_v3' },
  { label: '龙寒 (longhan_v3)', value: 'longhan_v3' },
  { label: '龙安智 (longanzhi_v3)', value: 'longanzhi_v3' },
  { label: '龙安灵 (longanling_v3)', value: 'longanling_v3' },
  { label: '龙安雅 (longanya_v3)', value: 'longanya_v3' },
  { label: '龙安亲 (longanqin_v3)', value: 'longanqin_v3' },
  { label: '龙妙 (longmiao_v3)', value: 'longmiao_v3' },
  { label: '龙三叔 (longsanshu_v3)', value: 'longsanshu_v3' },
  { label: '龙媛 (longyuan_v3)', value: 'longyuan_v3' },
  { label: '龙悦 (longyue_v3)', value: 'longyue_v3' },
  { label: '龙修 (longxiu_v3)', value: 'longxiu_v3' },
  { label: '龙楠 (longnan_v3)', value: 'longnan_v3' },
  { label: '龙安燃 (longanran_v3)', value: 'longanran_v3' },
  { label: '龙婉君 (longwanjun_v3)', value: 'longwanjun_v3' },
  { label: '龙逸尘 (longyichen_v3)', value: 'longyichen_v3' },
  { label: '龙老伯 (longlaobo_v3)', value: 'longlaobo_v3' },
  { label: '龙老姨 (longlaoyi_v3)', value: 'longlaoyi_v3' },
  { label: '龙机器 (longjiqi_v3)', value: 'longjiqi_v3' },
  { label: '龙猴哥 (longhouge_v3)', value: 'longhouge_v3' },
  { label: '龙黛玉 (longdaiyu_v3)', value: 'longdaiyu_v3' },
  { label: '龙安宣 (longanxuan_v3)', value: 'longanxuan_v3' },
  { label: '龙硕 (longshuo_v3)', value: 'longshuo_v3' },
  { label: '龙书 (longshu_v3)', value: 'longshu_v3' },
  { label: 'Bella3.0 (loongbella_v3)', value: 'loongbella_v3' },
]

export const COSYVOICE_V3_PLUS_VOICE_OPTIONS: VoiceOption[] = [
  { label: '龙安洋 (longanyang)', value: 'longanyang' },
  { label: '龙安欢 (longanhuan)', value: 'longanhuan' },
]

// Aliyun Qwen TTS system voices — values match the voice request parameter.
export const QWEN_TTS_VOICE_OPTIONS: VoiceOption[] = [
  { label: '芊悦 (Cherry)', value: 'Cherry' },
  { label: '苏瑶 (Serena)', value: 'Serena' },
  { label: '晨煦 (Ethan)', value: 'Ethan' },
  { label: '千雪 (Chelsie)', value: 'Chelsie' },
  { label: '茉兔 (Momo)', value: 'Momo' },
  { label: '十三 (Vivian)', value: 'Vivian' },
  { label: '月白 (Moon)', value: 'Moon' },
  { label: '四月 (Maia)', value: 'Maia' },
  { label: '凯 (Kai)', value: 'Kai' },
  { label: '不吃鱼 (Nofish)', value: 'Nofish' },
  { label: '萌宝 (Bella)', value: 'Bella' },
  { label: '詹妮弗 (Jennifer)', value: 'Jennifer' },
  { label: '甜茶 (Ryan)', value: 'Ryan' },
  { label: '卡捷琳娜 (Katerina)', value: 'Katerina' },
  { label: '艾登 (Aiden)', value: 'Aiden' },
  { label: '沧明子 (Eldric Sage)', value: 'Eldric Sage' },
  { label: '乖小妹 (Mia)', value: 'Mia' },
  { label: '沙小弥 (Mochi)', value: 'Mochi' },
  { label: '燕铮莺 (Bellona)', value: 'Bellona' },
  { label: '田叔 (Vincent)', value: 'Vincent' },
  { label: '萌小姬 (Bunny)', value: 'Bunny' },
  { label: '阿闻 (Neil)', value: 'Neil' },
  { label: '墨讲师 (Elias)', value: 'Elias' },
  { label: '徐大爷 (Arthur)', value: 'Arthur' },
  { label: '邻家妹妹 (Nini)', value: 'Nini' },
  { label: '小婉 (Seren)', value: 'Seren' },
  { label: '顽屁小孩 (Pip)', value: 'Pip' },
  { label: '少女阿月 (Stella)', value: 'Stella' },
  { label: '博德加 (Bodega)', value: 'Bodega' },
  { label: '索尼莎 (Sonrisa)', value: 'Sonrisa' },
  { label: '阿列克 (Alek)', value: 'Alek' },
  { label: '多尔切 (Dolce)', value: 'Dolce' },
  { label: '素熙 (Sohee)', value: 'Sohee' },
  { label: '小野杏 (Ono Anna)', value: 'Ono Anna' },
  { label: '莱恩 (Lenn)', value: 'Lenn' },
  { label: '埃米尔安 (Emilien)', value: 'Emilien' },
  { label: '安德雷 (Andre)', value: 'Andre' },
  { label: '拉迪奥·戈尔 (Radio Gol)', value: 'Radio Gol' },
  { label: '上海-阿珍 (Jada)', value: 'Jada' },
  { label: '北京-晓东 (Dylan)', value: 'Dylan' },
  { label: '南京-老李 (Li)', value: 'Li' },
  { label: '陕西-秦川 (Marcus)', value: 'Marcus' },
  { label: '闽南-阿杰 (Roy)', value: 'Roy' },
  { label: '天津-李彼得 (Peter)', value: 'Peter' },
  { label: '四川-晴儿 (Sunny)', value: 'Sunny' },
  { label: '四川-程川 (Eric)', value: 'Eric' },
  { label: '粤语-阿强 (Rocky)', value: 'Rocky' },
  { label: '粤语-阿清 (Kiki)', value: 'Kiki' },
]

// Aliyun Qwen3.5 Omni realtime voices — values match the voice request parameter.
export const QWEN_OMNI_VOICE_OPTIONS: VoiceOption[] = [
  { label: '甜甜 (Tina)', value: 'Tina' },
  { label: '林欣宜 (Cindy)', value: 'Cindy' },
  { label: '清欢 (Liora Mira)', value: 'Liora Mira' },
  { label: '知芝 (Sunnybobi)', value: 'Sunnybobi' },
  { label: '林川野 (Raymond)', value: 'Raymond' },
  { label: '晨煦 (Ethan)', value: 'Ethan' },
  { label: '予安 (Theo Calm)', value: 'Theo Calm' },
  { label: '苏瑶 (Serena)', value: 'Serena' },
  { label: '厚 (Harvey)', value: 'Harvey' },
  { label: '四月 (Maia)', value: 'Maia' },
  { label: '江晨 (Evan)', value: 'Evan' },
  { label: '小乔妹 (Qiao)', value: 'Qiao' },
  { label: '茉兔 (Momo)', value: 'Momo' },
  { label: '伟伦 (Wil)', value: 'Wil' },
  { label: '台普 - 安琪 (Angel)', value: 'Angel' },
  { label: '东厂 - 李公公 (Li Cassian)', value: 'Li Cassian' },
  { label: '温柔生活博主 - 舒然 (Mia)', value: 'Mia' },
  { label: '喜剧担当 - 阿逗 (Joyner)', value: 'Joyner' },
  { label: '金爷 (Gold)', value: 'Gold' },
  { label: '卡捷琳娜 (Katerina)', value: 'Katerina' },
  { label: '甜茶 (Ryan)', value: 'Ryan' },
  { label: '詹妮弗 (Jennifer)', value: 'Jennifer' },
  { label: '艾登 (Aiden)', value: 'Aiden' },
  { label: '敏儿 (Mione)', value: 'Mione' },
  { label: '四川 - 晴儿 (Sunny)', value: 'Sunny' },
  { label: '北京 - 晓东 (Dylan)', value: 'Dylan' },
  { label: '四川 - 程川 (Eric)', value: 'Eric' },
  { label: '天津 - 李彼得 (Peter)', value: 'Peter' },
  { label: '阿樸伯 (Joseph Chen)', value: 'Joseph Chen' },
  { label: '陕西 - 秦川 (Marcus)', value: 'Marcus' },
  { label: '南京 - 老李 (Li)', value: 'Li' },
  { label: '粤语 - 阿清 (Kiki)', value: 'Kiki' },
  { label: '粤语 - 阿强 (Rocky)', value: 'Rocky' },
  { label: '素熙 (Sohee)', value: 'Sohee' },
  { label: '莱恩 (Lenn)', value: 'Lenn' },
  { label: '小野杏 (Ono Anna)', value: 'Ono Anna' },
  { label: '索尼莎 (Sonrisa)', value: 'Sonrisa' },
  { label: '博德加 (Bodega)', value: 'Bodega' },
  { label: '埃米尔安 (Emilien)', value: 'Emilien' },
  { label: '安德雷 (Andre)', value: 'Andre' },
  { label: '拉迪奥·戈尔 (Radio Gol)', value: 'Radio Gol' },
  { label: '阿列克 (Alek)', value: 'Alek' },
  { label: '阿力 (Rizky)', value: 'Rizky' },
  { label: '萝雅 (Roya)', value: 'Roya' },
  { label: '阿尔达 (Arda)', value: 'Arda' },
  { label: '阿幸 (Hana)', value: 'Hana' },
  { label: '多尔切 (Dolce)', value: 'Dolce' },
  { label: '雅克 (Jakub)', value: 'Jakub' },
  { label: '海娜 (Griet)', value: 'Griet' },
  { label: '艾莉卡 (Eliška)', value: 'Eliška' },
  { label: '玛丽娜 (Marina)', value: 'Marina' },
  { label: '西芮 (Siiri)', value: 'Siiri' },
  { label: '林恩 (Ingrid)', value: 'Ingrid' },
  { label: '海娜 (Sigga)', value: 'Sigga' },
  { label: '雅娜 (Bea)', value: 'Bea' },
  { label: '思怡 (Chloe)', value: 'Chloe' },
]

// xAI Grok Voice Agent built-in voices — values match the voice session parameter.
export const GROK_VOICE_OPTIONS: VoiceOption[] = [
  { label: 'Eve', value: 'eve' },
  { label: 'Ara', value: 'ara' },
  { label: 'Rex', value: 'rex' },
  { label: 'Sal', value: 'sal' },
  { label: 'Leo', value: 'leo' },
]

// Google Gemini Live/TTS voices — values match the voice_name request parameter.
export const GEMINI_LIVE_VOICE_OPTIONS: VoiceOption[] = [
  { label: 'Kore / 坚定', value: 'Kore', labelEn: 'Kore · Firm' },
  { label: 'Puck / 活泼', value: 'Puck', labelEn: 'Puck · Upbeat' },
  { label: 'Zephyr / 明亮', value: 'Zephyr', labelEn: 'Zephyr · Bright' },
  { label: 'Charon / 信息感', value: 'Charon', labelEn: 'Charon · Informative' },
  { label: 'Fenrir / 兴奋', value: 'Fenrir', labelEn: 'Fenrir · Excitable' },
  { label: 'Leda / 年轻', value: 'Leda', labelEn: 'Leda · Youthful' },
  { label: 'Orus / 坚定', value: 'Orus', labelEn: 'Orus · Firm' },
  { label: 'Aoede / 轻快', value: 'Aoede', labelEn: 'Aoede · Breezy' },
  { label: 'Callirrhoe / 随和', value: 'Callirrhoe', labelEn: 'Callirrhoe · Easy-going' },
  { label: 'Autonoe / 明亮', value: 'Autonoe', labelEn: 'Autonoe · Bright' },
  { label: 'Enceladus / 气声', value: 'Enceladus', labelEn: 'Enceladus · Breathy' },
  { label: 'Iapetus / 清晰', value: 'Iapetus', labelEn: 'Iapetus · Clear' },
  { label: 'Umbriel / 随和', value: 'Umbriel', labelEn: 'Umbriel · Easy-going' },
  { label: 'Algieba / 顺滑', value: 'Algieba', labelEn: 'Algieba · Smooth' },
  { label: 'Despina / 顺滑', value: 'Despina', labelEn: 'Despina · Smooth' },
  { label: 'Erinome / 清晰', value: 'Erinome', labelEn: 'Erinome · Clear' },
  { label: 'Algenib / 沙哑', value: 'Algenib', labelEn: 'Algenib · Gravelly' },
  { label: 'Rasalgethi / 信息感', value: 'Rasalgethi', labelEn: 'Rasalgethi · Informative' },
  { label: 'Laomedeia / 活泼', value: 'Laomedeia', labelEn: 'Laomedeia · Upbeat' },
  { label: 'Achernar / 柔和', value: 'Achernar', labelEn: 'Achernar · Soft' },
  { label: 'Alnilam / 坚定', value: 'Alnilam', labelEn: 'Alnilam · Firm' },
  { label: 'Schedar / 平稳', value: 'Schedar', labelEn: 'Schedar · Even' },
  { label: 'Gacrux / 成熟', value: 'Gacrux', labelEn: 'Gacrux · Mature' },
  { label: 'Pulcherrima / 前倾', value: 'Pulcherrima', labelEn: 'Pulcherrima · Forward' },
  { label: 'Achird / 友好', value: 'Achird', labelEn: 'Achird · Friendly' },
  { label: 'Zubenelgenubi / 休闲', value: 'Zubenelgenubi', labelEn: 'Zubenelgenubi · Casual' },
  { label: 'Vindemiatrix / 温柔', value: 'Vindemiatrix', labelEn: 'Vindemiatrix · Gentle' },
  { label: 'Sadachbia / 生动', value: 'Sadachbia', labelEn: 'Sadachbia · Lively' },
  { label: 'Sadaltager / 知识感', value: 'Sadaltager', labelEn: 'Sadaltager · Knowledgeable' },
  { label: 'Sulafat / 温暖', value: 'Sulafat', labelEn: 'Sulafat · Warm' },
]

// SC2.0 official voices — values match SC20_VOICES keys in doubao_config.py
export const VOICE_OPTIONS: VoiceOption[] = [
  // Female
  { label: '傲娇女友', value: '傲娇女友' },
  { label: '冰娇姐姐', value: '冰娇姐姐' },
  { label: '成熟姐姐', value: '成熟姐姐' },
  { label: '可爱女生', value: '可爱女生' },
  { label: '暖心学姐', value: '暖心学姐' },
  { label: '贴心女友', value: '贴心女友' },
  { label: '温柔文雅', value: '温柔文雅' },
  { label: '妩媚御姐', value: '妩媚御姐' },
  { label: '性感御姐', value: '性感御姐' },
  // Male
  { label: '爱气凌人', value: '爱气凌人' },
  { label: '傲娇公子', value: '傲娇公子' },
  { label: '傲娇精英', value: '傲娇精英' },
  { label: '傲慢少爷', value: '傲慢少爷' },
  { label: '霸道少爷', value: '霸道少爷' },
  { label: '冰娇白莲', value: '冰娇白莲' },
  { label: '不羁青年', value: '不羁青年' },
  { label: '成熟总裁', value: '成熟总裁' },
  { label: '磁性男嗓', value: '磁性男嗓' },
  { label: '醋精男友', value: '醋精男友' },
  { label: '风发少年', value: '风发少年' },
  { label: '腹黑公子', value: '腹黑公子' },
]

export const OPENAI_VOICE_OPTIONS: VoiceOption[] = [
  { label: 'alloy', value: 'alloy' },
  { label: 'ash', value: 'ash' },
  { label: 'ballad', value: 'ballad' },
  { label: 'coral', value: 'coral' },
  { label: 'echo', value: 'echo' },
  { label: 'fable', value: 'fable' },
  { label: 'nova', value: 'nova' },
  { label: 'onyx', value: 'onyx' },
  { label: 'sage', value: 'sage' },
  { label: 'shimmer', value: 'shimmer' },
]

export const OPENAI_REALTIME_VOICE_OPTIONS: VoiceOption[] = [
  { label: 'Marin / 高质量', value: 'marin', labelEn: 'Marin · Recommended' },
  { label: 'Cedar / 高质量', value: 'cedar', labelEn: 'Cedar · Recommended' },
  { label: 'Alloy', value: 'alloy', labelEn: 'Alloy' },
  { label: 'Ash', value: 'ash', labelEn: 'Ash' },
  { label: 'Ballad', value: 'ballad', labelEn: 'Ballad' },
  { label: 'Coral', value: 'coral', labelEn: 'Coral' },
  { label: 'Echo', value: 'echo', labelEn: 'Echo' },
  { label: 'Sage', value: 'sage', labelEn: 'Sage' },
  { label: 'Shimmer', value: 'shimmer', labelEn: 'Shimmer' },
  { label: 'Verse', value: 'verse', labelEn: 'Verse' },
]
