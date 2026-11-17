variable "region" {
  description = "华为云区域"
  type        = string
  default     = "cn-north-4"
}

variable "project_name" {
  description = "项目名称，用于资源命名前缀"
  type        = string
  default     = "url-shortener"
}

variable "obs_bucket_name" {
  description = "OBS 业务桶名（全局唯一，需先手动创建并上传函数代码包）"
  type        = string
  default     = "url-shortener-store"
}
