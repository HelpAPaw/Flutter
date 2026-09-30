/**
 * The feedback email, checked against what nodemailer actually puts on the
 * wire rather than only against the strings it is handed.
 *
 * This is the one place the functions exercise nodemailer at all, so it is
 * also the regression test for major-version bumps of it (#85). The failure
 * modes are quiet: `onFeedbackCreated` catches and logs every send error, so a
 * broken email is a log line in production and a lost report.
 */

import * as nodemailer from "nodemailer";

import { buildFeedbackEmail } from "../feedbackEmail";

const FEEDBACK_ID = "fb-1";

function feedback(overrides: Record<string, unknown> = {}) {
  return {
    type: "bug",
    message: "The map is blank",
    userId: "user-1",
    email: "reporter@example.org",
    deviceInfo: {
      platform: "android",
      osVersion: "14",
      appVersion: "7.0.0",
      buildNumber: "131",
    },
    ...overrides,
  };
}

/** The raw message as an SMTP server would receive it (CRLF line endings). */
async function wire(data: Record<string, unknown>): Promise<string> {
  const info = await nodemailer
    .createTransport({ streamTransport: true, buffer: true, newline: "windows" })
    .sendMail({
      from: "\"Help a Paw Feedback\" <sender@example.org>",
      to: "recipient@example.org",
      ...buildFeedbackEmail(FEEDBACK_ID, data),
    });
  return (info.message as Buffer).toString();
}

const bareCr = /\r(?!\n)/g;

describe("buildFeedbackEmail", () => {
  it("never puts a bare CR on the wire, whatever the message contains", async () => {
    const raw = await wire(
      feedback({
        message: "x\r.\rMAIL FROM:<evil@example.com>\r\nsecond\rthird",
        deviceInfo: { platform: "android\r.\r" },
      })
    );

    expect(raw.match(bareCr)).toBeNull();
    // The content survives, just with its line endings normalised.
    expect(raw).toContain("x\r\n.\r\nMAIL FROM:<evil@example.com>\r\nsecond\r\nthird");
  });

  it("sends a valid address as Reply-To and names it in the subject", async () => {
    const raw = await wire(feedback());

    expect(raw).toMatch(/^Reply-To: reporter@example\.org\r$/m);
    expect(raw).toMatch(/^Subject: \[Help a Paw\] Bug Report from reporter@example\.org\r$/m);
  });

  it.each([
    ["not an address", "not-an-email"],
    ["an address with whitespace", "a b@example.org"],
    ["a non-string", 42],
  ])("drops %s instead of passing it on as Reply-To", (_, email) => {
    const mail = buildFeedbackEmail(FEEDBACK_ID, feedback({ email }));

    expect(mail.replyTo).toBeUndefined();
    expect(mail.subject).toBe("[Help a Paw] Bug Report");
    expect(mail.text).toContain("User Email: Not provided");
  });

  it("renders a device field that is not a string as N/A instead of throwing", () => {
    const mail = buildFeedbackEmail(
      FEEDBACK_ID,
      feedback({ deviceInfo: { platform: 5, osVersion: null, appVersion: "7.0.0" } })
    );

    expect(mail.text).toContain("- Platform: N/A\n- OS Version: N/A\n- App Version: 7.0.0\n- Build: N/A");
  });

  it("escapes client-written text in the HTML part", () => {
    const mail = buildFeedbackEmail(
      FEEDBACK_ID,
      feedback({ message: "<img src=x onerror=alert(1)>" })
    );

    expect(mail.html).toContain("&lt;img src=x onerror=alert(1)&gt;");
    expect(mail.html).not.toContain("<img");
  });
});
