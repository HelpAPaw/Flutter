/**
 * HTML escaping, shared by the two places that render client-controlled text
 * into markup: the feedback email (`feedbackEmail.ts`) and the hosted signal
 * preview page (`index.ts`).
 */
export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}
