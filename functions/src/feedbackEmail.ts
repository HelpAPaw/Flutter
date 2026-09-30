/**
 * The email `onFeedbackCreated` sends for a `feedback/{id}` document.
 *
 * Extracted from the trigger so it can be tested without a trigger event, and
 * through nodemailer's stream transport, against the bytes an SMTP server would
 * actually receive.
 *
 * Every input is client-written. The rules check `message`, `type` and `email`
 * but not `deviceInfo`, `createdAt` or the document id, so:
 *
 *  - anything rendered as HTML is escaped (M-2);
 *  - `email` is re-validated here before it becomes `replyTo`;
 *  - a `deviceInfo` field that is not a string renders as "N/A" instead of
 *    throwing: the caller has already booked a rate-limit slot by then;
 *  - line endings are normalised to LF. nodemailer turns LF into CRLF on the
 *    wire, but before 10.0.12 it passed a bare CR through unchanged, and a
 *    relay that treats a lone CR as a line end would read `\r.\r` as the end of
 *    the message and whatever followed as SMTP commands.
 */

import { escapeHtml } from "./html";

const FEEDBACK_TYPES: Record<string, string> = {
  general: "General Feedback",
  bug: "Bug Report",
  feature: "Feature Request",
  other: "Other",
};

const DEVICE_FIELDS = [
  ["Platform", "platform"],
  ["OS Version", "osVersion"],
  ["App Version", "appVersion"],
  ["Build", "buildNumber"],
] as const;

export interface FeedbackEmail {
  subject: string;
  text: string;
  html: string;
  replyTo: string | undefined;
}

// Minimal, conservative email syntax check (mirrors the rules-layer regex).
// We only need "is this safe to hand to nodemailer as replyTo / render as a
// mailto link", not full RFC 5322 compliance.
function isValidEmail(email: string): boolean {
  return email.length <= 254 && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email);
}

function toLf(value: string): string {
  return value.replace(/\r\n?/g, "\n");
}

export function buildFeedbackEmail(
  feedbackId: string,
  data: Record<string, unknown>
): FeedbackEmail {
  const type = String(data.type);
  const message = typeof data.message === "string" ? data.message : "";
  const userId = typeof data.userId === "string" ? data.userId : undefined;
  const createdAt =
    (data.createdAt as { toDate?: () => Date } | undefined)?.toDate?.() ||
    new Date();

  const userEmail =
    typeof data.email === "string" && isValidEmail(data.email)
      ? data.email
      : undefined;

  const info = data.deviceInfo as Record<string, unknown> | null | undefined;
  const device =
    typeof info === "object" && info !== null
      ? DEVICE_FIELDS.map(([label, key]) => {
          const value = info[key];
          return [label, typeof value === "string" && value ? value : "N/A"];
        })
      : undefined;

  const typeLabel = FEEDBACK_TYPES[type] || type;
  const consoleUrl = `https://console.firebase.google.com/project/help-a-paw-dev/firestore/data/~2Ffeedback~2F${encodeURIComponent(feedbackId)}`;

  const deviceInfoText = device
    ? `
Device Information:
${device.map(([label, value]) => `- ${label}: ${value}`).join("\n")}`
    : "";

  const text = `
New feedback submitted to Help a Paw

Type: ${typeLabel}
Date: ${createdAt.toISOString()}
User ID: ${userId || "Anonymous"}
User Email: ${userEmail || "Not provided"}

Message:
${message}
${deviceInfoText}

---
Feedback ID: ${feedbackId}
View in Firebase Console: ${consoleUrl}
`;

  // typeLabel/feedbackId/createdAt are escaped too, for consistency.
  const html = `
<h2>New feedback submitted to Help a Paw</h2>

<table style="border-collapse: collapse; margin-bottom: 20px;">
  <tr><td style="padding: 5px 10px; font-weight: bold;">Type:</td><td style="padding: 5px 10px;">${escapeHtml(typeLabel)}</td></tr>
  <tr><td style="padding: 5px 10px; font-weight: bold;">Date:</td><td style="padding: 5px 10px;">${escapeHtml(createdAt.toISOString())}</td></tr>
  <tr><td style="padding: 5px 10px; font-weight: bold;">User ID:</td><td style="padding: 5px 10px;">${escapeHtml(userId || "Anonymous")}</td></tr>
  <tr><td style="padding: 5px 10px; font-weight: bold;">User Email:</td><td style="padding: 5px 10px;">${userEmail ? `<a href="mailto:${escapeHtml(userEmail)}">${escapeHtml(userEmail)}</a>` : "Not provided"}</td></tr>
</table>

<h3>Message:</h3>
<p style="background: #f5f5f5; padding: 15px; border-radius: 5px; white-space: pre-wrap;">${escapeHtml(message)}</p>

${device ? `
<h3>Device Information:</h3>
<table style="border-collapse: collapse;">
${device.map(([label, value]) => `  <tr><td style="padding: 5px 10px;">${label}:</td><td style="padding: 5px 10px;">${escapeHtml(value)}</td></tr>`).join("\n")}
</table>
` : ""}

<hr>
<p style="color: #666; font-size: 12px;">
  Feedback ID: ${escapeHtml(feedbackId)}<br>
  <a href="${consoleUrl}">View in Firebase Console</a>
</p>
`;

  return {
    subject: `[Help a Paw] ${typeLabel}${userEmail ? ` from ${userEmail}` : ""}`,
    text: toLf(text),
    html: toLf(html),
    replyTo: userEmail,
  };
}
