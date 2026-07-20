<div align="center">

<!-- App Icon -->
<img src="https://github.com/Andrej-Antipov/MountEFI_Menu/blob/78dbaa90e72e1d98d66d28ef0eb8067df46972d4/MountEFI%20Menu/MenuLogo.png" alt="MountEFI Menu Logo" width="128" height="128">

<h1>💾 MountEFI Menu</h1>

<p><b>Native macOS Menu Bar utility written in Swift to mount EFI partitions in one click</b></p>

<!-- Language Switcher -->
<p>
  <b>English</b> • <a href="./README.ru.md">Русский</a>
</p>

<!-- Project Shields -->
<p>
  <img src="https://img.shields.io/badge/2.3%20Latest%20Release-8A2BE2" alt="2.3 Latest Release">
  <img src="https://img.shields.io/badge/github-repo-swift?logo=github" alt="Language">
  <img src="https://img.shields.io/badge/Apple-MacOS-blue" alt="Platform">
  <img src="https://img.shields.io/badge/SWIFT-red" alt="License">
</p>

<h4>
  <a href="#-features">Features</a> •
  <a href="#-installation">Installation</a> •
  <a href="#-building-from-source">Build</a> •
  <a href="#-requirements">Requirements</a>
</h4>

</div>

<hr />

## 📖 Overview

**MountEFI Menu** is a lightweight and fast macOS utility (ideal for Hackintosh users) built entirely in Swift. The app runs quietly in the background and lives inside your Mac's Menu Bar. It automatically scans your drive layout and allows you to instantly mount hidden ESP (EFI) partitions without opening Terminal or messing with `diskutil list`.

> [!TIP]
> This app is perfect for developers and users working with **OpenCore** or **Clover** bootloaders, making EFI management seamless and native.

---

## ✨ Features

- 🍏 **Menu Bar Integration:** Always accessible, keeps your Dock clean, and triggers with a single click.
- ⚡ **Written in Swift:** Lightning-fast execution, instant launch, and near-zero CPU/RAM footprint.
- 🔍 **Auto-Scanning:** Automatically updates the drive list whenever external USB drives are connected or disconnected.
- 📁 **Quick Open:** Automatically reveals the mounted EFI partition in Finder right after a successful mount.
- 🔒 **Native Security:** Securely requests `sudo` privileges using standard macOS authorization dialogs.
- 🚀 **Autostart:**  Easily enable or disable at startup via the checkbox in the settings menu.

---

## 📸 Screenshots

<div align="center">
  <img src="https://github.com/Andrej-Antipov/MountEFI_Menu/blob/2f03aa122ea0350b80130efac4311ce072ab3e51/111.png" alt="Menu Bar Interface Preview" width="400">
  <img src="https://github.com/Andrej-Antipov/MountEFI_Menu/blob/2f03aa122ea0350b80130efac4311ce072ab3e51/222.png" alt="Menu Bar Interface Preview" width="400">
  <img src="https://github.com/Andrej-Antipov/MountEFI_Menu/blob/2f03aa122ea0350b80130efac4311ce072ab3e51/112.png" alt="Menu Bar Interface Preview" width="400">
</div>

---

## 🛠️ Installation

### Pre-built Binary (Recommended)
1. Go to the **[Releases](https://github.com)** page.
2. Download the `MountEFI-Menu.dmg` or `MountEFI-Menu.app.zip` of the latest version.
3. Extract the archive and drag the app into your `/Applications` folder.
4. Launch the app. A disk icon will appear in your macOS Menu Bar.

> [!IMPORTANT]
> On the first launch, you might need to go to *System Settings -> Privacy & Security* and allow the app to run (since it is self-signed and not notarized by a paid Apple Developer account).

---

## 🏗️ Building from Source

To build the project yourself, you will need **Xcode** and its command-line tools installed.

```bash
# 1. Clone the repository
git clone https://github.com
cd MountEFI-Menu

# 2. Open project in Xcode
open MountEFI-Menu.xcodeproj

# 3. Build the project
# Inside Xcode: Product -> Build (or press Cmd+B)
```

---

## 📋 Requirements

- **OS:** macOS 12.0 Monterey or newer
- **Architecture:** Apple Silicon (M1/M2/M3/M4) & Intel (Universal Binary)
- **Privileges:** Administrator access is required to execute system mount commands.

---

## 📄 License

This project is licensed under the **MIT** License. See the [LICENSE](LICENSE) file for details.

<hr />

<div align="center">
  Made with ❤️ for the macOS community • <a href="https://github.com">@ваше_имя</a>
</div>
