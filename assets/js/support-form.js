(function () {
  "use strict";

  const form = document.getElementById("support-form");
  const statusEl = document.getElementById("form-status");
  const submitBtn = document.getElementById("submit-btn");

  if (!form) return;

  function setStatus(message, state) {
    statusEl.textContent = message;
    statusEl.dataset.state = state || "";
  }

  form.addEventListener("submit", async function (event) {
    event.preventDefault();

    // Honeypot: a real visitor never fills this in (it's visually hidden), a simple bot
    // filling every field on the page will. Silently pretend success rather than tipping
    // off the bot that it was caught.
    const honeypot = form.elements["company"].value.trim();
    if (honeypot) {
      setStatus("Thanks — your ticket has been sent.", "success");
      form.reset();
      return;
    }

    const endpoint = window.LATE_FEE_SUPPORT_ENDPOINT;
    if (!endpoint) {
      setStatus("Support form isn't connected yet — email us directly instead for now.", "error");
      return;
    }

    const payload = {
      name: form.elements["name"].value.trim(),
      email: form.elements["email"].value.trim(),
      topic: form.elements["topic"].value,
      message: form.elements["message"].value.trim(),
    };

    if (!payload.name || !payload.email || !payload.topic || !payload.message) {
      setStatus("Please fill in every field before sending.", "error");
      return;
    }

    submitBtn.disabled = true;
    setStatus("Sending…", "sending");

    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      if (!response.ok) {
        throw new Error("Request failed with status " + response.status);
      }

      setStatus("Thanks — your ticket has been sent. We'll be in touch by email.", "success");
      form.reset();
    } catch (error) {
      setStatus("Something went wrong sending that. Please try again in a moment.", "error");
    } finally {
      submitBtn.disabled = false;
    }
  });
})();
