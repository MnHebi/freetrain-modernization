# Phase 1D — verified .NET Framework 3.5 SP1 prerequisite

## Decision

Accept the Microsoft .NET Framework 3.5 Service Pack 1 full offline installer described below as the CLR 2 preservation-runtime prerequisite for the disposable Windows XP SP3 x86 VM.

The verified binary is staged only under ignored `.artifacts\prerequisites\dotnet35sp1`. It is not committed, copied into the FreeTrain package, executed on the Windows 11 host, or registered on the host.

## Exact file identity

| Property | Verified value |
|---|---|
| Filename | `dotnetfx35.exe` |
| Microsoft source | `https://download.microsoft.com/download/2/0/e/20e90413-712f-438c-988e-fdaa79a8ac3d/dotnetfx35.exe` |
| Download response filename | `dotnetfx35.exe` |
| Size | 242,743,296 bytes |
| SHA-256 | `0582515BDE321E072F8673E829E175ED2E7A53E803127C50253AF76528E66BC1` |
| SHA-1, for cross-checking only | `3DCE66BAE0DD71284AC7A971BAED07030A186918` |
| File version | `3.5.30729.01` |
| Product version | `3.5.30729.01` |
| Product name | `.NET Framework 3.5` |
| Description | `.NET Framework 3.5 Setup` |
| Company | `Microsoft Corporation` |
| Original filename | `dotnetfx35.exe` |
| PE architecture | i386 / x86 bootstrapper |
| PE subsystem requirement | Windows GUI, subsystem version 4.0 |

The Microsoft response reported `Content-Type: application/octet-stream`, `Content-Disposition: attachment; filename=dotnetfx35.exe`, and the same 242,743,296-byte length. A separate OpenSSL TLS probe validated the download endpoint certificate chain and identified the peer as `akamai.download.microsoft.com`, organization `Microsoft Corporation`.

Static payload-name inspection confirms this is the full multi-architecture package rather than the small web bootstrapper. The bundle contains references to the XP-relevant x86 payloads and prerequisites, including `Netfx20a_x86.msi`, `Netfx30a_x86.msi`, `netfx35_x86.exe`, `WIC_x86_enu.exe`, and `XPSEPSC-x86-en-US.exe`. Only the x86 path is relevant to the preservation VM.

## Signer and provenance verification

Windows `Get-AuthenticodeSignature` returned:

| Property | Verified value |
|---|---|
| Signature status | `Valid` — `Signature verified.` |
| Signature type | `Authenticode` |
| Signer subject | `CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US` |
| Signer issuer | `CN=Microsoft Code Signing PCA, O=Microsoft Corporation, L=Redmond, S=Washington, C=US` |
| Signer serial | `610F784D000000000003` |
| Signer SHA-1 thumbprint | `D57FAC60F1A8D34877AEB350E83F46F6EFC9E5F1` |
| Signer validity | 2007-08-23 through 2009-02-23 |
| Timestamp subject | `CN=Microsoft Timestamping Service, OU=nCipher DSE ESN:D8A9-CFCC-579C, O=Microsoft Corporation, L=Redmond, S=Washington, C=US` |
| Timestamp issuer | `CN=Microsoft Timestamping PCA, O=Microsoft Corporation, L=Redmond, S=Washington, C=US` |
| Timestamp SHA-1 thumbprint | `A1DC024FC8B2A76745D4661F663B8741C3D35313` |
| Signing timestamp | 2008-07-30 10:35:54, as reported by SignTool on the verification host |

Windows SDK 10 SignTool verification with `/pa /all /v` found exactly one primary signature, successfully built both the Microsoft code-signing and timestamp chains, and reported zero warnings and zero errors. Its chain terminated at the historical `Microsoft Root Authority`; the intermediate was `Microsoft Code Signing PCA`.

The outer executable is **not catalog-signed**. Its `SignatureType` is embedded Authenticode, so no external `.cat` file participates in verification. This is the correct signer/catalog provenance to record: exact outer bytes are pinned by SHA-256 and authenticated by the embedded, timestamped Microsoft signature. Do not describe it as Microsoft-catalog-verified. Inner MSI/MSP or catalog checks, if required for diagnostic evidence, must be performed after extraction inside the disposable guest and recorded separately; they are not needed to establish the outer installer's provenance.

## Expected clean XP installation result

.NET Framework 3.5 is an assembly layer over CLR 2.0; it does not install a CLR named 3.5. On an offline XP SP3 x86 guest with no later .NET servicing applied, the expected post-install baseline is:

| Component | Expected registry/file version | Expected service pack |
|---|---|---|
| CLR / .NET Framework 2.0 | `2.0.50727.3053` | SP2 |
| .NET Framework 3.0 | `3.0.30729.1` | SP2 |
| .NET Framework 3.5 | `3.5.30729.01` | SP1 |

Expected registry state:

```text
HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v2.0.50727
  Install = 1
  SP = 2
  Version = 2.0.50727.3053

HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.0\Setup
  InstallSuccess = 1
  SP = 2
  Version = 3.0.30729.1

HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5
  Install = 1
  SP = 1
  Version = 3.5.30729.01
```

For the CLR 2 engine itself, inspect `%WINDIR%\Microsoft.NET\Framework\v2.0.50727\mscorwks.dll` and `mscorlib.dll`; the expected unserviced SP2 file version is `2.0.50727.3053`. Later security servicing may legitimately raise file revisions, but such a VM is a different runtime baseline and its exact versions must be recorded.

## Guest-only installation and verification procedure

Do not run the installer from a host shared directory. Put the verified installer and a text copy of its hash on read-only virtual optical media, then use this sequence only after reverting to the `xp-sp3-clean` Phase 1D snapshot:

1. Keep the VM network adapter disconnected and log on as the disposable guest's local administrator.
2. Copy the installer from read-only media to `C:\FTVM\prerequisites\dotnetfx35.exe`.
3. Compare the guest copy byte-for-byte against the read-only-media copy with `fc /b`. The host-side ISO/file manifest must retain the SHA-256 above.
4. Record the three registry keys above before installation; they should be absent on a clean XP image.
5. Run only in the guest:

   ```bat
   cd /d C:\FTVM\prerequisites
   dotnetfx35.exe /q /norestart
   echo %ERRORLEVEL%
   ```

6. Accept exit code `0` as success or `3010` as success requiring a guest reboot. Any other exit is a failed prerequisite installation; preserve the setup logs before reverting.
7. Reboot the guest if requested. Save `.NET` setup logs from `%TEMP%`, including files beginning `dd_dotnetfx35` and relevant MSI logs.
8. Run and save:

   ```bat
   reg query "HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v2.0.50727"
   reg query "HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.0\Setup"
   reg query "HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5"
   ```

9. Inspect `mscorwks.dll` and `mscorlib.dll` versions, then create the `xp-sp3-clr2` snapshot required by `phase1d-runtime-validation.md`.
10. Only after that snapshot passes should the hash-verified FreeTrain package be copied in and the RV-00 through RV-06 scenarios begin.

Never register a .NET interop assembly, copy the runtime into the application directory, or install this package on Windows 11.

## Current execution status

Binary verification is complete. Guest installation and FreeTrain runtime validation have not run because no VirtualBox, VMware, QEMU, Hyper-V command/module, or corresponding virtualization service is available on the host. Enabling or installing a hypervisor would modify the host OS and is outside the authorization for Phase 1D.

Continue only when an already-provisioned disposable XP SP3 x86 VM or approved non-installing VM execution environment is attached. This is an environment blocker, not a problem with the verified installer or FreeTrain package.
