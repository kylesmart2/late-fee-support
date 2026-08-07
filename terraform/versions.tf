terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
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
    tags = {
      Project    = "late-fee-support"
      ManagedBy  = "terraform"
      Repository = "kylesmart2/late-fee-support"
    }
  }
}
