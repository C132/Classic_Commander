callbacks = {}

function AddListener(event, func)
    if not event then
        error("Event cannot be nil")
        return
    end
    
    if not func then
        error("Callback function cannot be nil") 
        return
    end

    --print("Adding listener for event '" .. tostring(event) .. "' with function " .. tostring(func))
    if not callbacks[event] then
        callbacks[event] = {}
    end
    table.insert(callbacks[event], func)
end

function Notify(event)
    if event and callbacks[event] then
        for _, func in ipairs(callbacks[event]) do
            func()
        end
    end
end