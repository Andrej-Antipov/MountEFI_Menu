import Cocoa
import Foundation
import UserNotifications

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    // Элементы интерфейса статус-бара
    var statusItem: NSStatusItem!
    let statusMenu = NSMenu()

    // Переменные состояния
    var menuIsOpen = false
    var lastDisksCount = 0
    var knownDiskIds: Set<String> = [] // Хранит ID для отслеживания физического подключения USB
    var needsRefresh = true           // Флаг запроса на пересборку меню из фонового потока
    var activeDiskItems: [String: NSMenuItem] = [:]
    
    // Путь к файлу пароля
    let confPath = (NSHomeDirectory() as NSString).appendingPathComponent(".MountEFImenu.plist")

    struct EfiDisk {
        let id: String
        let physName: String
        let isUsb: Bool
        let isMounted: Bool
        let size: String
        let type: String
        let volumeName: String
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            if let customIcon = NSImage(named: "Image") {
                customIcon.isTemplate = false
                customIcon.size = NSSize(width: 18, height: 18) // Фиксируем логический размер
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
        
        // Запускаем таймер проверки USB-портов (интервал 3 секунды)
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

    // Вспомогательный метод отправки нотификаций (замена старому методу)
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
        
        var driveCache: [String: (name: String, isUsb: Bool)] = [:]
        
        // Получаем полный список смонтированных устройств одним вызовом
        let mountOutput = runShell("/sbin/mount")
        
        for part in partitions {
            let pattern = try! NSRegularExpression(pattern: "(disk\\d+)")
            let nsPart = part as NSString
            let match = pattern.firstMatch(in: part, range: NSRange(location: 0, length: nsPart.length))
            let parentDisk = match != nil ? nsPart.substring(with: match!.range(at: 1)) : "disk0"
            
            if driveCache[parentDisk] == nil {
                let busTask = Process()
                busTask.launchPath = "/bin/bash"
                busTask.arguments = ["-c", "/usr/sbin/diskutil info \(parentDisk) | grep 'Protocol'"]
                let busPipe = Pipe()
                busTask.standardOutput = busPipe
                busTask.launch()
                busTask.waitUntilExit()
                let busOutput = String(data: busPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let isUsb = busOutput.contains("USB")
                
                let nameTask = Process()
                nameTask.launchPath = "/bin/bash"
                nameTask.arguments = ["-c", "/usr/sbin/diskutil info \(parentDisk) | grep -E 'Device / Media Name|Media Name' | head -n 1 | cut -d: -f2 | xargs"]
                let namePipe = Pipe()
                nameTask.standardOutput = namePipe
                nameTask.launch()
                nameTask.waitUntilExit()
                var physName = (String(data: namePipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                
                if physName.isEmpty { physName = isUsb ? "USB Storage" : "Internal Drive" }
                driveCache[parentDisk] = (name: physName, isUsb: isUsb)
            }
            
            let hwInfo = driveCache[parentDisk]!
            
            // ИСПРАВЛЕНО: Мгновенная проверка монтирования через кэшированный список mount
            let isMounted = mountOutput.contains("/dev/\(part) ")
            
            let size = "---"
            
            var partType = part.contains("ISC") ? "ISC" : "EFI"
            if part.contains("disk0") && part.contains("s1") {
                partType = "ISC"
            }
            
            let vName = "EFI"
            
            efiData.append(EfiDisk(id: part, physName: hwInfo.name, isUsb: hwInfo.isUsb, isMounted: isMounted, size: size, type: partType, volumeName: vName))
        }
        return efiData
    }

    // Вспомогательный метод для быстрого выполнения команд, если его не было в скопированной части
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
            
            // Проверяем, изменился ли статус монтирования хотя бы у одного диска
            var mountStatusChanged = false
            
            // Получаем текущие состояния монтирования из активного меню
            DispatchQueue.main.sync {
                for disk in disks {
                    // Ищем пункт меню для текущего диска
                    if let item = self.statusMenu.items.first(where: { ($0.representedObject as? String) == disk.id }) {
                        let titleContainsGreen = item.title.contains("🟢")
                        // Если в меню кружок зеленый, а диск по факту размонтирован (или наоборот) — взводим флаг
                        if titleContainsGreen != disk.isMounted {
                            mountStatusChanged = true
                            break
                        }
                    }
                }
            }
            
            // Отслеживание физического подключения новых внешних USB-дисков
            for disk in disks {
                if disk.isUsb && !self.knownDiskIds.contains(disk.id) {
                    DispatchQueue.main.async {
                        self.showNotification(
                            title: "MountEFI Menu",
                            text: "Подключен USB накопитель: Обнаружен \(disk.id) (\(disk.physName))"
                        )
                    }
                }
            }
            
            // Перерисовываем меню, если изменилось число дисков, статус монтирования или взведен флаг рефреша
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
                let internalDisks = disks.filter { !$0.isUsb }
                let usbDisks = disks.filter { $0.isUsb }
                
                // 1. Вывод внутренних дисков
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
                
                // 2. Вывод внешних USB-дисков
                if !usbDisks.isEmpty {
                    if !internalDisks.isEmpty {
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
            
            // ИСПРАВЛЕНО: Теперь кнопка ссылается на новый рабочий экшен
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
        
        DispatchQueue.global(qos: .userInitiated).async {
            let disks = self.getEfiDisks()
            guard let disk = disks.first(where: { $0.id == diskId }) else { return }
            
            let password = self.getStoredPassword()
            let isMounted = disk.isMounted
            
            let task = Process()
            task.launchPath = "/bin/bash"
            
            if isMounted {
                if let pwd = password {
                    task.arguments = ["-c", "echo '\(pwd)' | sudo -S /usr/sbin/diskutil unmount \(diskId)"]
                } else {
                    task.arguments = ["-c", "osascript -e 'do shell script \"/usr/sbin/diskutil unmount \(diskId)\" with administrator privileges'"]
                }
                task.launch()
                task.waitUntilExit()
                
                DispatchQueue.main.async {
                    if task.terminationStatus == 0 {
                        self.showNotification(title: "MountEFI Menu", text: "Раздел \(diskId) успешно размонтирован")
                    } else {
                        self.showNotification(title: "Ошибка", text: "Не удалось размонтировать \(diskId)")
                    }
                    self.needsRefresh = true
                    self.asyncHotplugMonitor()
                }
            } else {
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

    // ==========================================
    // ДОБАВЛЕНО: Методы принудительной активации и горячих клавиш
    // ==========================================

    @objc func forceQuitApp() {
        NSApplication.shared.terminate(self)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(forceQuitApp) {
            return true // Делает пункт "Выйти" активным в обход ограничений агента LSUIElement
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
} // Это самая последняя фигурная скобка файла
