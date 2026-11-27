terraform {
  required_version = ">= 1.5.0"
}

variable "aws_region" {
  description = "Región del bucket de estado y de la tabla de locks."
  type        = string
  default     = "us-east-1"
}

# El Learner Lab niega s3:GetBucketObjectLockConfiguration. El recurso
# aws_s3_bucket lee esa configuración al crearse y el apply falla, aunque
# el bucket ya exista. Este paso usa la CLI, que no hace esa lectura.
resource "terraform_data" "backend" {
  input = var.aws_region

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      export AWS_DEFAULT_REGION="${var.aws_region}"
      ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
      BUCKET="todo-list-tfstate-$${ACCOUNT}"
      if ! aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
        aws s3api create-bucket --bucket "$BUCKET" --region "$AWS_DEFAULT_REGION"
      fi
      aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
      aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
      aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
      if ! aws dynamodb describe-table --table-name todo-list-tfstate-lock >/dev/null 2>&1; then
        aws dynamodb create-table \
          --table-name todo-list-tfstate-lock \
          --attribute-definitions AttributeName=LockID,AttributeType=S \
          --key-schema AttributeName=LockID,KeyType=HASH \
          --billing-mode PAY_PER_REQUEST
        aws dynamodb wait table-exists --table-name todo-list-tfstate-lock
      fi
      echo "$BUCKET"
    EOT
  }
}

output "lock_table" {
  description = "Tabla DynamoDB para el lock del tfstate."
  value       = "todo-list-tfstate-lock"
}
