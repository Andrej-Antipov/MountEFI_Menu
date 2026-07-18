import Cocoa
import Foundation
import UserNotifications

// Перечисление доступных языков в приложении
enum AppLanguage: String {
    case russian = "ru"
    case english = "en"
}

class LocalizationManager {
    static let shared = LocalizationManager()
    
    // Ключ для сохранения настроек языка в UserDefaults
    private let langKey = "m_selected_language"
    
    // Текущий активный язык приложения
    var currentLanguage: AppLanguage = .english
    
    private init() {
        // 1. Проверяем, сохранял ли пользователь язык вручную ранее (UserDefaults)
        if let savedLang = UserDefaults.standard.string(forKey: langKey),
           let lang = AppLanguage(rawValue: savedLang) {
            currentLanguage = lang
        } else {
            // 2. СТРОГИЙ АВТОДЕТЕКТ ДЛЯ macOS 15+: Опрашиваем реальные приоритеты языков в системе
            // Метод preferredLanguages возвращает массив кодов (например, ["ru-RU", "en-US", "de-DE"])
            if let systemLangCode = Locale.preferredLanguages.first {
                let lowerCode = systemLangCode.lowercased()
                
                // Если первый (основной) язык системы начинается на "ru", ставим русский
                if lowerCode.hasPrefix("ru") {
                    currentLanguage = .russian
                } else {
                    // Во всех остальных случаях для всего мира ставим английский по умолчанию
                    currentLanguage = .english
                }
            } else {
                // Глубокий резервный вариант, если системный массив заблокирован песочницей
                let fallbackCode = Locale.current.identifier.lowercased()
                currentLanguage = fallbackCode.hasPrefix("ru") ? .russian : .english
            }
        }
    }

    // Метод принудительного переключения языка пользователем
    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: langKey)
        UserDefaults.standard.synchronize()
    }
    
    // Главный словарь переводов (Ключ строки -> [Русский, Английский])
    func localizedString(_ key: String) -> String {
        let translations: [String: [AppLanguage: String]] = [
            "eject_tooltip": [.russian: "Извлечь весь накопитель", .english: "Eject whole drive"],
            "eject_whole": [.russian: "!", .english: "!"],
            "eject_success_notif": [.russian: "Накопитель %@ успешно отключен и готов к безопасному извлечению.", .english: "Drive %@ has been successfully disconnected and is ready for safe removal."],
            "force_eject_title": [.russian: "Диск занят", .english: "Disk is Busy"],
            "force_eject_info": [.russian: "Некоторые разделы накопителя %@ используются другими программами. Отключить его принудительно?", .english: "Some partitions on drive %@ are currently in use by other applications. Force disconnection?"],
            "force_button": [.russian: "Принудительно", .english: "Force Eject"],
            "cancel_button": [.russian: "Отмена", .english: "Cancel"],
            "eject_error_notif": [.russian: "Не удалось отключить накопитель %@. Закройте использующие его программы.", .english: "Failed to disconnect drive %@. Please close any programs using it."],

            // Секции дисков
            "internal_disks": [.russian: "Внутренние диски", .english: "Internal Drives"],
            "thunderbolt_disks": [.russian: "Внешние Thunderbolt", .english: "External Thunderbolt"],
            "usb_disks": [.russian: "Внешние USB", .english: "External USB"],
            "not_found": [.russian: "Разделы не найдены", .english: "Partitions not found"],
            
            // Подвал меню
            "mount_current_efi": [.russian: "Подключить EFI текущей системы", .english: "Mount Current System EFI"],
            "unmount_current_efi": [.russian: "Размонтировать EFI текущей системы", .english: "Unmount Current System EFI"],
            "settings": [.russian: "⚙️ Настройки", .english: "⚙️ Settings"],
            "quit": [.russian: "Выйти", .english: "Quit"],
            
            // Подменю настроек
            "app_version": [.russian: "Версия приложения: v", .english: "App Version: v"],
            "set_pass": [.russian: "🔑 Задать пароль администратора", .english: "🔑 Set Administrator Password"],
            "remove_pass": [.russian: "🔒 Удалить пароль администратора", .english: "🔒 Remove Administrator Password"],
            "check_updates": [.russian: "🔄 Проверить обновления...", .english: "🔄 Check for Updates..."],
            "select_lang": [.russian: "🌐 Выбор языка / Language", .english: "🌐 Language / Выбор языка"],
            
            // Окна алертов и уведомлений
            "pass_title": [.russian: "Настройка пароля", .english: "Password Setup"],
            "pass_info": [.russian: "Введите пароль администратора этого Mac для быстрого монтирования дисков.", .english: "Enter the administrator password of this Mac for fast disk mounting."],
            "save": [.russian: "Сохранить", .english: "Save"],
            "cancel": [.russian: "Отмена", .english: "Cancel"],
            "pass_saved_notif": [.russian: "Пароль проверен и сохранен!", .english: "Password verified and saved!"],
            "pass_removed_notif": [.russian: "Пароль успешно удален", .english: "Password successfully removed"],
            "auth_error_title": [.russian: "Ошибка авторизации", .english: "Authorization Error"],
            "auth_error_info": [.russian: "Введенный пароль не является валидным паролем администратора для этого Mac. Попробуйте еще раз.", .english: "The entered password is not a valid administrator password for this Mac. Please try again."],
            
            // Статусы монтирования в уведомлениях
            "notif_title": [.russian: "MountEFI Menu", .english: "MountEFI Menu"],
            "disk_connected": [.russian: "Подключен %@ накопитель: Обнаружен %@ (%@)", .english: "%@ drive connected: Detected %@ (%@)"],
            "unmount_success": [.russian: "Раздел %@ успешно размонтирован", .english: "Partition %@ successfully unmounted"],
            "unmount_force": [.russian: "Раздел %@ принудительно отключен с помощью Force", .english: "Partition %@ forcefully unmounted via Force"],
            "unmount_error": [.russian: "Не удалось размонтировать %@ даже принудительно", .english: "Failed to unmount %@ even with force"],
            "mount_success": [.russian: "Раздел %@ успешно смонтирован", .english: "Partition %@ successfully mounted"],
            "mount_error": [.russian: "Не удалось смонтировать %@", .english: "Failed to mount %@"],
            
            // Окна апдейтера
            "upd_title": [.russian: "Доступно обновление", .english: "Update Available"],
            "upd_info": [.russian: "Доступна новая версия MountEFI Menu: v%@. Желаете обновиться?", .english: "A new version of MountEFI Menu is available: v%@. Would you like to update?"],
            "upd_download": [.russian: "Скачать и обновить", .english: "Download and Update"],
            "upd_later": [.russian: "Позже", .english: "Later"],
            "upd_not_needed_title": [.russian: "Обновление не требуется", .english: "No Update Needed"],
            "upd_not_needed_info": [.russian: "У вас установлена самая свежая версия v%@.", .english: "You have the latest version v%@ installed."]
            
        ]
        
        return translations[key]?[currentLanguage] ?? key
    }
}

