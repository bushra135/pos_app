# ShopPad email verification

The server provides email verification by six-digit code. Payments remain cash or manually confirmed BenefitPay. The store assistant runs local rule-based analysis and does not call an external AI service.

## Setup

1. Enable Cloud Functions billing for your Firebase project and install the Firebase CLI.
2. Run `npm ci` inside `functions`.
3. Verify a sender domain with Resend. Copy `.env.example` to `.env.PROJECT_ID` and set `SHOPPAD_EMAIL_FROM` to the sender address only. The display name and email subject include ShopPad.
4. Set `RESEND_API_KEY` and `OTP_HASH_KEY` using `firebase functions:secrets:set`. Use a random secret of at least 32 bytes for the hash key. Keep secrets off the client and out of Git.
5. Apply the restrictions in `firestore-security.md` to the current deployed rules.
6. Deploy with `firebase deploy --only functions:shoppad --project PROJECT_ID`.

Deployment and real email delivery have not been performed. Existing unverified accounts need these services configured before they can complete verification. Password reset still uses Firebase's separate reset link.

Codes expire after 10 minutes, allow five guesses, and have a 60-second resend cooldown and six-request hourly limit. Only hashes are stored. Successful verification updates Firebase Auth's emailVerified flag.

Run `npm test` and test actual delivery, expiration, attempt limits, and sign-in after verification before release.
