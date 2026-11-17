# ============================================================================
# URL 缩短器（华为云 APIG + FunctionGraph + OBS）
# ============================================================================
# 业务语义：
#   GET  /{linkId}         短链重定向（返回 301 Location=目标 URL）
#   GET  /app              列出短链
#   POST /app              创建短链（校验 URL、生成短码、写入存储）
#   PUT  /app/{linkId}     更新短链目标
#   DELETE /app/{linkId}   删除短链
# 存储：OBS 对象（key=links/{id}，内容=URL，metadata.owner）
# 部署：对象读写走 FunctionGraph（Node.js，OBS SDK），无数据库依赖。
# ============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = ">= 1.97.0"
    }
  }
}

# 访问密钥通过环境变量 HW_ACCESS_KEY / HW_SECRET_KEY 提供（provider 原生读取，
# 密钥不写入任何文件）；使用临时安全令牌时额外设置 HW_SECURITY_TOKEN。
provider "huaweicloud" {
  region = var.region
}

# ============================================================================
# Layer 1: 网络（APIG 专享实例所属 VPC）
# ============================================================================

resource "huaweicloud_vpc" "main" {
  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"
}

resource "huaweicloud_vpc_subnet" "main" {
  name       = "${var.project_name}-subnet"
  vpc_id     = huaweicloud_vpc.main.id
  cidr       = "10.0.1.0/24"
  gateway_ip = "10.0.1.1"
}

resource "huaweicloud_networking_secgroup" "main" {
  name        = "${var.project_name}-sg"
  description = "Security group for ${var.project_name}"
}

# ============================================================================
# Layer 2: 存储（OBS：短链对象 + 函数依赖包）
# ============================================================================

# 业务桶（预置）：部署前 obsutil 建桶并上传 code/url-handler-v2.zip（见 deployment-guide）
# 桶内运行时对象（links/{id}）由函数创建，无需 Terraform 管理。
# ============================================================================
# Layer 3: 计算（FunctionGraph 单函数 + 委托访问 OBS）
# ============================================================================

# 函数委托：授予 OBS 操作权限，函数运行时据此获得临时凭据访问对象存储。
# OBS OperateAccess 为全局服务角色，使用 domain_roles 在账号级授权，避免
# 项目级角色需等待 IAM 生效而返回 403。
resource "huaweicloud_identity_agency" "fgs_obs" {
  name                   = "${var.project_name}-fgs-obs-agency"
  description            = "Agency for FunctionGraph to access OBS"
  duration               = "FOREVER"
  delegated_service_name = "op_svc_cff"

  domain_roles = [
    "OBS OperateAccess",
  ]
}

resource "huaweicloud_fgs_function" "url_handler" {
  name        = "${var.project_name}-url-handler"
  app         = "default"
  agency      = huaweicloud_identity_agency.fgs_obs.name
  handler     = "index.handler"
  memory_size = 128
  timeout     = 30
  runtime     = "Node.js18.15"

  code_type = "obs"
  code_url  = "https://${var.obs_bucket_name}.obs.${var.region}.myhuaweicloud.com/code/url-handler.zip"

  user_data = jsonencode({
    OBS_BUCKET   = var.obs_bucket_name
    OBS_ENDPOINT = "https://obs.${var.region}.myhuaweicloud.com"
    REGION       = var.region
  })

  depends_on = [huaweicloud_identity_agency.fgs_obs]
}

# ============================================================================
# Layer 4: API 接入（APIG 专享实例 + 分组 + 5 路由 + CORS）
# ============================================================================

data "huaweicloud_availability_zones" "main" {}

# 公网入口弹性公网 IP（APIG 专享实例默认只有内网入口）
resource "huaweicloud_vpc_eip" "apig" {
  publicip {
    type = "5_bgp"
  }

  bandwidth {
    name        = "${var.project_name}-apig-eip"
    size        = 5
    share_type  = "PER"
    charge_mode = "traffic"
  }
}

resource "huaweicloud_apig_instance" "main" {
  name              = "${var.project_name}-apig"
  eip_id            = huaweicloud_vpc_eip.apig.id
  edition           = "BASIC"
  vpc_id            = huaweicloud_vpc.main.id
  subnet_id         = huaweicloud_vpc_subnet.main.id
  security_group_id = huaweicloud_networking_secgroup.main.id
  available_zones   = [data.huaweicloud_availability_zones.main.names[0]]
}

resource "huaweicloud_apig_group" "main" {
  name        = "${var.project_name}-group"
  instance_id = huaweicloud_apig_instance.main.id
  description = "API group for ${var.project_name}"
}

# 专享实例内置 RELEASE 环境，其环境 ID 为固定常量，不可重复创建
locals {
  release_env_id = "DEFAULT_ENVIRONMENT_RELEASE_ID"
}

