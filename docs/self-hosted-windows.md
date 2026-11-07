# Self-hosted Windows desktop

This build uses the upstream self-hosted flags. It does not mint a plan, sign a token, or skip the server checks on Readest Cloud.

`SELF_HOSTED=true` is the Docker server's runtime variable. The Windows app is a static export, so it cannot read that variable, and it does not serve `/runtime-config.js`. Next 16 inlines a `process.env.NEXT_PUBLIC_SELF_HOSTED` member expression and leaves a bracket lookup of the same name untouched. The access check uses the member form (through a cast, because this repo forbids index-signature property access). A production export built with `NEXT_PUBLIC_SELF_HOSTED=true` compiles `isSelfHosted` to a comparison against the literal `"true"`. The Docker server still reads `SELF_HOSTED` with brackets at request time.

## What the flag changes

Client gates that call `isCustomizationAllowed` open without a Plus or Pro token. That includes custom theme options, WebDAV / S3 / Drive settings, offline Read Aloud download controls, Anki, Nearby pairing, and a custom translator or custom TTS endpoint.

It does not make hosted services free:

- Readest Voice (`/api/tts/readest`) still requires a Plus or Pro plan. `isTTSInPlan` does not look at the self-hosted flag, and a one-time `purchase` plan is not enough. `TTS_FIXED_QUOTA` is read on the server only.
- Official DeepL, Azure, and Yandex routes still require a signed-in session. The server does not treat `SELF_HOSTED` as a paid plan.
- Storage and daily translation quotas on your own server come from `STORAGE_FIXED_QUOTA` (Docker default `1073741824`, 1 GiB) and `TRANSLATION_FIXED_QUOTA` (Docker default `50000`). The desktop UI shows the same numbers only when `NEXT_PUBLIC_STORAGE_FIXED_QUOTA` and `NEXT_PUBLIC_TRANSLATION_FIXED_QUOTA` were set for that build. A missing value falls back to the plan on the token (`free` is 500 MiB storage and 10 KiB of translation a day).
- Signing in to the public Readest Cloud project uses the anon key already committed in `apps/readest-app/.env`. The server still applies that account's plan.

Sync, Readest Voice, and the hosted translators need a backend you run and the keys that backend is configured with. The supported backend is the Docker stack in `docker/README.md` (`SELF_HOSTED`, the Supabase keys, and the MinIO/S3 settings). Point a desktop rebuild at it with:

- `NEXT_PUBLIC_SUPABASE_URL` — browser URL of Kong, `SUPABASE_PUBLIC_URL` in the compose file
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` — the anon JWT you minted for that stack
- `NEXT_PUBLIC_API_BASE_URL` — the Readest client origin (`SITE_URL`), with no `/api` suffix
- `NEXT_PUBLIC_OBJECT_STORAGE_TYPE=s3` when that stack uses MinIO

Leave them unset to keep the public client defaults. Unset does not grant storage, voice, or translation on that cloud.

## What runs with no backend

Local files, the library, highlights, and Windows' own speech engine. Books for this build stay under the identifier `com.bilingify.readest.selfhosted`, not the official `com.bilingify.readest` profile. The installer does not register EPUB/PDF associations and does not write the official thumbnail CLSID `{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}`. Install it per user; the product name is **Readest Self-Hosted**. The in-app updater is compiled off so an official signed update cannot replace this binary.

WebView2 has to be present. The installer embeds Microsoft's bootstrapper. A copy of `readest-selfhosted.exe` run on its own does not.

## Reproduce

From an extracted tree (no clone):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows-selfhosted\build-windows.ps1
```

The script pins Node.js 24.22.2, pnpm 11.1.1, and rustc 1.99.1, adds the `x86_64-pc-windows-msvc` target, and leaves rustup's default toolchain alone. It expects the VS 2022 C++ tools already installed. `package.json`'s `build-win-x64` script passes `--target i686-pc-windows-msvc`. That is 32-bit. Do not use it for this x64 build.

Linux can cross-build with `scripts/windows-selfhosted/build-linux-cross.sh` (cargo-xwin 0.23.1). Call `node ./node_modules/@tauri-apps/cli/tauri.js`. `pnpm tauri` on Linux builds the CEF runtime instead of a Windows exe.
