const {
  assertPaidTappySession,
  json,
  licensePayloadForSession,
  retrieveCheckoutSession,
  retrieveSessionLineItems,
  signLicense,
} = require("./_shared");

module.exports = async function handler(req, res) {
  if (req.method !== "GET") {
    json(res, 405, { success: false, message: "Method not allowed." });
    return;
  }

  try {
    const sessionID = req.query?.session_id || new URL(req.url, "https://tappy.local").searchParams.get("session_id");
    const session = await retrieveCheckoutSession(sessionID);
    const lineItems = await retrieveSessionLineItems(session.id);
    assertPaidTappySession(session, lineItems);

    const payload = licensePayloadForSession(session);
    const licenseKey = signLicense(payload);

    json(res, 200, {
      success: true,
      license_key: licenseKey,
      product: payload.product,
      message: "Tappy license generated.",
    });
  } catch (error) {
    json(res, error.statusCode || 500, {
      success: false,
      message: error.message || "Could not generate a license.",
    });
  }
};
