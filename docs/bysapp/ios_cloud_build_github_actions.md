# iOS cloud build from Windows (GitHub Actions)

This project includes a workflow at .github/workflows/ios-cloud-build.yml to build iOS in GitHub cloud runners.

## What this gives you

- Automatic unsigned iOS build on push to stable
- Manual signed IPA build and TestFlight upload (workflow_dispatch)
- No local Mac required for the build machine

## One-time setup in GitHub

Go to repository Settings > Secrets and variables > Actions, then create these repository secrets:

1. IOS_CERTIFICATE_P12_BASE64
2. IOS_CERTIFICATE_PASSWORD
3. IOS_PROVISIONING_PROFILE_BASE64
4. IOS_TEAM_ID
5. APPSTORE_API_KEY_ID
6. APPSTORE_API_ISSUER_ID
7. APPSTORE_API_PRIVATE_KEY_BASE64

## How to prepare the secret values

### P12 certificate

- Export your iOS Distribution certificate as .p12 from Keychain (on any Mac where the cert exists)
- Encode to base64

### Provisioning profile

- Download the App Store provisioning profile (.mobileprovision)
- Encode to base64

### App Store Connect API key

- Create API key in App Store Connect
- Save Key ID and Issuer ID
- Encode the .p8 file as base64 and save as APPSTORE_API_PRIVATE_KEY_BASE64

## Running the workflow

### Unsigned build (automatic)

- Push to stable
- Workflow uploads artifact: ios-runner-app-unsigned

### Signed build + TestFlight upload (manual)

1. Open Actions tab
2. Run workflow: iOS Cloud Build
3. Set upload_to_testflight to true
4. Optionally set build_number
5. Run workflow

If successful:

- Signed IPA artifact is uploaded as ios-ipa-signed
- Build is uploaded to TestFlight

## Notes

- Signing must match your app bundle id and team
- If upload fails, check provisioning profile and certificate validity first
- You can run without upload (upload_to_testflight=false) to validate compilation only