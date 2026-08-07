# Apex (latefeetracker.app) becomes the one canonical GitHub Pages domain — GitHub only
# supports a single custom domain per Pages site, so support.latefeetracker.app (which was
# working as its own canonical domain up to this point) can't *also* independently serve this
# same repo's content. Instead it becomes a real HTTP redirect to
# https://latefeetracker.app/support.html via an S3 "redirect all requests" bucket — DNS alone
# (a CNAME/ALIAS) can't do a path-specific redirect like that; it needed real static-hosting
# redirect infrastructure, not just another record.
#
# Assumes latefeetracker.app is already a hosted zone in this AWS account/region set (Route 53
# zones are global, not per-region, so this works regardless of the provider's us-east-2
# default). If it isn't yet, this data source fails with a clear error rather than silently
# creating a second zone you'd then have to repoint your registrar's nameservers at.
data "aws_route53_zone" "root" {
  name = "latefeetracker.app."
}

# GitHub Pages' documented apex IPs — see
# https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site
locals {
  github_pages_ipv4 = [
    "185.199.108.153",
    "185.199.109.153",
    "185.199.110.153",
    "185.199.111.153",
  ]
  github_pages_ipv6 = [
    "2606:50c0:8000::153",
    "2606:50c0:8001::153",
    "2606:50c0:8002::153",
    "2606:50c0:8003::153",
  ]
}

resource "aws_route53_record" "apex_a" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = "latefeetracker.app"
  type    = "A"
  ttl     = 300
  records = local.github_pages_ipv4
}

resource "aws_route53_record" "apex_aaaa" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = "latefeetracker.app"
  type    = "AAAA"
  ttl     = 300
  records = local.github_pages_ipv6
}

# --- support.latefeetracker.app -> redirect to https://latefeetracker.app/support.html ---

# Bucket name matches the domain on purpose — this is the idiomatic S3-static-redirect
# pattern and makes the setup self-documenting. Holds no actual content; the website
# configuration below intercepts every request before any object would need to be read, so
# no public bucket policy is needed either.
resource "aws_s3_bucket" "support_redirect" {
  bucket = "support.latefeetracker.app"

  tags = { Name = "support.latefeetracker.app-redirect" }
}

resource "aws_s3_bucket_website_configuration" "support_redirect" {
  bucket = aws_s3_bucket.support_redirect.id

  # S3's PutBucketWebsite API requires *some* IndexDocument even when RedirectAllRequestsTo
  # is unused — this one is dead configuration in practice: the routing_rule below has no
  # condition, so it matches and overrides every single request before this could ever be
  # reached. Present purely to satisfy the API's validation.
  index_document {
    suffix = "index.html"
  }

  routing_rule {
    redirect {
      host_name           = "latefeetracker.app"
      protocol            = "https"
      replace_key_with    = "support.html"
      http_redirect_code  = "301"
    }
  }
}

# S3 website endpoints are one of the few non-AWS-service targets Route 53 ALIAS records
# support directly (no separate CloudFront distribution needed for a plain redirect).
# S3 website endpoints don't live in us-east-2 specifically — they're regional based on where
# the bucket was created, which for a bucket with no explicit provider/region argument follows
# the provider's own default (us-east-2, matching everything else in this config).
resource "aws_route53_record" "support_alias" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = "support.latefeetracker.app"
  type    = "A"

  alias {
    name                   = aws_s3_bucket_website_configuration.support_redirect.website_domain
    zone_id                = aws_s3_bucket.support_redirect.hosted_zone_id
    evaluate_target_health = false
  }
}