// Удобное глобальное расширение для компактного вызова локализации: "key".localized
extension String {
    var localized: String {
        return LocalizationManager.shared.localizedString(self)
    }
}

class BootEFIFinder {
    static func findCurrentSystemEFI() -> String? {
        let masterPort = mach_port_t(0)
        // 1. Заглядываем в узел "chosen" дерева устройств Apple, который мы проверяли в ioreg
        let chosenEntry = IORegistryEntryFromPath(masterPort, "IODeviceTree:/chosen")
        guard chosenEntry != MACH_PORT_NULL else { return findFallbackEFI() }
        defer { IOObjectRelease(chosenEntry) }
        
        // 2. Считываем сырой бинарный дамп путей загрузки (Data Blob)
        if let bootDeviceData = IORegistryEntryCreateCFProperty(chosenEntry, "boot-device-path" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data {
            
            // Ищем UEFI-маркер GPT-раздела диска: 0x04 (Type), 0x01 (Subtype), 0x2A 0x00 (Length = 42)
            let uefiGptMarker = Data([0x04, 0x01, 0x2A, 0x00])
            if let range = bootDeviceData.range(of: uefiGptMarker) {
                
                // UUID раздела по спецификации UEFI лежит ровно через 16 байт после маркера
                let uuidStartIndex = range.upperBound + 16
                let uuidEndIndex = uuidStartIndex + 16
                
                if uuidEndIndex <= bootDeviceData.count {
                    let uuidData = bootDeviceData.subdata(in: uuidStartIndex..<uuidEndIndex)
                    let bytes = [UInt8](uuidData)
                    
                    // 3. ИСПРАВЛЕНО (LITTLE-ENDIAN): Декодируем байты в строковый UUID с правильным разворотом байт,
                    // чтобы получить именно "0F953C51-FE0D-4FF3-A748-1FFF7E0EC043"
                    let bootPartitionUUID = String(
                        format: "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                        bytes[3], bytes[2], bytes[1], bytes[0], // Первые 4 байта разворачиваются
                        bytes[5], bytes[4],                     // Следующие 2 байта разворачиваются
                        bytes[7], bytes[6],                     // Следующие 2 байта разворачиваются
                        bytes[8], bytes[9],                     // Остальные байты идут по порядку (Big-Endian)
                        bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
                    ).uppercased()
                    
                    // 4. Через DiskArbitration ищем, какому BSD-разделу принадлежит этот UUID
                    guard let session = DASessionCreate(kCFAllocatorDefault) else { return findFallbackEFI() }
                    
                    // Временно запрашиваем список всех доступных разделов в системе
                    let appDelegate = NSApplication.shared.delegate as? AppDelegate
                    let partitions = appDelegate?.getEfiPartitionsList() ?? []
                    
                    for part in partitions {
                        if let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, part),
                           let desc = DADiskCopyDescription(disk) as? [String: Any],
                           let mediaUUID = desc[kDADiskDescriptionMediaUUIDKey as String] as? String {
                            
                            // Если UUID системного раздела из ioreg совпал с кэшем Арбитра (это disk0s2)
                            if mediaUUID.uppercased() == bootPartitionUUID {
                                // Поднимаемся к "целому" физическому диску (disk0)
                                if let wholeDisk = DADiskCopyWholeDisk(disk),
                                   let wholeDesc = DADiskCopyDescription(wholeDisk) as? [String: Any],
                                   let parentDiskName = wholeDesc[kDADiskDescriptionMediaBSDNameKey as String] as? String {
                                    
                                    // Возвращаем его первый легитимный EFI-раздел (disk0s1)
                                    return "\(parentDiskName)s1"
                                }
                            }
                        }
                    }
                }
            }
        }
        return findFallbackEFI()
    }
    
