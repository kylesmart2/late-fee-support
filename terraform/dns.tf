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

# S3 website endpoints are HTTP-only — no TLS at all, confirmed live (a plain TCP connection
# on :443 just resets, there's nothing to even negotiate a handshake against). Most browsers
# try HTTPS first today, so aliasing DNS straight at the S3 website endpoint meant the
# redirect only ever worked over http://, silently failing for anyone/anything defaulting to
# https:// — confirmed as the actual cause of Kyle's "redirect isn't working" report. CloudFront
# in front of the same S3 origin is what actually adds real HTTPS support.

resource "aws_acm_certificate" "support_redirect" {
  provider          = aws.us_east_1
  domain_name       = "support.latefeetracker.app"
  validation_method = "DNS"

  tags = { Name = "support.latefeetracker.app-redirect" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "support_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.support_redirect.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.root.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 300
}

resource "aws_acm_certificate_validation" "support_redirect" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.support_redirect.arn
  validation_record_fqdns = [for record in aws_route53_record.support_cert_validation : record.fqdn]
}

resource "aws_cloudfront_distribution" "support_redirect" {
  enabled         = true
  is_ipv6_enabled = true
  aliases         = ["support.latefeetracker.app"]
  comment         = "HTTPS front-end for the support.latefeetracker.app -> /support.html redirect"

  origin {
    # The S3 *website* endpoint specifically (not the plain bucket REST endpoint) — that's
    # what actually runs the redirect-all-requests logic from the website configuration
    # above. CloudFront treats this as a generic custom HTTP origin, not an S3 origin, since
    # website endpoints don't support the S3-origin integration (OAC/OAI don't apply here).
    domain_name = aws_s3_bucket_website_configuration.support_redirect.website_endpoint
    origin_id   = "support-redirect-s3-website"

    custom_origin_config {
      http_port              = 80
      https_port              = 443
      origin_protocol_policy  = "http-only"
      origin_ssl_protocols    = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods          = ["GET", "HEAD"]
    target_origin_id        = "support-redirect-s3-website"
    viewer_protocol_policy  = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    # Short TTL — this exists purely to serve a redirect, not cacheable content; if the
    # redirect target ever changes there's no reason for visitors to be stuck on a stale one
    # for longer than a few minutes.
    min_ttl     = 0
    default_ttl = 300
    max_ttl     = 300
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.support_redirect.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = { Name = "support.latefeetracker.app-redirect" }
}

resource "aws_route53_record" "support_alias" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = "support.latefeetracker.app"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.support_redirect.domain_name
    zone_id                = aws_cloudfront_distribution.support_redirect.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "support_alias_v6" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = "support.latefeetracker.app"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.support_redirect.domain_name
    zone_id                = aws_cloudfront_distribution.support_redirect.hosted_zone_id
    evaluate_target_health = false
  }
}

# --- iCloud Mail for latefeetracker.app ---
# Route 53 can't have two separate record sets sharing the same name+type, so both TXT
# values (Apple's domain-ownership token and the SPF policy) live in one record, same for
# both MX values below (priority folded into the value string, per Route 53's MX format).

resource "aws_route53_record" "apex_txt" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = "latefeetracker.app"
  type    = "TXT"
  ttl     = 300
  records = [
    "apple-domain=ggHnHYDAp1JBPDZY",
    "v=spf1 include:icloud.com ~all",
  ]
}

resource "aws_route53_record" "apex_mx" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = "latefeetracker.app"
  type    = "MX"
  ttl     = 300
  records = [
    "10 mx01.mail.icloud.com.",
    "10 mx02.mail.icloud.com.",
  ]
}

resource "aws_route53_record" "icloud_dkim" {
  zone_id = data.aws_route53_zone.root.zone_id
  name    = "sig1._domainkey.latefeetracker.app"
  type    = "CNAME"
  ttl     = 300
  records = ["sig1.dkim.latefeetracker.app.at.icloudmailadmin.com."]
}
