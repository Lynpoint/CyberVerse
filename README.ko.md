<h1 align="center">CyberVerse</h1>
<p align="center"><em>CyberVerse는 오픈소스 <strong>실시간 디지털 휴먼 Agent 프레임워크</strong>입니다. WebRTC, persona memory, tools, RAG, 선택적 디지털 휴먼 비디오 기능을 기반으로 음성 상호작용 중심의 AI Agent를 구축하도록 돕습니다.</em></p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md"><strong>한국어</strong></a>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPL%20v3-blue.svg" alt="License: GPL v3"/></a>
  <a href="https://github.com/dsd2077/CyberVerse/pulls"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs Welcome"/></a>
  <a href="https://deepwiki.com/dsd2077/CyberVerse"><img src="https://deepwiki.com/badge.svg" alt="Ask DeepWiki" /></a>
  <a href="https://x.com/dsd2077"><img src="https://img.shields.io/badge/@dsd2077-black?logo=x&logoColor=white" alt="X" /></a>
</p>

<p align="center">
  <a href="docs/assets/logo.png"><img src="docs/assets/logo.png" alt="CyberVerse logo" width="100%"/></a>
</p>

## 후원사

<details open>
<summary>클릭하여 접기</summary>

<table>
<tr>
<td width="180"><a href="https://passport.compshare.cn/register?referral_code=IBmJcGPVu1RF78dMihkQCX"><img src="https://www.compshare.cn/logo-compshare.png" alt="Compshare" width="150"></a></td>
<td>CyberVerse를 후원해 주신 Compshare(优云智算)에 감사드립니다! Compshare는 UCloud 산하의 AI 클라우드 플랫폼으로, 온디맨드 GPU 대여와 모델 API 서비스를 제공합니다. <strong>핵심 GPU 대여 서비스는 모델, 알고리즘 및 애플리케이션 개발자를 위해 빠르게 시작할 수 있고 사용량에 따라 과금되는 GPU 인스턴스를 제공합니다.</strong> 또한 국내외 주요 모델에 대한 원스톱 액세스를 제공하며 Claude Code, Codex 및 API 호출을 지원합니다. <a href="https://passport.compshare.cn/register?referral_code=IBmJcGPVu1RF78dMihkQCX">이 초대 링크를 통해 등록하세요</a>.</td>
</tr>
</table>

</details>

---

### 사진 한 장으로 살아 움직이는 디지털 휴먼.

> 당신을 진짜로 보고, 듣고, 실시간으로 말을 건네는 나만의 J.A.R.V.I.S. 같은 AI를 꿈꿔본 적이 있나요?
>
> 그리운 사람을 다시 보고, 그 목소리를 듣고, 미소 짓는 모습을 볼 수 있다면 어떨까요?
>
> 혹은 늘 현실로 불러오고 싶었던 캐릭터가 있을지도 모릅니다.
>
> **사진 한 장이면 됩니다. CyberVerse가 그 존재를 살아 움직이게 합니다.**

## 디지털 휴먼 Agent란?

<p align="center">
  <a href="docs/assets/digital-human-agent.jpeg"><img src="docs/assets/digital-human-agent.jpeg" alt="CyberVerse 디지털 휴먼 Agent" width="100%"/></a>
</p>

## 데모
<p align="center"><em>아래 캐릭터는 데모 예시일 뿐입니다. CyberVerse에 내장되어 제공되지 않으며, 상업적 용도로 제공되지 않습니다.</em></p>

<p align="center">
  <a href="docs/assets/character1.png"><img src="docs/assets/character1.png" alt="CyberVerse 캐릭터 선택 갤러리" width="100%"/></a>
</p>

<p align="center">
  <a href="docs/assets/character2.png"><img src="docs/assets/character2.png" alt="CyberVerse 캐릭터 예시 갤러리" width="100%"/></a>
</p>

<div align="center">

