# AI Chat 功能设计方案 (基于 XJP airouter)

## 后端实现状态

✅ **已完成**:
- 数据库迁移: `services/auth/migrations/0035_ai_conversations.sql`
- 数据模型: `services/auth/src/models/ai_conversation.rs`
- Repository: `services/auth/src/repos/ai_conversation_repo.rs`
- API 路由: `services/auth/src/routes/v1/ai_conversations/mod.rs`

---

## API 概览

**基础 URL**: `https://auth.xiaojinpro.com`

### 认证方式
- 使用 XJPkey (通过 `Authorization: Bearer {xjpkey}`)
- 需要 `router:read` scope 读取模型
- 需要 `router:write` scope 发送消息和上传文件

### 核心 API 端点

#### 1. Chat Completions (OpenAI 兼容)
```
POST /v1/chat/completions
Authorization: Bearer {xjpkey}
Content-Type: application/json

{
  "model": "claude-sonnet-4.5",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "Hello!"}
  ],
  "stream": true,
  "temperature": 0.7,
  "max_tokens": 4096
}

// 流式响应 (SSE):
data: {"id":"chatcmpl-xxx","choices":[{"delta":{"content":"Hello"}}]}
data: [DONE]
```

#### 2. 多模态消息格式
```json
{
  "role": "user",
  "content": [
    {"type": "text", "text": "What's in this image?"},
    {"type": "image_url", "image_url": {"url": "https://..."}},
    {"type": "video_url", "video_url": {"url": "https://..."}},
    {"type": "file_url", "file_url": {"url": "https://..."}}
  ]
}
```

#### 3. Models API
```
GET /v1/models
GET /v1/models/extended
```

#### 4. Storage API (文件上传)
```
GET /v1/storage/upload-url?name=xxx&content_type=image/png
POST /v1/storage/objects  (直接上传)
GET /v1/storage/download-url?name=xxx
```

### 可用模型
- `claude-sonnet-4.5` - Claude Sonnet 4.5 (推荐)
- `claude-sonnet-4.5-thinking` - Claude Sonnet 4.5 Thinking
- `claude-opus-4.1` - Claude Opus 4.1
- `claude-opus-4.1-thinking` - Claude Opus 4.1 Thinking
- `gemini-3-pro-preview` - Gemini 3 Pro

---

## 功能需求

### 核心功能
1. **多模态支持**: 文本、图片、视频、PDF
2. **云端同步**: 对话历史云端存储
3. **模型选择**: 动态获取可用模型
4. **流式输出**: SSE 实时显示
5. **Thinking 模式**: 支持深度思考

### 与现有 Chat 的区别
| 现有 Chat (xjp-cli) | 新 AI Chat (airouter) |
|---------------------|----------------------|
| 通过 `/ai/conversations` | 通过 `/v1/chat/completions` |
| 支持工具调用/技能执行 | 纯 AI 对话 |
| 复杂的多轮交互 | 简洁的聊天体验 |
| 固定模型 | 用户可选模型 |

---

## 文件结构

```
Features/AIChat/
├── Views/
│   ├── AIChatHomeView.swift        # 对话列表
│   ├── AIChatView.swift            # 聊天界面
│   └── Components/
│       ├── AIMessageBubble.swift   # 消息气泡 (支持 Markdown)
│       ├── AIInputBar.swift        # 输入栏 (支持附件)
│       ├── AIModelPicker.swift     # 模型选择器
│       └── AIAttachmentPicker.swift # 附件选择器
├── Models/
│   ├── AIChat.swift                # 对话模型
│   ├── AIMessage.swift             # 消息模型
│   └── AIModel.swift               # 模型信息
├── ViewModels/
│   └── AIChatStore.swift           # 聊天状态管理
└── Services/
    ├── AIRouterService.swift       # airouter API
    └── AIStorageService.swift      # 文件上传服务
```

---

## 数据模型

### AIConversation (云端同步)
```swift
struct AIConversation: Codable, Identifiable {
    let id: String
    var title: String?
    var model: String
    var systemPrompt: String?
    var messageCount: Int
    let createdAt: Date
    var updatedAt: Date
}
```

### AIMessage
```swift
struct AIMessage: Codable, Identifiable {
    let id: String
    let conversationId: String
    let role: AIMessageRole
    var content: [AIContentPart]
    let createdAt: Date

    // 使用量统计
    var promptTokens: Int?
    var completionTokens: Int?
}

enum AIMessageRole: String, Codable {
    case system, user, assistant
}

enum AIContentPart: Codable {
    case text(String)
    case imageUrl(String)
    case videoUrl(String)
    case fileUrl(String, mimeType: String?)
}
```

### AIModel
```swift
struct AIModel: Codable, Identifiable {
    let id: String
    let name: String
    let provider: String
    let capabilities: AIModelCapabilities
    let contextLength: Int
    let maxOutputTokens: Int
}

struct AIModelCapabilities: Codable {
    let text: Bool
    let vision: Bool
    let video: Bool
    let tools: Bool
    let streaming: Bool
    let thinkingMode: Bool
}
```

---

## 实现计划

### Phase 1: 基础架构
1. AIRouterService - API 调用
2. AIStorageService - 文件上传
3. 数据模型定义

### Phase 2: 对话管理 (云端同步)
1. 对话 CRUD API
2. 消息存储 API
3. AIChatHomeView - 对话列表

