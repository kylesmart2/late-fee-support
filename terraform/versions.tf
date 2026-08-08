terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # Needs >= 6.0: aws_lambda_permission's invoked_via_function_url argument (required for
      # public Function URLs since AWS's October 2025 policy change) only exists from v6 on.
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

locals {
  default_tags = {
    Project    = "late-fee-support"
    ManagedBy  = "terraform"
    Repository = "kylesmart2/late-fee-support"
  }
}

provider "aws" {
  region = "us-east-2"

  # Applies automatically to every resource type that supports tagging (Lambda, IAM role,
  # CloudWatch log group, S3 bucket — SES identities and Route 53 records don't support tags
  # at all, so those just silently don't get these regardless). Search by tag in the AWS
  # Console via Resource Groups & Tag Editor to pull up everything this config created at
  # once, across services.
  default_tags {
    tags = local.default_tags
  }
}

# CloudFront only ever accepts ACM certificates from us-east-1, regardless of which region
# the distribution itself (or anything else in this config) actually lives in — a hard AWS
# requirement, not a choice made here. Only used for the one certificate resource below.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.default_tags
  }
}
