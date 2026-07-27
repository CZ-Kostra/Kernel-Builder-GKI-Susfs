# Universal GKI Kernel Builder CI

Welcome to the Universal GKI Kernel Builder! This repository hosts an automated, highly flexible GitHub Actions CI pipeline designed to compile custom GKI kernels directly from source. 

Whether you need a pristine upstream kernel or a heavily modified build featuring advanced root hiding and systemless integrations, this pipeline builds exactly what you want, right when you want it.

## 🚀 Overview

The core philosophy of this project is **Dynamic Generation over Bulk Compilation**. 

Unlike massive kernel distribution repositories (like WildKernels) that compile hundreds of generic permutations on a fixed schedule, this CI is designed to be a personal build engine. When you trigger a workflow, the pipeline dynamically resolves the correct Google manifest branches, fetches the absolute latest source code for your chosen root environment, and integrates stealth patches on the fly. 

The result? You get one single, tailor-made kernel artifact and its exact matching manager APK, perfectly synced with the upstream ecosystem.

### ✨ Key Points of Difference
* **No Waiting for Updates:** You don't have to wait for a maintainer to trigger a batch build. If Google drops a new GKI update, or KernelSU merges a new commit, you can build it yourself immediately.
* **Bleeding Edge by Default:** The `dynamic` build channel pulls the latest upstream commits for the Linux kernel, your chosen root manager, and SuSFS every single time you run it. 
* **Precision Output:** Instead of sifting through hundreds of zip files to find your device's specific combination, the CI builds exactly what you ask for and packages it cleanly.
* **Guaranteed Version Matching:** The pipeline automatically fetches the exact Manager APK that matches the root environment source code used during compilation. No more signature mismatches or incompatible userspace apps.
* **Safe Fallbacks:** If the bleeding-edge upstream commits break compilation, you can instantly toggle the CI to the `stable` channel to build from verified, safe forks.

## ⚙️ Features
* **Multiple Root Managers:** Native integration support for `KernelSU`, `KernelSU-Next`, `SukiSU-Ultra`, and `ReSukiSU`.
* **SuSFS Integration:** Automated patching and macro injection for SuSFS to enable advanced path hiding, kstat spoofing, and mount masking.
* **ZeroMount VFS:** Optional integration for stealth overlay mounting.
* **WireGuard Support:** Optional native WireGuard module compilation.
* **Flexible Packaging:** Outputs a standard `AnyKernel3` (AK3) flashable zip by default. If you provide a full OTA URL, it will extract, patch, and repack a raw `boot.img` for direct fastboot flashing.

---

## 🛠️ How to Use

To start building your own custom kernels, follow these steps:

### 1. Fork the Repository
Click the **Fork** button at the top right of this page to create your own copy of the repository.

### 2. Enable GitHub Actions
In your forked repository, navigate to the **Actions** tab. You will likely see a warning that workflows are disabled. Click **"I understand my workflows, go ahead and enable them"**.

### 3. Trigger a Build
1. Still on the **Actions** tab, select **Build Custom GKI** from the left sidebar.
2. Click the **Run workflow** dropdown on the right side of the screen.
3. Fill out the configuration parameters for your build:

| Parameter | Description |
| :--- | :--- |
| **Build Channel** | Choose `dynamic` (latest upstream commits) or `stable` (fallback to verified forks if dynamic fails). |
| **Build Name** | A custom name for your output artifact (e.g., `Pixel_10_Pro_Testing`). |
| **Kernel Version** | The exact GKI target version you wish to build (e.g., `6.6.127`). |
| **Root Environment** | Select your preferred root manager from the dropdown list. |
| **Integrate SUSFS** | Check to enable advanced stealth and hiding features. |
| **Integrate ZeroMount** | Check to include the ZeroMount VFS module. |
| **Build WireGuard** | Check to compile WireGuard support into the kernel. |
| **OTA URL (Optional)** | Leave blank to output an `AnyKernel3` zip. Provide a direct link to a full OTA zip to output a pre-patched `boot.img`. |

4. Click **Run workflow**.

### 4. Download Your Artifacts
Once the CI pipeline completes successfully, scroll to the bottom of the workflow summary page. Under the **Artifacts** section, you will find your compiled kernel (either an AK3 zip or a repacked boot image) alongside the exact Manager APK required to control it. Download, flash, and enjoy!
