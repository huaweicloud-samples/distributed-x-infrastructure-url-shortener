# distributed-x-infrastructure-url-shortener / URL Shortener

[中文版](README.cn.md)

[![License](https://img.shields.io/badge/License-MIT%20No%20Attribution-blue.svg)](LICENSE)
[![Huawei Cloud](https://img.shields.io/badge/Huawei%20Cloud-IAM%20Auth-red.svg)](https://support.huaweicloud.com/intl/en-us/)
[![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg)](#)

> Serverless URL Shortener Service
> 无服务器 URL 缩短服务

---

## 1. Overview

This practice provides the core capability of **short link creation and 301 redirect** for **long-URL shortening, sharing and tracking** scenarios. It is intended for DevOps / backend engineers and can be used as a reference architecture / learning sample / production template.

### Core Capabilities

- Serverless API: APIG gateway + a single FunctionGraph function, auto-scaling, no idle capacity
- Full short-link lifecycle: create / redirect / list / update / delete
- Simple storage: OBS objects directly carry the short code and target URL; no database

---

## 2. Table of Contents

- [1. Overview](#1-overview)
- [2. Table of Contents](#2-table-of-contents)
- [3. Architecture](#3-architecture)
- [4. Highlights](#4-highlights)
- [5. Involved Cloud Services](#5-involved-cloud-services)
- [6. Prerequisites](#6-prerequisites-critical)
- [7. Quick Start](#7-quick-start-critical)
- [8. Step-by-step Deployment](#8-step-by-step-deployment)
- [9. Usage / Verification](#9-usage--verification-critical)
- [10. Clean Up Resources](#10-clean-up-resources)
- [11. Detailed Explanation](#11-detailed-explanation)
- [12. Dependencies](#12-dependencies)
- [13. FAQ / Troubleshooting](#13-faq--troubleshooting)
- [14. Contribution Guide](#14-contribution-guide)
- [15. License](#15-license-critical)
- [16. Contact / Maintainers](#16-contact--maintainers-critical)

---

## 3. Architecture

> One deployment gives you a complete URL shortener: gateway routing + function logic + object storage persistence.

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

**Key Components**:
- APIG Dedicated Instance: API gateway entry hosting 5 routes published to RELEASE
- FunctionGraph `url-handler`: routes business logic by HTTP method/path, accesses object storage via agency
- OBS bucket: short-link object storage (key=`links/{id}`, content=target URL)

---

## 4. Highlights

- **Auto-scaling without idle capacity**: serverless, no persistent compute
- **Single function covers lifecycle**: create / redirect / list / update / delete in one handler
- **Storage as data**: OBS objects directly carry short code and URL, no database
- **Easy to integrate**: REST-style routes callable by frontends / clients

---

## 5. Involved Cloud Services

| Service | Purpose | Notes |
|---|---|---|
| Application and Website Services (APIG) | API gateway entry, routes and release | Dedicated instance, BASIC edition |
| FunctionGraph | Short-link business logic | Node.js18.15, 128MB |
| Object Storage Service (OBS) | Short-link objects + function code package | Private bucket |
| Virtual Private Cloud (VPC) | Network for the APIG instance | Includes subnet and security group |

> **Note**: All services can be created with one command through the Terraform in this repository; to clean up, see [Section 10](#10-clean-up-resources).

---

## 6. Prerequisites

| Item | Requirement | Notes |
|---|---|---|
| **Account** | A real-name verified Huawei Cloud account | Personal or enterprise |
| **Permissions** | IAM **Tenant Administrator** or equivalent | To create VPC / APIG / FunctionGraph / OBS resources |
| **Region** | Recommended `cn-north-4` | Cross-region availability may vary |
| **Terraform** | `>= 1.5.0` | IaC deployment tool |
| **huaweicloud Provider** | `>= 1.97.0` | Huawei Cloud Terraform Provider (locked to 1.98.2) |
| **obsutil** | `>= 5.5.0` | Provision OBS bucket and upload function code |
| **Node.js** | `>= 18` *(local)* | Install function dependencies and package |
| **Access keys** | Create Access Key ID and Secret Access Key in "My Credentials", then export them as `HW_ACCESS_KEY` / `HW_SECRET_KEY` | **Do not** write credentials into any code or config file |
| **OBS agency** | FunctionGraph needs an `OBS OperateAccess` agency to access object storage | After deployment, verify in the IAM console that the agency project role is effective, otherwise OBS returns 403 (see FAQ Q3) |

---

## 7. Quick Start

### One-command Deployment (Recommended)

```bash
# 1. Clone this repository
git clone <repo-https-url> distributed-x-infrastructure-url-shortener
cd distributed-x-infrastructure-url-shortener

# 2. Prepare Huawei Cloud access keys (see [Prerequisites §6](#6-prerequisites-critical))
export HW_ACCESS_KEY="<your-access-key>"
export HW_SECRET_KEY="<your-secret-key>"

# 3. Provision the OBS bucket and upload function code (see [Section 8](#8-step-by-step-deployment) Step 1)
obsutil mb obs://<obs-bucket-name> -location=cn-north-4

# 4. Deploy with one command
cd infra
terraform init
terraform plan
terraform apply -auto-approve
```

> **Deployment time**: about 10-15 minutes (APIG dedicated instance creation is slow).
> **Full steps and expected output**: see [Section 8](#8-step-by-step-deployment).

---

## 8. Step-by-step Deployment

### Step 1: Provision OBS bucket and upload function code

```bash
cd src/functions/url-handler
npm install --omit=dev
zip -rq /tmp/url-handler.zip index.js node_modules
obsutil mb obs://<obs-bucket-name> -location=cn-north-4
obsutil cp /tmp/url-handler.zip obs://<obs-bucket-name>/code/url-handler.zip -f
```

**Expected output**: `Upload successfully`; then put the bucket name into `obs_bucket_name` in `infra/terraform.tfvars`.

### Step 2: Initialize Working Directory

```bash
cd distributed-x-infrastructure-url-shortener/infra
terraform init
```

**Expected output**: `Terraform has been successfully initialized!`

### Step 3: Preview Resource Changes

```bash
terraform plan
```

**Expected output**: `Plan: N to add, 0 to change, 0 to destroy.`

### Step 4: Execute Deployment

```bash
terraform apply -auto-approve
```

**Expected output**: `Apply complete! Resources: N added, 0 changed, 0 destroyed.`

---

## 9. Usage / Verification

> **Verification status**: the function-invocation commands below were actually executed during deployment verification — `POST /app`, `PUT /app/{linkId}` and `DELETE /app/{linkId}` returned 201 / 200 / 200. The end-to-end redirect and list calls were blocked by an OBS 403 in the account's function runtime; the public-gateway `curl` was not executed. Re-run every command yourself and confirm the business function works before considering delivery complete.

### Verify 1: Create short link

```bash
# Invoke the function to create a short link (POST /app)
hcloud FunctionGraph InvokeFunction --cli-region=cn-north-4 \
  --function_urn="<url-handler function URN>" \
  --body='{"httpMethod":"POST","path":"/app","body":"{\"url\":\"https://example.com/very/long\"}"}'
```

**Expected output**:
```
{"id":"<short-code>","url":"https://example.com/very/long","owner":"public",...}
```

### Verify 2: Redirect

```bash
# Use the short-code from above to test redirect (GET /{linkId})
hcloud FunctionGraph InvokeFunction --cli-region=cn-north-4 \
  --function_urn="<url-handler function URN>" \
  --body='{"httpMethod":"GET","path":"/<short-code>","pathParameters":{"linkId":"<short-code>"}}'
```

**Expected output**:
```
{"statusCode":301,"headers":{"Location":"https://example.com/very/long",...}}
```

### Verify 3: End-to-end via the public gateway

```bash
# The public entry is the EIP bound to the APIG instance (output `api_domain`).
# Published APIs are addressed through the environment segment `/release`.
curl -i "https://<api_domain>/release/<short-code>"
```

**Expected output**:
```
HTTP/1.1 301 Moved Permanently
Location: https://example.com/very/long
```

> **Two different entry points**: the group domain (`<group-id>.apic.<region>.huaweicloudapis.com`, output `api_group_domain`) resolves **only inside the VPC** — public DNS cannot resolve it. Use the EIP (`api_domain`) for public access. Both use the `/release` environment segment.

### Verify 4: End-to-end business flow (recommended)

```bash
# Create → redirect → list → delete (create/redirect see Verify 1/2; list/delete via FGS invoke or public REST)
```

**Expected result**: after creating a short link, 301 redirect works via gateway or function invoke; list/update/delete operations behave consistently.

### Step 5: Build and host the frontend (optional)

```bash
cd src/frontend
npm install
echo 'VUE_APP_API_ROOT=https://<api_domain>/release' > .env
npm run build
# upload dist/ to OBS static hosting (obsutil cp src/frontend/dist obs://<obs-bucket-name>/frontend/ -r -f)
```

---

## 10. Clean Up Resources

```bash
# Enter the deployment directory
cd distributed-x-infrastructure-url-shortener/infra

# Release all Terraform-managed resources
terraform destroy -auto-approve

# Manually clean the provisioned OBS bucket (objects + bucket)
obsutil rm obs://<obs-bucket-name> -r -f
obsutil rm obs://<obs-bucket-name> -f
```

**Expected output**: `Destroy complete! Resources: N destroyed.`

> **Avoid resource leftovers**:
> - `terraform destroy` only releases resources tracked in the Terraform state;
> - The provisioned OBS bucket and function code package must be removed manually with obsutil;
> - Shared resources (NAT / VPC shared by other tasks in the account) are not affected.

---

## 11. Detailed Explanation

### Workflow

1. `POST /app` (body with `url`) → APIG → function validates URL, generates a base62 code, writes an OBS object → returns the short link
2. `GET /{linkId}` → APIG → function reads the OBS object → returns 301 + `Location`
3. Management operations (list / update / delete) use `/app` and `/app/{linkId}` routes

### Configuration

| Variable | Default | Description |
|---|---|---|
| `region` | `cn-north-4` | Huawei Cloud region |
| `project_name` | `url-shortener` | Resource name prefix |
| `obs_bucket_name` | (required) | Provisioned OBS business bucket (globally unique) |

### API

| Method / Path | Description | Returns |
|---|---|---|
| `GET /{linkId}` | Short-link redirect | 301 + Location |
| `GET /app` | List short links | 200 array |
| `POST /app` | Create short link | 201 `{id,url}` |
| `PUT /app/{linkId}` | Update target URL | 200 |
| `DELETE /app/{linkId}` | Delete short link | 200 |

Request / response example:

```bash
curl -X POST "https://<api_domain>/release/app" -H 'Content-Type: application/json' -d '{"url":"https://example.com/very/long"}'
# {"id":"Ab3xYz","url":"https://example.com/very/long","owner":"public","timestamp":...}
```

---

## 12. Dependencies

### Main Dependencies

| Name | Version | Purpose |
|---|---|---|
| Terraform | `>= 1.5.0` | IaC orchestration |
| huaweicloud Provider | `>= 1.97.0` (locked to 1.98.2) | Huawei Cloud resources |
| Node.js | `18.15` | FunctionGraph runtime |
| esdk-obs-nodejs | `^3.26.8` | OBS access in function |

---

## 13. FAQ / Troubleshooting

### Q1: Creating a short link returns "invalid url"?

**A**: Only addresses starting with `http://` or `https://` are accepted; check the input.

### Q2: Redirect returns 404?

**A**: The short code does not exist, or the OBS bucket / agency permission is misconfigured (the function needs the `OBS OperateAccess` agency).

### Q3: Create returns 2xx but the object is not stored / redirect 404 / list 502?

**A**: This is the typical symptom of OBS access returning 403 inside the function. Check the FunctionGraph agency (`<project>-fgs-obs-agency`) and confirm the `OBS OperateAccess` project role is effective in the IAM console; agency propagation may take a short while, retry later; if it still fails, create a new agency and re-apply.

### Q4: Public access times out after `terraform apply`?

**A**: The APIG dedicated instance takes about 10 minutes to be ready. Also verify you are calling the EIP entry (`api_domain`) with the `/release` segment — the group domain is VPC-internal only and cannot be resolved from the public Internet.

### Troubleshooting Checklist

| Symptom | Possible Cause | How to Check |
|---|---|---|
| plan fails | access keys not set | Re-export `HW_ACCESS_KEY/HW_SECRET_KEY` |
| function credential error | agency not effective | Check function `xrole` and `OBS OperateAccess` agency |
| bucket conflict | bucket name not globally unique | Change `obs_bucket_name` |

---

## 14. Contribution Guide

Welcome Issues and PRs. Please follow this flow:

1. **Issue**: describe the problem / suggestion (with repro commands, expected / actual output, screenshots)
2. **PR**: create a feature branch from `main`; run `terraform validate` and `terraform fmt -check` before submitting
3. **Code Review**: reviewed and merged by **[@<github-username>](https://github.com/<github-username>)**

See `CONTRIBUTING.md` for details (if present).

---

## 15. License

This practice is released under the **MIT No Attribution** license. See the [`LICENSE`](LICENSE) file in the repository root.

```
MIT No Attribution

Copyright (c) Huawei Cloud

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software... (no attribution required)
```

---

## 16. Contact / Maintainers

| Item | Content |
|---|---|
| **Creator** | [@<github-username>](https://github.com/<github-username>) |
| **Maintainer** | [@<github-username>](https://github.com/<github-username>) |
| **Contact** | GitHub Issues / PR (see [Section 14](#14-contribution-guide)) |

---
