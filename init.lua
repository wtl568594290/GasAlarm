--io:2 warning,3 key,4 led
warningPin = 2
gpio.write(warningPin, gpio.LOW)
gpio.mode(warningPin, gpio.INPUT)

keyPin = 3
gpio.write(keyPin, gpio.HIGH)
gpio.mode(keyPin, gpio.INPUT)

ledPin = 4
gpio.write(ledPin, gpio.HIGH)
gpio.mode(ledPin, gpio.OUTPUT)
--led blink
--high:light,low:black
--type:1-short blink,2-long blink,3-blink 3,4-long light

function ledBlink(type)
    type = type == nil and 1 or type
    local array = {200 * 1000, 200 * 1000}
    if type == 2 then
        array = {1000 * 1000, 500 * 1000}
    end
    local cycle = 100
    if type == 3 then
        cycle = 3
    elseif type == 4 then
        cycle = 1
    end
    gpio.serout(
        ledPin,
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

--json decode
function decode(str)
    local function local_decode(local_str)
        local json = sjson.decode(local_str)
        return json
    end
    local status, result = pcall(local_decode, str)
    if status then
        return result
    else
        return nil
    end
end

--http get,sending led blink
deviceCode = string.upper(string.gsub(wifi.sta.getmac(), ":", ""))
actionStart, actionStop, quantityNormal, quantityCycle = "052", "053", "100", "50"
function get(actionType, quantity)
    local url =
        string.format(
        "http://www.zhihuiyanglao.com/gateMagnetController.do?gateDeviceRecord&deviceCode=%s&actionType=%s&warningType=0&quantity=%s",
        deviceCode,
        actionType,
        quantity
    )
    local tryAgain = 0
    local function localGet(url)
        -- --blink 3 times
        ledBlink(3)
        http.get(
            url,
            nil,
            function(code, data)
                if code == 200 then
                    local json = decode(data)
                    if json then
                        if json.isSuc == "1" then
                            print("operate success")
                        else
                            print("operate failed")
                        end
                    else
                        print("no json")
                    end
                else
                    if tryAgain < 5 then
                        tmr:create():alarm(
                            1000,
                            tmr.ALARM_SINGLE,
                            function()
                                localGet(url)
                            end
                        )
                    end
                    tryAgain = tryAgain + 1
                    print("get error")
                end
            end
        )
    end
    localGet(url)
    --1h last get again
    if getHourAgainTmr then
        getHourAgainTmr:unregister()
        getHourAgainTmr = nil
    end
    againCount = 0
    getHourAgainTmr = tmr.create()
    getHourAgainTmr:alarm(
        1000 * 60,
        tmr.ALARM_AUTO,
        function(timer)
            againCount = againCount + 1
            if againCount >= 60 then
                if gpio.read(2) == gpio.LOW then
                    get(actionStop, quantityCycle)
                else
                    get(actionStart, quantityNormal)
                end
                againCount = 0
            end
        end
    )
end

--wifi init
--configRunningFlag: wifi config is running ,disconnected register don't blink
wifi.setmode(wifi.STATION)
wifi.sta.sleeptype(wifi.MODEM_SLEEP)

wifi.eventmon.register(
    wifi.eventmon.STA_GOT_IP,
    function(T)
        ledBlink(4)
        if gpio.read(2) == gpio.LOW then
            get(actionStop, quantityCycle)
        else
            get(actionStart, quantityNormal)
        end
        print("wifi is connected,ip is " .. T.IP)
    end
)

wifi.eventmon.register(
    wifi.eventmon.STA_DISCONNECTED,
    function(T)
        print("\n\tSTA - DISCONNECTED" .. "\n\t\reason: " .. T.reason)
        --Set disconnected_flag to prevent repeated calls
        if not configRunningFlag then
            ledBlink(2)
        end
    end
)

--wifi configuration
function startConfig()
    if not configRunningFlag then
        configRunningFlag = true
        --60s last reload ssid and pwd
        configTmr = tmr.create()
        configTmr:alarm(
            60 * 1000,
            tmr.ALARM_SINGLE,
            function()
                print("after 60s....")
                if configRunningFlag then
                    ledBlink(4)
                    configRunningFlag = nil
                    wifi.stopsmart()
                end
            end
        )
        --start config
        wifi.stopsmart()
        wifi.startsmart(
            function()
                print("wifi config success")
                configRunningFlag = nil
                print("remove 60s tmr")
                configTmr:unregister()
                configTmr = nil
            end
        )
        ledBlink()
    end
end
--Boot without wifi boot configuration
do
    local ssid = wifi.sta.getconfig()
    if ssid == "" or ssid == nil then
        startConfig()
    end
end

--interrupt
function warningStart()
    print("warning...")
    get(actionStart, quantityNormal)
end

function warningStop()
    print("warning stop")
    get(actionStop, quantityNormal)
end

gpio.trig(
    warningPin,
    "up",
    function(level)
        if not warningFlag then
            warningFlag = true
            local warningCount = 0
            local warningHas = false
            tmr:create():alarm(
                20,
                tmr.ALARM_AUTO,
                function(timer)
                    if gpio.read(warningPin) == gpio.HIGH then
                        warningCount = warningCount + 1
                        if warningCount == 25 then
                            warningHas = true
                            warningStart()
                        end
                    else
                        if warningHas then
                            warningStop()
                        end
                        warningFlag = nil
                        timer:unregister()
                    end
                end
            )
        end
    end
)

--key press
function keyPress()
    print("key press")
    startConfig()
end

gpio.trig(
    keyPin,
    "down",
    function()
        if not keyCheckFlag then
            keyCheckFlag = true
            local keyLongPressCount = 0
            tmr:create():alarm(
                20,
                tmr.ALARM_AUTO,
                function(timer)
                    if gpio.read(keyPin) == gpio.LOW then
                        keyLongPressCount = keyLongPressCount + 1
                        if keyLongPressCount == 150 then
                            keyPress()
                        end
                    else
                        timer:unregister()
                        keyCheckFlag = nil
                    end
                end
            )
        end
    end
)
