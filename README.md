# 🌀 Windows Insider Restoration & Management Utility

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-blue.svg)](#)
[![PowerShell: 5.1+](https://img.shields.io/badge/PowerShell-5.1%20%2F%207+-blueviolet.svg)](#)

A premium, interactive PowerShell utility designed to restore, force-enroll, and manage the **Windows Insider Program** on custom, optimized, or aggressively stripped operating systems (such as **AtlasOS**, **Ghost Spectre**, and **ReviOS**).

---

## ✨ Features

- **⚡ Option 1: Standard Online Enrollment**
  - Fully restores all core telemetry requirements, flight signing kernels, and settings page visibility to allow a standard Microsoft Account (MSA) sign-in.
- **🛡️ Option 2: Offline Bypass Channel Force**
  - Uses advanced registry signatures (`OfflineInsiderEnroll` compatibility) to force-enroll local accounts into **Canary**, **Dev**, **Beta**, or **Release Preview** channels without requiring any Microsoft Account.
  - Automatically writes Group Policy overrides (`ManagePreviewBuilds = 1`, `ManagePreviewBuildsPolicyValue = 1`) to ensure stripped systems successfully handshake with Microsoft flight servers.
- **🔄 Option 3: Clean System Reversion (1-Click Restore)**
  - Instantly reverses all registry keys, flight signing kernel options, and telemetry components back to your system's original highly-optimized, secure, and private baseline.
- **🔍 Option 4: Live Config Diagnostics**
  - Real-time check of all core Windows Insider services (`wisvc`, `DiagTrack`, `wuauserv`, `UsoSvc`) and registry overrides to inspect your exact flight status.

---

## 🚀 Quick Run (No Download Required)

Open **PowerShell as Administrator** and paste the following command:

```powershell
irm "https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO_NAME/main/Manage-WindowsInsider.ps1" | iex
```

---

## 🛠️ Manual Installation & Run

1. Clone or download this repository.
2. Open PowerShell as Administrator in the folder.
3. Set your execution policy to allow running scripts:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   ```
4. Run the interactive utility:
   ```powershell
   .\Manage-WindowsInsider.ps1
   ```

---

## ⚠️ Important Configuration Notes

- **System Reboot Mandatory:** When enabling flighting or changing channels, a reboot is absolutely required to initialize flight signature verification and reset the Windows Update service cache.
- **Empty Settings Page on Stripped OS:** In custom OS baseline configurations (like AtlasOS), the native Settings app pages for Windows Insider may remain blank or fail to load. This is normal because the system packages were physically stripped. Your system **IS** successfully enrolled, and Insider updates will still stream directly through the standard Windows Update screen.

---

## 🤝 Credits & Acknowledgments

- **Bypass Signature Base:** The offline enrollment bypass leverages logic inspired by the legendary `OfflineInsiderEnroll` script by [abbodi1406](https://github.com/abbodi1406).
- **Tested Environments:** Optimized and validated for AtlasOS 11, Ghost Spectre, and Windows 10/11 Pro baselines.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
