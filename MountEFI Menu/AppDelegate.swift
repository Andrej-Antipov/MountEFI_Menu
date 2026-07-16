import Cocoa
import Foundation
import UserNotifications

class BootEFIFinder {
    static func findCurrentSystemEFI() -> String? {
        let masterPort = mach_port_t(0)
        // Находим узел "chosen" в дереве устройств, где macOS хранит точный путь железного устройства загрузки
        let chosenEntry = IORegistryEntryFromPath(masterPort, "IODeviceTree:/chosen")
        var bootPartitionBSD = ""
        
        if chosenEntry != MACH_PORT_NULL {
            defer { IOObjectRelease(chosenEntry) }
            if let bootDevicePath = IORegistryEntryCreateCFProperty(chosenEntry, "boot-device-path" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                // Извлекаем BSD-имя из аппаратного пути (ищет подстроку вида diskXsY)
                if let range = bootDevicePath.range(of: "disk[0-9]+s[0-9]+", options: .regularExpression) {
                    bootPartitionBSD = String(bootDevicePath[range])
                }
            }
        }
        
        // Резервный вариант (Fallback): если NVRAM пуста, берем корень системы через statfs (модуль Foundation)
        if bootPartitionBSD.isEmpty {
            var stats = statfs()
            if statfs("/", &stats) == 0 {
                bootPartitionBSD = withUnsafePointer(to: &stats.f_mntfromname) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) { String(cString: $0) }
                }.replacingOccurrences(of: "/dev/", with: "")
            }
        }
        
        guard !bootPartitionBSD.isEmpty else { return nil }
        
        // Передаем точное загрузочное имя диска в DiskArbitration, чтобы найти именно его родной EFI
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bootPartitionBSD),
              let _ = DADiskCopyDescription(disk) as? [String: Any],
              let wholeDisk = DADiskCopyWholeDisk(disk),
              let wholeDesc = DADiskCopyDescription(wholeDisk) as? [String: Any],
              let parentDisk = wholeDesc[kDADiskDescriptionMediaBSDNameKey as String] as? String else { return nil }
        
        // Сканируем разделы именно того физического диска, с которого запущен загрузчик
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
            return parts.first
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
    
    // Путь к файлу пароля
    let confPath = (NSHomeDirectory() as NSString).appendingPathComponent(".MountEFImenu.plist")

    // Флаги структуры дисков
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
                customIcon.isTemplate = false
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
        
        // ПЕРЕНОС ВЫЧИСЛЕНИЕ СЮДА (В фоновый поток инициализации):
        DispatchQueue.global(qos: .userInitiated).async {
            // Вычисляем один раз в фоне, исключая зависание интерфейса и гонку потоков
            self.systemEFIDisk = BootEFIFinder.findCurrentSystemEFI()
 //           self.systemEFIDisk = "disk0s1" // - проверка появления меню системного диска
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
        
        let mountOutput = runShell("/sbin/mount")
        
        // Создаем сессию диалога с дисковым арбитром macOS
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return [] }
        
        for part in partitions {
            var physName = "Internal Drive"
            var isUsb = false
            var isThunderbolt = false
            
            // Получаем низкоуровневый объект диска по его BSD-имени ("disk0s1")
            if let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, part) {
                // Извлекаем весь словарь свойств этого диска (аналог ioreg -l)
                if let description = DADiskCopyDescription(disk) as? [String: Any] {
                    
                    // ИЩЕМ НАСТОЯЩЕЕ ИМЯ МОДЕЛИ (Media Name / Device Model)
                    // DiskArbitration возвращает имя физического железа
                    // Поднимаемся к "целому" физическому диску, чтобы забрать имя вендора и модели
                    var targetDict = description
                    if let wholeDisk = DADiskCopyWholeDisk(disk),
                       let wholeDesc = DADiskCopyDescription(wholeDisk) as? [String: Any] {
                        targetDict = wholeDesc
                    }
                    
                    // считываем свойства ФИЗИЧЕСКОГО устройства целиком
                    if let modelName = targetDict[kDADiskDescriptionDeviceModelKey as String] as? String {
                        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && trimmed != "Internal Drive" {
                            physName = trimmed
                        }
                    }
                    
                    // Если производитель зашит в Media Name на уровне ЦЕЛОГО диска
                    if physName.isEmpty || physName.count < 5,
                       let mediaName = targetDict[kDADiskDescriptionMediaNameKey as String] as? String {
                        let trimmed = mediaName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && trimmed != "Internal Drive" && !trimmed.contains("Partition") && !trimmed.contains("Container") {
                            physName = trimmed
                        }
                    }
                    
                    // Дополнительная проверка: имя вендора (Vendor) из свойств железа, если имя все еще короткое
                    if let vendorName = targetDict[kDADiskDescriptionDeviceVendorKey as String] as? String {
                        let vendorTrimmed = vendorName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !vendorTrimmed.isEmpty && !physName.contains(vendorTrimmed) && vendorTrimmed != "Apple" {
                            physName = "\(vendorTrimmed) \(physName)"
                        }
                    }

                    
                    // 2. ОПРЕДЕЛЯЕМ ПРОТОКОЛЫ ПОДКЛЮЧЕНИЯ (USB / Thunderbolt)
                    if let protocolName = description[kDADiskDescriptionDeviceProtocolKey as String] as? String {
                        let protoUpper = protocolName.uppercased()
                        if protoUpper.contains("USB") {
                            isUsb = true
                        } else if protoUpper.contains("PCI") || protoUpper.contains("NVME") || protoUpper.contains("THUNDERBOLT") {
                            // Если диск внешний (не встроенный) и протокол PCIe/NVMe — это Thunderbolt
                            if let isInternalNum = description[kDADiskDescriptionDeviceInternalKey as String] as? Bool, !isInternalNum {
                                isThunderbolt = true
                            }
                        }
                    }
                }
            }
            
            // Если имя диска вернулось системной заглушкой, подставляем дефолты
            if physName.isEmpty || physName == "Internal Drive" || physName == "Media" {
                if isThunderbolt { physName = "Thunderbolt NVMe" }
                else { physName = isUsb ? "USB Storage" : "Internal Drive" }
            }
            
            let isMounted = mountOutput.contains("/dev/\(part) ")
            let size = "---"
            
            var partType = part.contains("ISC") ? "ISC" : "EFI"
            if part.contains("disk0") && part.contains("s1") {
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


    // Этот метод остается только для вызова базовых команд mount/unmount в macOS
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
        guard let efiTarget = sender.representedObject as? String else { return }
        
        let dummyItem = NSMenuItem()
        dummyItem.representedObject = efiTarget
        
        self.toggleMount(dummyItem)
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
            
            // ПОДВАЛ МЕНЮ (Формируется ВСЕГДА)
            self.statusMenu.addItem(NSMenuItem.separator())
            
            // ВЫВОДИМ СИСТЕМНЫЙ ПУНКТ (стиль без индикаторов и скобок)
            if let bootEFI = self.systemEFIDisk {
                let systemDiskInfo = disks.first { $0.id == bootEFI }
                let isMounted = systemDiskInfo?.isMounted ?? false
                
                // Текст меняется (Подключить/Размонтировать)
                let actionText = isMounted ? "Размонтировать" : "Подключить"
                
                let bootEfiItem = NSMenuItem(
                    title: "💻 \(actionText) EFI текущей системы",
                    action: #selector(self.mountCurrentSystemEFI(_:)),
                    keyEquivalent: "e"
                )
                bootEfiItem.representedObject = bootEFI
                bootEfiItem.target = self
                
                self.statusMenu.addItem(bootEfiItem)
                self.statusMenu.addItem(NSMenuItem.separator()) // Разделитель перед паролем
            }
            
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
    } // Конец метода updateMenuOnMainThread



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

