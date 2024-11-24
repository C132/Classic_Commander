callbacks = {}

function AddListener(event, func)
    print("Adding Listener for event '" .. event .. "' with function " .. tostring(func))
    if not event then return end
    if not callbacks[event] then
        callbacks[event] = {}
    end
    table.insert(callbacks[event], func)
end

function Notify(event)
    print("Raising event: " .. event)
    if event and callbacks[event] then
        for _, func in ipairs(callbacks[event]) do
            func()
        end
    end
end