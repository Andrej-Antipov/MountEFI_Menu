<div align="center">

<!-- Иконка приложения -->
<img src="https://github.com/Andrej-Antipov/MountEFI_Menu/blob/78dbaa90e72e1d98d66d28ef0eb8067df46972d4/MountEFI%20Menu/MenuLogo.png" alt="MountEFI Menu Логотип" width="128" height="128">

<h1>💾 MountEFI Menu</h1>

<p><b>Нативное Swift-приложение для macOS, позволяющее монтировать разделы EFI прямо из строки меню в один клик</b></p>

<!-- Переключатель языков -->
<p>
  <a href="./README.md">English</a> • <b>Русский</b>
</p>

<!-- Бейджи проекта -->
<p>
  <img src="https://img.shields.io/badge/2.3%20Latest%20Release-8A2BE2" alt="Последний релиз 2.3">
  <img src="https://img.shields.io/badge/github-repo-swift?logo=github" alt="SWIFT">
  <img src="https://img.shields.io/badge/Apple-MacOS-blue" alt="Platform"> alt="MacOS">
  <img src="https://img.shields.io/badge/SWIFT-red" alt="License"> alt="MIT">
</p>

<h4>
  <a href="#-особенности">Особенности</a> •
  <a href="#-установка">Установка</a> •
  <a href="#-сборка-из-исходников">Сборка</a> •
  <a href="#-системные-требования">Требования</a>
</h4>

</div>

<hr />

## 📖 Описание

**MountEFI Menu** — это легковесная и быстрая утилита для macOS (включая Хакинтош), написанная на Swift. Приложение работает в фоне и доступно прямо из системного статус-бара (Menu Bar). Оно автоматически сканирует структуру накопителей и позволяет мгновенно монтировать скрытые ESP (EFI) разделы без использования Терминала и ручного ввода `diskutil list`.

> [!TIP]
> Приложение идеально подходит для постоянной работы с загрузчиками **OpenCore** и **Clover**, делая процесс настройки конфигурации максимально быстрым и нативным.

---

## ✨ Особенности

- 🍏 **Интеграция со строкой меню:** Утилита всегда под рукой, не занимает место в Dock-панели и активируется в один клик.
- ⚡ **Написано на Swift:** Работает молниеносно, запускается мгновенно и практически не потребляет ресурсы процессора и оперативную память.
- 🔍 **Автоматическое сканирование:** Самостоятельно обновляет список дисков при подключении или отключении внешних накопителей.
- 📁 **Быстрое открытие:** Автоматически открывает смонтированный раздел EFI в Finder сразу после успешного ввода пароля.
- 🔒 **Нативная безопасность:** Безопасный запрос привилегий `sudo` с использованием авторизационных диалоговых окон macOS.

---

## 📸 Скриншоты

<div align="center">
  <img src="https://github.com/Andrej-Antipov/MountEFI_Menu/blob/2f03aa122ea0350b80130efac4311ce072ab3e51/111.png" alt="Menu Bar Interface Preview" width="400">
  <img src="https://github.com/Andrej-Antipov/MountEFI_Menu/blob/2f03aa122ea0350b80130efac4311ce072ab3e51/222.png" alt="Menu Bar Interface Preview" width="400">
  <img src="https://github.com/Andrej-Antipov/MountEFI_Menu/blob/2f03aa122ea0350b80130efac4311ce072ab3e51/112.png" alt="Menu Bar Interface Preview" width="400">
</div>
---

## 🛠️ Установка

### Готовая сборка (Рекомендуется)
1. Перейдите в раздел **[Releases](https://github.com)**.
2. Скачайте архив `MountEFI-Menu.dmg` или `MountEFI-Menu.app.zip` последней версии.
3. Распакуйте архив и перетащите приложение в папку `/Applications` (Программы).
4. Запустите приложение. В строке меню macOS появится иконка диска.

> [!IMPORTANT]
> При первом запуске может потребоваться зайти в *Системные настройки -> Конфиденциальность и безопасность* и разрешить запуск приложения от стороннего разработчика (из-за отсутствия платной подписи Apple Developer).

---

## 🏗️ Сборка из исходников

Для самостоятельной сборки вам понадобятся установленный **Xcode** и инструменты командной строки.

```bash
# 1. Клонируйте репозиторий
git clone https://github.com
cd MountEFI-Menu

# 2. Откройте проект в Xcode
open MountEFI-Menu.xcodeproj

# 3. Соберите проект
# Внутри Xcode выберите: Product -> Build (или нажмите Cmd+B)
```

---

## 📋 Системные требования

- **Операционная система:** macOS 12.0 Monterey и новее
- **Архитектура:** Apple Silicon (M1/M2/M3/M4) & Intel (Universal Binary)
- **Права доступа:** Требуются права Администратора для выполнения системных команд монтирования.

---

## 📄 Лицензия

Этот проект распространяется под лицензией **MIT**. Подробности в файле [LICENSE](LICENSE).

<hr />

<div align="center">
  Создано с ❤️ для macOS сообщества • <a href="https://github.com">@ваше_имя</a>
</div>
