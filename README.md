# Late Fee — support website

Static marketing + support site for the Late Fee iOS app, built for GitHub Pages (plain
HTML/CSS/JS, no build step or framework). Screenshots in `assets/screenshots/` are real
captures from the app, not mockups.

## Structure

```
index.html                 Marketing homepage
support.html                Support page + contact form
assets/css/styles.css       All styling
assets/js/config.js          Contact form endpoint config (fill in after deploying the Lambda)
assets/js/support-form.js    Contact form submit handling
assets/screenshots/          Real app screenshots
assets/icons/                App icon
lambda/                      Contact form backend (Node.js, deploy separately — see lambda/README.md)
terraform/                   Terraform to deploy the Lambda into AWS (us-east-2) — see terraform/README.md
```

## Local preview

No build step — just serve the folder:

```
python3 -m http.server 8080
```

Then open `http://localhost:8080`.

## Deploying to GitHub Pages

**Already done** — this repo is live at **https://kylesmart2.github.io/late-fee-support/**,
served from the `main` branch, root folder (Repo → Settings → Pages). Any push to `main`
redeploys automatically within a minute or two; no separate deploy step needed.

To redo this from scratch (a fork, a new repo, etc.):
```
gh repo create <name> --public --source=. --remote=origin
git push -u origin main
gh api repos/<you>/<repo>/pages -X POST -f "source[branch]=main" -f "source[path]=/"
```
or the same thing via the GitHub web UI: Settings → Pages → Source → deploy from `main`, `/`.

## Custom domain

Not set up yet. Once you have a domain, here's the whole path:

1. **Add a `CNAME` file** at the repo root (same level as `index.html`) containing just the
   domain, e.g.:
   ```
   support.latefeeapp.com
   ```
   Commit and push it.

2. **Point the domain's DNS at GitHub Pages**, at whichever registrar/DNS host the domain
   lives with:
   - **Subdomain** (e.g. `support.latefeeapp.com`) — add a `CNAME` record:
     ```
     support.latefeeapp.com.  CNAME  kylesmart2.github.io.
     ```
   - **Apex/root domain** (e.g. `latefeeapp.com` with no subdomain) — GitHub Pages doesn't
     accept a `CNAME` at the apex (DNS doesn't allow that), so instead add `A` records
     pointing at GitHub's four Pages IPs:
     ```
     185.199.108.153
     185.199.109.153
     185.199.110.153
     185.199.111.153
     ```
     (and optionally `AAAA` records for IPv6 — GitHub's current list is in their own
     [custom domain docs](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site)
     if these ever change).

3. **Set the domain in the repo itself**: Settings → Pages → Custom domain → enter the
   domain → Save. GitHub verifies the DNS and writes the `CNAME` file for you if you didn't
   already add it in step 1 (either order works).

4. **Wait for DNS to propagate** (usually minutes, can take longer depending on the
   registrar/TTL), then **enable "Enforce HTTPS"** in that same Pages settings panel once
   it's available — GitHub provisions a free TLS certificate for the domain automatically,
   but that toggle only unlocks after DNS resolves correctly.

5. Update `assets/js/config.js`'s CORS-adjacent expectations if needed — nothing in this
   repo hardcodes the `github.io` URL, so no code changes are required for the domain switch
   itself. The one place that *does* need the new domain is the Lambda's `ALLOWED_ORIGIN`
   environment variable (see below) — update it to the new domain once DNS is live, or the
   contact form will get blocked by CORS.

## Contact form

The form on `support.html` POSTs JSON to whatever URL is set in
`assets/js/config.js` (`window.LATE_FEE_SUPPORT_ENDPOINT`). Until that URL is set, the form
shows a clear "not configured yet" message instead of failing silently.

### What the Lambda does

`lambda/handler.js` is a small, stateless Node.js function — no database, nothing persisted.
On each request it:

1. Handles the browser's CORS preflight (`OPTIONS`) request, restricted to whatever origin
   is set in `ALLOWED_ORIGIN` (kept an exact match, not `*`, since this endpoint accepts
   writes).
2. Parses and validates the POST body — `name`, `email`, `topic`, `message` all required,
   `email` checked against a basic pattern, `topic` checked against the four allowed values
   (`bug`/`feature`/`account`/`other`), every field capped at 5000 characters.
3. Sends the ticket as an email via **Amazon SES** — to `SUPPORT_TO_EMAIL`, from the verified
   sender `SUPPORT_FROM_EMAIL`, with the visitor's own address set as *Reply-To* so you can
   just hit reply in your inbox. Subject: `[Late Fee Support] <topic> — <name>`.
4. Returns `{ok: true}` on success, or a JSON error with an appropriate status code (400 for
   validation failures, 500/502 for missing config or a failed SES send) — the site's JS
   turns that into the "Sent"/"Something went wrong" message under the form.

### Deploying it

**Fastest path: `terraform/`** — `cd terraform && terraform apply` deploys the function, its
IAM role, a public Function URL, and the SES sender identity into us-east-2 in one pass (still
requires clicking the SES verification email yourself — see `terraform/README.md`). The steps
below are the manual/by-hand equivalent, useful for understanding what Terraform is doing or
if you'd rather not use it.

1. **Zip and upload**:
   ```
   cd lambda
   npm install
   zip -r function.zip .
   ```
   Create a new Lambda function (Node.js 22.x runtime) and upload `function.zip`.

2. **Environment variables** (Lambda → Configuration → Environment variables):
   | Variable | Value |
   |---|---|
   | `SUPPORT_TO_EMAIL` | The inbox that should receive tickets |
   | `SUPPORT_FROM_EMAIL` | A sender address verified in SES (SES → Verified identities) — in SES sandbox mode this also needs to be a *verified recipient* until you request production access |
   | `ALLOWED_ORIGIN` | The site's live origin — `https://kylesmart2.github.io` for now, or your custom domain once that's set up |

3. **IAM permissions** — attach a policy allowing `ses:SendEmail` (and `ses:SendRawEmail` if
   you want headroom) scoped to the verified identity.

4. **Expose it to the browser** — either:
   - **Lambda Function URL** (simplest): Lambda → Configuration → Function URL → Create,
     Auth type `NONE` (the honeypot field + SES-side validation are the only gate on this
     endpoint — fine for a low-volume support form, but it is public). Enable CORS there, or
     rely on the handler's own headers — make sure the two don't disagree.
   - **API Gateway HTTP API**: a `POST /support` route pointing at this Lambda, with CORS
     configured for the site's origin and the `Content-Type` header.

5. **Point the site at it** — put the resulting URL into `assets/js/config.js`:
   ```js
   window.LATE_FEE_SUPPORT_ENDPOINT = "https://your-endpoint-here";
   ```
   Commit and push — Pages redeploys automatically.

Full details, plus a local test snippet that exercises the handler without deploying
anything, are in `lambda/README.md`.

## Brand

Colors and the "membership card" motif are pulled directly from the app's own UI (navy
`#1E3A8A`, gold `#FFC72C`, cream `#F5F1E6` — see the app's `TicketSectionHeader.swift`) and
its app icon, not invented separately for the website.
