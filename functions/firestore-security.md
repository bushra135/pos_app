# Email verification security requirements

The deployed Firestore rules are not available in this repository. Deny all client access to the private `_emailCodes` collection before enabling verification:

```text
match /_emailCodes/{id} { allow read, write: if false; }
```

Firestore permissions are additive: an existing broad recursive allow can override this restriction. Remove broad permits and preserve explicit authorized rules for users, stores, products and sales. Cloud Functions use Admin SDK access.

Clients must not be allowed to change their own role, store membership or authorization flags. Keep cross-store reads and writes restricted to the appropriate users. This file documents deployment requirements; it does not replace or verify the deployed policy.
