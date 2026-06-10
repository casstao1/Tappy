const crypto = require("crypto");

const PRODUCT_CODE = "tappy-asmr-pack-unlock";
const PRODUCT_NAME = "Tappy ASMR Pack Unlock";
const EXPECTED_AMOUNT = 499;
const EXPECTED_CURRENCY = "usd";

function publicBaseURL(req) {
  if (process.env.PUBLIC_SITE_URL) {
    return process.env.PUBLIC_SITE_URL.replace(/\/$/, "");
  }

  const host = req.headers["x-forwarded-host"] || req.headers.host;
  const proto = req.headers["x-forwarded-proto"] || "https";
  return `${proto}://${host}`;
}

function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw httpError(500, `${name} is not configured.`);
  }
  return value;
}

function httpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

function json(res, statusCode, payload) {
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.end(JSON.stringify(payload));
}

function htmlError(res, error) {
  const statusCode = error.statusCode || 500;
  const message = escapeHTML(error.message || "Something went wrong.");
  res.statusCode = statusCode;
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.end(`<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Tappy Checkout</title>
    <style>
      body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f5f7fb; color: #111317; }
      main { min-height: 100vh; display: grid; place-items: center; padding: 24px; }
      section { max-width: 560px; padding: 28px; border: 1px solid rgba(17, 19, 23, .12); border-radius: 8px; background: #fff; box-shadow: 0 18px 45px rgba(18, 24, 35, .08); }
      h1 { margin: 0 0 10px; font-size: 26px; }
      p { margin: 0 0 18px; color: #626976; line-height: 1.6; }
      a { color: #3569ff; font-weight: 700; }
    </style>
  </head>
  <body>
    <main>
      <section>
        <h1>Checkout is not ready yet</h1>
        <p>${message}</p>
        <a href="/">Return to Tappy</a>
      </section>
    </main>
  </body>
</html>`);
}

function escapeHTML(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function base64URL(input) {
  return Buffer.from(input)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function decodeBase64URL(value) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(normalized.length + ((4 - normalized.length % 4) % 4), "=");
  return Buffer.from(padded, "base64");
}

function timingSafeEqual(a, b) {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

function licensePayloadForSession(session) {
  const email = session.customer_details?.email || session.customer_email || "";
  const paymentIntent = typeof session.payment_intent === "string"
    ? session.payment_intent
    : session.payment_intent?.id || null;

  return {
    v: 1,
    product: PRODUCT_CODE,
    session_id: session.id,
    payment_intent: paymentIntent,
    livemode: Boolean(session.livemode),
    created: session.created || Math.floor(Date.now() / 1000),
    email_hash: email
      ? crypto.createHash("sha256").update(email.trim().toLowerCase()).digest("hex").slice(0, 16)
      : null,
  };
}

function signLicense(payload, secret = requireEnv("TAPPY_LICENSE_SECRET")) {
  const encodedPayload = base64URL(JSON.stringify(payload));
  const signature = base64URL(
    crypto.createHmac("sha256", secret).update(encodedPayload).digest()
  );
  return `TAPPY-${encodedPayload}.${signature}`;
}

function verifyLicenseKey(rawLicenseKey, secret = requireEnv("TAPPY_LICENSE_SECRET")) {
  const licenseKey = String(rawLicenseKey || "").trim();
  const body = licenseKey.startsWith("TAPPY-") ? licenseKey.slice(6) : licenseKey;
  const [encodedPayload, signature] = body.split(".");

  if (!encodedPayload || !signature) {
    throw httpError(400, "That license key is not in the expected Tappy format.");
  }

  const expectedSignature = base64URL(
    crypto.createHmac("sha256", secret).update(encodedPayload).digest()
  );

  if (!timingSafeEqual(signature, expectedSignature)) {
    throw httpError(400, "That license key could not be verified.");
  }

  let payload;
  try {
    payload = JSON.parse(decodeBase64URL(encodedPayload).toString("utf8"));
  } catch {
    throw httpError(400, "That license key could not be read.");
  }

  if (payload.v !== 1 || payload.product !== PRODUCT_CODE || !payload.session_id) {
    throw httpError(400, "That license key is not valid for Tappy.");
  }

  return payload;
}

async function readRequestBody(req) {
  if (req.body && typeof req.body === "object") {
    return req.body;
  }

  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
  }

  const rawBody = Buffer.concat(chunks).toString("utf8");
  const contentType = req.headers["content-type"] || "";

  if (contentType.includes("application/json")) {
    return rawBody ? JSON.parse(rawBody) : {};
  }

  if (contentType.includes("application/x-www-form-urlencoded")) {
    return Object.fromEntries(new URLSearchParams(rawBody));
  }

  return { rawBody };
}

async function stripeRequest(path, options = {}) {
  const secretKey = requireEnv("STRIPE_SECRET_KEY");
  const response = await fetch(`https://api.stripe.com/v1/${path}`, {
    method: options.method || "GET",
    headers: {
      Authorization: `Bearer ${secretKey}`,
      ...(options.body ? { "Content-Type": "application/x-www-form-urlencoded" } : {}),
    },
    body: options.body ? new URLSearchParams(options.body) : undefined,
  });

  const text = await response.text();
  const payload = text ? JSON.parse(text) : {};

  if (!response.ok) {
    throw httpError(response.status, payload.error?.message || "Stripe returned an unexpected response.");
  }

  return payload;
}

async function retrieveCheckoutSession(sessionID) {
  if (!sessionID || !String(sessionID).startsWith("cs_")) {
    throw httpError(400, "Missing or invalid Stripe Checkout Session.");
  }

  return stripeRequest(`checkout/sessions/${encodeURIComponent(sessionID)}`);
}

async function retrieveSessionLineItems(sessionID) {
  return stripeRequest(`checkout/sessions/${encodeURIComponent(sessionID)}/line_items?limit=10`);
}

function assertPaidTappySession(session, lineItems) {
  const expectedPriceID = requireEnv("STRIPE_PRICE_ID");
  const hasExpectedPrice = Array.isArray(lineItems?.data)
    && lineItems.data.some((item) => item.price?.id === expectedPriceID);

  if (session.mode !== "payment") {
    throw httpError(400, "That Stripe session is not a one-time payment.");
  }

  if (session.payment_status !== "paid") {
    throw httpError(402, "Stripe has not marked this checkout as paid yet.");
  }

  if (!hasExpectedPrice) {
    throw httpError(400, "That Stripe purchase is not for the Tappy ASMR unlock.");
  }

  if (session.amount_total && session.amount_total < EXPECTED_AMOUNT) {
    throw httpError(400, "That Stripe purchase amount is not valid for this unlock.");
  }

  if (session.currency && session.currency !== EXPECTED_CURRENCY) {
    throw httpError(400, "That Stripe purchase currency is not valid for this unlock.");
  }
}

module.exports = {
  EXPECTED_AMOUNT,
  EXPECTED_CURRENCY,
  PRODUCT_CODE,
  PRODUCT_NAME,
  assertPaidTappySession,
  htmlError,
  httpError,
  json,
  licensePayloadForSession,
  publicBaseURL,
  readRequestBody,
  requireEnv,
  retrieveCheckoutSession,
  retrieveSessionLineItems,
  signLicense,
  stripeRequest,
  verifyLicenseKey,
};