    // Резервный вариант через APFS Physical StoreJ
    private static func findFallbackEFI() -> String? {
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "/usr/sbin/diskutil info /System/Volumes/Data | /usr/bin/grep 'APFS Physical Store' | /usr/bin/awk '{print $NF}'"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let physPartition = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !physPartition.isEmpty else { return nil }
        let pattern = try! NSRegularExpression(pattern: "(disk\\d+)")
        let nsDisk = physPartition as NSString
        let match = pattern.firstMatch(in: physPartition, range: NSRange(location: 0, length: nsDisk.length))
        let parentDisk = match != nil ? nsDisk.substring(with: match!.range(at: 1)) : "disk0"
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
    
    // Путь к файлу зашифрованного пароля администратора
    let confPath = (NSHomeDirectory() as NSString).appendingPathComponent(".MountEFImenu.plist")

    // Структура диска со всеми флагами интерфейсов
    struct EfiDisk {
        let id: String
        let physName: String
        let isUsb: Bool
        let isThunderbolt: Bool
        let isMounted: Bool
        let size: String
        let type: String
        let volumeName: String // Оставляем только имя тома в кавычках
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
                    // Переведено на технический английский язык для консоли Xcode
                    print("Notification authorization request error: \(error)")
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
        
        // =================================================================
        // ИСПРАВЛЕНО ДЛЯ АКТУАЛЬНОГО SWIFT SDK: Используем новое имя RunLoop.Mode.common
        // =================================================================
        let hotplugTimer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.asyncHotplugMonitor()
        }
        RunLoop.current.add(hotplugTimer, forMode: RunLoop.Mode.common)
        // =================================================================
        
        DispatchQueue.main.async {
            NSApplication.shared.windows.forEach { window in
                if window != self.statusItem.button?.window {
                    window.close()
                }
            }
        }
    }

    // Переменная-флаг, которая защитит от бесконечного цикла автооткрытия
    var isAutoReopening = false

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        
        // Если переоткрытие уже идет, сбрасываем флаг и выходим
        if isAutoReopening {
            isAutoReopening = false
            return
        }
        
        // Проверяем: если меню закрылось из-за того, что фоновый монитор затребовал обновление
        // (то есть кэш дисков не совпадает с реальностью)
        // ИСПРАВЛЕНО: Считываем актуальный массив дисков и обновляем меню БЕЗ задержек,
        // сразу возвращая обновленное окно курьеру на экран
        let actualDisks = self.getEfiDisks()
        let actualIds = Set(actualDisks.map { $0.id })
        
