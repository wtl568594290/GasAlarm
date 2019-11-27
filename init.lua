--io:2 warning,3 key,4 led
pinWarning_G = 2
gpio.write(pinWarning_G, gpio.LOW)
gpio.mode(pinWarning_G, gpio.INT)
gpio.mode(pinWarning_G, gpio.INPUT)

pinKey_G = 3
gpio.write(pinKey_G, gpio.HIGH)
gpio.mode(pinKey_G, gpio.INT)
gpio.mode(pinKey_G, gpio.INPUT)

pinLed_G = 4
gpio.write(pinLed_G, gpio.HIGH)
gpio.mode(pinLed_G, gpio.OUTPUT)
--led blink
--high:light,low:black
--type:1-short blink,2-long blink,3-blink 3,4-long light
function ledBlink(type)
    type = type == nil and 1 or type
    local array = {200 * 1000, 200 * 1000}
    if type == 2 then
        array = {500 * 1000, 1000 * 1000}
    end
    local cycle = 100
    if type == 3 then
        cycle = 3
    elseif type == 4 then
        cycle = 1
    end
    gpio.serout(
        pinLed_G,
        gpio.LOW,
        array,
        cycle,
        function()
            if type == 1 then
                ledBlink(1)
            elseif type == 2 then
                ledBlink(2)
            end
        end
    )
end

--insert url
deviceCode_G = string.upper(string.gsub(wifi.sta.getmac(), ":", ""))
action_G, actionStart_G, actionStop_G, quantityNormal, quantityCycle = "053", "052", "053", 100, 50
function insertURL(quantity)
    if not isConfigRun_G then
        local url =
            string.format(
            "http://www.zhihuiyanglao.com/gateMagnetController.do?gateDeviceRecord&deviceCode=%s&actionType=%s&warningType=0&quantity=%s",
            deviceCode_G,
            action_G,
            quantity
        )
        table.insert(urlList_G, url)
    end
end
--wifi init
wifi.setmode(wifi.STATION)
wifi.sta.autoconnect(1)
wifi.sta.sleeptype(wifi.MODEM_SLEEP)

wifi.eventmon.register(
    wifi.eventmon.STA_GOT_IP,
    function(T)
        print("wifi is connected,ip is " .. T.IP)
        ledBlink(4)
        insertURL(quantityCycle)
    end
)

wifi.eventmon.register(
    wifi.eventmon.STA_DISCONNECTED,
    function(T)
        print("STA - DISCONNECTED")
        if not isConfigRun_G then
            ledBlink(2)
        end
    end
)

--config net
function configNet()
    if not isConfigRun_G then
        isConfigRun_G = true
        --start config
        print("start config net...")
        configTmr = tmr.create()
        configTmr:register(
            1000 * 60,
            tmr.ALARM_SINGLE,
            function()
                if isConfigRun_G then
                    print("stop config net...")
                    ledBlink(2)
                    wifi.stopsmart()
                    isConfigRun_G = nil
                end
            end
        )
        configTmr:start()
        wifi.startsmart(
            function()
                print("config net success...")
                isConfigRun_G = nil
                configTmr:stop()
            end
        )
        ledBlink()
    end
end

--Boot without wifi boot configuration
do
    local ssid = wifi.sta.getconfig()
    if ssid == "" or ssid == nil then
        configNet()
    end
end

-----------------
-- get request
urlList_G = {}
ready_G = true
tryCount_G = 0
wakeCount_G = 0
tmr.create():alarm(
    1000,
    tmr.ALARM_AUTO,
    function()
        if #urlList_G > 0 then
            wakeCount_G = 0
            if ready_G then
                tryCount_G = tryCount_G + 1
                if tryCount_G <= 5 then
                    if wifi.sta.status() == wifi.STA_GOTIP then
                        ready_G = false
                        http.get(
                            urlList_G[1],
                            nil,
                            function(code)
                                print(code)
                                if code > 0 then
                                    table.remove(urlList_G, 1)
                                    tryCount_G = 0
                                end
                                ready_G = true
                            end
                        )
                    end
                else
                    urlList_G = {}
                    tryCount_G = 0
                end
            end
        else
            wakeCount_G = wakeCount_G + 1
            if wakeCount_G == 60 * 60 then
                insertURL(quantityCycle)
            end
        end
    end
)
--warning interrupt
function warningcb(level)
    if level == gpio.HIGH then
        print("start warning...")
        action_G = actionStart_G
    else
        print("stop waring...")
        action_G = actionStop_G
    end
    insertURL(quantityNormal)
    gpio.trig(pinWarning_G, level == gpio.HIGH and "low" or "high")
end
gpio.trig(pinWarning_G, "high", warningcb)

--key press
do
    local function keyPress()
        print("key long press")
        configNet()
    end
    local function keyPresscb()
        gpio.trig(pinKey_G)
        keyCount_G = 0
        tmr:create():alarm(
            100,
            tmr.ALARM_AUTO,
            function(timer)
                if gpio.read(pinKey_G) == gpio.LOW then
                    keyCount_G = keyCount_G + 1
                    if keyCount_G == 30 then
                        keyPress()
                    end
                else
                    timer:unregister()
                    keyCount_G = 0
                    gpio.trig(pinKey_G, "down", keyPresscb)
                end
            end
        )
    end
    gpio.trig(pinKey_G, "down", keyPresscb)
end
--welcome
VERSION = 1.00
print("ranqi version = " .. VERSION)
