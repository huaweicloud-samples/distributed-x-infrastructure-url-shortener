# distributed-x-infrastructure-url-shortener / URL 缩短器

[English](README.md)

[![License](https://img.shields.io/badge/License-MIT%20No%20Attribution-blue.svg)](LICENSE)
[![Huawei Cloud](https://img.shields.io/badge/Huawei%20Cloud-IAM%20Auth-red.svg)](https://support.huaweicloud.com/intl/en-us/)
[![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg)](#)

> 无服务器 URL 缩短服务
> Serverless URL Shortener Service

---

## 1. 简介 / Overview

**中文**：本实践提供 **短链接创建与 301 重定向** 核心能力，用于 **长 URL 转短链、分享与追踪** 场景。面向 DevOps / 后端工程师，可作为参考架构 / 学习样例 / 生产模板 使用。

### 核心能力

- 无服务器 API：APIG 网关 + FunctionGraph 单函数，按需伸缩、无常驻资源
- 短链生命周期：创建 / 重定向 / 列表 / 更新 / 删除
- 简单存储：OBS 对象直接承载短码与目标 URL，无数据库依赖

---

## 2. 目录

- [1. 简介](#1-简介--overview-critical)
- [2. 目录](#2-目录)
- [3. 架构图](#3-架构图)
- [4. 方案亮点](#4-方案亮点)
- [5. 涉及云服务](#5-涉及云服务)
- [6. 前置条件](#6-前置条件-critical)
- [7. 快速开始](#7-快速开始-critical)
- [8. 分步部署](#8-分步部署)
- [9. 使用方法 / 验证](#9-使用方法--验证-critical)
- [10. 清理资源](#10-清理资源)
- [11. 详细说明](#11-详细说明)
- [12. 依赖](#12-依赖)
- [13. FAQ / 故障排除](#13-faq--故障排除)
- [14. 贡献指南](#14-贡献指南)
- [15. 许可证](#15-许可证-critical)
- [16. 联系方式 / 维护者](#16-联系方式--维护者-critical)

---

## 3. 架构图

> 一次部署即获得完整 URL 缩短服务：网关路由 + 函数逻辑 + 对象存储持久化。

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

**关键组件说明**：
- APIG 专享实例：API 网关入口，承载 5 个路由并发布到 RELEASE 环境
- FunctionGraph `url-handler`：按 HTTP 方法与路径分发业务逻辑，经委托访问对象存储
- OBS 业务桶：短链对象存储（key=`links/{id}`、内容=目标 URL）

---

## 4. 方案亮点

- **按需伸缩**：无服务器架构，无常驻计算资源
- **单一函数覆盖全生命周期**：创建 / 重定向 / 列表 / 更新 / 删除 5 个路由集约管理
- **存储即数据**：OBS 对象直接承载短码与 URL，不引入数据库与运维
- **易于集成**：REST API 风格路由，前端 / 客户端可直接调用

---

## 5. 涉及云服务

| 服务 | 用途 | 备注 |
|---|---|---|
| 应用与网站应用服务（APIG） | API 网关入口、路由与发布 | 专享实例 BASIC 规格 |
| 函数工作流 FunctionGraph | 短链业务逻辑 | Node.js18.15，128MB |
| 对象存储服务 OBS | 短链对象持久化 + 函数代码包 | 私有桶 |
| 虚拟私有云 VPC | APIG 实例所属网络 | 含子网与安全组 |

> **提示**：所有服务均可通过本仓库的 Terraform 一键创建；如需清理，请参见 [第 10 节「清理资源」](#10-清理资源)。

---

## 6. 前置条件

| 项 | 要求 | 说明 |
|---|---|---|
| **账号** | 已开通华为云账号并完成实名认证 | 个人/企业账号均可 |
| **权限** | 账号具备 IAM **Tenant Administrator** 或等效权限 | 用于创建 VPC / APIG / FunctionGraph / OBS 等资源 |
| **Region** | 推荐 `cn-north-4` | 跨 region 可能涉及服务可用性差异 |
| **Terraform** | `>= 1.5.0` | IaC 部署工具 |
| **huaweicloud Provider** | `>= 1.97.0`（锁定至 1.98.2） | 华为云 Terraform Provider |
| **obsutil** | `>= 5.5.0` | 预置 OBS 桶与上传函数代码包 |
| **Node.js** | `>= 18` *(本地)* | 安装函数依赖并打包 |
| **访问密钥** | 在华为云『我的凭证』页面获取 Access Key ID 与 Secret Access Key，通过 `export HW_ACCESS_KEY` / `export HW_SECRET_KEY` 注入 | **不要**将凭据写入任何代码或配置文件 |
| **OBS 委托** | FunctionGraph 需 `OBS OperateAccess` 委托访问对象存储 | 部署后请到 IAM 控制台确认委托项目角色已生效，否则 OBS 读写返回 403（见 FAQ Q3） |

---

## 7. 快速开始

### 一键部署（推荐）

```bash
# 1. 克隆本仓库
git clone <repo-https-url> distributed-x-infrastructure-url-shortener
cd distributed-x-infrastructure-url-shortener

# 2. 准备华为云访问密钥（参见 [前置条件 §6](#6-前置条件-critical)）
export HW_ACCESS_KEY="<your-access-key>"
export HW_SECRET_KEY="<your-secret-key>"

# 3. 预置 OBS 桶与函数代码包（详见 [第 8 节](#8-分步部署) 步骤 1）
obsutil mb obs://<obs-bucket-name> -location=cn-north-4

# 4. 一键部署
cd infra
terraform init
terraform plan
terraform apply -auto-approve
```

> **部署耗时**：约 10-15 分钟（APIG 专享实例创建较慢）。
> **完整步骤与每步预期输出**：参见 [第 8 节「分步部署」](#8-分步部署)。

---

## 8. 分步部署

### 步骤 1：预置 OBS 桶并上传函数代码包

```bash
cd src/functions/url-handler
npm install --omit=dev
zip -rq /tmp/url-handler.zip index.js node_modules
obsutil mb obs://<obs-bucket-name> -location=cn-north-4
obsutil cp /tmp/url-handler.zip obs://<obs-bucket-name>/code/url-handler.zip -f
```

**预期输出**：`Upload successfully`；之后将桶名填入 `infra/terraform.tfvars` 的 `obs_bucket_name`。

### 步骤 2：初始化工作目录

```bash
cd distributed-x-infrastructure-url-shortener/infra
terraform init
```

**预期输出**：`Terraform has been successfully initialized!`

### 步骤 3：预演资源变更

```bash
terraform plan
```

**预期输出**：`Plan: N to add, 0 to change, 0 to destroy.`

### 步骤 4：执行部署

```bash
terraform apply -auto-approve
```

**预期输出**：`Apply complete! Resources: N added, 0 changed, 0 destroyed.`

---

## 9. 使用方法 / 验证

> **验证状态**：下述函数直调命令在部署验证中已实际执行——`POST /app`、`PUT /app/{linkId}`、`DELETE /app/{linkId}` 分别返回 201 / 200 / 200。端到端重定向与列表调用在实测中被函数运行时的 OBS 403 阻塞；公网网关 `curl` 未执行。请自行重跑全部命令，确认业务功能可用后方可视为交付完成。

### 验证 1：创建短链

```bash
# 调用函数创建短链（POST /app）
hcloud FunctionGraph InvokeFunction --cli-region=cn-north-4 \
  --function_urn="<url-handler 函数 URN>" \
  --body='{"httpMethod":"POST","path":"/app","body":"{\"url\":\"https://example.com/very/long\"}"}'
```

**预期输出**：
```
{"id":"<short-code>","url":"https://example.com/very/long","owner":"public",...}
```

### 验证 2：短链重定向

```bash
# 用上一步的 short-code 调用重定向（GET /{linkId}）
hcloud FunctionGraph InvokeFunction --cli-region=cn-north-4 \
  --function_urn="<url-handler 函数 URN>" \
  --body='{"httpMethod":"GET","path":"/<short-code>","pathParameters":{"linkId":"<short-code>"}}'
```

**预期输出**：
```
{"statusCode":301,"headers":{"Location":"https://example.com/very/long",...}}
```

### 验证 3：公网网关端到端

```bash
# 公网入口为绑定到 APIG 实例的 EIP（terraform 输出 `api_domain`）。
# 已发布 API 需带发布环境段 `/release`。
curl -i "https://<api_domain>/release/<short-code>"
```

**预期输出**：
```
HTTP/1.1 301 Moved Permanently
Location: https://example.com/very/long
```

> **两个入口的区别**：分组域名（`<分组ID>.apic.<region>.huaweicloudapis.com`，输出 `api_group_domain`）**仅在 VPC 内可解析**，公网 DNS 无法解析；公网访问请用 EIP（`api_domain`）。两者调用路径都需带 `/release` 环境段。

### 验证 4：业务端到端（推荐）

```bash
# 创建 → 验证重定向 → 列表 → 删除
# （创建与重定向见验证 1/2；列表与删除同样通过 FGS 同步调用或公网 REST 完成）
```

**预期结果**：短链创建后可通过网关或函数调用完成 301 重定向；列表、更新、删除操作可用性一致。

### 步骤 5：构建并托管前端（可选）

```bash
cd src/frontend
npm install
echo 'VUE_APP_API_ROOT=https://<api_domain>/release' > .env
npm run build
# 将 dist/ 上传至 OBS 静态托管（obsutil cp src/frontend/dist obs://<obs-bucket-name>/frontend/ -r -f）
```

---

## 10. 清理资源

```bash
# 进入部署目录
cd distributed-x-infrastructure-url-shortener/infra

# 一键释放 Terraform 管理的资源
terraform destroy -auto-approve

# 手动清理预置 OBS 桶（对象 + 桶）
obsutil rm obs://<obs-bucket-name> -r -f
obsutil rm obs://<obs-bucket-name> -f
```

**预期输出**：`Destroy complete! Resources: N destroyed.`

> **避免资源残留**：
> - `terraform destroy` 仅释放 Terraform state 中追踪的资源；
> - 预置 OBS 桶与函数代码包需用 obsutil 手动删除；
> - 公共资源（账号内其他任务共享的 NAT / VPC 等）不会被影响。

---

## 11. 详细说明

### 工作流程

1. 调用方请求 `POST /app`（body 含 `url`）→ APIG → 函数校验 URL、生成 62 进制短码、写入 OBS 对象 → 返回短链
2. 调用方访问 `GET /{linkId}` → APIG → 函数读取 OBS 对象 → 返回 301 + `Location`
3. 管理操作（列表 / 更新 / 删除）走 `/app` 与 `/app/{linkId}` 路由

### 配置项

| 变量 | 默认值 | 说明 |
|---|---|---|
| `region` | `cn-north-4` | 华为云区域 |
| `project_name` | `url-shortener` | 资源命名前缀 |
| `obs_bucket_name` | （需填写） | 预置 OBS 业务桶名（全局唯一） |

### 接口 / API

| 方法 / 路径 | 说明 | 返回 |
|---|---|---|
| `GET /{linkId}` | 短链重定向 | 301 + Location |
| `GET /app` | 列出短链 | 200 数组 |
| `POST /app` | 创建短链 | 201 `{id,url}` |
| `PUT /app/{linkId}` | 更新短链目标 | 200 |
| `DELETE /app/{linkId}` | 删除短链 | 200 |

请求 / 响应示例：

```bash
curl -X POST "https://<api_domain>/release/app" -H 'Content-Type: application/json' -d '{"url":"https://example.com/very/long"}'
# {"id":"Ab3xYz","url":"https://example.com/very/long","owner":"public","timestamp":...}
```

---

## 12. 依赖

### 主要依赖

| 名称 | 版本 | 用途 |
|---|---|---|
| Terraform | `>= 1.5.0` | IaC 编排 |
| huaweicloud Provider | `>= 1.97.0`（锁定至 1.98.2） | 华为云资源 |
| Node.js | `18.15` | FunctionGraph 运行环境 |
| esdk-obs-nodejs | `^3.26.8` | 函数内 OBS 访问 |

---

## 13. FAQ / 故障排除

### Q1：创建短链返回「invalid url」？

**A**：仅接受 `http://` 或 `https://` 开头的地址，请检查输入。

### Q2：重定向返回 404？

**A**：短码不存在，或 OBS 桶 / 函数委托权限未配置（函数需 `OBS OperateAccess` 委托）。

### Q3：创建短链返回 2xx 但对象未落盘 / 重定向 404 / 列表 502？

**A**：这是函数访问 OBS 返回 403 的典型表现。请检查 FunctionGraph 的委托（`<project>-fgs-obs-agency`）是否已在 IAM 控制台确认 `OBS OperateAccess` 项目角色生效；委托生效有短暂延迟，可稍后重试；仍失败则新建委托并重新 apply。

### Q4：`terraform apply` 后公网访问超时？

**A**：APIG 专享实例创建约需 10 分钟。同时请确认调用的是 EIP 入口（`api_domain`）且带 `/release` 段——分组域名仅 VPC 内可解析，公网无法解析。

### 故障排查清单

| 现象 | 可能原因 | 排查方法 |
|---|---|---|
| plan 失败 | 访问密钥未设置 | 重新 `export HW_ACCESS_KEY/HW_SECRET_KEY` |
| 函数报凭据错误 | 函数委托未生效 | 检查函数 `xrole` 与 `OBS OperateAccess` 委托 |
| 部署时桶冲突 | 桶名非全局唯一 | 更换 `obs_bucket_name` |

---

## 14. 贡献指南

欢迎提交 Issue 与 PR。请遵循以下流程：

1. **Issue**：描述问题 / 建议（含复现命令、预期 / 实际输出、截图）
2. **PR**：基于 `main` 分支新建 feature 分支；提交前运行 `terraform validate` 与 `terraform fmt -check`
3. **Code Review**：由 **[@<github-username>](https://github.com/<github-username>)** reviewer 审核通过后合并

详细规范参见 `CONTRIBUTING.md`（如有）。

---

## 15. 许可证

本实践采用 **MIT No Attribution** 许可证发布。详见仓库根目录 [`LICENSE`](LICENSE) 文件。

```
MIT No Attribution

Copyright (c) Huawei Cloud

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software... (no attribution required)
```

---

## 16. 联系方式 / 维护者

| 项 | 内容 |
|---|---|
| **创建者** | [@<github-username>](https://github.com/<github-username>) |
| **维护者** | [@<github-username>](https://github.com/<github-username>) |
| **联系方式** | GitHub Issues / PR（见 [第 14 节](#14-贡献指南)） |

---