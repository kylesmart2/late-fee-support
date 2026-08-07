# Late Fee support form — Lambda backend

`handler.js` is a plain Node.js Lambda that receives the support form's POST, validates it,
and emails it to you via Amazon SES. It has no dependency on API Gateway specifically — a
Lambda Function URL works too and is less to set up if you don't need the rest of API
Gateway's features.

## Deploy

1. **Zip and upload**, or point your existing deploy pipeline at this folder:
   ```
   cd lambda
   npm install
   zip -r function.zip .
   ```
   Upload `function.zip` as a new Lambda function (Node.js 22.x runtime).

2. **Environment variables** (Lambda → Configuration → Environment variables):
   - `SUPPORT_TO_EMAIL` — the inbox that should receive tickets.
   - `SUPPORT_FROM_EMAIL` — a sender address verified in SES (SES → Verified identities).
     In sandbox mode this also needs to be a *verified* recipient until you request
     production access.
   - `ALLOWED_ORIGIN` — the site's deployed origin, e.g. `https://<you>.github.io`. Used
     for the CORS header; keep it an exact origin, not `*`, since this endpoint accepts
     writes.

3. **IAM permissions** — attach a policy allowing `ses:SendEmail` on the identity you
   verified (or `ses:SendEmail`/`ses:SendRawEmail` broadly, scoped down later if you want).

4. **Expose it to the browser**, either:
   - **Lambda Function URL** (simplest): Lambda → Configuration → Function URL → Create.
     Set Auth type to `NONE` (the honeypot + SES-side validation are the only gate on this
     endpoint — fine for a low-volume support form, but be aware it's public). Enable CORS
     in the Function URL config, or rely on the handler's own `corsHeaders()` — both need
     to agree, don't set conflicting values in two places.
   - **API Gateway HTTP API**: create a route (`POST /support`) pointing at this Lambda,
     with CORS configured to allow your site's origin and `Content-Type` header.

5. **Point the site at it** — put the resulting URL into
   `assets/js/config.js`'s `window.LATE_FEE_SUPPORT_ENDPOINT`.

## Testing without deploying

```
node -e '
const { handler } = require("./handler.js");
process.env.SUPPORT_TO_EMAIL = "you@example.com";
process.env.SUPPORT_FROM_EMAIL = "noreply@example.com";
process.env.ALLOWED_ORIGIN = "http://localhost:8080";
handler({ body: JSON.stringify({ name: "Test", email: "test@example.com", topic: "bug", message: "Hello" }) })
  .then(console.log);
'
```

This will attempt a real SES send if your AWS credentials are configured locally — use a
sandboxed/verified test recipient, or temporarily stub `ses.send` if you just want to check
the validation logic.
