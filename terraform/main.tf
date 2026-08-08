# Deploys the Late Fee support form's Lambda backend (../lambda/handler.js) into us-east-2:
# the function itself, its IAM role (scoped to just ses:SendEmail on the one identity below),
# a public Function URL (simplest way to expose a single POST endpoint to a static site — no
# API Gateway needed), and the SES sender identity. Run `terraform apply` — everything else
# (npm install, zipping) happens automatically as part of the apply.
#
# What Terraform can't do for you: click the verification link SES emails to
# var.support_from_email (or, if you switch to a domain identity later, add the DNS records
# SES gives you). Sends will fail with an SES error until that's done — see the plan/apply
# output or the AWS Console (SES → Verified identities) to check status.

locals {
  lambda_src_dir = "${path.module}/../lambda"
  build_dir      = "${path.module}/.build"
}

# `npm install` isn't something `archive_file` can do on its own — it only zips whatever's
# already on disk. This runs it first, gated on package.json/package-lock.json so it doesn't
# needlessly reinstall on every apply.
resource "null_resource" "npm_install" {
  triggers = {
    package_json_hash = filesha256("${local.lambda_src_dir}/package.json")
  }

  provisioner "local-exec" {
    command     = "npm install --production"
    working_dir = local.lambda_src_dir
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = local.lambda_src_dir
  output_path = "${local.build_dir}/function.zip"
  excludes    = ["README.md"]

  depends_on = [null_resource.npm_install]
}

resource "aws_ses_email_identity" "support_sender" {
  email = var.support_from_email
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  tags = { Name = "${var.function_name}-logs" }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = { Name = "${var.function_name}-role" }
}

data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid       = "SendSupportTicketEmail"
    actions   = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = [aws_ses_email_identity.support_sender.arn]
  }

  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.function_name}-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

resource "aws_lambda_function" "support_form" {
  function_name    = var.function_name
  role             = aws_iam_role.lambda.arn
  handler          = "handler.handler"
  runtime          = "nodejs22.x"
  timeout          = 10
  memory_size      = 128

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SUPPORT_TO_EMAIL   = var.support_to_email
      SUPPORT_FROM_EMAIL = var.support_from_email
      ALLOWED_ORIGIN     = var.allowed_origin
    }
  }

  tags = { Name = var.function_name }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

# Public HTTPS endpoint for the contact form's fetch() POST — no API Gateway needed for a
# single route like this. Auth type NONE is intentional (see handler.js's own doc comment):
# the honeypot field plus SES-side validation are the only gate, which is fine for a
# low-volume support form but does mean the URL is publicly invokable by anyone who has it.
resource "aws_lambda_function_url" "support_form" {
  function_name      = aws_lambda_function.support_form.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = [var.allowed_origin]
    allow_methods = ["POST"]
    allow_headers = ["content-type"]
    max_age       = 300
  }
}

# Function URLs with authorization_type = NONE still need an explicit resource policy
# granting anonymous invoke — the auth-type setting alone doesn't do it.
resource "aws_lambda_permission" "public_invoke" {
  statement_id           = "AllowPublicInvokeViaFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.support_form.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# As of October 2025, AWS requires a *second*, separate grant for public Function URLs:
# plain lambda:InvokeFunction, scoped to only calls made via the function URL (not other
# invocation paths) by invoked_via_function_url. Without this, every call gets a 403
# AccessDeniedException even with AuthType NONE and the InvokeFunctionUrl grant above already
# in place — see https://docs.aws.amazon.com/lambda/latest/dg/urls-auth.html.
resource "aws_lambda_permission" "public_invoke_function" {
  statement_id              = "AllowPublicInvokeFunctionViaURL"
  action                    = "lambda:InvokeFunction"
  function_name             = aws_lambda_function.support_form.function_name
  principal                 = "*"
  invoked_via_function_url  = true
}
