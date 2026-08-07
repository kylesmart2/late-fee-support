output "function_url" {
  description = "Paste this into ../assets/js/config.js as window.LATE_FEE_SUPPORT_ENDPOINT."
  value       = aws_lambda_function_url.support_form.function_url
}

output "ses_verification_status" {
  description = "Reminder — check AWS Console (SES → Verified identities) or `aws ses get-identity-verification-attributes --identities <email>` to confirm the sender address is actually verified before expecting real sends to succeed."
  value       = "Verify ${aws_ses_email_identity.support_sender.email} by clicking the link SES emailed to it."
}

output "cloudwatch_log_group" {
  description = "Where to look if the form reports an error — /aws/lambda/<function_name> in us-east-2."
  value       = aws_cloudwatch_log_group.lambda.name
}
