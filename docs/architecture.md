# 架构说明

`distributed-x-infrastructure-url-shortener` 提供一套无服务器 URL 缩短服务：API 网关承载 5 个 REST 路由，函数工作流处理业务逻辑，对象存储存放短链映射。适用于需要按需伸缩的短链接服务。

## 架构图

```
┌────────────────────────────────────────────────────────────────────┐
│                        Client / REST caller                        │
│        POST /app   GET /{linkId}   GET /app   PUT / DELETE         │
└──────────────────────────────────┬─────────────────────────────────┘
                                   │ HTTPS
                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│                    APIG Gateway (5 REST routes)                    │
│                Route dispatch + request validation                 │
└──────────────────────────────────┬─────────────────────────────────┘
                                   │ proxy event
                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│                FunctionGraph url-handler (Node.js)                 │
│             create / redirect / list / update / delete             │
└──────────────────────────────────┬─────────────────────────────────┘
                                   │ OBS SDK
                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│                OBS Bucket: links/{id} -> target URL                │
│            IAM agency grants object access; no database            │
└────────────────────────────────────────────────────────────────────┘
```

## 核心组件

| 组件 | 说明 |
|---|---|
| APIG 专享实例 | API 网关入口，承载 5 个路由并发布到 RELEASE 环境 |
| FunctionGraph `url-handler` | 单函数按 HTTP 方法与路径分发业务逻辑，经委托访问 OBS |
| OBS 业务桶 | 短链对象存储：对象 key=`links/{id}`、内容为目标 URL |
| 函数委托 | OBS OperateAccess 委托，函数以临时凭证访问对象存储 |

## 接口

| 方法 / 路径 | 功能 | 返回 |
|---|---|---|
| `GET /{linkId}` | 短链重定向 | 301 + Location |
| `GET /app` | 列出全部短链 | 200 数组 |
| `POST /app` | 创建短链（body: url） | 201 `{id,url}` |
| `PUT /app/{linkId}` | 更新短链目标 | 200 |
| `DELETE /app/{linkId}` | 删除短链 | 200 |

## 设计说明

- 短码生成：62 进制 6 位随机码；写入前先 `getObject` 探测同名对象，命中则重新生成（最多重试 5 次），避免覆盖已有短链
- URL 校验：仅接受 `http/https` 开头的合法地址
- 超链接重定向由函数构造 301 响应，客户端不感知存储细节
- 认证：本实践以开放模式（owner=`public`）演示，未接入用户目录鉴权；生产接入时可在 API 网关追加自定义认证

## 访问入口

| 入口 | 地址 | 可达范围 | 用途 |
|---|---|---|---|
| EIP 公网入口 | terraform 输出 `api_domain`（实例 `ingress_address`） | 公网可达 | 外部客户端调用，需带 `/release` |
| 分组内网域名 | terraform 输出 `api_group_domain`（`<分组ID>.apic.<region>.huaweicloudapis.com`） | **仅 VPC 内可达**，公网 DNS 不可解析 | VPC 内服务间调用，需带 `/release` |
