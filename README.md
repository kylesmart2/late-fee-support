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
```

## Local preview

No build step — just serve the folder:

```
python3 -m http.server 8080
```

Then open `http://localhost:8080`.

## Deploying to GitHub Pages

1. Push this repo to GitHub.
2. Repo → Settings → Pages → Source: deploy from the `main` branch, root folder.
3. The site will be live at `https://<username>.github.io/<repo-name>/`. For a custom
   domain, add a `CNAME` file at the repo root with the domain, and point its DNS at
   GitHub Pages per GitHub's own custom-domain docs.

## Contact form

The form on `support.html` POSTs JSON to whatever URL is set in
`assets/js/config.js` (`window.LATE_FEE_SUPPORT_ENDPOINT`). See `lambda/README.md` for
deploying the AWS Lambda backend that receives it. Until that URL is set, the form shows a
clear "not configured yet" message instead of failing silently.

## Brand

Colors and the "membership card" motif are pulled directly from the app's own UI (navy
`#1E3A8A`, gold `#FFC72C`, cream `#F5F1E6` — see the app's `TicketSectionHeader.swift`) and
its app icon, not invented separately for the website.
