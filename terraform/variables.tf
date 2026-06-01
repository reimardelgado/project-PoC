variable "aws_region" {
  description = "Región lógica usada por la emulación local."
  type        = string
  default     = "eu-west-1"
}

variable "minio_s3_endpoint" {
  description = "Endpoint S3-compatible de MinIO."
  type        = string
  default     = "http://localhost:9000"
}

variable "minio_access_key" {
  description = "Access key de MinIO."
  type        = string
  default     = "admin"
}

variable "minio_secret_key" {
  description = "Secret key de MinIO."
  type        = string
  default     = "password"
  sensitive   = true
}

variable "localstack_endpoint" {
  description = "Endpoint único de LocalStack para IAM, Glue y STS."
  type        = string
  default     = "http://localhost:4566"
}

variable "localstack_access_key" {
  description = "Credencial dummy compatible con LocalStack."
  type        = string
  default     = "test"
}

variable "localstack_secret_key" {
  description = "Secreto dummy compatible con LocalStack."
  type        = string
  default     = "test"
  sensitive   = true
}

variable "legacy_bucket_name" {
  description = "Bucket que simula el Data Lake heredado monolítico."
  type        = string
  default     = "monolithic-datalake-legacy"
}

variable "sales_bucket_name" {
  description = "Bucket del dominio productor de Ventas."
  type        = string
  default     = "sales-domain-data-product"
}

variable "glue_database_name" {
  description = "Base de datos lógica del catálogo federado."
  type        = string
  default     = "mesh_poc_catalog"
}

variable "sales_secure_table_name" {
  description = "Tabla completa del producto de datos de Ventas, incluyendo columnas PII."
  type        = string
  default     = "sales_product_secure"
}

variable "sales_marketing_table_name" {
  description = "Proyección segura para Marketing sin columnas PII."
  type        = string
  default     = "sales_product_marketing"
}

variable "sales_product_prefix" {
  description = "Prefijo donde el dominio Ventas publicará el parquet curado."
  type        = string
  default     = "curated/sales_transactions"
}