### Phase 3: 聊天界面
1. AIChatView - 主聊天界面
2. AIMessageBubble - 消息气泡
3. AIInputBar - 输入栏
4. 流式输出

### Phase 4: 多模态支持
1. 图片选择和上传
2. 文件选择和上传
3. 视频选择和上传
4. PDF 预览

### Phase 5: 高级功能
1. 模型选择器
2. Markdown 渲染
3. 代码高亮
4. 消息操作 (复制、重新生成)

---

## UI 设计

### 对话列表
```
┌─────────────────────────────────────┐
│  AI 助手                    ⚙️  +   │
├─────────────────────────────────────┤
│  🔍 搜索对话...                      │
├─────────────────────────────────────┤
│  ┌─────────────────────────────────┐│
│  │ 💬 关于 SwiftUI 的问题          ││
│  │    Claude 4.5 · 3条 · 2分钟前   ││
│  └─────────────────────────────────┘│
│  ┌─────────────────────────────────┐│
│  │ 📸 分析这张图片                  ││
│  │    Gemini 3 · 5条 · 1小时前     ││
│  └─────────────────────────────────┘│
└─────────────────────────────────────┘
```

### 聊天界面
```
┌─────────────────────────────────────┐
│  < 返回     Claude 4.5 ▼       ⚙️   │
├─────────────────────────────────────┤
│                                     │
│     ┌─────────────────────────┐     │
│     │ 你好！有什么可以帮你的？   │     │
│     └─────────────────────────┘     │
│                                     │
│  ┌─────────────────────────┐        │
│  │ [📷 图片预览]            │        │
│  │ 这张图片是什么？         │        │
│  └─────────────────────────┘        │
│                                     │
│     ┌─────────────────────────┐     │
│     │ 这是一张风景照片...      │     │
│     │                         │     │
│     │ [复制] [重新生成]        │     │
│     └─────────────────────────┘     │
│                                     │
├─────────────────────────────────────┤
│ ┌─────────────────────────────┐     │
│ │ 📷 📎  输入消息...           │ ⬆️  │
│ └─────────────────────────────┘     │
└─────────────────────────────────────┘
```

---

## 后端 API 详情 (Cloud Sync)

### 认证
所有 API 需要 Bearer Token (OAuth2 access_token)

### Conversations API

#### 列出对话
```
GET /v1/ai/conversations?include_archived=false&limit=50&cursor=xxx&search=xxx
Authorization: Bearer {access_token}

Response:
{
  "data": [
    {
      "id": "uuid",
      "title": "对话标题",
      "model": "claude-sonnet-4.5",
      "system_prompt": "...",
      "temperature": 0.7,
      "max_tokens": 4096,
      "message_count": 10,
      "total_tokens": 5000,
      "is_archived": false,
      "last_message_at": "2025-12-05T10:00:00Z",
      "created_at": "2025-12-05T09:00:00Z",
      "updated_at": "2025-12-05T10:00:00Z"
    }
  ],
  "has_more": true,
  "next_cursor": "2025-12-05T10:00:00Z"
}
```

#### 创建对话
```
POST /v1/ai/conversations
Authorization: Bearer {access_token}
Content-Type: application/json

{
  "title": "可选标题",
  "model": "claude-sonnet-4.5",
  "system_prompt": "可选 system prompt",
  "temperature": 0.7,
  "max_tokens": 4096
}
```

#### 获取对话详情
```
GET /v1/ai/conversations/:id
```

#### 更新对话
```
PATCH /v1/ai/conversations/:id

{
  "title": "新标题",
  "model": "claude-opus-4.1",
  "is_archived": true
}
```

#### 删除对话
```
DELETE /v1/ai/conversations/:id
```

### Messages API

#### 列出消息
```
GET /v1/ai/conversations/:id/messages?limit=100&before=xxx&after=xxx

Response:
{
  "data": [
    {
      "id": "uuid",
      "conversation_id": "uuid",
      "role": "user",
      "content": "消息内容",
      "content_parts": [...],
      "prompt_tokens": 100,
      "completion_tokens": 200,
      "model_used": "claude-sonnet-4.5",
      "finish_reason": "stop",
      "attachments": [...],
      "created_at": "2025-12-05T10:00:00Z"
    }
  ],
  "has_more": false,
  "next_cursor": null
}
```

#### 创建消息
```
POST /v1/ai/conversations/:id/messages

{
  "role": "user",
  "content": "消息文本",
  "content_parts": [
    {"type": "text", "text": "..."},
    {"type": "image_url", "url": "https://..."}
  ],
  "attachments": [{"id": "attachment-uuid"}]
}
```

### Attachments API

#### 创建附件 (获取上传 URL)
```
POST /v1/ai/conversations/:id/attachments

{
  "file_name": "image.png",
  "file_type": "image",
  "file_size": 1024000,
  "mime_type": "image/png"
}

Response:
{
  "attachment_id": "uuid",
  "upload_url": "https://...",
  "expires_at": "2025-12-05T10:15:00Z"
}
```

#### 列出附件
```
GET /v1/ai/conversations/:id/attachments
```

---

## 下一步

1. **部署后端**: 运行数据库迁移，重新部署 auth 服务
2. **iOS 实现**: 创建 AI Chat 功能界面和服务

准备好后告诉我继续实现 iOS 端！