        if actualIds != self.knownDiskIds || self.needsRefresh {
            self.lastDisksCount = actualDisks.count
            self.knownDiskIds = actualIds
            
            // 1. Чисто пересобираем элементы на свободном потоке UI
            self.updateMenuOnMainThread(with: actualDisks)
            
            // 2. Имитируем клик по иконке для автоматического раскрытия обновленного списка
            self.isAutoReopening = true
            self.statusItem.button?.performClick(nil)
                }
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
            if arm64Supported == 1 { isAppleSilicon = true }
        }
        
        for part in partitions {
            var physName = "Internal Drive"
            var isUsb = false
            var isThunderbolt = false
            var isVirtualImage = false
            
            if let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, part) {
                // СТРОГАЯ ЗАЩИТА: Безопасный пропуск диска, если он стирается или недоступен
                guard let description = DADiskCopyDescription(disk) as? [String: Any] else { continue }
                
                if let wholeDisk = DADiskCopyWholeDisk(disk),
                   let wholeDesc = DADiskCopyDescription(wholeDisk) as? [String: Any] {
                    
                    // ФИЛЬТР ВИРТУАЛЬНЫХ ОБРАЗОВ
                    if let modelName = wholeDesc[kDADiskDescriptionDeviceModelKey as String] as? String {
                        let modelUpper = modelName.uppercased()
                        if modelUpper.contains("DISK IMAGE") || modelUpper.contains("VIRTUAL") { isVirtualImage = true }
                    }
                    if let protocolName = wholeDesc[kDADiskDescriptionDeviceProtocolKey as String] as? String {
                        let protoUpper = protocolName.uppercased()
                        if protoUpper.contains("VIRTUAL") || protoUpper.contains("IMAGE") { isVirtualImage = true }
                    }
                    if let mediaName = wholeDesc[kDADiskDescriptionMediaNameKey as String] as? String {
                        let mediaUpper = mediaName.uppercased()
                        if mediaUpper.contains("DISK IMAGE") || mediaUpper.contains("VIRTUAL") { isVirtualImage = true }
                    }
                    
                    // Чтение коммерческого названия модели
                    if let modelName = wholeDesc[kDADiskDescriptionDeviceModelKey as String] as? String {
                        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && trimmed != "Internal Drive" { physName = trimmed }
                    }
                    if physName.isEmpty || physName.count < 5,
                       let mediaName = wholeDesc[kDADiskDescriptionMediaNameKey as String] as? String {
                        let trimmed = mediaName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && trimmed != "Internal Drive" && !trimmed.contains("Partition") && !trimmed.contains("Container") { physName = trimmed }
                    }
                    if let vendorName = wholeDesc[kDADiskDescriptionDeviceVendorKey as String] as? String {
                        let vendorTrimmed = vendorName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !vendorTrimmed.isEmpty && !physName.contains(vendorTrimmed) && vendorTrimmed != "Apple" { physName = "\(vendorTrimmed) \(physName)" }
                    }
                    
                    // Определяем протоколы (USB/Thunderbolt)
                    if let protocolName = wholeDesc[kDADiskDescriptionDeviceProtocolKey as String] as? String {
                        let protoUpper = protocolName.uppercased()
                        if protoUpper.contains("USB") { isUsb = true }
                        else if protoUpper.contains("PCI") || protoUpper.contains("NVME") || protoUpper.contains("THUNDERBOLT") {
                            if let isInternalNum = wholeDesc[kDADiskDescriptionDeviceInternalKey as String] as? Bool, !isInternalNum { isThunderbolt = true }
                        }
                    }
                }
            }
            
            if isVirtualImage { continue }
            
            if physName.isEmpty || physName == "Internal Drive" || physName == "Media" {
                if isThunderbolt { physName = "Thunderbolt NVMe" }
                else { physName = isUsb ? "USB Storage" : "Internal Drive" }
            }
            
            let isMounted = mountOutput.contains("/dev/\(part) ")
            let size = "---"
            
            // Нативно считываем уникальное имя тома
            var volumeName = "EFI"
            if let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, part),
               let desc = DADiskCopyDescription(disk) as? [String: Any],
               let volName = desc[kDADiskDescriptionVolumeNameKey as String] as? String {
                let trimmedVol = volName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedVol.isEmpty { volumeName = trimmedVol }
            }
            
            var partType = "EFI"
            if isAppleSilicon && !isUsb && !isThunderbolt && part == "disk0s1" { partType = "ISC" }
            
            efiData.append(EfiDisk(
                id: part,
                physName: physName,
                isUsb: isUsb,
                isThunderbolt: isThunderbolt,
                isMounted: isMounted,
                size: size,
                type: partType,
                volumeName: volumeName
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
        DispatchQueue.global(qos: .userInitiated).async {
            let disks = self.getEfiDisks()
            let currentCount = disks.count
            
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
                
                // ЛОГ ТАЙМЕРА: Выводим статус каждые 3 секунды в консоль
                if self.menuIsOpen {
 //                   print("[Monitor] ТАКТ: Меню ОТКРЫТО. Найдено дисков: \(currentCount) (Прошлый раз: \(self.lastDisksCount)). Статус монтирования изменился: \(mountStatusChanged)")
                }
                
                for disk in disks {
                    if (disk.isUsb || disk.isThunderbolt) && !self.knownDiskIds.contains(disk.id) {
                        let typeStr = disk.isThunderbolt ? "Thunderbolt" : "USB"
                        let localizedText = String(format: "disk_connected".localized, typeStr, disk.id, disk.physName)
                        self.showNotification(title: "notif_title".localized, text: localizedText)
                    }
                }
                
                // Фиксируем изменение количества накопителей на портах
                if currentCount != self.lastDisksCount {
 //                   print("[Monitor] ИЗМЕНЕНИЕ: Количество дисков изменилось! Взводим принудительный рефреш.")
                    self.needsRefresh = true
                }
                
                if currentCount != self.lastDisksCount || mountStatusChanged || self.needsRefresh {
//                    print("[Monitor] ДЕЙСТВИЕ: Отправляем запрос на перерисовку меню...")
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
//            print("[UI-Menu] Вызван метод перерисовки. menuIsOpen = \(self.menuIsOpen), needsRefresh = \(self.needsRefresh)")
            
            // =================================================================
            // СЦЕНАРИЙ А: Точечное обновление строк
            // =================================================================
            if self.menuIsOpen && !self.needsRefresh {
//                print("[UI-Menu] ЗАПУЩЕН СЦЕНАРИЙ А: Точечное обновление кружков и стрелочек на лету...")
                for disk in disks {
                    if let item = self.statusMenu.items.first(where: { ($0.representedObject as? String) == disk.id }) {
                        let status = disk.isMounted ? "🟢" : "🔴"
                        let vName = disk.volumeName.uppercased()
                        let displayVolume = (vName == "EFI" || vName == "ESP" || vName.isEmpty) ? "" : "\"\(disk.volumeName)\" "
                        
                        let iconStr = disk.isThunderbolt ? "⚡️" : (disk.isUsb ? "🔌" : "")
                        let newTitle = "\(status) \(iconStr) \(disk.id) [\(disk.type)] \(displayVolume)(\(disk.physName))"
                        
                        if item.title != newTitle {
                            item.title = newTitle
                        }
                        
                        if disk.isMounted && item.submenu == nil {
                            let diskSubmenu = NSMenu()
                            let ejectAllItem = NSMenuItem(title: "⏏️", action: #selector(self.ejectWholeDisk(_:)), keyEquivalent: "")
                            ejectAllItem.toolTip = "eject_tooltip".localized
                            ejectAllItem.representedObject = disk.id
                            ejectAllItem.target = self
                            diskSubmenu.addItem(ejectAllItem)
                            item.submenu = diskSubmenu
                        } else if !disk.isMounted && item.submenu != nil {
                            item.submenu = nil
                        }
                    }
                }
                self.needsRefresh = false
//                print("[UI-Menu] СЦЕНАРИЙ А успешно завершен.")
                return
            }
            
            // =================================================================
            // СЦЕНАРИЙ Б: Полная монолитная пересборка меню
            // =================================================================
//            print("[UI-Menu] ЗАПУЩЕН СЦЕНАРИЙ Б: Полная очистка и пересборка всего меню с нуля!")
            self.statusMenu.removeAllItems()
            self.activeDiskItems.removeAll()
            self.needsRefresh = false
            
            if disks.isEmpty {
                let emptyItem = NSMenuItem(title: "not_found".localized, action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                self.statusMenu.addItem(emptyItem)
            } else {
                let internalDisks = disks.filter { !$0.isUsb && !$0.isThunderbolt }
                let thunderboltDisks = disks.filter { $0.isThunderbolt }
                let usbDisks = disks.filter { $0.isUsb }
                
                // 1. СЕКЦИЯ: Внутренние диски
                if !internalDisks.isEmpty {
                    let header = NSMenuItem(title: "internal_disks".localized, action: nil, keyEquivalent: "")
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
                    if !internalDisks.isEmpty { self.statusMenu.addItem(NSMenuItem.separator()) }
                    let header = NSMenuItem(title: "thunderbolt_disks".localized, action: nil, keyEquivalent: "")
                    header.isEnabled = false
                    self.statusMenu.addItem(header)
                    for disk in thunderboltDisks {
                        let status = disk.isMounted ? "🟢" : "🔴"
                        let vName = disk.volumeName.uppercased()
                        let displayVolume = (vName == "EFI" || vName == "ESP" || vName.isEmpty) ? "" : "\"\(disk.volumeName)\" "
                        let title = "\(status) ⚡️ \(disk.id) [\(disk.type)] \(displayVolume)(\(disk.physName))"
                        let item = NSMenuItem(title: title, action: #selector(self.toggleMount(_:)), keyEquivalent: "")
                        item.representedObject = disk.id
                        item.target = self
                        
                        let diskSubmenu = NSMenu()
                        let ejectAllItem = NSMenuItem(title: "⏏️", action: #selector(self.ejectWholeDisk(_:)), keyEquivalent: "")
                        ejectAllItem.toolTip = "eject_tooltip".localized
                        ejectAllItem.representedObject = disk.id
                        ejectAllItem.target = self
                        diskSubmenu.addItem(ejectAllItem)
                        item.submenu = diskSubmenu
                        
                        self.statusMenu.addItem(item)
                    }
                }
                
                // 3. СЕКЦИЯ: Внешние USB накопители
                if !usbDisks.isEmpty {
                    if !internalDisks.isEmpty || !thunderboltDisks.isEmpty { self.statusMenu.addItem(NSMenuItem.separator()) }
                    let header = NSMenuItem(title: "usb_disks".localized, action: nil, keyEquivalent: "")
                    header.isEnabled = false
                    self.statusMenu.addItem(header)
                    for disk in usbDisks {
                        let status = disk.isMounted ? "🟢" : "🔴"
                        let vName = disk.volumeName.uppercased()
                        let displayVolume = (vName == "EFI" || vName == "ESP" || vName.isEmpty) ? "" : "\"\(disk.volumeName)\" "
                        let title = "\(status) 🔌 \(disk.id) [\(disk.type)] \(displayVolume)(\(disk.physName))"
                        let item = NSMenuItem(title: title, action: #selector(self.toggleMount(_:)), keyEquivalent: "")
                        item.representedObject = disk.id
                        item.target = self
                        
                        let diskSubmenu = NSMenu()
                        let ejectAllItem = NSMenuItem(title: "⏏️", action: #selector(self.ejectWholeDisk(_:)), keyEquivalent: "")
                        ejectAllItem.toolTip = "eject_tooltip".localized
                        ejectAllItem.representedObject = disk.id
                        ejectAllItem.target = self
                        diskSubmenu.addItem(ejectAllItem)
                        item.submenu = diskSubmenu
                        
                        self.statusMenu.addItem(item)
                    }
                }
            }
            
            // =================================================================
            // ПОДВАЛ МЕНЮ И НАСТРОЙКИ
            // =================================================================
            self.statusMenu.addItem(NSMenuItem.separator())
            if let bootEFI = self.systemEFIDisk {
                let systemDiskInfo = disks.first { $0.id == bootEFI }
                let isMounted = systemDiskInfo?.isMounted ?? false
                let actionKey = isMounted ? "unmount_current_efi" : "mount_current_efi"
                let bootEfiItem = NSMenuItem(title: "💻 \(actionKey.localized)", action: #selector(self.mountCurrentSystemEFI(_:)), keyEquivalent: "e")
                bootEfiItem.representedObject = bootEFI
                bootEfiItem.target = self
                self.statusMenu.addItem(bootEfiItem)
                self.statusMenu.addItem(NSMenuItem.separator())
            }
            
            let settingsItem = NSMenuItem(title: "settings".localized, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            let versionItem = NSMenuItem(title: "\("app_version".localized)\(currentVersion)", action: nil, keyEquivalent: "")
            versionItem.isEnabled = false
            submenu.addItem(versionItem)
            submenu.addItem(NSMenuItem.separator())
            let hasPassword = FileManager.default.fileExists(atPath: self.confPath)
            let passTitle = hasPassword ? "remove_pass".localized : "set_pass".localized
            let passItem = NSMenuItem(title: passTitle, action: #selector(self.handlePasswordButton(_:)), keyEquivalent: "")
            passItem.target = self
            submenu.addItem(passItem)
            submenu.addItem(NSMenuItem.separator())
            let langMenuItem = NSMenuItem(title: "select_lang".localized, action: nil, keyEquivalent: "")
            let langSubmenu = NSMenu()
            let ruItem = NSMenuItem(title: "Русский", action: #selector(self.changeLanguageToRussian), keyEquivalent: "")
            ruItem.target = self
            ruItem.state = LocalizationManager.shared.currentLanguage == .russian ? .on : .off
            langSubmenu.addItem(ruItem)
            let enItem = NSMenuItem(title: "English", action: #selector(self.changeLanguageToEnglish), keyEquivalent: "")
            enItem.target = self
            enItem.state = LocalizationManager.shared.currentLanguage == .english ? .on : .off
            langSubmenu.addItem(enItem)
            langMenuItem.submenu = langSubmenu
            submenu.addItem(langMenuItem)
            submenu.addItem(NSMenuItem.separator())
            let updateItem = NSMenuItem(title: "check_updates".localized, action: #selector(self.manualUpdateCheck), keyEquivalent: "")
            updateItem.target = self
            submenu.addItem(updateItem)
            settingsItem.submenu = submenu
            self.statusMenu.addItem(settingsItem)
            self.statusMenu.addItem(NSMenuItem.separator())
            let quitItem = NSMenuItem(title: "quit".localized, action: #selector(self.forceQuitApp), keyEquivalent: "q")
            quitItem.target = self
            self.statusMenu.addItem(quitItem)
        }
    } // <--- КОНЕЦ МЕТОДА UPDATEMENUONMAINTHREAD

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
        if FileManager.default.fileExists(atPath: confPath) {
            try? FileManager.default.removeItem(atPath: confPath)
            showNotification(title: "notif_title".localized, text: "pass_removed_notif".localized)
            
            // ИСПРАВЛЕНО: Принудительно обновляем меню на главном потоке, чтобы кнопка мгновенно сменилась на "Задать пароль"
            DispatchQueue.main.async {
                self.needsRefresh = true
                self.asyncHotplugMonitor()
            }
        } else {
            let alert = NSAlert()
            alert.messageText = "pass_title".localized
            alert.informativeText = "pass_info".localized
            alert.addButton(withTitle: "save".localized)
            alert.addButton(withTitle: "cancel".localized)
            
            let inputTextField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            alert.accessoryView = inputTextField
            
            let alertWindow = alert.window
            alertWindow.makeKeyAndOrderFront(nil)
            alertWindow.initialFirstResponder = inputTextField
            
            if alert.runModal() == .alertFirstButtonReturn {
                let password = inputTextField.stringValue
                
                if !password.isEmpty {
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
                        showNotification(title: "notif_title".localized, text: "pass_saved_notif".localized)
                    } else {
                        let errorAlert = NSAlert()
                        errorAlert.messageText = "auth_error_title".localized
                        errorAlert.informativeText = "auth_error_info".localized
                        errorAlert.addButton(withTitle: "ОК")
                        errorAlert.runModal()
                    }
                }
            }
            
            // ИСПРАВЛЕНО: Принудительно обновляем меню на главном потоке после закрытия окна ввода
            DispatchQueue.main.async {
                self.needsRefresh = true
                self.asyncHotplugMonitor()
            }
        }
    }

    @objc func toggleMount(_ sender: NSMenuItem) {
        guard let diskId = sender.representedObject as? String else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let disks = self.getEfiDisks()
            let password = self.getStoredPassword()
            
            let mountOutput = self.runShell("/sbin/mount")
            guard let disk = disks.first(where: { $0.id == diskId }) else { return }
            let isMounted = disk.isMounted
            
            // 1. ОЧИСТКА ИМЕНИ: Убираем пробелы и спецсимволы из названия модели
            let safePhysName = disk.physName
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "", options: .regularExpression)
            
            // Формируем базовое наглядное имя с префиксом EFI (например, "EFI_SanDisk_Ultra")
            let baseVolumeName = safePhysName.isEmpty ? "EFI_\(diskId)" : "EFI_\(safePhysName)"
            
            // Переменные для финального уникального имени
            var uniqueVolumeName = baseVolumeName
            var customMountPath = "/System/Volumes/Data/Volumes/\(uniqueVolumeName)"
            
            // 2. ЗАЩИТА ОТ ДУБЛИКАТОВ: Если диск еще НЕ смонтирован, проверяем занятость папки в /Volumes
            if !isMounted {
                var counter = 1
                let fileManager = FileManager.default
                
                // Цикл крутится до тех пор, пока не найдет свободное имя (например, EFI_SanDisk_Ultra_1)
                while fileManager.fileExists(atPath: customMountPath) {
                    uniqueVolumeName = "\(baseVolumeName)_\(counter)"
                    customMountPath = "/System/Volumes/Data/Volumes/\(uniqueVolumeName)"
                    counter += 1
                }
            } else {
                // Если диск УЖЕ смонтирован и мы его отключаем, нам нужно узнать, под каким именно именем он висит в системе.
                // Вытаскиваем точную точку монтирования из системного вывода /sbin/mount
                let lines = mountOutput.components(separatedBy: "\n")
                for line in lines {
                    if line.contains("/dev/\(diskId) on ") {
                        // Строка выглядит как: "/dev/disk3s1 on /Volumes/EFI_SanDisk_Ultra (msdos...)"
                        if let startRange = line.range(of: " on "),
                           let endRange = line.range(of: " (") {
                            let fullPath = line[startRange.upperBound..<endRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                            customMountPath = fullPath
                            uniqueVolumeName = fullPath.components(separatedBy: "/").last ?? baseVolumeName
                            break
                        }
                    }
                }
            }
            
            if isMounted {
                // 3. ЗАКРЫВАЕМ ОКНО FINDER: Закрываем уникальное окно конкретно этого диска
                let fastCloseScript = "tell application \"Finder\" to if window \"\(uniqueVolumeName)\" exists then close window \"\(uniqueVolumeName)\""
                let closeTask = Process()
                closeTask.launchPath = "/usr/bin/osascript"
                closeTask.arguments = ["-e", fastCloseScript]
                closeTask.launch()
                closeTask.waitUntilExit()
                
                // 4. РАЗМОНТИРОВАНИЕ
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
                        let text = String(format: forced ? "unmount_force".localized : "unmount_success".localized, diskId)
                        self.showNotification(title: "notif_title".localized, text: text)
                    } else {
                        let text = String(format: "unmount_error".localized, diskId)
                        self.showNotification(title: "notif_title".localized, text: text)
                    }
                    self.needsRefresh = true
                    self.asyncHotplugMonitor()
                }
            } else {
                // ИСПРАВЛЕНО: Переводим путь на классический /Volumes/ для беспрепятственного доступа diskutil
                let standardMountPath = "/Volumes/\(uniqueVolumeName)"
                
                // 5. МОНТИРОВАНИЕ В УНИКАЛЬНУЮ ПАПКУ С ПРЕФИКСОМ EFI_
                let task = Process()
                task.launchPath = "/bin/bash"
                
                // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Создаем папку (mkdir) и монтируем в нее в рамках ОДНОГО bash-процесса с нужными правами
                if let pwd = password {
                    task.arguments = ["-c", "echo '\(pwd)' | sudo -S /bin/mkdir -p \(standardMountPath) && echo '\(pwd)' | sudo -S /usr/sbin/diskutil mount -mountPoint \(standardMountPath) \(diskId)"]
                } else {
                    task.arguments = ["-c", "osascript -e 'do shell script \"/bin/mkdir -p \(standardMountPath) && /usr/sbin/diskutil mount -mountPoint \(standardMountPath) \(diskId)\" with administrator privileges'"]
                }
                task.launch()
                task.waitUntilExit()
                
                // 6. ГАРАНТИРОВАННОЕ ОТКРЫТИЕ ОКНА FINDER ДЛЯ КАЖДОГО ДИСКА
                let openTask = Process()
                openTask.launchPath = "/usr/bin/open"
                openTask.arguments = [standardMountPath]
                openTask.launch()
                
                DispatchQueue.main.async {
                    if task.terminationStatus == 0 {
                        let text = String(format: "mount_success".localized, diskId)
                        self.showNotification(title: "notif_title".localized, text: text)
                    } else {
                        let text = String(format: "mount_error".localized, diskId)
                        self.showNotification(title: "notif_title".localized, text: text)
                        
                        // Если монтирование сорвалось — подчищаем созданную пустую папку через bash
                        let cleanTask = Process()
                        cleanTask.launchPath = "/bin/bash"
                        if let pwd = password {
                            cleanTask.arguments = ["-c", "echo '\(pwd)' | sudo -S /bin/rmdir \(standardMountPath)"]
                        } else {
                            cleanTask.arguments = ["-c", "osascript -e 'do shell script \"/bin/rmdir \(standardMountPath)\" with administrator privileges'"]
                        }
                        cleanTask.launch()
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
    
    @objc func ejectWholeDisk(_ sender: NSMenuItem) {
        guard let partitionId = sender.representedObject as? String else { return }
        let password = self.getStoredPassword()
        
        // Автоматически вырезаем имя базового физического диска (из disk3s1 получаем disk3)
        let pattern = try! NSRegularExpression(pattern: "(disk\\d+)")
        let nsDisk = partitionId as NSString
        let match = pattern.firstMatch(in: partitionId, range: NSRange(location: 0, length: nsDisk.length))
        let targetDisk = match != nil ? nsDisk.substring(with: match!.range(at: 1)) : partitionId
        
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.launchPath = "/bin/bash"
            
            if let pwd = password {
                task.arguments = ["-c", "echo '\(pwd)' | sudo -S /usr/sbin/diskutil unmountDisk \(targetDisk)"]
            } else {
                task.arguments = ["-c", "osascript -e 'do shell script \"/usr/sbin/diskutil unmountDisk \(targetDisk)\" with administrator privileges'"]
            }
            task.launch()
            task.waitUntilExit()
            
            let isCleanSuccess = (task.terminationStatus == 0)
            
            if isCleanSuccess {
                // А. Сценарий: Диск успешно и чисто отключился сразу
                DispatchQueue.main.async {
                    let text = String(format: "eject_success_notif".localized, targetDisk)
                    self.showNotification(title: "notif_title".localized, text: text)
                    self.needsRefresh = true
                    self.asyncHotplugMonitor()
                }
            } else {
                // Б. Сценарий: Диск занят процессами. Выводим системное окно Force Eject
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "force_eject_title".localized
                    alert.informativeText = String(format: "force_eject_info".localized, targetDisk)
                    alert.addButton(withTitle: "force_button".localized)
                    alert.addButton(withTitle: "cancel_button".localized)
                    
                    // Если пользователь нажал кнопку "Принудительно"
                    if alert.runModal() == .alertFirstButtonReturn {
                        DispatchQueue.global(qos: .userInitiated).async {
                            let forceTask = Process()
                            forceTask.launchPath = "/bin/bash"
                            
                            // Посылаем unmountDisk force для жесткого закрытия всех хвостов системы
                            if let pwd = password {
                                forceTask.arguments = ["-c", "echo '\(pwd)' | sudo -S /usr/sbin/diskutil unmountDisk force \(targetDisk)"]
                            } else {
                                forceTask.arguments = ["-c", "osascript -e 'do shell script \"/usr/sbin/diskutil unmountDisk force \(targetDisk)\" with administrator privileges'"]
                            }
                            forceTask.launch()
                            forceTask.waitUntilExit()
                            
                            let isForceSuccess = (forceTask.terminationStatus == 0)
                            
                            DispatchQueue.main.async {
                                if isForceSuccess {
                                    let text = String(format: "eject_success_notif".localized, targetDisk)
                                    self.showNotification(title: "notif_title".localized, text: text)
                                } else {
                                    let text = String(format: "eject_error_notif".localized, targetDisk)
                                    self.showNotification(title: "notif_title".localized, text: text)
                                }
                                self.needsRefresh = true
                                self.asyncHotplugMonitor()
                            }
                        }
                    }
                }
            }
        }
    }
    
    @objc func changeLanguageToRussian() {
        LocalizationManager.shared.setLanguage(.russian)
        self.refreshMenu() // Перерисовываем интерфейс с новыми строками "на лету"
    }

    @objc func changeLanguageToEnglish() {
        LocalizationManager.shared.setLanguage(.english)
        self.refreshMenu() // Перерисовываем интерфейс с новыми строками "на лету"
    }

    func simulateEscapeKey() {
        // Создаем событие нажатия клавиши Esc (код 53)
        if let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true),
           let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false) {
            // Отправляем сигналы напрямую в системную очередь ввода
            eventDown.post(tap: .cghidEventTap)
            eventUp.post(tap: .cghidEventTap)
        }
    }
    
    @objc func manualUpdateCheck() {
        AppUpdater.checkForUpdates(silent: false)
    }
} // <--- ЗДЕСЬ ОКОНЧАТЕЛЬНО ЗАКРЫВАЕТСЯ КЛАСС APPDELEGATE

// =================================================================
// КЛАСС АВТООБНОВЛЕНИЯ
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
                            alert.messageText = "upd_not_needed_title".localized
                            alert.informativeText = String(format: "upd_not_needed_info".localized, currentVersion)
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
        alert.messageText = "upd_title".localized
        alert.informativeText = String(format: "upd_info".localized, version)
        alert.buttons[0].title = "upd_download".localized
        alert.buttons[1].title = "upd_later".localized

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(url)
            NSApplication.shared.terminate(nil)
        }
    }
}
