# Firebase Cloud Functions Setup for Agricart

This document explains how to set up Firebase Cloud Functions to properly delete Firebase Authentication accounts with admin privileges.

## Problem

The client-side `firebase.auth().deleteUser()` function cannot delete other users' accounts - it only works for users deleting their own accounts. This is why rejected and removed customer accounts still exist in Firebase Authentication even though they're deleted from the database.

## Solution

Firebase Cloud Functions with Admin SDK privileges can delete any user account. This setup provides the necessary server-side functions to handle Firebase Auth account deletion.

## Setup Instructions

### 1. Install Firebase CLI

```bash
npm install -g firebase-tools
```

### 2. Login to Firebase

```bash
firebase login
```

### 3. Initialize Firebase Functions (if not already done)

```bash
firebase init functions
```

### 4. Install Dependencies

```bash
cd functions
npm install firebase-admin firebase-functions
```

### 5. Deploy the Functions

```bash
firebase deploy --only functions
```

## Functions Provided

### `deleteUserAccount`
- **Purpose**: Delete a single Firebase Auth account
- **Parameters**: `{ uid: string }`
- **Returns**: `{ success: boolean, message: string }`
- **Permissions**: Only admin and staff can call this function

### `deleteMultipleUserAccounts`
- **Purpose**: Delete multiple Firebase Auth accounts at once
- **Parameters**: `{ uids: string[] }`
- **Returns**: `{ success: boolean, results: Array<{uid, success, message|error}> }`
- **Permissions**: Only admin and staff can call this function

## Security

- Functions verify that the caller is authenticated
- Functions check that the caller has admin or staff role
- Only authorized users can delete Firebase Auth accounts

## Usage

The client-side code automatically uses these functions when:
- Rejecting customer accounts
- Removing rejected customer accounts
- Removing approved customer accounts

## Testing

After deployment, test by:
1. Rejecting a customer account
2. Checking Firebase Console → Authentication to verify the account is deleted
3. Trying to register with the same email/phone - should work

## Troubleshooting

### Function Not Found Error
- Ensure functions are deployed: `firebase deploy --only functions`
- Check function names match exactly

### Permission Denied Error
- Ensure the caller is logged in as admin or staff
- Check that the user has the correct role in the database

### Function Timeout
- Cloud Functions have a timeout limit
- For large batches, use `deleteMultipleUserAccounts` instead of individual calls

## Cost Considerations

- Firebase Cloud Functions have usage-based pricing
- Each function call counts toward your quota
- Consider batching operations when possible

## Alternative: Manual Cleanup

If Cloud Functions are not available, you can manually delete Firebase Auth accounts through:
1. Firebase Console → Authentication → Users
2. Find the user by email/phone
3. Click the three dots → Delete user

This is not scalable but works for small numbers of accounts.
