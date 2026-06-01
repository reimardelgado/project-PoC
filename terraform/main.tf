terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  alias      = "storage"
  region     = var.aws_region
  access_key = var.minio_access_key
  secret_key = var.minio_secret_key

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  skip_region_validation      = true
  s3_use_path_style           = true

  endpoints {
    s3 = var.minio_s3_endpoint
  }
}

provider "aws" {
  alias      = "control"
  region     = var.aws_region
  access_key = var.localstack_access_key
  secret_key = var.localstack_secret_key

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  skip_region_validation      = true

  endpoints {
    glue = var.localstack_endpoint
    iam  = var.localstack_endpoint
    sts  = var.localstack_endpoint
  }
}

locals {
  pii_columns                 = ["customer_email", "credit_card"]
  sales_product_location      = "s3a://${var.sales_bucket_name}/${var.sales_product_prefix}/"
  marketing_projection_fields = [
    { name = "transaction_id", type = "string", comment = "Identificador único de la transacción" },
    { name = "order_date", type = "string", comment = "Fecha heredada, pendiente de normalización aguas arriba" },
    { name = "customer_id", type = "string", comment = "Identificador pseudonimizado del cliente" },
    { name = "territory", type = "string", comment = "Territorio comercial" },
    { name = "product_category", type = "string", comment = "Categoría de producto" },
    { name = "sales_channel", type = "string", comment = "Canal de venta" },
    { name = "payment_method", type = "string", comment = "Método de pago" },
    { name = "quantity", type = "int", comment = "Unidades vendidas" },
    { name = "unit_price", type = "double", comment = "Precio unitario estandarizado" },
    { name = "gross_amount", type = "double", comment = "Importe bruto estandarizado en EUR" },
    { name = "legacy_status", type = "string", comment = "Estado heredado para trazabilidad" },
    { name = "source_system", type = "string", comment = "Sistema origen" }
  ]

  secure_projection_fields = concat(
    local.marketing_projection_fields,
    [
      { name = "customer_email", type = "string", comment = "PII-Tag" },
      { name = "credit_card", type = "string", comment = "PII-Tag" }
    ]
  )
}

resource "aws_s3_bucket" "legacy" {
  provider      = aws.storage
  bucket        = var.legacy_bucket_name
  force_destroy = true

  tags = {
    domain      = "legacy"
    mesh_role   = "source"
    strangler   = "true"
    environment = "local-first"
  }
}

resource "aws_s3_bucket" "sales" {
  provider      = aws.storage
  bucket        = var.sales_bucket_name
  force_destroy = true

  tags = {
    domain      = "sales"
    mesh_role   = "data-product"
    environment = "local-first"
  }
}

resource "aws_s3_bucket_public_access_block" "legacy" {
  provider                = aws.storage
  bucket                  = aws_s3_bucket.legacy.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "sales" {
  provider                = aws.storage
  bucket                  = aws_s3_bucket.sales.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_glue_catalog_database" "mesh" {
  provider = aws.control
  name     = var.glue_database_name

  description = "Catálogo federado local-first para la PoC Data Mesh"
}

resource "aws_glue_catalog_table" "sales_secure" {
  provider      = aws.control
  name          = var.sales_secure_table_name
  database_name = aws_glue_catalog_database.mesh.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL             = "TRUE"
    classification       = "parquet"
    "data_product.domain" = "sales"
    "mesh.visibility"   = "restricted"
    "pii.columns"       = join(",", local.pii_columns)
    "rbac.note"         = "Tabla completa con PII; no debe ser visible para Marketing"
  }

  storage_descriptor {
    location      = local.sales_product_location
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    dynamic "columns" {
      for_each = local.secure_projection_fields

      content {
        name    = columns.value.name
        type    = columns.value.type
        comment = columns.value.comment
      }
    }
  }
}

resource "aws_glue_catalog_table" "sales_marketing" {
  provider      = aws.control
  name          = var.sales_marketing_table_name
  database_name = aws_glue_catalog_database.mesh.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL               = "TRUE"
    classification         = "parquet"
    "data_product.domain" = "sales"
    "mesh.visibility"     = "marketing-safe"
    "pii.columns"         = join(",", local.pii_columns)
    "rbac.note"           = "Proyección sin columnas PII; esta es la interfaz autorizada para Marketing"
  }

  storage_descriptor {
    location      = local.sales_product_location
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    dynamic "columns" {
      for_each = local.marketing_projection_fields

      content {
        name    = columns.value.name
        type    = columns.value.type
        comment = columns.value.comment
      }
    }
  }
}

data "aws_iam_policy_document" "marketing_assume_role" {
  statement {
    sid     = "AllowLocalMarketingPrincipal"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }
}

resource "aws_iam_role" "marketing" {
  provider           = aws.control
  name               = "MarketingRole"
  assume_role_policy = data.aws_iam_policy_document.marketing_assume_role.json

  tags = {
    domain = "marketing"
    scope  = "consumer"
  }
}

data "aws_iam_policy_document" "marketing_sales_access" {
  statement {
    sid    = "AllowListSalesBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    resources = [aws_s3_bucket.sales.arn]
  }

  statement {
    sid    = "AllowReadSalesProductObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    resources = ["${aws_s3_bucket.sales.arn}/${var.sales_product_prefix}/*"]
  }

  statement {
    sid    = "AllowGlueLookupForMarketingProjection"
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables"
    ]
    resources = [
      "arn:aws:glue:${var.aws_region}:000000000000:catalog",
      "arn:aws:glue:${var.aws_region}:000000000000:database/${aws_glue_catalog_database.mesh.name}",
      "arn:aws:glue:${var.aws_region}:000000000000:table/${aws_glue_catalog_database.mesh.name}/${aws_glue_catalog_table.sales_marketing.name}"
    ]
  }

  statement {
    sid    = "DenySecureTableWithPII"
    effect = "Deny"
    actions = [
      "glue:GetTable",
      "glue:GetTables"
    ]
    resources = [
      "arn:aws:glue:${var.aws_region}:000000000000:table/${aws_glue_catalog_database.mesh.name}/${aws_glue_catalog_table.sales_secure.name}"
    ]
  }
}

resource "aws_iam_policy" "marketing_sales_access" {
  provider    = aws.control
  name        = "MarketingSalesDomainAccess"
  description = "RBAC simulado: Marketing consume el producto de Ventas mediante una proyección sin PII"
  policy      = data.aws_iam_policy_document.marketing_sales_access.json
}

resource "aws_iam_role_policy_attachment" "marketing_sales_access" {
  provider   = aws.control
  role       = aws_iam_role.marketing.name
  policy_arn = aws_iam_policy.marketing_sales_access.arn
}

output "legacy_bucket_name" {
  value       = aws_s3_bucket.legacy.bucket
  description = "Bucket legado que actúa como origen del patrón estrangulador"
}

output "sales_bucket_name" {
  value       = aws_s3_bucket.sales.bucket
  description = "Bucket del producto de datos del dominio Ventas"
}

output "glue_database_name" {
  value       = aws_glue_catalog_database.mesh.name
  description = "Base de datos del catálogo federado"
}

output "marketing_role_name" {
  value       = aws_iam_role.marketing.name
  description = "Rol consumidor autorizado para el dominio Marketing"
}

output "marketing_safe_table" {
  value       = aws_glue_catalog_table.sales_marketing.name
  description = "Tabla/proyección sin PII visible para Marketing"
}
