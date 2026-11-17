# 部署指导书

本指导书说明如何在华为云部署 `distributed-x-infrastructure-url-shortener` 并完成短链创建与重定向验证。

## 1. 前置条件

- 华为云账号（已实名认证），区域 `cn-north-4`
- Terraform ≥ 1.5、obsutil
- 访问密钥（在「我的凭证」创建），具备 APIG / FunctionGraph / OBS / VPC 操作权限
- **函数委托（强制前置）**：FunctionGraph 需以 `OBS OperateAccess` 委托访问对象存储。部署 Terraform 会自动创建委托（`<project>-fgs-obs-agency`），但**请先在 IAM 控制台确认该委托的项目级角色已生效**（委托详情 → 授权记录 → 应有 `OBS OperateAccess`），否则函数运行时的 OBS 读写会返回 403（表现为：创建短链返回 2xx 但对象未落盘、重定向 404、列表 502）

## 2. 预置 OBS 业务桶与函数代码

函数代码通过 OBS 包发布，需先建桶并上传依赖包：

```bash
# 建桶（桶名全局唯一）
obsutil mb obs://<obs-bucket-name> -location=cn-north-4

# 在 src/functions/url-handler 下安装依赖并打包
cd src/functions/url-handler
npm install --omit=dev
zip -rq /tmp/url-handler.zip index.js node_modules

# 上传函数代码包
obsutil cp /tmp/url-handler.zip obs://<obs-bucket-name>/code/url-handler.zip -f
```

## 3. 配置并部署

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # 填写 region / project_name / obs_bucket_name
export HW_ACCESS_KEY="<your-access-key>"
export HW_SECRET_KEY="<your-secret-key>"
terraform init
terraform plan
terraform apply -auto-approve
```

apply 完成后记录 OBS 桶名与两个入口地址：

- `api_domain`——实例 EIP 公网入口，公网可达；
- `api_group_domain`——分组内网域名（`<分组ID>.apic.<region>.huaweicloudapis.com`），仅 VPC 内可达。

两者调用路径均需带发布环境段 `/release`。

### 部署前最小验证（建议）

确认函数委托可用后，部署前可先建一个最小对象读写函数验证 OBS 通路：

```bash
# 观察函数日志输出（无 403 即委托生效；有 403 请先修复委托再继续）
# 详情见 README 第 9 节验证命令
```

若部署后出现 403 类现象，按上述「函数委托（强制前置）」排查 IAM 委托权限。

## 4. 验证

```bash
# 创建短链（FGS 同步调用）
hcloud FunctionGraph InvokeFunction --cli-region=cn-north-4 \
  --function_urn="<函数 URN>" \
  --body='{"httpMethod":"POST","path":"/app","body":"{\"url\":\"https://example.com/very/long\"}"}'
# 期望：201 {"id":"<short-code>","url":...}

# 重定向（FGS 同步调用）
hcloud FunctionGraph InvokeFunction --cli-region=cn-north-4 \
  --function_urn="<函数 URN>" \
  --body='{"httpMethod":"GET","path":"/<short-code>","pathParameters":{"linkId":"<short-code>"}}'
# 期望：301 + Location

# 公网调用（走 EIP 入口，需带发布环境段 /release）
curl -i "https://<api_domain>/release/<short-code>"
# 期望：HTTP/1.1 301 Location: https://example.com/very/long

# VPC 内调用（走分组内网域名，公网 DNS 不可解析）
curl -i "https://<api_group_domain>/release/<short-code>"
```

## 5. 清理资源

```bash
cd infra
terraform destroy -auto-approve
# 手动删除预置 OBS 桶与对象
obsutil rm obs://<obs-bucket-name> -r -f
obsutil rm obs://<obs-bucket-name> -f
```


## 6. 构建并托管前端（可选）

```bash
cd src/frontend
npm install
echo 'VUE_APP_API_ROOT=https://<api_domain>/release' > .env
npm run build
# 将构建产物上传至 OBS 并开启静态网站托管
obsutil cp dist obs://<obs-bucket-name>/frontend/ -r -f
```

前端面板（`src/frontend/src/views/ShortenerDashboard.vue`）通过 `VUE_APP_API_ROOT` 指向网关入口，以开放模式调用 5 个 REST 接口（不注入任何身份请求头）。