# GET /{linkId} 重定向
resource "huaweicloud_apig_api" "redirect" {
  name             = "redirect"
  group_id         = huaweicloud_apig_group.main.id
  instance_id      = huaweicloud_apig_instance.main.id
  type             = "FunctionGraph"
  request_method   = "GET"
  request_path     = "/{linkId}"
  request_protocol = "HTTPS"


  func_graph {
    function_urn     = replace(huaweicloud_fgs_function.url_handler.urn, ":latest", "")
    network_type     = "V1"
    request_protocol = "HTTPS"
    version          = "latest"
  }

  lifecycle {
    ignore_changes = [func_graph]
  }
}

# POST /app 创建
resource "huaweicloud_apig_api" "create" {
  name             = "create-link"
  group_id         = huaweicloud_apig_group.main.id
  instance_id      = huaweicloud_apig_instance.main.id
  type             = "FunctionGraph"
  request_method   = "POST"
  request_path     = "/app"
  request_protocol = "HTTPS"

  func_graph {
    function_urn     = replace(huaweicloud_fgs_function.url_handler.urn, ":latest", "")
    network_type     = "V1"
    request_protocol = "HTTPS"
    version          = "latest"
  }

  lifecycle {
    ignore_changes = [func_graph]
  }
}

# GET /app 列表
resource "huaweicloud_apig_api" "list" {
  name             = "list-links"
  group_id         = huaweicloud_apig_group.main.id
  instance_id      = huaweicloud_apig_instance.main.id
  type             = "FunctionGraph"
  request_method   = "GET"
  request_path     = "/app"
  request_protocol = "HTTPS"

  func_graph {
    function_urn     = replace(huaweicloud_fgs_function.url_handler.urn, ":latest", "")
    network_type     = "V1"
    request_protocol = "HTTPS"
    version          = "latest"
  }

  lifecycle {
    ignore_changes = [func_graph]
  }
}

# PUT /app/{linkId} 更新
resource "huaweicloud_apig_api" "update" {
  name             = "update-link"
  group_id         = huaweicloud_apig_group.main.id
  instance_id      = huaweicloud_apig_instance.main.id
  type             = "FunctionGraph"
  request_method   = "PUT"
  request_path     = "/app/{linkId}"
  request_protocol = "HTTPS"


  func_graph {
    function_urn     = replace(huaweicloud_fgs_function.url_handler.urn, ":latest", "")
    network_type     = "V1"
    request_protocol = "HTTPS"
    version          = "latest"
  }

  lifecycle {
    ignore_changes = [func_graph]
  }
}

# DELETE /app/{linkId} 删除
resource "huaweicloud_apig_api" "delete" {
  name             = "delete-link"
  group_id         = huaweicloud_apig_group.main.id
  instance_id      = huaweicloud_apig_instance.main.id
  type             = "FunctionGraph"
  request_method   = "DELETE"
  request_path     = "/app/{linkId}"
  request_protocol = "HTTPS"


  func_graph {
    function_urn     = replace(huaweicloud_fgs_function.url_handler.urn, ":latest", "")
    network_type     = "V1"
    request_protocol = "HTTPS"
    version          = "latest"
  }

  lifecycle {
    ignore_changes = [func_graph]
  }
}

# 发布到 RELEASE 环境（API 发布后才能访问）
resource "huaweicloud_apig_api_publishment" "redirect" {
  instance_id = huaweicloud_apig_instance.main.id
  api_id      = huaweicloud_apig_api.redirect.id
  env_id      = local.release_env_id
}

resource "huaweicloud_apig_api_publishment" "create" {
  instance_id = huaweicloud_apig_instance.main.id
  api_id      = huaweicloud_apig_api.create.id
  env_id      = local.release_env_id
}

resource "huaweicloud_apig_api_publishment" "list" {
  instance_id = huaweicloud_apig_instance.main.id
  api_id      = huaweicloud_apig_api.list.id
  env_id      = local.release_env_id
}

resource "huaweicloud_apig_api_publishment" "update" {
  instance_id = huaweicloud_apig_instance.main.id
  api_id      = huaweicloud_apig_api.update.id
  env_id      = local.release_env_id
}

resource "huaweicloud_apig_api_publishment" "delete" {
  instance_id = huaweicloud_apig_instance.main.id
  api_id      = huaweicloud_apig_api.delete.id
  env_id      = local.release_env_id
}

output "api_domain" {
  description = "APIG 实例公网入口地址（调用时需拼接发布环境 RELEASE 与 API 路径）"
  value       = huaweicloud_apig_instance.main.ingress_address
}

output "api_group_domain" {
  description = "APIG 分组访问域名（形如 <分组ID>.apic.<区域>.huaweicloudapis.com）"
  value       = "${huaweicloud_apig_group.main.id}.apic.${var.region}.huaweicloudapis.com"
}

output "obs_bucket" {
  description = "OBS 存储桶"
  value       = var.obs_bucket_name
}