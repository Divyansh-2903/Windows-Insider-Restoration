# 🌀 Release v1.1.0 - Windows Insider Channel Overhaul Update

Welcome to the **v1.1.0** release of the **Windows Insider Restoration & Management Utility**! This release brings full compatibility with Microsoft's recent 2026 Windows Insider Program channel modernization.

---

## 🚀 Key Updates

### 🪐 Support for the Consolidated "Experimental" Channel
Microsoft has simplified the Windows Insider channels by merging the **Canary** and **Dev** channels into the new **Experimental** channel. 
- The utility now features **Experimental Channel** as its primary option `[1]` for offline/bypass enrollment.
- Registry mappings automatically configure `BranchName="Experimental"`, `Ring="External"`, and properly handle the new telemetry/readiness signatures.

### 🛡️ Complete Legacy Compatibility
To ensure users running older Windows 10 or 11 builds (where the new consolidated "Experimental" channel names are not yet flighted) can still enroll successfully:
- Retained **Canary Channel (Legacy)** and **Dev Channel (Legacy)** as alternative options `[4]` and `[5]`.
- Keeps existing readiness level configurations (`BranchReadinessLevel = 2` for legacy Dev) intact for perfect backwards compatibility.

### 📦 Documentation Updates
- Aligned `README.md` features overview with the new consolidated channel layout.

---

## 🛠️ Detailed Commit History
- `feat: support consolidated Experimental Insider channel and legacy options` (f9e215a)

---

## 📋 Registry Mapping Details

| Option Selected | Registry `BranchName` | Registry `Ring` | Registry `BranchReadinessLevel` |
| :--- | :--- | :--- | :--- |
| **Experimental** | `Experimental` | `External` | `$null` (Cleaned) |
| **Beta** | `Beta` | `External` | `4` |
| **Release Preview** | `ReleasePreview` | `External` | `8` |
| **Canary (Legacy)** | `CanaryChannel` | `External` | `$null` (Cleaned) |
| **Dev (Legacy)** | `Dev` | `External` | `2` |

---

## ⚡ How to Run
Open **PowerShell as Administrator** and execute:
```powershell
irm "https://raw.githubusercontent.com/Divyansh-2903/Windows-Insider-Restoration/main/Manage-WindowsInsider.ps1" | iex
```
