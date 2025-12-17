# PandorasVault
## PandorasVault

PandorasVault is a small macOS desktop app that lets you drop files into a local “vault”, stores them encrypted on disk, and lets you export (decrypt) them later.

I built this as a portfolio project to demonstrate a pragmatic security-minded macOS app: clear UX, explicit cryptography, predictable on-disk format, and a clean separation between UI and core vault logic.

### What it’s useful for

- **Local file protection**: keep copies of sensitive files encrypted at rest on your machine.
- **A reference implementation**: a readable example of wrapping a vault key with a password-derived key, plus chunked AES-GCM for large files.
- **A macOS app architecture sample**: SwiftUI UI + an AppKit window + a small “core” layer (`VaultCore`) that is easy to test and extend.

### Features

- **Create / Unlock / Lock a vault** using a password
- **Drag & drop** files into the app once unlocked
- **Encrypt on import** (streaming/chunked encryption to keep memory bounded)
- **List vault contents** (filename, size, timestamp)
- **Export** (decrypt to a user-selected destination)
- **Delete** encrypted items from the vault
- **Keychain convenience**: caches the vault key in the user Keychain to allow “unlock on launch” when available
- **Basic brute-force throttling**: locks out after repeated failed unlock attempts (cool-down timer)

### How it works (high level)

- On first run, the app **creates a random 256-bit vault key**.
- Your password is run through **PBKDF2-HMAC-SHA256** to derive a key-encryption-key (KEK).
- The vault key is **wrapped** (encrypted) using **AES-256-GCM** with the derived KEK and stored in `vault-config.json`.
- File bytes are encrypted with the **vault key** using a **chunked AES-GCM format** (`.pvlt` files).
- Vault metadata (the list of items) is stored as **encrypted JSON** (`items.json.pvlt`).

### Storage layout (on disk)

Vault data is stored under the current user’s Application Support directory:

- **Directory**: `~/Library/Application Support/PandorasVault/`
- **Config**: `vault-config.json`
- **Encrypted items list**: `items.json.pvlt`
- **Encrypted file blobs**: `files/<uuid>.pvlt`

### Crypto / format specification (implementation details)

This is meant to be explicit and inspectable. Nothing here claims to be “novel crypto”; it’s standard primitives with straightforward composition.

- **Password KDF**
  - **Algorithm**: PBKDF2-HMAC-SHA256
  - **Salt**: 16 bytes (random)
  - **Iterations**: 200,000 (default)
  - **Derived key size**: 32 bytes

- **Vault config**
  - `vault-config.json` contains:
    - KDF parameters (`saltB64`, `iterations`, algorithm label)
    - `wrappedVaultKeyB64`: AES-GCM “combined” representation of the wrapped vault key

- **Items list encryption**
  - `items.json.pvlt` is the AES-GCM “combined” representation of JSON-encoded `[VaultItem]`

- **Encrypted file format (`PVLT1`)**
  - Implemented in `AESGCMChunkedFileCrypto`
  - Header:
    - magic: `"PVLT1"` (5 bytes)
    - chunk size: UInt32 (big endian)
    - nonce prefix: 8 random bytes
    - original size: UInt64 (big endian)
    - chunk count: UInt32 (big endian)
  - Then `chunkCount` entries:
    - sealed length: UInt32 (big endian)
    - sealed bytes: AES-GCM “combined” (nonce + ciphertext + tag)
  - Chunks use a deterministic nonce constructed as `noncePrefix(8) + counter(4)` where counter increments per chunk.

### Technology stack

- **Language**: Swift 5
- **UI**: SwiftUI (views) + AppKit (`NSApplication`, `NSWindow`) for lifecycle/windowing
- **Crypto**: CryptoKit (AES-GCM, HMAC/SHA256) + Security (`SecRandomCopyBytes`, Keychain APIs)
- **Persistence**: JSON (config + item metadata), files on disk (Application Support)
- **Platform**: macOS 10.15+
- **Build tooling**: Xcode (`PandorasVault.xcodeproj`)

### Development

#### Run locally

- Open `PandorasVault.xcodeproj`
- Select the `PandorasVault` scheme
- Run (⌘R)

#### Code layout

- `PandorasVault/`
  - `ContentView.swift`: SwiftUI UI (status, password controls, drag & drop, list/export/delete)
  - `VaultViewModel.swift`: UI state + actions; calls into `VaultService`
  - `VaultCore/`
    - `VaultService.swift`: “use-case” layer (create/unlock, add/export/delete)
    - `Storage/`: vault directory paths + reading/writing config + encrypted items list
    - `Crypto/`: PBKDF2 + chunked AES-GCM file format
    - `Keychain/`: Keychain save/load/delete for cached vault key
    - `Models/`: `VaultItem` metadata

#### Implementation notes

- **Key separation**: password-derived key is only used to wrap/unwrap the vault key; file encryption uses the vault key.
- **Bounded memory**: files are processed in chunks (default 1 MiB) so large files don’t require loading into RAM.
- **Encrypted metadata**: the item list is encrypted, not just the file bytes.
- **Keychain behavior**: vault key caching is “best effort” for convenience; deleting it effectively “locks” the vault for the current user session.


