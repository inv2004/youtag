import tables

const TAG_RUNES* = 4..20

type
  Locale* = enum Ru = "ru", En = "en"

const title* = "YouTag   -   Tag the World!"

const hello* = {
  En: """
Hello,
  The bot helps to collect anonymous feedbacks across the internet and classify users

*Forward* message from any user and *add* space or comma separated *tags* in text.

The user can check his tags without information about setter.

Tag length is from 4 to 25 characters.

Use /help for help

""",
  Ru: """
Привет,
  Этот бот позволяет узнать теги, которые другие пользователи могут поставить вам анонимно.

*Отправьте* сообщение от любого пользователя этому боту, после чего ты можете *добавить теги*, разделяемые пробелами или запятыми, или же добавить "популярные" теги с помощью кнопок.

Пользователь может провить свои теги, но не увидит информации о том кто его поставил.

Длина тега от 4 до 25 символов.

Используйте /help для помощи
"""
}.toTable

const help* = {
  En: """
Forward message from any user and add space- or comma-separated tags in text.

/help        - usage
/me          - show tags you marked with
/my          - show tags set by you
/top         - top tags and users
/top #[tag]  - top user's with the tag
/top @[user] - top tag's for the user

""",
  Ru: """
Отправьте сообщение от любого пользователя и добавьте теги, разделённые запятыми или пробелами.

/help        - помощь
/me          - показать установленные вам теги
/my          - показать теги, которые установили вы
/top         - top тегов и их пользователей
/top #[tag]  - top пользователей по тегу
/top @[user] - top тегов по пользователю

help"""
}.toTable

const stopped* = {
  En: "stopped",
  Ru: "Спасибо, приходите ещё"
}.toTable

const top* = {
  En: "This command is temporary disabled due to the toxicity of IT community",
  Ru: "Команда временно отключена для избежания токсичности"
}.toTable

const unknown* = {
  En: "Unknown command, check /help please",
  Ru: "Неизвестная команда, используйте /help для помощи"
}.toTable

const tag* = {
  En: "You can add more tags manually or use the following trending tags buttons:",
  Ru: """Вы поможете ввести теги в сообщении или использовать кнопки популярных тегов:"""
}.toTable

const done* = {
  En: "Done",
  Ru: "Готово"
}.toTable

const found* = {
  En: "BTW, We just found that someone has set tags on you already, you can check it with /me command",
  Ru: "Между прочим, кто-то уже посватил вам теги, вы можете проверить их командой /me"
}.toTable

const protected* = {
  En: "The user is protected by her(his) privacy settings",
  Ru: "Настройки пользователя не позволяют идентифицировать его сообщения"
}.toTable

const wrong* = {
  En: "The following tags are not set (tag len is from " & $TAG_RUNES.a & " to " & $TAG_RUNES.b & " characters):",
  Ru: "Данные теги не установлены (длина тега от " & $TAG_RUNES.a & " до " & $TAG_RUNES.b & " символов):"
}.toTable
