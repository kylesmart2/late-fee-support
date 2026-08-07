// Deployed via terraform/ into us-east-2 — see terraform/README.md for how to redeploy or
// change this. The Lambda's ALLOWED_ORIGIN is locked to https://support.latefeetracker.app,
// so this endpoint will only actually accept requests once the site is served from that
// origin (custom domain DNS + GitHub Pages config), not from the github.io URL.
window.LATE_FEE_SUPPORT_ENDPOINT = "https://dpb35fiabb2s7e26nja4migj7a0ogydn.lambda-url.us-east-2.on.aws/";
