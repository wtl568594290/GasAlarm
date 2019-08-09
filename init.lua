--io:2 warning,3 key,4 led
--led blink
--high:light,low:black
--type:1-short blink,2-long blink,3-blink 3,4-long light
ledPin = 4
gpio.mode(ledPin, gpio.OUTPUT)
gpio.write(ledPin, gpio.HIGH)
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
function get(actionType, warningType, quantity)
    local url =
        string.format(
        "http://www.zhihuiyanglao.com/gateMagnetController.do?gateDeviceRecord&deviceCode=%s&actionType=%s&warningType=%s&quantity=%s",
        deviceCode,
        actionType,
        warningType,
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
    --8h last get again
    lastActionType = actionType
    lastWarningType = warningType
    if get8AgainTmr then
        get8AgainTmr:unregister()
        get8AgainTmr = nil
    end
    againCount = 0
    get8AgainTmr = tmr.create()
    get8AgainTmr:alarm(
        1000 * 60 * 60,
        tmr.ALARM_AUTO,
        function(timer)
            againCount = againCount + 1
            if againCount == 8 then
                if lastActionType and lastWarningType then
                    get(lastActionType, lastWarningType, "100")
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
    if wifi.getmode() ~= wifi.STATIONAP and configRunningFlag == nil then
        configRunningFlag = true
        --save last config
        last_ssid, last_pwd = wifi.sta.getconfig()
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
                    enduser_setup.stop()
                    if last_ssid ~= nil then
                        wifi.sta.config({ssid = last_ssid, pwd = last_pwd})
                    end
                end
            end
        )
        --start config
        wifi.sta.clearconfig()
        wifi.sta.autoconnect(1)
        enduser_setup.start(
            function()
                print("wifi config success")
                configRunningFlag = nil
                --wifi config end,send a GET
                get("053", "0", "50")
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
function warning()
    print("warning...")
    get("052", "0", "100")
end

function endCheck(hasWarning)
    print("check end")
    if hasWarning then
        get("053", "0", "100")
    end
end

interPin = 2
gpio.mode(interPin, gpio.INPUT)
gpio.trig(
    interPin,
    "up",
    function(level)
        if not interCheckFlag then
            interCheckFlag = true
            local warning_flag = false
            local high_level_count = 0
            tmr:create():alarm(
                20,
                tmr.ALARM_AUTO,
                function(timer)
                    if gpio.read(interPin) == gpio.HIGH then
                        high_level_count = high_level_count + 1
                    else
                        interCheckFlag = nil
                        endCheck(warning_flag)
                        timer:unregister()
                    end
                    if not warning_flag and high_level_count > 25 then
                        warning_flag = true
                        warning()
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

keyPin = 3
gpio.mode(keyPin, gpio.INPUT)
gpio.trig(
    keyPin,
    "down",
    function()
        if not keyCheckFlag then
            keyCheckFlag = true
            local key_long_press_count = 0
            tmr:create():alarm(
                20,
                tmr.ALARM_AUTO,
                function(timer)
                    if key_long_press_count == 150 then
                        keyPress()
                    end
                    if gpio.read(keyPin) == gpio.LOW then
                        key_long_press_count = key_long_press_count + 1
                    else
                        timer:unregister()
                        keyCheckFlag = nil
                    end
                end
            )
        end
    end
)
