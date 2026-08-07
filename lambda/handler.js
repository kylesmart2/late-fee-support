// Late Fee support form handler.
//
// Expects a JSON POST body: { name, email, topic, message }.
// Sends the ticket as an email via Amazon SES. Swap the `sendTicketEmail` call for
// whatever you already use on your personal site if it's not SES — the validation and
// response shape below don't depend on it.
//
// Environment variables expected:
//   SUPPORT_TO_EMAIL    - where tickets should land (your inbox)
//   SUPPORT_FROM_EMAIL  - a verified SES sender identity
//   ALLOWED_ORIGIN       - the deployed site's origin, e.g. "https://yourname.github.io"
//                          (used for the CORS header — keep this an exact match, not "*",
//                          since this endpoint accepts writes)

const { SESClient, SendEmailCommand } = require("@aws-sdk/client-ses");

const ses = new SESClient({});

const MAX_FIELD_LENGTH = 5000;
const ALLOWED_TOPICS = new Set(["bug", "feature", "account", "other"]);

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": process.env.ALLOWED_ORIGIN || "",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  };
}

function jsonResponse(statusCode, body) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json", ...corsHeaders() },
    body: JSON.stringify(body),
  };
}

function isValidEmail(value) {
  // Deliberately simple — full RFC 5322 validation isn't worth it here, this only needs
  // to catch obvious garbage before it goes out as a reply-to address.
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function sanitizeText(value) {
  return String(value).slice(0, MAX_FIELD_LENGTH);
}

exports.handler = async (event) => {
  // API Gateway (REST/HTTP API) and a Lambda Function URL both hit an OPTIONS preflight
  // for a JSON POST from the browser — respond to it directly rather than routing through
  // the rest of the handler.
  if (event.requestContext?.http?.method === "OPTIONS" || event.httpMethod === "OPTIONS") {
    return { statusCode: 204, headers: corsHeaders(), body: "" };
  }

  let payload;
  try {
    payload = JSON.parse(event.body || "{}");
  } catch {
    return jsonResponse(400, { error: "Malformed request body." });
  }

  const name = sanitizeText(payload.name || "").trim();
  const email = sanitizeText(payload.email || "").trim();
  const topic = sanitizeText(payload.topic || "").trim();
  const message = sanitizeText(payload.message || "").trim();

  if (!name || !email || !topic || !message) {
    return jsonResponse(400, { error: "All fields are required." });
  }
  if (!isValidEmail(email)) {
    return jsonResponse(400, { error: "That email address doesn't look right." });
  }
  if (!ALLOWED_TOPICS.has(topic)) {
    return jsonResponse(400, { error: "Unrecognized topic." });
  }

  const toEmail = process.env.SUPPORT_TO_EMAIL;
  const fromEmail = process.env.SUPPORT_FROM_EMAIL;
  if (!toEmail || !fromEmail) {
    console.error("Missing SUPPORT_TO_EMAIL or SUPPORT_FROM_EMAIL environment variable.");
    return jsonResponse(500, { error: "Support form isn't fully configured yet." });
  }

  try {
    await ses.send(
      new SendEmailCommand({
        Destination: { ToAddresses: [toEmail] },
        Source: fromEmail,
        ReplyToAddresses: [email],
        Message: {
          Subject: { Data: `[Late Fee Support] ${topic} — ${name}` },
          Body: {
            Text: {
              Data: `From: ${name} <${email}>\nTopic: ${topic}\n\n${message}`,
            },
          },
        },
      })
    );
  } catch (error) {
    console.error("SES send failed:", error);
    return jsonResponse(502, { error: "Couldn't send that right now. Please try again shortly." });
  }

  return jsonResponse(200, { ok: true });
};
