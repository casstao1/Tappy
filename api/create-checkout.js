const {
  PRODUCT_CODE,
  PRODUCT_NAME,
  htmlError,
  publicBaseURL,
  requireEnv,
  stripeRequest,
} = require("./_shared");

module.exports = async function handler(req, res) {
  if (!["GET", "POST"].includes(req.method)) {
    res.statusCode = 405;
    res.setHeader("Allow", "GET, POST");
    res.end("Method not allowed");
    return;
  }

  try {
    const baseURL = publicBaseURL(req);
    const priceID = requireEnv("STRIPE_PRICE_ID");
    const session = await stripeRequest("checkout/sessions", {
      method: "POST",
      body: {
        mode: "payment",
        success_url: `${baseURL}/success.html?session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${baseURL}/#buy`,
        "line_items[0][price]": priceID,
        "line_items[0][quantity]": "1",
        "metadata[product]": PRODUCT_CODE,
        "metadata[product_name]": PRODUCT_NAME,
        allow_promotion_codes: "true",
        billing_address_collection: "auto",
        "invoice_creation[enabled]": "true",
      },
    });

    res.statusCode = 303;
    res.setHeader("Location", session.url);
    res.end();
  } catch (error) {
    htmlError(res, error);
  }
};
