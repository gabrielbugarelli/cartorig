# CartoRig Windows 11 — Natural Earth experimental pack and real Resolve 20 QA

**Branch / PR:** feat/natural-earth-offline-data / #3 (draft).  
**Status:** Local acceptance kit, not Natural Earth Complete.  
**Host:** Windows 11 x64 + DaVinci Resolve Studio 20 + persistent SSD.

## 1. Windows QA kit

The artifact CartoRig-Resolve20-Windows-QA-Kit contains the genuine
compiled CartoRigNative.ofx.bundle, installation scripts, offline native
preview executable, and an exact source snapshot in CartoRigNative-Source.zip.

Unzip to C:\CartoRigQA. **Close Resolve**, then in elevated PowerShell:

~~~powershell
.\Install-CartoRigNative.ps1 -BundlePath '.\CartoRigNative.ofx.bundle' -Upgrade -Confirm:$false
~~~

Unzip CartoRigNative-Source.zip into C:\CartoRigQA\source, with CMakeLists.txt,
tools, src, data, third_party and packaging immediately within that folder.

Prerequisites: Python 3.12, CMake, Visual Studio C++ Build Tools,
ImageMagick 7 (magick), and substantial SSD space for the 51 publisher
source ZIPs, GeoPackage, and the large compiled lossless atlas pyramids.
Only build-time release scripts download data; the installed OpenFX stays offline.

The verified 2026-11-07 publisher HEAD audit measured **6,687,019,474 bytes (6.23 GiB)** of zipped source data across the 51 accessible variants alone. Atlas conversion, GeoPackage and staging require considerably more free disk space. The default preflight requires **50 GiB free on both the source and pack destination volumes**; this is a conservative guard, not a proven maximum or a guarantee of sufficient capacity.

## 2. End-to-end source download, build and native 4K QA

From PowerShell inside the source folder, with explicit release-time
network permission:

~~~powershell
.\packaging\Run-NaturalEarth-QA.ps1 -Workspace 'C:\CartoRigQA\publisher-build' -Output 'C:\CartoRigQA\experimental-pack' -AllowNetwork -SetupDependencies -MaxDownloads 12 -MaxBatches 10 -MinFreeGiB 50 -InstallExperimentalPack
~~~

The command:
1. Revalidates the frozen 52-raster source discovery.
2. Fetches 51 accessible official Natural Earth ZIPs using the publisher S3
   mirror, keeping original WordPress URLs for provenance, and skips only the
   reviewed unavailable US_MSR_10M.zip (issue #4).
3. Hashes the publisher ZIPs with SHA256, checks CRC/security, and saves a
   persistent checkpoint after every download, resumable after power loss.
4. Fetches the exact SHA-pinned official vector GeoPackage and prepares the
   33 supplemental sources, requiring 215 indexed vector layers.
5. Converts the entire available raster source set into real PNG v2 atlases,
   produces a manifest-verified EXPERIMENTAL_INCOMPLETE pack, and runs
   genuine C++ tests at 720p, 1440p and 3840x2160 on 10m and 50m assets.
6. If requested by the explicit flag, installs the experimental pack into
   %LOCALAPPDATA%\CartoRigNative\NaturalEarth with Resolve closed.

Repeat the command after interruption. Do NOT delete the workspace; verified
ZIPs and partially converted assets remain resumable. The required result
is EXPERIMENTAL_PACK_AND_NATIVE_4K_VERIFIED_HOST_QA_PENDING, never a
full Natural Earth production certification.

If an experimental pack is already installed, explicitly upgrade it
after closing Resolve:

~~~powershell
.\packaging\Install-DataPack.ps1 -SourceRoot 'C:\CartoRigQA\experimental-pack' -Upgrade -AllowIncomplete -Confirm:$false
~~~

Evidence: publisher-build\workstation-qa-report.json,
publisher-build\downloads\source-archives.json and
experimental-pack\pack.json. Never upload the raw publisher datasets to
Actions Artifacts, Cache, LFS or a paid runner.

## 3. Actual DaVinci Resolve Studio 20 test on the user's machine

Restart Resolve and enable **Preferences > General > External scripting
using: Local** if necessary. Do not enable remote/network scripting.

From the source folder, with Resolve open:

~~~powershell
python -m tools.resolve_host_acceptance --mode inspect --report 'C:\CartoRigQA\resolve-inspect.json'
python -m tools.resolve_host_acceptance --mode prepare --project CartoRig_NaturalEarth_20_QA --report 'C:\CartoRigQA\resolve-prepare.json'
~~~

The first command connects to **actual Resolve 20**, checks the installed
OpenFX binary and independently SHA256-verifies the offline experimental
pack. The second creates **one new dedicated QA project** and inserts
CartoRig Map (Edit) into independent 2560x1440 and 3840x2160 timelines.
It will NOT overwrite an existing project.

### Manual Inspector signoff, mandatory

The public Resolve scripting API does NOT reliably expose CartoRig OpenFX
Inspector controls. In each newly created QA timeline, manually enable
**Use installed offline Natural Earth data pack** and choose an actual
verified raster asset. Exercise Geographic Region dropdown, search, per-region
independent colors, camera/keyframes, save and reopen, dateline behavior,
lack of Brazil/Venezuela demo animation. Record any failures honestly.

When both QA timelines have been saved and inspected, export real
DaVinci Resolve Deliver MP4/H.264 files:

~~~powershell
python -m tools.resolve_host_acceptance --mode render --project CartoRig_NaturalEarth_20_QA --render-dir 'C:\CartoRigQA\ResolveRenders' --report 'C:\CartoRigQA\resolve-render.json'
~~~

This checks real Resolve render job completion and output files, and optionally
uses ffprobe for independent video dimensions. It does **not** automatically
prove Raster Inspector selection or Overlay transparency.

To test **CartoRig Overlay (Edit)**, apply it over an actual video clip, put
another clip behind it, check transparency and compositing, render both
resolutions and inspect alpha output. The script cannot insert or validate
that OFX filter through an undocumented API: visual host evidence remains
required.

Keep exact Resolve Studio version/build, Inspector screenshots, render
outputs and the three host QA JSON reports. Only evidence captured from
the actual installed Resolve host can close the host gate.

## 4. Remaining limits

A public GitHub runner cannot access a locally installed licensed Resolve
Studio 20. The 51-archive persistent workstation acquisition and the host
acceptance have NOT been performed remotely by this PR. The 52nd publisher
archive US_MSR_10M.zip is still unavailable (issue #4), so the experimental
data pack MUST NOT be labeled NATURAL_EARTH_COMPLETE. The PR remains draft.
