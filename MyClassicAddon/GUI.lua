local GUI = {}
GUI.__index = GUI

function DrawButton(parentFrame, name)
    local this = CreateFrame("Button", nil, parentFrame, "UIPanelButtonTemplate")
    this:SetSize(100, 15)
    this:SetPoint("TOPLEFT", lastUI, "BOTTOMLEFT", 0, -10)
    this:SetText(name)
    lastUI = this
    return this
end

function ActionButton(parentFrame, name, func)
    local button = DrawButton(parentFrame, name)
    button:SetScript("OnClick", func)
    return button
end

function DrawCheckBox(parentFrame, name, state)
    local this = CreateFrame("CheckButton", nil, parentFrame, "ChatConfigCheckButtonTemplate")
    this:SetPoint("TOPLEFT", lastUI, "BOTTOMLEFT", 0, -10)
    this:SetChecked(state)
    this.Text:SetText(name)
    lastUI = this
    return this
end

function Checkbox(parentFrame, name, state, func)
    local check = DrawCheckBox(parentFrame, name, state)
    return check
end