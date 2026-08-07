# Terraform — Late Fee support form Lambda

Deploys `../lambda/handler.js` into **us-east-2**: the Lambda function, its IAM role (scoped
to just `ses:SendEmail`/`ses:SendRawEmail` on one identity, plus writing its own CloudWatch
logs), a public Function URL, and the SES sender identity. `terraform apply` handles `npm
install` and zipping for you — no manual build step.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- AWS credentials available to the CLI (`aws configure`, or an `AWS_PROFILE` env var, or SSO
  — anything the AWS provider can pick up normally)
- Node.js/npm installed locally (used during `apply` to install the Lambda's dependencies)

## Usage

```
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your real support inbox + sender address

terraform init
terraform plan
terraform apply
```

State is local (`terraform.tfstate`, gitignored) — fine for a single person on one machine.
If you ever want to run this from more than one place, switch to an S3 backend at that point;
not set up by default since it adds a bucket + DynamoDB lock table to provision first.

## After `apply`

1. **Verify the sender address.** `terraform apply` creates the SES identity but can't click
   the verification link for you — check your inbox for `support_from_email` and confirm it.
   Sends silently fail with an SES error until this is done.
2. **Copy the Function URL** from the `function_url` output into
   `../assets/js/config.js`:
   ```js
   window.LATE_FEE_SUPPORT_ENDPOINT = "<function_url output>";
   ```
   Commit and push — GitHub Pages redeploys automatically.
3. **Test it** — submit the form on the live site, or:
   ```
   curl -X POST "<function_url output>" \
     -H "Content-Type: application/json" \
     -d '{"name":"Test","email":"you@example.com","topic":"bug","message":"Hello"}'
   ```

## Updating `ALLOWED_ORIGIN` for a custom domain

Once `latefeetracker.app` (or whatever domain) is live on GitHub Pages, update
`allowed_origin` in `terraform.tfvars` to the new origin and re-run `terraform apply` — this
updates both the Lambda's CORS-checking env var and the Function URL's own CORS config in one
pass. Forgetting this step means the contact form gets blocked by CORS from the new domain
even though the Lambda itself is otherwise working fine.

## Tearing it down

```
terraform destroy
```

Removes the Lambda, its Function URL, IAM role, log group, and the SES identity. Doesn't
touch anything outside this Terraform state (the GitHub Pages site itself is unaffected).
