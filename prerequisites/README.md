# Prerequisites

Run the prerequisite acquisition script before building the offline installer:

```powershell
.\scripts\acquire-prerequisites.ps1
```

The script downloads the official Microsoft `vstor_redist.exe` from:

```text
https://download.microsoft.com/download/5/d/2/5d24f8f8-efbb-4b63-aa33-3785e3104713/vstor_redist.exe
```

Expected path:

```text
prerequisites/vstor_redist.exe
```

The acquisition and build scripts validate that the file is a Windows PE executable, is larger than 30 MB, has a valid Microsoft Authenticode signature, and matches the VSTO Runtime 10.0.60917 version family. The verified version, size, SHA-256, signer, and source URL are recorded in `prerequisites/prerequisites.lock.json`.

Do not place an HTML download page, web stub, Visual Studio installer, Build Tools installer, or any unrelated runtime in this directory.