| [![](docs/assets/爱丽丝.mov.png)](https://youtu.be/Lk88sew2x4o) | [![](docs/assets/丽娜.mov.png)](https://youtu.be/8jdQ3ThcwgA) |
|:---:|:---:|
| [**Alice — YouTube에서 보기**](https://youtu.be/Lk88sew2x4o) | [**Lina — YouTube에서 보기**](https://youtu.be/8jdQ3ThcwgA) |

| [![](docs/assets/小龙女.mov.png)](https://youtu.be/WjEHUYZx5Gs) |
|:---:|
| [**Xiaolongnü — YouTube에서 보기**](https://youtu.be/WjEHUYZx5Gs) |

</div>

## 주요 기능

### 실시간 디지털 휴먼 비디오 상호작용

사진 한 장만으로 실시간 영상 통화가 가능한 디지털 휴먼을 만들 수 있습니다. 사용자는 실제 사람과 영상 통화하듯 자연스럽게 대화하고, 디지털 휴먼이 말하는 중에도 언제든 끼어들거나 interrupt할 수 있어 full-duplex 실시간 상호작용을 경험할 수 있습니다.

CyberVerse는 FlashHead, LiveAct 두 로컬 디지털 휴먼 모델을 통합했고, Baidu Xiling, Xunfei Digital Human 같은 클라우드 디지털 휴먼 솔루션도 지원합니다. 현재 우수한 오픈소스 및 상용 디지털 휴먼 선택지를 포괄합니다.

| 모델 | 품질 | GPU | 수량 | 해상도 | FPS | 실시간 가능? |
|-------|---------|-----|-------|------------|-----|------------|
| FlashHead 1.3B | Pro | RTX 5090 | 2 | 512×512 | 25+ | ✅ 예 |
| FlashHead 1.3B | Pro | RTX 5090 | 1 | 464x464 | 20 | ✅ 예 |
| LiveAct 18B | — | RTX PRO 6000 | 2 | 320×480 | 20 | ✅ 예 |
| LiveAct 18B | — | RTX PRO 6000 | 1 | 256×417 | 20 | ✅ 예 |
| [Vidu S1](https://www.vidu.cn/subscription/personal?bonus-code=GWCK5M) | 클라우드 API | 로컬 GPU 불필요 | — | 540P | 25 | ✅ 예 |
| [Baidu Xiling Digital Human](https://xiling.cloud.baidu.com/) | 클라우드 API | 로컬 GPU 불필요 | — | 플랫폼/아바타 설정에 따름 | 플랫폼 응답 | ✅ 예 |
| [Xunfei Digital Human](https://virtual-man.xfyun.cn/) | 클라우드 API | 로컬 GPU 불필요 | — | 플랫폼/아바타 설정에 따름 | 플랫폼 응답 | ✅ 예 |

### PersonaAgent + SubAgent Tasks

CyberVerse는 multi-agent 아키텍처를 사용합니다. PersonaAgent는 항상 전면에서 사용자와의 부드러운 대화, 빠른 interrupt 대응, context switching을 담당합니다. 검색, 리서치, 자료 정리, 요약, HTML 리포트 생성처럼 시간이 오래 걸리는 작업은 백그라운드 SubAgent가 비동기로 실행합니다.

따라서 복잡한 작업이 음성 턴을 늦추지 않습니다. 사용자는 계속 말하거나, 후속 질문을 하거나, 방향을 조정할 수 있으며, SubAgent가 완료되면 결과가 전면 대화로 다시 전달됩니다.

### 캐릭터 메모리와 RAG

각 캐릭터의 대화 기록은 로컬 디스크에 영속화되고, 다시 대화에 들어가면 자동으로 로드되어 세션을 넘나드는 연속성을 유지합니다. 캐릭터를 위한 지식 베이스, 문서, 인물 생애 자료를 가져올 수도 있습니다. 시스템은 이를 인덱싱해 retrieval-augmented generation에 사용하고, 답변이 캐릭터 배경과 설정에 더 잘 맞도록 합니다.

### 플러그인 기반 스택

두뇌, 음성, 청각, 도구, 메모리, 얼굴은 모두 교체 가능한 모듈입니다. 런타임 동작은 계속 `config/cyberverse.yaml` 에 두고, omni model, LLM, TTS, ASR, Embedding provider 정의는 내장 `infra/config/*_models/` 디렉터리에서 자동으로 로드됩니다. 필요하면 `config/*_models/` 아래에 로컬 override 파일을 둘 수 있습니다. Web UI의 **`/settings`** 에서 벤더별 API Key와 서비스 엔드포인트를 설정하고, 시나리오에 따라 provider와 model 조합을 자유롭게 바꿀 수 있습니다.

## 빠른 시작

### 클라우드 이미지

CyberVerse를 빠르게 체험하고 환경 의존성을 수동으로 설정하는 일을 피하고 싶다면 클라우드 이미지에서 시작할 수 있습니다:

- [Compshare CyberVerse 이미지](https://www.compshare.cn/images/hKNKJSOUwn5H?referral_code=IBmJcGPVu1RF78dMihkQCX)
- [AutoDL CyberVerse 이미지](https://www.autodl.art/i/dsd2077/CyberVerse/CyberVerse)

로컬로 배포해야 할 때는 아래 단계에 따라 설치를 계속하세요.

### 사전 준비

- Node 18+
- Go 1.25 (`protoc-gen-go`, `protoc-gen-go-grpc` 필요)
- Conda
- Python 3.10+
- FFmpeg
- libopus-dev、libopusfile-dev、libsoxr-dev，pkg-config

> 순수 음성 세션에는 로컬 Avatar GPU가 필요하지 않습니다. 실행 비용은 설정한 실시간 음성 / omni / LLM / TTS / ASR provider에 따라 달라집니다.

다음 명령으로 확인할 수 있습니다:

```bash
node --version
go version
protoc --version
ffmpeg -version
conda --version
```

### 1단계: 클론

```bash
git clone https://github.com/dsd2077/CyberVerse.git
cd CyberVerse
```

### 2단계: Python 환경 만들기

```bash
conda create -n cyberverse python=3.10
conda activate cyberverse
```

### 3단계: 환경 변수 설정

```bash
cp -r infra/config config
```

`config/env`를 편집해 지원되는 API Key를 입력합니다.

Alibaba Cloud Qwen 시리즈 모델:

```env
DASHSCOPE_API_KEY=your_dashscope_api_key
```

또는 Volcengine Doubao 시리즈 모델:

```env
DOUBAO_ACCESS_TOKEN=your_doubao_access_token
DOUBAO_APP_ID=your_doubao_app_id
```

Doubao Voice: [Volcengine 빠른 시작](https://www.volcengine.com/docs/6561/2119699?lang=zh)에 따라 **App ID** / **API Key**를 확인하고 `DOUBAO_APP_ID` / `DOUBAO_ACCESS_TOKEN`에 넣습니다.

스택이 실행된 뒤에는 `config/env`만 수정할 필요 없이, Web UI의 **`/settings`** 에서 API 키와 서비스 엔드포인트를 변경할 수 있습니다.

omni, LLM, Embedding, TTS, ASR 모델 정의는 `infra/config/*_models/` 에서 자동으로 발견됩니다. 로컬에서 덮어쓰고 싶을 때만 같은 이름의 모델 파일을 `config/*_models/` 아래에 두세요.

### 4단계: 로컬 설정 생성 및 voice-only 모드 활성화

`config/cyberverse.yaml`을 편집합니다:

```yaml
inference:
  avatar:
    enabled: false
```

`enabled: false`이면 CyberVerse는 순수 음성 Agent assistant로 실행됩니다.

### 5단계: 프로젝트 의존성 설치

```bash
make setup
```

이 단계에서는 기본 editable package(`.[dev,inference]`)를 설치하고, gRPC stubs를 생성하며, 프런트엔드 의존성도 함께 설치합니다.

기본 설정에 필요한 voice-agent extras를 설치합니다:

```bash
# 모든 optional 그룹 한 번에 설치
pip install -e ".[all]"
```

### 6단계: 서비스 시작(터미널 3개)

**터미널 1** — Python 추론 서버:

```bash
conda activate cyberverse
make inference
```

**터미널 2** — Go API 서버:

```bash
make server
```

**터미널 3** — 프런트엔드:

```bash
make frontend
```

### 7단계: 확인

```bash
# API 상태 확인
curl -s http://localhost:8080/api/v1/health
```

브라우저에서 http://localhost:5173 를 엽니다.

## 선택 사항: 전체 디지털 휴먼 비디오

FlashHead 또는 LiveAct로 실시간 Avatar 비디오를 구동하려면 아래 절차를 따르세요.

### 추가 요구 사항

- CUDA 12.8+ 지원 GPU
- PyTorch 2.8(CUDA 12.8)
- `libvpx`가 포함된 FFmpeg(영상 인코딩용)
- Avatar 모델 가중치

PyTorch(CUDA 12.8)를 설치합니다:

```bash
pip3 install torch==2.8.0 torchvision==0.23.0 torchaudio==2.8.0 --index-url https://download.pytorch.org/whl/cu128
```

LiveAct를 사용한다면 vllm을 설치합니다:

```bash
pip install vllm==0.11.0
```

### 모델 가중치 다운로드

CyberVerse는 현재 **FlashHead**와 **LiveAct**를 지원합니다. 필요한 것만 다운로드하면 됩니다. 앞으로 더 많은 모델을 계속 연결할 예정입니다.

```bash
pip install "huggingface_hub[cli]"
```

#### FlashHead（SoulX-FlashHead）

| 모델 구성 요소 | 설명 | 링크 |
| :--- | :--- | :--- |
| `SoulX-FlashHead-1_3B` | 1.3B FlashHead 가중치 | [Hugging Face](https://huggingface.co/Soul-AILab/SoulX-FlashHead-1_3B), [ModelScope](https://modelscope.cn/models/Soul-AILab/SoulX-FlashHead-1_3B) |
| `wav2vec2-base-960h` | 오디오 특징 추출기 | [Hugging Face](https://huggingface.co/facebook/wav2vec2-base-960h), [ModelScope](https://modelscope.cn/models/facebook/wav2vec2-base-960h) |

```bash
# 중국 본토에서는 먼저 미러를 사용할 수 있습니다:
# export HF_ENDPOINT=https://hf-mirror.com

hf download Soul-AILab/SoulX-FlashHead-1_3B \
  --local-dir ./checkpoints/SoulX-FlashHead-1_3B

hf download facebook/wav2vec2-base-960h \
  --local-dir ./checkpoints/wav2vec2-base-960h
```

#### LiveAct（SoulX-LiveAct）

| 모델명 | 다운로드 |
|-----------|----------|
| SoulX-LiveAct | [Hugging Face](https://huggingface.co/Soul-AILab/LiveAct), [ModelScope](https://modelscope.cn/models/Soul-AILab/LiveAct) |
| chinese-wav2vec2-base | [Hugging Face](https://huggingface.co/TencentGameMate/chinese-wav2vec2-base), [ModelScope](https://modelscope.cn/models/TencentGameMate/chinese-wav2vec2-base) |

```bash
hf download Soul-AILab/LiveAct \
  --local-dir ./checkpoints/LiveAct

hf download TencentGameMate/chinese-wav2vec2-base \
  --local-dir ./checkpoints/chinese-wav2vec2-base
```

### Avatar Inference 설정

`config/cyberverse.yaml`에서 `enabled`를 `true`로 설정합니다. 모델별 설정은
`config/avatar_models/` 아래에 모델마다 하나의 YAML 파일로 두고, 그 파일에서 로컬
checkpoint 경로를 수정합니다:

```yaml
inference:
  avatar:
    enabled: true
    default: "flash_head"
    idle_strategy: "silent_inference"
    runtime:
      cuda_visible_devices: 0      # 공용 GPU ID. 멀티 GPU라면 0,1 등으로 설정
      world_size: 1                # 공용 GPU 수. 듀얼 GPU면 2로 설정
    model_config_dir: "avatar_models"
```

그다음 `config/avatar_models/flash_head.yaml` 또는 `config/avatar_models/live_act.yaml`을 수정합니다.
모델 파라미터는 나중에 Web UI에서도 조정할 수 있으며, 해당 모델 설정 파일에 다시 저장됩니다.

### Baidu Xiling H5 디지털 휴먼

Baidu Xiling을 사용할 때는 인증 정보를 `config/env`에 둡니다:

```env
BAIDU_XILING_APP_ID="your-app-id"
BAIDU_XILING_APP_KEY="your-app-key"
# Optional when the figure needs a fixed camera.
BAIDU_XILING_CAMERA_ID="0"
```

Baidu Xiling은 Web UI에서 캐릭터별로 선택합니다. 로컬 avatar inference 모델이 아니므로 `inference.avatar.default`로 설정하면 안 됩니다. CyberVerse는 여전히 orchestrator에서 ASR, LLM, TTS, 대화 기록 컨텍스트, 캐릭터 설정을 처리한 뒤 16 kHz, 16-bit, mono PCM 오디오 chunk를 브라우저로 보냅니다. 프론트엔드는 Baidu H5 iframe을 임베드하고 공식 `sendAudioData` / `AUDIO_STREAM_RENDER` 메시지 형식으로 디지털 휴먼을 구동합니다.

### LiveAct FP4 GEMM(선택 사항)

FP4 가속을 사용하려면 [LightX2V](https://github.com/ModelTC/LightX2V)에서 `lightx2v_kernel`을 빌드해 설치해야 합니다. 빌드 머신에는 **PyTorch 2.7+**와 CUTLASS 소스가 필요합니다.

#### 준비

```bash
pip install scikit_build_core uv
```

#### whl 빌드

```bash
git clone https://github.com/NVIDIA/cutlass.git
git clone https://github.com/ModelTC/LightX2V.git
cd LightX2V/lightx2v_kernel
# /path/to/cutlass를 로컬 cutlass 클론의 절대 경로로 바꿉니다.
MAX_JOBS=$(nproc) && CMAKE_BUILD_PARALLEL_LEVEL=$(nproc) \
uv build --wheel \
    -Cbuild-dir=build . \
    -Ccmake.define.CUTLASS_PATH=/path/to/cutlass \
    --verbose \
    --color=always \
    --no-build-isolation
```

#### whl 설치

```bash
pip install dist/*.whl --force-reinstall --no-deps
```

#### CyberVerse에서 활성화

`config/avatar_models/live_act.yaml`(또는 Web UI)의 `live_act`에서 다음을 설정합니다:

```yaml
fp8_gemm: false
fp4_gemm: true
```

플래그를 변경한 뒤 추론 서비스를 재시작하세요.

### SageAttention 및 FlashAttention(선택 사항)

```bash
# SageAttention(소스 빌드)
git clone https://github.com/thu-ml/SageAttention.git
cd SageAttention
export EXT_PARALLEL=4 NVCC_APPEND_FLAGS="--threads 8" MAX_JOBS=32 # Optional
python setup.py install
```

```bash
# FlashAttention (optional)
wget -O flash_attn-2.8.1+cu12torch2.8cxx11abiTRUE-cp312-cp312-linux_x86_64.whl \
  "https://github.com/Dao-AILab/flash-attention/releases/download/v2.8.1/flash_attn-2.8.1%2Bcu12torch2.8cxx11abiTRUE-cp312-cp312-linux_x86_64.whl"

pip install flash_attn-2.8.1+cu12torch2.8cxx11abiTRUE-cp312-cp312-linux_x86_64.whl
```

## 자주 묻는 질문 — 자가 점검(QA)

아바타 영상이 **끊기거나, 멈추거나, 음성보다 눈에 띄게 늦어질** 때는 먼저 추론이 재생 속도를 따라갈 수 있는지 확인하세요.

### 추론 로그로 RTP 확인

**RTP**(실시간 성능 계수)는 chunk 생성에 걸린 시간과, 해당 chunk를 설정 FPS로 재생하는 데 필요한 시간의 비율입니다.

```text
RTP = elapsed / (frames / fps)
```

| RTP | 의미 |
|-----|------|
| **&lt; 1** | 생성이 재생보다 빠름 — 실시간 스트리밍 여유 있음 |
| **= 1** | 정확히 실시간 |
| **&gt; 1** | 생성이 재생보다 느림 — **산출 속도가 소비 속도를 따라가지 못해** 지연·끊김이 발생하기 쉬움 |

캐릭터가 말하는 동안 추론 터미널(`make inference`) 로그에서 **LiveAct** 또는 **FlashHead** chunk 줄을 확인합니다.

**LiveAct 예시(RTP &gt; 1 — 실시간 불가):**

```text
INFO:inference.plugins.avatar.live_act_plugin:LiveAct chunk: idx=2 frames=32 320x480 fps=20 iter=2 elapsed=1.870s is_final=False
```

- 이 chunk 재생 시간: `32 / 20 = 1.6` 초  
- RTP: `1.870 / 1.6 ≈ 1.17` (**&gt; 1** — 현재 GPU에서 320×480 @ 20 fps를 따라가지 못함)

**FlashHead**도 `elapsed`와 `num_frames`, `fps`로 동일하게 계산합니다.

```text
INFO:...FlashHead video chunk generated: chunk_index=1 num_frames=33 512x512 fps=20 ... elapsed=2.100s
```

이 경우 RTP = `2.100 / (33/20) ≈ 1.27`로 실시간을 초과합니다.

### RTP &gt; 1일 때 조치

1. **해상도 또는 화질 낮추기** — 예: LiveAct `infer_params.size`, FlashHead `height` / `width`, 또는 FlashHead `model_type: "lite"`.
2. **연산 자원 늘리기** — GPU 추가(`runtime.world_size`, `cuda_visible_devices`), 지원 시 FP8/FP4 GEMM·컴파일 가속 활성화, 더 빠른 GPU 사용.
3. **위 지원 표와 맞추기** — 로컬 GPU 모델은 [실시간 디지털 휴먼 비디오 상호작용](#실시간-디지털-휴먼-비디오-상호작용)에서 **실시간 가능?** 이 **예**인 해상도·FPS·GPU 조합을 선택.

순수 음성 모드(`inference.avatar.enabled: false`)는 Avatar RTP와 무관합니다. Baidu Xiling과 Xunfei Digital Human은 클라우드 API이므로 로컬 Avatar RTP도 사용하지 않습니다. 음성만 끊기면 네트워크/WebRTC 또는 상류 음성 지연을 의심하고 [원격 접속 참고](#원격-접속-참고)를 보세요.

## 원격 접속 참고

`streaming_mode: direct` 에서 내장 TURN 서버를 사용하는 경우, 브라우저가 서버의 `8443/TCP` 에 접속할 수 있어야 합니다. 페이지는 열리지만 오디오/비디오 연결이 끝내 성립하지 않거나, 서버 로그에 `ICE connection state: failed` 또는 `publish timeout waiting for connection` 이 보이면 먼저 로컬 머신에서 서버 `8443` 포트에 연결 가능한지 확인하세요.

```bash
nc -vz <server-ip> 8443
```

`8443` 에 연결되지 않는다면 보통 클라우드 보안 그룹, 방화벽, 또는 NAT 제한이 원인입니다. 이 경우 SSH 터널로 로컬 `8443` 을 서버로 포워딩할 수 있습니다.

```bash
ssh -L 8443:127.0.0.1:8443 user@host -p port
```

터널이 만들어지면 브라우저는 로컬 `127.0.0.1:8443` 을 통해 원격 TURN 서비스에 접속합니다.

SSH 터널이 아니라 브라우저가 원격 서버에 직접 연결되게 하려면 `config/cyberverse.yaml` 의 `pipeline.ice_public_ip` 를 서버의 공인 IP 또는 도메인으로 설정하세요. SSH 터널을 사용할 경우에는 기본값(`127.0.0.1`)을 그대로 사용하면 됩니다.

## 로드맵

로드맵은 Yuque로 이전되었습니다: [CyberVerse 요구사항 관리](https://www.yuque.com/u32995802/ilet4r/qu7lhylertuzx7dh?singleDoc#).

## 커뮤니티

<p align="center">
  <a href="docs/assets/wechat_group.jpg"><img src="docs/assets/wechat_group.jpg" alt="CyberVerse WeChat 그룹 QR 코드" width="320"/></a>
</p>

<p align="center">QR 코드가 만료된 경우 관리자 WeChat <strong>wx_dsd2077</strong>에 추가하고, 친구 신청 시 <strong>CyberVerse</strong>라고 남겨 주세요. 그룹으로 초대해 드립니다.</p>

## Star History

<p align="center">
  <a href="https://star-history.com/#dsd2077/CyberVerse&Date">
    <img src="https://api.star-history.com/svg?repos=dsd2077/CyberVerse&type=Date" alt="Star History Chart" width="100%"/>
  </a>
</p>

## 라이선스

GNU General Public License v3.0. 자세한 내용은 [LICENSE](LICENSE)를 참고하세요.

## 감사의 말

- [SoulX-FlashHead](https://github.com/Soul-AILab/SoulX-FlashHead) — Soul AI Lab의 아바타 모델

- [SoulX-LiveAct](https://github.com/Soul-AILab/SoulX-LiveAct) - Soul AI Lab의 아바타 모델
- [MuseTalk](https://github.com/TMElyralab/MuseTalk) — TME Lyra Lab의 실시간 립싱크 모델
- [Pion](https://github.com/pion/webrtc) — Go WebRTC 구현체
- [Linux.do](https://linux.do/)
