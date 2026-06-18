# 中文项目文档约定

本目录存放 `zh-CN` 中文文档。

语言层级统一放在 `docs/<locale>/` 下：

- `docs/zh-CN/`
- `docs/en/`
- `docs/ja/`

当前项目先维护中文文档，后续如果需要其他语言，再在对应目录补充。

## 目标

这套文档的目标不是“写很多”，而是让未来开发者和 AI 能在几分钟内回答下面几个问题：

- 这个功能为什么要做
- 现在系统是怎么工作的
- 改动落在哪些模块
- 当前实现的边界、风险和待办是什么
- 出问题时应该从哪里排查

## 中文文档推荐目录

- `docs/assets/`
  - 演示素材、截图、录屏。
- `docs/zh-CN/features/`
  - 每个已实现功能或重要重构一篇文档。
  - 这是最常用、也最应该持续维护的目录。
- `docs/zh-CN/architecture/`
  - 跨功能、长期稳定的系统设计文档。
  - 例如：会话模型、媒体链路、插件系统、推理服务分层。
- `docs/zh-CN/operations/`
  - 部署、排障、回滚、环境依赖、运行手册。
- `docs/zh-CN/templates/`
  - 文档模板，保证后续 feature 文档结构一致。

## 当前 Feature 文档

- [PersonaAgent 与后台任务 MVP](features/2026-05-11-persona-agent-task-mvp.md)
- [VoiceLLM 文本输入改走 Doubao 的设计与实现](features/2026-04-24-voice-llm-text-input-via-doubao.md)

## 当前 Operations 文档

- [www.cyberverse.cc 域名部署](operations/www-cyberverse-cc-domain-deployment.md)

## feature 文档命名建议

统一使用：

- `YYYY-MM-DD-<area>-<feature>.md`

例如：

- `2026-04-24-voice-llm-text-input-via-doubao.md`
- `2026-04-25-avatar-streaming-buffer-tuning.md`

如果同一天同一领域有多个变更，可以继续追加更具体的语义，不建议用 `v2`、`final` 这类名字。

## 每篇 feature 文档至少包含

1. 背景与问题
2. 目标与非目标
3. 核心设计决策
4. 端到端时序图或流程图
5. 涉及模块与关键文件
6. 实现细节
7. 协议 / 数据结构 / 配置变更
8. 风险、限制与未决问题
9. 验证方式
10. 回滚思路（如有必要）

## 推荐维护方式

- 每实现一个功能或重要重构，就在 `docs/zh-CN/features/` 新增一篇文档。
- 功能文档优先描述“为什么这样设计”和“代码实际怎么落地”，不要只写需求摘要。
- 如果某个主题已经跨越多个 feature，且结论逐渐稳定，再沉淀到 `docs/zh-CN/architecture/`。
- 如果某个问题主要和运行、部署、排障有关，不放到 feature 文档，放到 `docs/zh-CN/operations/`。

## 一个实用原则

文档按“稳定性”分层，而不是按“作者心情”分层：

- 短周期、随功能变化快的，放 `features/`
- 长周期、跨功能复用的，放 `architecture/`
- 面向运行与值班的，放 `operations/`

这样未来不管是人还是 AI，定位成本都会低很多。
