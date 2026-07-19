import Foundation
import LaunchAtLogin // Импортируем добавленный пакет

final class AutoStartManager {
    static let shared = AutoStartManager()
    
    // Проверка текущего статуса автозапуска
    var isEnabled: Bool {
        return LaunchAtLogin.isEnabled
    }
    
    // Включение или выключение автозапуска
    func setEnabled(_ newValue: Bool) {
        LaunchAtLogin.isEnabled = newValue
    }
}
