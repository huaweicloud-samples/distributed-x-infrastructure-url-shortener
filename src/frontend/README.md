# 短链管理前端

Vue 短链管理前端，通过 5 个 REST 接口管理短链（创建 / 重定向展示 / 列表 / 更新 / 删除）。

## 环境变量

复制 `.env.example` 为 `.env` 并填写：

| 变量 | 说明 |
|---|---|
| `VUE_APP_NAME` | 应用名（导航标题） |
| `VUE_APP_API_ROOT` | API 网关入口地址，公网用 EIP 入口，如 `https://<api_domain>/release` |

开放模式无需认证，代码中不注入任何身份请求头；生产接入自定义认证后，可在 `src/views/ShortenerDashboard.vue` 中自行补充请求头注入。

## 构建

```bash
npm install
echo 'VUE_APP_API_ROOT=https://<api_domain>/release' > .env
npm run build
```

## 部署（OBS 静态托管）

```bash
# 将构建产物 dist/ 上传到 OBS 桶并开启静态网站托管
obsutil cp dist obs://<obs-bucket-name>/frontend/ -r -f
```

访问 OBS 静态网站端点即可使用；如绑定自定义域名，请配置 CDN / DNS 指向。