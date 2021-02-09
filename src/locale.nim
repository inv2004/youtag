import tables

const TAG_RUNES* = 4..20

type
  Locale* = enum Ru = "ru", En = "en"

const title* = "*YouTag*   -   Tag the World!"

const hello* = {
  En: """
Hello,
  The bot is for anonymous feedbacks using tags. It helps to send and collect anonymous feedbacks via tags.

*Forward* message from any user and *add* space or comma separated *tags* in text.

The user can check his tags without information about setter.
You can subscribe to new tags' notifications by /on command.

Tag length is from 4 to 25 characters.

Example:
  1) You just set tag "good-guy" to someone, someone else set the same tag for the guy
  2) The guy can see he's available anonymous tags and can make a conclusion about it
  3) In the future, if you meet someone you can check if you have set something on the guy

Use /help for help

""",
  Ru: """
Привет,
  Это бот для анонимных отзывов с использованием тегов. Он позволяет отправить кому-то тег и узнать теги поставленные вам.

*Отправьте* сообщение от любого пользователя этому боту, после чего ты можете *добавить теги*, разделяемые пробелами или запятыми, или же добавить "популярные" теги с помощью кнопок.

Пользователь может посмотреть свои теги, но не увидит информации о том кто их поставил.
Можно подписаться на нотификацию о новых тегах командой /on.

Длина тега от 4 до 25 символов.

Пример:
  1) Вы поставили кому-то тег "молодец", кто-то ещё ставит этот же тег ему тоже
  2) Пользователь делает вывод на основании анонимные тегов, которые достались ему
  3) В будущем, вы можете посмореть ставили ли вы теги комкретному пользователю

Используйте /help для помощи
"""
}.toTable

const help* = {
  En: """
Forward message from any user and add space- or comma-separated tags in text.

/help         - usage
/on           - you will receive notifications about new tags
/on interval  - enable nofifications with specific interval: 1m, 1h, 1d
/off          - disable notification (default)
/me           - show tags you marked with
/my           - show tags set by you
/id           - show tags you set for user (use /id in forwarded message only)
/id @username - show tags you set for the username
/top          - top tags and users
/top #[tag]   - top user's with the tag
/top @[user]  - top tag's for the user

""",
  Ru: """
Отправьте сообщение от любого пользователя и добавьте теги, разделённые запятыми или пробелами.

/help         - помощь
/on           - получать нотификации о новых тегах
/on interval  - информировать о тегах с переодичностью: 1m, 1h, 1d
/off          - отключить нотификации (режим по-умолчанию)
/me           - показать установленные вам теги
/my           - показать теги, которые установили вы
/id           - показать теги, которые вы поставили пользователю (работает только при пересылке сообщения от кого-то)
/id @username - показать теги, которые вы поставили этому пользователю
/top          - top тегов и их пользователей
/top #[tag]   - top пользователей по тегу
/top @[user]  - top тегов по пользователю

"""
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

const tagsForUser* = {
  En: "You have set following tags for the user: ",
  Ru: "Вы устанавливали следующие теги на этого пользователя: "
}.toTable

const noTagsForUser* = {
  En: "You have not set tags for the user yet",
  Ru: "Вы не устанавливали теги для этого пользователя"
}.toTable

const idUsage* = {
  En: "Use /id command after fowarded message from the user you want to check or use /id @username",
  Ru: "Используйте команду /id после того, как переслали сообщение от пользователя которого хотите проверить или /id @username"
}.toTable

const userTagsHelp* = {
  En: "\\* tags confirmed by someone else marked in bold",
  Ru: "\\* Теги, подтверждённые кем-то ещё, выделены болдом"
}.toTable

const forwardHelp* = {
  En: "Please forward message from user first",
  Ru: "Сначала перешлите сообщение от пользователя"
}.toTable

const onNote* = {
  En: "You just subscribed to tags' notification",
  Ru: "Вы подписались на нотификации о тегах"
}.toTable

const offNote* = {
  En: "You just turned tag's notifications off",
  Ru: "Вы отписались от нотификации"
}.toTable

