# 🌀 Release v1.1.0: Windows Insider Overhaul Update

An update to align with Microsoft's recent **Windows Insider Program** consolidation (Dev + Canary ➡️ **Experimental** channel). This release brings native support for the new consolidated channel while guaranteeing full backwards compatibility for older Windows builds via legacy mappings.

---

## 🚀 What's New

### 🧪 Consolidated "Experimental" Channel
* **New Primary Target**: Native support for the new consolidated **Experimental** channel (replaces the old Dev/Canary options in standard settings).
* **Automatic Registry Mapping**: Enrolls devices into `BranchName="Experimental"`, `Ring="External"`, and `ContentType="Mainline"`.
* **Smart GPO Cleanup**: Safely strips legacy update locks and readiness parameters (`BranchReadinessLevel = $null`) to match Microsoft's platform-agnostic flighting path.

### 🛡️ Legacy Engine (Dev & Canary)
* **Backwards Compatibility**: Retained **Canary Channel (Legacy)** and **Dev Channel (Legacy)** options.
* **Smart Detection**: Users on older Windows 10/11 builds can still opt-in to the previous branch names (`CanaryChannel` / `Dev`) seamlessly.

### 📦 Documentation & UX
* **Clean Menu Layout**: Redesigned interactive prompt with colored high-contrast selections and an expanded 6-option flow.
* Aligned [README.md](file:///D:/Vibe%20Coding%20projects/Windows%20Insider%20Script/README.md) details with modern Windows Insider guidelines.

---

## 📋 Registry Configuration Specs

<details>
<summary><b>🔍 View Advanced Registry & GPO Mapping Rules (Click to Expand)</b></summary>

Here is the exact registry scheme written in offline bypass mode:

| Selected Option | Registry `BranchName` | Registry `Ring` | GPO `BranchReadinessLevel` |
| :--- | :--- | :--- | :--- |
| **`[1] Experimental`** | `Experimental` | `External` | `$null` (Cleaned) |
| **`[2] Beta`** | `Beta` | `External` | `4` |
| **`[3] Release Preview`** | `ReleasePreview` | `External` | `8` |
| **`[4] Canary (Legacy)`** | `CanaryChannel` | `External` | `$null` (Cleaned) |
| **`[5] Dev (Legacy)`** | `Dev` | `External` | `2` |

</details>

---

## ⚡ Direct Execution Policy
To run the premium restored interactive menu on your machine instantly:

```powershell
irm "https://raw.githubusercontent.com/Divyansh-2903/Windows-Insider-Restoration/main/Manage-WindowsInsider.ps1" | iex
```

> [!NOTE]
> **Mandatory Action**: A system reboot is strictly required after running the enrollment tool to initialize Microsoft Flight Signing and flush your Windows Update Orchestrator cache.
