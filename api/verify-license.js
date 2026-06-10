const {
  assertPaidTappySession,
  json,
  readRequestBody,
  retrieveCheckoutSession,
  retrieveSessionLineItems,
  verifyLicenseKey,
} = require("./_shared");

module.exports = async function handler(req, res) {
  if (req.method === "OPTIONS") {
    res.statusCode = 204;
    res.end();
    return;
  }

  if (req.method !== "POST") {
    json(res, 405, { success: false, active: false, message: "Method not allowed." });
    return;
  }

  try {
    const body = await readRequestBody(req);
    const licenseKey = body.license_key || body.licenseKey;
    const payload = verifyLicenseKey(licenseKey);
    const session = await retrieveCheckoutSession(payload.session_id);
    const lineItems = await retrieveSessionLineItems(session.id);
    assertPaidTappySession(session, lineItems);

    json(res, 200, {
      success: true,
      active: true,
      product: payload.product,
      message: "License verified.",
    });
  } catch (error) {
    json(res, error.statusCode || 500, {
      success: false,
      active: false,
      message: error.message || "License verification failed.",
    });
  }
};
