/// Built-in GoldED template shared by settings and message composition.
const defaultMessageTemplate = '''; Оформление пересылки
@Forward=============================================================================
@Forward* Forwarded by @CName (@CAddr)
@Forward* Area : @OEcho (@ODesc)
@Forward* From : @OName, @OAddr (@ODate @OTime)
@Forward* To   : @DName
@Forward* Subj : @Subject
@Forward=============================================================================
@Message
@Forward=============================================================================
@Forward

; Приветствие
Hello, @pseudo!
@New
@Position

; Ответ без цитаты
@ReplyReply to message from <@ODate>, @OName -> @DName:

; Ответ с цитатой
@Quoted@ODate @OTime, from @OName -> @DName:
@Quote

Best Regards, @CFName
''';
