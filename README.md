"# GasAlarm"
io口定义:
2:报警检测,高电平发送启动，低电平发送停止
3:配网按键，低电平有效，长按3秒
4:LED,高电平有效

消息池：
    每秒检测url池，池中有url时发送get请求，发送成功，从消息池中清除这条url，发送失败，重试5次，重试5次不成功，清空消息池。
    当设备处于配网状态时，消息池不能插入url。每过一小时，向上次url发送get请求，并将电量设为50。

更新日志:
    
    v1.00 2019-11-27:
        加入消息池机制。 