import Cocoa
import Foundation
import UserNotifications

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {

    // Элементы интерфейса статус-бара
    var statusItem: NSStatusItem!
    let statusMenu = NSMenu()

    // Переменные состояния
    var menuIsOpen = false
    var lastDisksCount = 0
    var knownDiskIds: Set<String> = [] // Хранит ID для отслеживания физического подключения дисков
    var needsRefresh = false           // Флаг запроса на пересборку меню из фонового потока
    var activeDiskItems: [String: NSMenuItem] = [:]
    
    // Путь к файлу пароля
    let confPath = (NSHomeDirectory() as NSString).appendingPathComponent(".MountEFImenu.plist")

    // ДОБАВЛЕНО: Новый флаг isThunderbolt в структуру диска
    struct EfiDisk {
        let id: String
        let physName: String
        let isUsb: Bool
        let isThunderbolt: Bool
        let isMounted: Bool
        let size: String
        let type: String
        let volumeName: String
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            // ДОБАВЛЕНО: Всплывающая подсказка при наведении мышки
            button.toolTip = "MountEFI Menu"
            if let resourcePath = Bundle.main.path(forResource: "MenuLogo", ofType: "png"),
               let customIcon = NSImage(contentsOfFile: resourcePath) {
                customIcon.isTemplate = false // Автоматический Dark Mode
                customIcon.size = NSSize(width: 18, height: 18)
                button.image = customIcon
            } else {
                button.title = "💾"
            }
            
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error = error {
                    print("Ошибка запроса прав на уведомления: \(error)")
                }
            }
        }

        statusMenu.delegate = self
        statusItem.menu = statusMenu
        
        // Первичное наполнение структуры известных ID дисков при старте
        DispatchQueue.global(qos: .userInitiated).async {
            let initialDisks = self.getEfiDisks()
            self.knownDiskIds = Set(initialDisks.map { $0.id })
            self.lastDisksCount = initialDisks.count
            self.updateMenuOnMainThread(with: initialDisks)
        }
        
        // Запускаем таймер проверки портов (интервал 3 секунды)
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.asyncHotplugMonitor()
        }
        
        DispatchQueue.main.async {
            NSApplication.shared.windows.forEach { window in
                if window != self.statusItem.button?.window {
                    window.close()
                }
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    func showNotification(title: String, text: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = text
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func getEfiPartitionsList() -> [String] {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "/usr/sbin/diskutil list | grep -E 'EFI|ESP|Apple_ISC|Apple_APFS_ISC' | awk '{print $NF}'"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            return output.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return []
    }

    func getEfiDisks() -> [EfiDisk] {
        let partitions = getEfiPartitionsList()
        var efiData: [EfiDisk] = []
        if partitions.isEmpty { return [] }
        
        // КЭШ ИСПРАВЛЕН: Добавлен булев флаг для Thunderbolt накопителей
        var driveCache: [String: (name: String, isUsb: Bool, isThunderbolt: Bool)] = [:]
        let mountOutput = runShell("/sbin/mount")
        
        for part in partitions {
            let pattern = try! NSRegularExpression(pattern: "(disk\\d+)")
            let nsPart = part as NSString
            let match = pattern.firstMatch(in: part, range: NSRange(location: 0, length: nsPart.length))
            let parentDisk = match != nil ? nsPart.substring(with: match!.range(at: 1)) : "disk0"
            
            if driveCache[parentDisk] == nil {
                let infoTask = Process()
                infoTask.launchPath = "/bin/bash"
                
                // ОПТИМИЗИРОВАНО: Запрашиваем протокол, локацию и медиа-имя одновременно за ОДИН вызов
                infoTask.arguments = ["-c", "/usr/sbin/diskutil info \(parentDisk) | grep -E 'Protocol|Location|Device / Media Name|Media Name'"]
                
                let infoPipe = Pipe()
                infoTask.standardOutput = infoPipe
                infoTask.launch()
                infoTask.waitUntilExit()
                
                let infoOutput = String(data: infoPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                
                let isUsb = infoOutput.contains("USB")
                let isExternal = infoOutput.contains("External")
                let isPCIe = infoOutput.contains("PCI-Express") || infoOutput.contains("Apple Fabric")
                let isThunderbolt = isExternal && isPCIe // Определение Thunderbolt шины
                
                var physName = ""
                let lines = infoOutput.components(separatedBy: "\n")
                if let nameLine = lines.first(where: { $0.contains("Media Name") }) {
                    if let colonIndex = nameLine.firstIndex(of: ":") {
                        let afterColon = nameLine[nameLine.index(after: colonIndex)...]
                        physName = afterColon.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                
                if physName.isEmpty {
                    if isThunderbolt { physName = "Thunderbolt NVMe" }
                    else { physName = isUsb ? "USB Storage" : "Internal Drive" }
                }
                
                driveCache[parentDisk] = (name: physName, isUsb: isUsb, isThunderbolt: isThunderbolt)
            }
            
            let hwInfo = driveCache[parentDisk]!
            let isMounted = mountOutput.contains("/dev/\(part) ")
            let size = "---"
            
            var partType = part.contains("ISC") ? "ISC" : "EFI"
            if part.contains("disk0") && part.contains("s1") {
                partType = "ISC"
            }
            
            let vName = "EFI"
            
            efiData.append(EfiDisk(id: part, physName: hwInfo.name, isUsb: hwInfo.isUsb, isThunderbolt: hwInfo.isThunderbolt, isMounted: isMounted, size: size, type: partType, volumeName: vName))
        }
        return efiData
    }

    func runShell(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/bash"
        task.launch()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    @objc func asyncHotplugMonitor() {
        if menuIsOpen { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let disks = self.getEfiDisks()
            let currentCount = disks.count
            var mountStatusChanged = false
            
            DispatchQueue.main.sync {
                for disk in disks {
                    if let item = self.statusMenu.items.first(where: { ($0.representedObject as? String) == disk.id }) {
                        let titleContainsGreen = item.title.contains("🟢")
                        if titleContainsGreen != disk.isMounted {
                            mountStatusChanged = true
                            break
                        }
                    }
                }
            }
            
            for disk in disks {
                // Уведомление о подключении любого внешнего диска (USB или Thunderbolt)
                if (disk.isUsb || disk.isThunderbolt) && !self.knownDiskIds.contains(disk.id) {
                    let typeStr = disk.isThunderbolt ? "Thunderbolt" : "USB"
                    DispatchQueue.main.async {
                        self.showNotification(
                            title: "MountEFI Menu",
                            text: "Подключен \(typeStr) накопитель: Обнаружен \(disk.id) (\(disk.physName))"
                        )
                    }
                }
            }
            
            if currentCount != self.lastDisksCount || mountStatusChanged || self.needsRefresh {
                self.lastDisksCount = currentCount
                self.knownDiskIds = Set(disks.map { $0.id })
                self.updateMenuOnMainThread(with: disks)
            } else {
                self.knownDiskIds = Set(disks.map { $0.id })
            }
        }
    }
    func refreshMenu() {
        self.needsRefresh = true
        self.asyncHotplugMonitor()
    }

    func updateMenuOnMainThread(with disks: [EfiDisk]) {
        DispatchQueue.main.async {
            self.statusMenu.removeAllItems()
            self.activeDiskItems.removeAll()
            self.needsRefresh = false
            
            if disks.isEmpty {
                let emptyItem = NSMenuItem(title: "Разделы не найдены", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                self.statusMenu.addItem(emptyItem)
            } else {
                // Разделяем массив дисков строго на три независимые категории
                let internalDisks = disks.filter { !$0.isUsb && !$0.isThunderbolt }
                let thunderboltDisks = disks.filter { $0.isThunderbolt }
                let usbDisks = disks.filter { $0.isUsb }
                
                // 1. СЕКЦИЯ: Внутренние диски
                if !internalDisks.isEmpty {
                    let header = NSMenuItem(title: "Внутренние диски", action: nil, keyEquivalent: "")
                    header.isEnabled = false
                    self.statusMenu.addItem(header)
                    
                    for disk in internalDisks {
                        let status = disk.isMounted ? "🟢" : "🔴"
                        let title = "\(status) \(disk.id) [\(disk.type)] (\(disk.physName))"

                        let item = NSMenuItem(title: title, action: #selector(self.toggleMount(_:)), keyEquivalent: "")
                        item.representedObject = disk.id
                        item.target = self
                        self.statusMenu.addItem(item)
                    }
                }
                
                // 2. СЕКЦИЯ: Внешние Thunderbolt диски (Размещена второй)
                if !thunderboltDisks.isEmpty {
                    if !internalDisks.isEmpty {
                        self.statusMenu.addItem(NSMenuItem.separator())
                    }
                    
                    let header = NSMenuItem(title: "Внешние Thunderbolt", action: nil, keyEquivalent: "")
                    header.isEnabled = false
                    self.statusMenu.addItem(header)
                    
                    for disk in thunderboltDisks {
                        let status = disk.isMounted ? "🟢" : "🔴"
                        // Для Thunderbolt выводим красивую иконку молнии ⚡️
                        let title = "\(status) ⚡️ \(disk.id) [\(disk.type)] (\(disk.physName))"

                        let item = NSMenuItem(title: title, action: #selector(self.toggleMount(_:)), keyEquivalent: "")
                        item.representedObject = disk.id
                        item.target = self
                        self.statusMenu.addItem(item)
                    }
                }
                
                // 3. СЕКЦИЯ: Внешние USB накопители
                if !usbDisks.isEmpty {
                    if !internalDisks.isEmpty || !thunderboltDisks.isEmpty {
                        self.statusMenu.addItem(NSMenuItem.separator())
                    }
                    
                    let header = NSMenuItem(title: "Внешние USB", action: nil, keyEquivalent: "")
                    header.isEnabled = false
                    self.statusMenu.addItem(header)
                    
                    for disk in usbDisks {
                        let status = disk.isMounted ? "🟢" : "🔴"
                        let title = "\(status) 🔌 \(disk.id) [\(disk.type)] (\(disk.physName))"

                        let item = NSMenuItem(title: title, action: #selector(self.toggleMount(_:)), keyEquivalent: "")
                        item.representedObject = disk.id
                        item.target = self
                        self.statusMenu.addItem(item)
                    }
                }
            }
            
            // Подвал меню
            self.statusMenu.addItem(NSMenuItem.separator())
            
            let hasPassword = self.getStoredPassword() != nil
            let passTitle = hasPassword ? "Удалить пароль администратора" : "Задать пароль администратора"
            let passItem = NSMenuItem(title: passTitle, action: #selector(self.handlePasswordButton(_:)), keyEquivalent: "")
            passItem.target = self
            self.statusMenu.addItem(passItem)
            
            self.statusMenu.addItem(NSMenuItem.separator())
            let quitItem = NSMenuItem(title: "Выйти", action: #selector(self.forceQuitApp), keyEquivalent: "q")
            quitItem.target = self
            self.statusMenu.addItem(quitItem)
        }
    }

    func getStoredPassword() -> String? {
        if let dict = NSDictionary(contentsOfFile: confPath),
           let base64Str = dict["m_pass"] as? String,
           let decodedData = Data(base64Encoded: base64Str),
           let password = String(data: decodedData, encoding: .utf8) {
            return password
        }
        return nil
    }

    @objc func handlePasswordButton(_ sender: NSMenuItem) {
        if sender.title == "Удалить пароль администратора" {
            try? FileManager.default.removeItem(atPath: confPath)
            showNotification(title: "Связка ключей", text: "Пароль успешно удален")
        } else {
            let alert = NSAlert()
            alert.messageText = "Настройка пароля"
            alert.informativeText = "Введите пароль администратора этого Mac."
            alert.addButton(withTitle: "Сохранить")
            alert.addButton(withTitle: "Отмена")
            
            let inputTextField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            alert.accessoryView = inputTextField
            
            if alert.runModal() == .alertFirstButtonReturn {
                let password = inputTextField.stringValue
                if !password.isEmpty {
                    let base64Str = Data(password.utf8).base64EncodedString()
                    let dict: NSDictionary = ["m_pass": base64Str]
                    dict.write(toFile: confPath, atomically: true)
                    showNotification(title: "Успешно", text: "Пароль зашифрован и сохранен!")
                }
            }
        }
        self.needsRefresh = true
        self.asyncHotplugMonitor()
    }

    @objc func toggleMount(_ sender: NSMenuItem) {
        guard let diskId = sender.representedObject as? String else { return }
        
        // Уходим в фоновый режим выполнения, чтобы избежать фризов UI клавиатуры
        DispatchQueue.global(qos: .userInitiated).async {
            let disks = self.getEfiDisks()
            guard let disk = disks.first(where: { $0.id == diskId }) else { return }
            
            let password = self.getStoredPassword()
            let isMounted = disk.isMounted
            
            if isMounted {
                // 1. Асинхронно закрываем окно Finder, если оно открыто
                let fastCloseScript = "tell application \"Finder\" to if window \"\(disk.volumeName)\" exists then close window \"\(disk.volumeName)\""
                let closeTask = Process()
                closeTask.launchPath = "/usr/bin/osascript"
                closeTask.arguments = ["-e", fastCloseScript]
                closeTask.launch()
                closeTask.waitUntilExit()
                
                // 2. Первая попытка: Стандартное размонтирование
                let task = Process()
                task.launchPath = "/bin/bash"
                
                if let pwd = password {
                    task.arguments = ["-c", "echo '\(pwd)' | sudo -S /usr/sbin/diskutil unmount \(diskId)"]
                } else {
                    task.arguments = ["-c", "osascript -e 'do shell script \"/usr/sbin/diskutil unmount \(diskId)\" with administrator privileges'"]
                }
                task.launch()
                task.waitUntilExit()
                
                var success = (task.terminationStatus == 0)
                var forced = false
                
                // 3. АВТО-ПОВТОР: Если обычный unmount не сработал, принудительно используем FORCE
                if !success {
                    forced = true
                    let forceTask = Process()
                    forceTask.launchPath = "/bin/bash"
                    
                    if let pwd = password {
                        forceTask.arguments = ["-c", "echo '\(pwd)' | sudo -S /usr/sbin/diskutil unmount force \(diskId)"]
                    } else {
                        forceTask.arguments = ["-c", "osascript -e 'do shell script \"/usr/sbin/diskutil unmount force \(diskId)\" with administrator privileges'"]
                    }
                    forceTask.launch()
                    forceTask.waitUntilExit()
                    success = (forceTask.terminationStatus == 0)
                }
                // Обработка результатов размонтирования
                DispatchQueue.main.async {
                    if success {
                        if forced {
                            self.showNotification(title: "MountEFI Menu", text: "Раздел \(diskId) принудительно отключен с помощью Force")
                        } else {
                            self.showNotification(title: "MountEFI Menu", text: "Раздел \(diskId) успешно размонтирован")
                        }
                    } else {
                        self.showNotification(title: "Ошибка", text: "Не удалось размонтировать \(diskId) даже принудительно")
                    }
                    self.needsRefresh = true
                    self.asyncHotplugMonitor()
                }
            } else {
                // 4. Логика монтирования (осталась без изменений)
                let task = Process()
                task.launchPath = "/bin/bash"
                
                if let pwd = password {
                    task.arguments = ["-c", "echo '\(pwd)' | sudo -S /usr/sbin/diskutil mount \(diskId)"]
                } else {
                    task.arguments = ["-c", "osascript -e 'do shell script \"/usr/sbin/diskutil mount \(diskId)\" with administrator privileges'"]
                }
                task.launch()
                task.waitUntilExit()
                
                let targetPath = "/Volumes/\(disk.volumeName)"
                let openTask = Process()
                openTask.launchPath = "/usr/bin/open"
                openTask.arguments = [FileManager.default.fileExists(atPath: targetPath) ? targetPath : "/Volumes/EFI"]
                openTask.launch()
                
                DispatchQueue.main.async {
                    if task.terminationStatus == 0 {
                        self.showNotification(title: "MountEFI Menu", text: "Раздел \(diskId) успешно смонтирован")
                    } else {
                        self.showNotification(title: "Ошибка", text: "Не удалось смонтировать \(diskId)")
                    }
                    self.needsRefresh = true
                    self.asyncHotplugMonitor()
                }
            }
        }
    }

    @objc func forceQuitApp() {
        NSApplication.shared.terminate(self)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(forceQuitApp) {
            return true
        }
        return true
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        if let currentEvent = NSApplication.shared.currentEvent, currentEvent.type == .keyDown {
            let modifierFlags = currentEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifierFlags == .command && currentEvent.charactersIgnoringModifiers == "q" {
                statusMenu.cancelTracking()
                forceQuitApp()
            }
        }
    }
}

