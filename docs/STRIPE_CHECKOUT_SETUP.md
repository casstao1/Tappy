# Tappy Stripe Checkout Setup

Tappy uses Stripe Checkout for the one-time premium ASMR pack unlock. Stripe secrets stay in Vercel environment variables and are never bundled into the macOS app.

## Flow

1. The website buy button opens `/api/create-checkout`.
2. The Vercel API creates a Stripe Checkout Session for the configured price.
3. Stripe redirects back to `/success.html?session_id={CHECKOUT_SESSION_ID}`.
4. `/api/checkout-license` verifies the paid Stripe session and generates a signed Tappy license key.
5. Tappy sends that license key to `/api/verify-license` to unlock premium ASMR packs.

This is intentionally database-free. The license key is a signed token tied to the paid Stripe Checkout Session.

## Stripe Dashboard

Create a Stripe product:

- Name: `Tappy ASMR Pack Unlock`
- Price: `$4.99`
- Type: One-time
- Currency: USD

Copy the Stripe Price ID. It looks like:

```text
price_...
```

## Vercel Environment Variables

Set these in the Vercel project settings for Production, Preview, and Development as needed:

```text
STRIPE_SECRET_KEY=sk_live_...
STRIPE_PRICE_ID=price_...
TAPPY_LICENSE_SECRET=<long random secret>
PUBLIC_SITE_URL=https://tappy-plum.vercel.app
```

Generate `TAPPY_LICENSE_SECRET` locally with:

```sh
openssl rand -base64 48
```

Do not commit these values.

## Local Smoke Test

After setting Vercel variables and deploying:

```sh
curl -I https://tappy-plum.vercel.app/api/create-checkout
```

The response should redirect to a Stripe Checkout URL. Complete a test checkout in Stripe test mode first if you are using test keys.

## App Verification

The macOS app verifies licenses against:

```text
https://tappy-plum.vercel.app/api/verify-license
```

If the network is unavailable after a license was already activated, Tappy keeps the premium packs available offline on that Mac.
