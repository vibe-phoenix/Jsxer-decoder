# README.md

## JSXER Decoder — packaged Windows build (v1.7.4)
Small self-contained GUI wrapper around **Jsxer** (v1.7.4) that lets you pick a `.jsxbin` (or a wrapped `.js`/`.jsx`), decodes it with the embedded `jsxer.exe`, and saves the results and logs while **preserving the original file**.

---

# Credits
- `Jsxer` original project and contributors — https://github.com/AngeloD2022/jsxer  
- Wrapper / builder — Vibe
```

## What's included in this folder
```
jsxer-v1.7.4-Windows/
├─ release/
│  ├─ static/libjsxer.lib
│  ├─ dll/lib-jsxer.dll
│  ├─ jsxer.exe
├─ JSXER-Decoder.exe                      (build)
├─ jsxer-1.7.4-original sourceCode/       (original project source tree)
├─ jsxer-packed-wrapper.ps1               (generated runtime wrapper script)
├─ icon_jsxer.ico                         (icon used for EXE)
├─ build-packed-jsxer.ps1                 (builder: packs release into single EXE)
├─ buid decoder.bat                       (optional batch helper)
```

---

# Quick usage (run the ready EXE)
1. Double-click `JSXER-Decoder_YYYYMMDD_HHMMSS.exe` (or `JSXER-Decoder.exe`) in this folder.  
2. A file-open dialog appears — select the `.jsxbin` (or wrapped `.js`/`.jsx`) file you want to decode.  
3. The tool creates a folder next to your selected file named:
   ```
   <selectedfilename>-JsxerLogs/
     └─ temp/                 (a working copy lives here)
     └─ stderr.txt            (collected stderr from jsxer)
     └─ decode.log            (detailed run log)
   ```
4. The original file is **never modified**. The runtime will:
   - copy the original file to the Logs `temp` folder,
   - decode the copy / extract `@JSXBIN@` if wrapped,
   - write the decoded JS to `<selectedfilename>-jsxer.jsx` (next to original),
   - rename & copy the temp copy to `<selectedfilename>-Jsxer<ext>` (next to original),
   - write `stderr` and `decode.log` inside `<selectedfilename>-JsxerLogs`.

5. A messagebox will indicate success or point you to the logs in case of problems.

---

# How to build your own single-file EXE
If you prefer to rebuild the single-file EXE (the repository already contains `build-packed-jsxer.ps1`), run:

1. Open PowerShell as your normal user (or Admin if required).  
2. From this folder run:
```powershell
powershell -ExecutionPolicy Bypass -File .\build-packed-jsxer.ps1
```
3. The builder will:
   - embed `release/jsxer.exe`, `release/dll/lib-jsxer.dll`, and `release/static/libjsxer.lib` into a script,
   - compile a timestamped single-file EXE (requires PS2EXE; the builder installs it if missing),
   - apply `icon_jsxer.ico` (if present) to the output EXE.

4. Result: `JSXER-Decoder_YYYYMMDD_HHMMSS.exe` in this folder.

Notes:
- The builder uses the PS2EXE PowerShell module to compile. Internet access (PSGallery) is required the first time to install PS2EXE.
- If your environment blocks module installs, run `Install-Module PS2EXE -Scope CurrentUser` first or build on another machine.

---

# Developer / advanced usage
- The original Jsxer C++ source code is included under `jsxer-1.7.4-original sourceCode/`. Use CMake + Visual Studio or your usual toolchain to build `jsxer.exe` from source if you want to produce a different build.
- The builder script expects `release/jsxer.exe` and the DLL/lib files to exist. If you replace `jsxer.exe`, rebuild the packed EXE to embed the new binary.

---

# Troubleshooting
- **No output / empty output**: Check the `<selectedfilename>-JsxerLogs/stderr.txt` and `decode.log` for the jsxer exit code and messages.
- **Permissions / locked file**: If the builder cannot overwrite or remove files, try building outside OneDrive (e.g., `C:\Temp\`), pause OneDrive syncing, or run PowerShell as Administrator.
- **Antivirus / SmartScreen**: Windows Defender or SmartScreen may block the generated EXE. If blocked, use “More info → Run anyway” or whitelist the file in your AV temporarily.
- **PS2EXE argument errors**: If the builder complains about `Invoke-PS2EXE`, ensure PS2EXE is installed:  
  `Install-Module PS2EXE -Scope CurrentUser -Force`
- **Icon not applied**: Ensure `icon_jsxer.ico` is present in this folder before running the builder.

---

# Security & legal
- The tool executes the embedded `jsxer.exe` on files you supply. Only decode files you trust or have permission to examine.
- The Jsxer project is third-party software — see the included `jsxer-1.7.4-original sourceCode/LICENSE` for its license and attribution.
- This wrapper and build scripts are provided as-is. Use at your own risk.

---

# Quick contact / next steps
If you want any of the following, tell me which and I’ll give the script update:
- Add an option to toggle `--unblind` (deobfuscation) before decoding.  
- Change the default decoded filename pattern.  
- Produce a Windows installer (MSI) that places the EXE on PATH.  
- Add version-info metadata to the compiled EXE (Company/Product/FileVersion).

