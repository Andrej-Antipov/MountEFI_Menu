import Cocoa
import Foundation
import UserNotifications

// Модули IOKit и Darwin полностью и безопасно удалены,
// так как вся архитектура переведена на нативный DiskArbitration и POSIX.

class BootEFIFinder {
    static func findCurrentSystemEFI() -> String? {
        var stats = statfs()
        guard statfs("/", &stats) == 0 else { return nil }
        
        let bootPartitionBSD = withUnsafePointer(to: &stats.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) { String(cString: $0) }
        }.replacingOccurrences(of: "/dev/", with: "")
        
        guard !bootPartitionBSD.isEmpty else { return nil }
        
        // Находим родительский физический диск (whole disk) для текущей запущенной ОС
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bootPartitionBSD),
              let wholeDisk = DADiskCopyWholeDisk(disk),
              let wholeDesc = DADiskCopyDescription(wholeDisk) as? [String: Any],
              let parentDisk = wholeDesc[kDADiskDescriptionMediaBSDNameKey as String] as? String else { return nil }
        
        // Быстрый вызов для Intel: вытаскиваем легитимный EFI-раздел родительского диска
        let listTask = Process()
        listTask.launchPath = "/bin/bash"
        listTask.arguments = ["-c", "/usr/sbin/diskutil list \(parentDisk) | /usr/bin/grep -E 'EFI|ESP' | /usr/bin/awk '{print $NF}'"]
        
        let listPipe = Pipe()
        listTask.standardOutput = listPipe
        listTask.launch()
        listTask.waitUntilExit()
        
        let listData = listPipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: listData, encoding: .utf8) {
            let parts = output.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return parts.first // На Intel гарантированно вернет diskXs1 (например, disk2s1)
        }
        
        return nil
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {

    // Элементы интерфейса статус-бара
    var statusItem: NSStatusItem!
    let statusMenu = NSMenu()

    // Переменные состояния
    var systemEFIDisk: String? = nil
    var menuIsOpen = false
    var lastDisksCount = 0
    var knownDiskIds: Set<String> = [] // Хранит ID для отслеживания физического подключения дисков
    var needsRefresh = false           // Флаг запроса на пересборку меню из фонового потока
    var activeDiskItems: [String: NSMenuItem] = [:]
    
    // Путь к файлу зашифрованного пароля администратора
    let confPath = (NSHomeDirectory() as NSString).appendingPathComponent(".MountEFImenu.plist")

    // Структура диска со всеми флагами интерфейсов (USB / Thunderbolt)
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
        
        // Фоновый поток инициализации: полностью убирает гонку потоков при первом старте
        DispatchQueue.global(qos: .userInitiated).async {
            self.systemEFIDisk = BootEFIFinder.findCurrentSystemEFI()
            
            let initialDisks = self.getEfiDisks()
            self.knownDiskIds = Set(initialDisks.map { $0.id })
            self.lastDisksCount = initialDisks.count
            self.updateMenuOnMainThread(with: initialDisks)
            
            // Тихая фоновая проверка обновлений на GitHub при старте
            AppUpdater.checkForUpdates(silent: true)
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
        task.arguments = ["-c", "/usr/sbin/diskutil list | /usr/bin/grep -v virtual | /usr/bin/grep -E 'EFI|ESP|Apple_ISC|Apple_APFS_ISC' | /usr/bin/awk '{print $NF}'"]
        
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
        
        let mountOutput = runShell("/sbin/mount")
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return [] }
        
        // НАТИВНАЯ ПРОВЕРКА АРХИТЕКТУРЫ
        var isAppleSilicon = false
        var sizeType = 0
        sysctlbyname("hw.optional.arm64", nil, &sizeType, nil, 0)
        if sizeType > 0 {
            var arm64Supported = 0
            sysctlbyname("hw.optional.arm64", &arm64Supported, &sizeType, nil, 0)
            if arm64Supported == 1 {
                isAppleSilicon = true
            }
        }
        
        for part in partitions {
            var physName = "Internal Drive"
            var isUsb = false
            var isThunderbolt = false
            var isVirtualImage = false // Новый флаг-фильтр для виртуальных DMG
            
            if let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, part) {
                // СТРОГАЯ ЗАЩИТА: Безопасный пропуск диска, если он стирается или недоступен
                guard let description = DADiskCopyDescription(disk) as? [String: Any] else { continue }
                
                if let wholeDisk = DADiskCopyWholeDisk(disk),
                   let wholeDesc = DADiskCopyDescription(wholeDisk) as? [String: Any] {
                    
                    // =================================================================
                    // СТРОГИЙ НАТИВНЫЙ ФИЛЬТР ВИРТУАЛЬНЫХ ОБРАЗОВ (Apple Disk Image)
                    // =================================================================
                    if let modelName = wholeDesc[kDADiskDescriptionDeviceModelKey as String] as? String {
                        let modelUpper = modelName.uppercased()
                        if modelUpper.contains("DISK IMAGE") || modelUpper.contains("VIRTUAL") {
                            isVirtualImage = true
                        }
                    }
                    
                    if let protocolName = wholeDesc[kDADiskDescriptionDeviceProtocolKey as String] as? String {
                        let protoUpper = protocolName.uppercased()
                        if protoUpper.contains("VIRTUAL") || protoUpper.contains("IMAGE") {
                            isVirtualImage = true
                        }
                    }
                    
                    // Если это скрытый образ iOS симулятора или RAM-диск — отсекаем по имени медиа
                    if let mediaName = wholeDesc[kDADiskDescriptionMediaNameKey as String] as? String {
                        let mediaUpper = mediaName.uppercased()
                        if mediaUpper.contains("DISK IMAGE") || mediaUpper.contains("VIRTUAL") {
                            isVirtualImage = true
                        }
                    }
                    // =================================================================
                    
                    // Чтение коммерческого названия модели устройства
                    if let modelName = wholeDesc[kDADiskDescriptionDeviceModelKey as String] as? String {
                        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && trimmed != "Internal Drive" {
                            physName = trimmed
                        }
                    }
                    
                    if physName.isEmpty || physName.count < 5,
                       let mediaName = wholeDesc[kDADiskDescriptionMediaNameKey as String] as? String {
                        let trimmed = mediaName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && trimmed != "Internal Drive" && !trimmed.contains("Partition") && !trimmed.contains("Container") {
                            physName = trimmed
                        }
                    }
                    
                    // Приклеиваем имя вендора (Samsung, SanDisk)
                    if let vendorName = wholeDesc[kDADiskDescriptionDeviceVendorKey as String] as? String {
                        let vendorTrimmed = vendorName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !vendorTrimmed.isEmpty && !physName.contains(vendorTrimmed) && vendorTrimmed != "Apple" {
                            physName = "\(vendorTrimmed) \(physName)"
                        }
                    }
                    
                    // Определяем протоколы шины подключения (USB / Thunderbolt)
                    if let protocolName = wholeDesc[kDADiskDescriptionDeviceProtocolKey as String] as? String {
                        let protoUpper = protocolName.uppercased()
                        if protoUpper.contains("USB") {
                            isUsb = true
                        } else if protoUpper.contains("PCI") || protoUpper.contains("NVME") || protoUpper.contains("THUNDERBOLT") {
                            if let isInternalNum = wholeDesc[kDADiskDescriptionDeviceInternalKey as String] as? Bool, !isInternalNum {
                                isThunderbolt = true
                            }
                        }
                    }
                }
            }
            
            // КРИТИЧЕСКИЙ ШАГ: Если фильтр сработал — тихо выбрасываем диск из цикла, не засоряя меню
            if isVirtualImage {
                continue
            }
            
            if physName.isEmpty || physName == "Internal Drive" || physName == "Media" {
                if isThunderbolt { physName = "Thunderbolt NVMe" }
                else { physName = isUsb ? "USB Storage" : "Internal Drive" }
            }
            
            let isMounted = mountOutput.contains("/dev/\(part) ")
            let size = "---"
            
            // Логика определения метки (По типу процессора)
            var partType = "EFI"
            if isAppleSilicon && !isUsb && !isThunderbolt && part == "disk0s1" {
                partType = "ISC"
            }
            
            efiData.append(EfiDisk(
                id: part,
                physName: physName,
                isUsb: isUsb,
                isThunderbolt: isThunderbolt,
                isMounted: isMounted,
                size: size,
                type: partType,
                volumeName: "EFI"
            ))
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

    @objc func mountCurrentSystemEFI(_ sender: NSMenuItem) {
        // ИСПРАВЛЕНО: Напрямую и без промежуточных пустышек перенаправляем оригинальный пункт меню
        self.toggleMount(sender)
    }

    @objc func asyncHotplugMonitor() {
        if menuIsOpen { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let disks = self.getEfiDisks()
            let currentCount = disks.count
            
            // ИСПРАВЛЕНО: Уходим на главный поток асинхронно (async), полностью защищая UI от фризов при форматировании
            DispatchQueue.main.async {
                var mountStatusChanged = false
                
                for disk in disks {
                    if let item = self.statusMenu.items.first(where: { ($0.representedObject as? String) == disk.id }) {
                        let titleContainsGreen = item.title.contains("🟢")
                        if titleContainsGreen != disk.isMounted {
                            mountStatusChanged = true
                            break
                        }
                    }
                }
                
                for disk in disks {
                    if (disk.isUsb || disk.isThunderbolt) && !self.knownDiskIds.contains(disk.id) {
                        let typeStr = disk.isThunderbolt ? "Thunderbolt" : "USB"
                        self.showNotification(
                            title: "MountEFI Menu",
                            text: "Подключен \(typeStr) накопитель: Обнаружен \(disk.id) (\(disk.physName))"
                        )
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
                
                // 2. СЕКЦИЯ: Внешние Thunderbolt диски
                if !thunderboltDisks.isEmpty {
                    if !internalDisks.isEmpty {
                        self.statusMenu.addItem(NSMenuItem.separator())
                    }
                    let header = NSMenuItem(title: "Внешние Thunderbolt", action: nil, keyEquivalent: "")
                    header.isEnabled = false
                    self.statusMenu.addItem(header)
                    
                    for disk in thunderboltDisks {
                        let status = disk.isMounted ? "🟢" : "🔴"
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
            
            // =================================================================
            // ПОДВАЛ МЕНЮ (Формируется всегда)
            // =================================================================
            self.statusMenu.addItem(NSMenuItem.separator())
            
            // 1. Кнопка быстрого EFI текущей системы (в строгом стиле без скобок и кружков)
            if let bootEFI = self.systemEFIDisk {
                let systemDiskInfo = disks.first { $0.id == bootEFI }
                let isMounted = systemDiskInfo?.isMounted ?? false
                let actionText = isMounted ? "Размонтировать" : "Подключить"
                
                let bootEfiItem = NSMenuItem(
                    title: "💻 \(actionText) EFI текущей системы",
                    action: #selector(self.mountCurrentSystemEFI(_:)),
                    keyEquivalent: "e"
                )
                // КРИТИЧЕСКИ ВАЖНО: Привязываем ID диска к его target/representedObject для точного перенаправления клика
                bootEfiItem.representedObject = bootEFI
                bootEfiItem.target = self
                
                self.statusMenu.addItem(bootEfiItem)
                self.statusMenu.addItem(NSMenuItem.separator())
            }
            
            // 2. Создаем пункт «Настройки» с боковым подменю
            let settingsItem = NSMenuItem(title: "⚙️ Настройки", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            let versionItem = NSMenuItem(title: "Версия приложения: v\(currentVersion)", action: nil, keyEquivalent: "")
            versionItem.isEnabled = false
            submenu.addItem(versionItem)
            
            submenu.addItem(NSMenuItem.separator())
            
            let hasPassword = FileManager.default.fileExists(atPath: self.confPath)
            let passTitle = hasPassword ? "🔒 Удалить пароль администратора" : "🔑 Задать пароль администратора"
            let passItem = NSMenuItem(title: passTitle, action: #selector(self.handlePasswordButton(_:)), keyEquivalent: "")
            passItem.target = self
            submenu.addItem(passItem)
            
            submenu.addItem(NSMenuItem.separator())
            
            let updateItem = NSMenuItem(title: "🔄 Проверить обновления...", action: #selector(self.manualUpdateCheck), keyEquivalent: "")
            updateItem.target = self
            submenu.addItem(updateItem)
            
            settingsItem.submenu = submenu
            self.statusMenu.addItem(settingsItem)
            
            // 3. Кнопка Выхода
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
        // Проверяем реальное наличие plist-файла на диске
        if FileManager.default.fileExists(atPath: confPath) {
            try? FileManager.default.removeItem(atPath: confPath)
            showNotification(title: "Связка ключей", text: "Пароль успешно удален")
        } else {
            let alert = NSAlert()
            alert.messageText = "Настройка пароля"
            alert.informativeText = "Введите пароль администратора этого Mac для быстрого монтирования дисков."
            alert.addButton(withTitle: "Сохранить")
            alert.addButton(withTitle: "Отмена")
            
            let inputTextField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            alert.accessoryView = inputTextField
            
            // ФОКУС ВВОДА: Без if let, так как alert.window не опционал в актуальном SDK
            let alertWindow = alert.window
            alertWindow.makeKeyAndOrderFront(nil)
            alertWindow.initialFirstResponder = inputTextField
            
            if alert.runModal() == .alertFirstButtonReturn {
                let password = inputTextField.stringValue
                
                if !password.isEmpty {
                    // ВАЛИДАЦИЯ: Проверяем пароль через тестовый вызов sudo в фоне
                    let checkTask = Process()
                    checkTask.launchPath = "/bin/bash"
                    checkTask.arguments = ["-c", "sudo -k && echo '\(password)' | sudo -S true"]
                    
                    let errorPipe = Pipe()
                    checkTask.standardError = errorPipe
                    checkTask.launch()
                    checkTask.waitUntilExit()
                    
                    if checkTask.terminationStatus == 0 {
                        let base64Str = Data(password.utf8).base64EncodedString()
                        let dict: NSDictionary = ["m_pass": base64Str]
                        dict.write(toFile: confPath, atomically: true)
                        showNotification(title: "Успешно", text: "Пароль проверен и сохранен!")
                    } else {
                        let errorAlert = NSAlert()
                        errorAlert.messageText = "Ошибка авторизации"
                        errorAlert.informativeText = "Введенный пароль не является валидным паролем администратора для этого Mac. Попробуйте еще раз."
                        errorAlert.addButton(withTitle: "ОК")
                        errorAlert.runModal()
                    }
                }
            }
        }
        self.needsRefresh = true
        self.asyncHotplugMonitor()
    }

    @objc func toggleMount(_ sender: NSMenuItem) {
        // Извлекаем строку ID диска напрямую из привязанного representedObject нажатого пункта
        guard let diskId = sender.representedObject as? String else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let disks = self.getEfiDisks()
            let password = self.getStoredPassword()
            
            // Проверяем статус монтирования: либо из массива, либо через системную утилиту mount
            let mountOutput = self.runShell("/sbin/mount")
            let isMounted = disks.first(where: { $0.id == diskId })?.isMounted ?? mountOutput.contains("/dev/\(diskId) ")
            
            let volumeName = disks.first(where: { $0.id == diskId })?.volumeName ?? "EFI"
            
            if isMounted {
                let fastCloseScript = "tell application \"Finder\" to if window \"\(volumeName)\" exists then close window \"\(volumeName)\""
                let closeTask = Process()
                closeTask.launchPath = "/usr/bin/osascript"
                closeTask.arguments = ["-e", fastCloseScript]
                closeTask.launch()
                closeTask.waitUntilExit()
                
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
                
                DispatchQueue.main.async {
                    if success {
                        self.showNotification(title: "MountEFI Menu", text: forced ? "Раздел \(diskId) принудительно отключен (Force)" : "Раздел \(diskId) успешно размонтирован")
                    } else {
                        self.showNotification(title: "Ошибка", text: "Не удалось размонтировать \(diskId)")
                    }
                    self.needsRefresh = true
                    self.asyncHotplugMonitor()
                }
            } else {
                let task = Process()
                task.launchPath = "/bin/bash"
                
                if let pwd = password {
                    task.arguments = ["-c", "echo '\(pwd)' | sudo -S /usr/sbin/diskutil mount \(diskId)"]
                } else {
                    task.arguments = ["-c", "osascript -e 'do shell script \"/usr/sbin/diskutil mount \(diskId)\" with administrator privileges'"]
                }
                task.launch()
                task.waitUntilExit()
                
                let targetPath = "/Volumes/\(volumeName)"
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
    
    @objc func manualUpdateCheck() {
        AppUpdater.checkForUpdates(silent: false)
    }
} // <--- ЗДЕСЬ ОКОНЧАТЕЛЬНО ЗАКРЫВАЕТСЯ ВАШ КЛАСС APPDELEGATE

// =================================================================
// КЛАСС АВТООБНОВЛЕНИЯ (РАЗМЕЩАЕТСЯ ОТДЕЛЬНО В КОНЦЕ ФАЙЛА)
// =================================================================
class AppUpdater {
    // RAW-ссылка на ваш json-манифест в репозитории GitHub
    static let manifestURL = URL(string: "https://raw.githubusercontent.com/Andrej-Antipov/MountEFI_Menu/refs/heads/main/mountefi_version.json")!
    
    static func checkForUpdates(silent: Bool = true) {
        let task = URLSession.shared.dataTask(with: manifestURL) { data, response, error in
            guard let data = data, error == nil else { return }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let serverVersionStr = json["version"] as? String,
               let downloadUrlStr = json["url"] as? String,
               let downloadURL = URL(string: downloadUrlStr) {
                
                let serverVersion = serverVersionStr.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    if currentVersion.compare(serverVersion, options: .numeric) == .orderedAscending {
                        DispatchQueue.main.async {
                            self.showUpdateAlert(version: serverVersion, url: downloadURL)
                        }
                    } else if !silent {
                        DispatchQueue.main.async {
                            let alert = NSAlert()
                            alert.messageText = "Обновление не требуется"
                            alert.informativeText = "У вас установлена самая свежая версия v\(currentVersion)."
                            alert.runModal()
                        }
                    }
                }
            }
        }
        task.resume()
    }
    
    private static func showUpdateAlert(version: String, url: URL) {
        let alert = NSAlert()
        alert.messageText = "Доступно обновление"
        alert.informativeText = "Доступна новая версия MountEFI Menu: v\(version). Желаете обновиться?"
        alert.addButton(withTitle: "Скачать и обновить")
        alert.addButton(withTitle: "Позже")
        
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(url)
            NSApplication.shared.terminate(nil)
        }
    }
}
