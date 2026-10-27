# Turning on Google Drive backup (about 5 minutes)

My Food uses the Google Cloud project you already made for Explorer. You only add one new
"client" for My Food. No card, nothing to pay.

Values you'll need:

| Field | Value |
|---|---|
| Package name | `com.mahmoud.myfood` |
| SHA-1 certificate fingerprint | `7F:DB:04:77:3C:4F:8D:59:D1:EE:C5:5A:2F:95:2D:A9:0B:67:E1:C0` |

(It's the same SHA-1 as Explorer, because both apps are signed with the same key.)

## Steps

1. Open <https://console.cloud.google.com> and select your **Explorer** project at the top.
2. Search bar: **Google Auth Platform** → left menu **Data access**. Check that
   `.../auth/drive.appdata` is in the list (it was added for Explorer). If not:
   **Add or remove scopes** → tick it → **Update** → **Save**.
3. Left menu **Audience** → under **Test users**, make sure your own Gmail address is listed
   (the project is in Testing mode, so only listed users can sign in).
4. Left menu **Clients** → **+ Create client**.
   - Application type: **Android**
   - Name: `My Food Android`
   - Package name: `com.mahmoud.myfood`
   - SHA-1: `7F:DB:04:77:3C:4F:8D:59:D1:EE:C5:5A:2F:95:2D:A9:0B:67:E1:C0`
   - **Create**
5. Open the new client → **Advanced settings** → turn on **Enable custom URI scheme** → **Save**.
6. Copy the **Client ID** (it ends with `.apps.googleusercontent.com`).

## Put the client ID in the app

Either send it to me so I build it into the app, or paste it yourself:
My Food → **Me** → **Backup** → **Google client ID**. Then tap **Back up to Google Drive** and sign in.

## Good to know

- The backup goes to a hidden app folder in your Drive. The app can't see your other Drive files.
- While the Google project is in **Testing** mode, Google signs you out every 7 days. The app
  notices and shows **Back up to Google Drive** again; just sign in once more.
- **Export to a file** (same Backup section) works without any of this, for example to save a
  backup into your OneDrive folder.
