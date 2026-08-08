# Terraform — Late Fee support infrastructure

Two things, split across `main.tf` and `dns.tf`:

- **The Lambda contact-form backend** (`main.tf`), in **us-east-2**: the function, its IAM
  role (scoped to just `ses:SendEmail`/`ses:SendRawEmail` on one identity, plus writing its
  own CloudWatch logs), a public Function URL, and the SES sender identity. `terraform apply`
  handles `npm install` and zipping for you — no manual build step. The Function URL's public
  access needs *two* separate `aws_lambda_permission` grants — `lambda:InvokeFunctionUrl` and,
  as of an AWS policy change in October 2025, a second one for plain `lambda:InvokeFunction`
  scoped via `invoked_via_function_url` — or every call 403s with `AccessDeniedException` even
  though `AuthType` is `NONE`. See the comment above `aws_lambda_permission.public_invoke_function`
  in `main.tf`.
- **DNS + the domain setup** (`dns.tf`): `latefeetracker.app` (apex) A/AAAA records pointed
  at GitHub Pages, and `support.latefeetracker.app` set up as a real HTTPS redirect to
  `https://latefeetracker.app/support.html`. That redirect needs more than a DNS record —
  S3 static-website endpoints (the thing that actually runs the redirect logic) are
  **HTTP-only, no TLS at all** (confirmed live: a direct TLS handshake to the S3 website
  endpoint just resets), so there's a small CloudFront distribution + ACM certificate in
  front of it purely to add HTTPS. The ACM certificate is requested in **us-east-1**
  specifically — a hard CloudFront requirement regardless of where anything else lives —
  via a second, aliased provider block in `versions.tf`.

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

## A note on `apply` timing

The Lambda side finishes in well under a minute. The DNS/CloudFront side is slower and has
two separate waits, both automatic (`terraform apply` blocks until each is done, no manual
step needed) but worth knowing about if `apply` seems to be hanging:

- **ACM DNS validation** — `aws_acm_certificate_validation` waits for the Route 53 record it
  just created to actually be visible to AWS's own validators. Usually a few minutes.
- **CloudFront distribution deployment** — a new/changed distribution takes CloudFront
  several minutes (sometimes 10-15+) to roll out to all edge locations before Terraform
  considers the resource settled.

## Tearing it down

```
terraform destroy
```

Removes the Lambda, its Function URL, IAM role, log group, the SES identity, the DNS records,
the CloudFront distribution, its ACM certificate, and the S3 redirect bucket. Doesn't touch
anything outside this Terraform state (the GitHub Pages site itself, or the Route 53 hosted
zone — that's a `data` lookup against a zone this config never created, not a resource it
owns).
