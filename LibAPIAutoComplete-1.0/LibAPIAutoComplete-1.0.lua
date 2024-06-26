local MAJOR, MINOR = "LibAPIAutoComplete-1.0", 3
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local SharedMedia = LibStub("LibSharedMedia-3.0")

local config = {}

local function LoadBlizzard_APIDocumentation()
  local apiAddonName = "Blizzard_APIDocumentation"
  local _, loaded = C_AddOns.IsAddOnLoaded(apiAddonName)
  if not loaded then
    C_AddOns.LoadAddOn(apiAddonName)
  end
  if #APIDocumentation.systems == 0 then
    APIDocumentation_LoadUI()
  end
end

---Create APIDoc widget and ensure Blizzard_APIDocumentation is loaded
local isInit = false
local function Init()
  if isInit then
    return
  end
  isInit = true

  -- load Blizzard_APIDocumentation
  LoadBlizzard_APIDocumentation()

  local scrollBox = CreateFrame("Frame", nil, UIParent, "WowScrollBoxList")
  scrollBox:SetSize(400, 150)
  scrollBox:Hide()

  local background = scrollBox:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  scrollBox.background = background

  local scrollBar = CreateFrame("EventFrame", nil, UIParent, "WowTrimScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT")
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT")
  scrollBar:Hide()

  local view = CreateScrollBoxListLinearView()
  view:SetElementExtentCalculator(function(dataIndex, elementData)
    return 20
  end)
  view:SetElementInitializer("button", function(frame, elementData)
    Mixin(frame, APIAutoCompleteLineMixin)
    frame:Init(elementData)
  end)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
  local selectionBehaviour = ScrollUtil.AddSelectionBehavior(scrollBox, SelectionBehaviorFlags.Deselectable, SelectionBehaviorFlags.Intrusive)
  selectionBehaviour:RegisterCallback(SelectionBehaviorMixin.Event.OnSelectionChanged, function(o, elementData, selected)
    local elementFrame = scrollBox:FindFrame(elementData)
    if elementFrame then
      elementFrame:SetSelected(selected)
    end

    if selected and lib.editbox and config[lib.editbox] then
      local maxLinesShown = config[lib.editbox].maxLinesShown
      local index = lib.data:FindIndex(elementData)
      local divisor = lib.data:GetSize() - maxLinesShown
      if divisor == 0 then
        divisor = 1
      end
      local percent = (index - maxLinesShown / 2) / divisor
      if percent < 0 then
        percent = 0
      elseif percent > 1 then
        percent = 1
      end
      scrollBar:SetScrollPercentage(percent)
    end
  end)

  lib.data = CreateDataProvider()
  scrollBox:SetDataProvider(lib.data)

  lib.scrollBar = scrollBar
  lib.scrollBox = scrollBox
  lib.selectionBehaviour = selectionBehaviour

  scrollBox.selectionBehaviour = selectionBehaviour

  scrollBox:SetScript("OnKeyDown", function(self, key)
    if key == "DOWN" then
      lib.scrollBox:SetPropagateKeyboardInput(false)
      self.selectionBehaviour:SelectNextElementData()
    elseif key == "UP" then
      self.selectionBehaviour:SelectPreviousElementData()
    elseif key == "ENTER" then
      lib.scrollBox:SetPropagateKeyboardInput(false)
      local selectedElementData = self.selectionBehaviour:GetFirstSelectedElementData()
      local elementFrame = scrollBox:FindFrame(selectedElementData)
      elementFrame:Insert()
    elseif key == "ESCAPE" then
      lib.scrollBox:SetPropagateKeyboardInput(false)
      lib.data:Flush()
      lib:UpdateWidget(lib.editbox)
    else
      lib.scrollBox:SetPropagateKeyboardInput(true)
      lib.data:Flush()
      lib:UpdateWidget(lib.editbox)
    end
  end)
end

local lastPosition

---@private
---@param editbox EditBox
---@param x number
---@param y number
---@param w number
---@param h number
local function OnCursorChanged(editbox, x, y, w, h)
  local cursorPosition = editbox:GetCursorPosition()
  if cursorPosition ~= lastPosition then
    lib.scrollBox:Hide()
    lib.scrollBar:Hide()
    lib.scrollBox:ClearAllPoints()
    lib.scrollBox:SetPoint("TOPLEFT", editbox, "TOPLEFT", x, y - h)
    local currentWord = lib:GetWord(editbox)
    if #currentWord > 4 then
      lib:Search(currentWord, config[editbox])
      lib:UpdateWidget(editbox)
    end
  end
  lastPosition = cursorPosition
end

---@class Color
---@field r integer
---@field g integer
---@field b integer
---@field a integer?

---@class Params
---@field backgroundColor Color?
---@field maxLinesShown integer?
---@field disableFunctions boolean?
---@field disableEvents boolean?
---@field disableSystems boolean?

---Enable APIDoc widget on editbox
---ForAllIndentsAndPurpose replace GetText, APIDoc must be enabled before FAIAP
---@param editbox EditBox
---@param params Params
function lib:enable(editbox, params)
  if config[editbox] then
    return
  end
  config[editbox] = {
    backgroundColor = params and params.backgroundColor or {.3, .3, .3, .9},
    maxLinesShown = params and params.maxLinesShown or 7,
    disableFunctions = params and params.disableFunctions or false,
    disableEvents = params and params.disableEvents or false,
    disableSystems = params and params.disableSystems or false,
  }
  Init()
  editbox.APIDoc_oldOnCursorChanged = editbox:GetScript("OnCursorChanged")
  -- hack for WeakAuras
  editbox.APIDoc_originalGetText = editbox.GetText
  -- hack for WowLua
  if editbox == WowLuaFrameEditBox then
    editbox.APIDoc_originalGetText = function()
      return WowLua.indent.coloredGetText(editbox)
    end
  end
  editbox:SetScript("OnCursorChanged", function(...)
    editbox.APIDoc_oldOnCursorChanged(...)
    OnCursorChanged(...)
  end)
  editbox.APIDoc_hiddenString = editbox:CreateFontString()
end

---Disable APIDoc widget on editbox
---@param editbox EditBox
function lib:disable(editbox)
  if not config[editbox] then
    return
  end
  config[editbox] = nil
  editbox:SetScript("OnCursorChanged", editbox.APIDoc_oldOnCursorChanged)
  editbox.APIDoc_oldOnCursorChanged = nil
end

function lib:addLine(apiInfo)
  local name
  if apiInfo.Type == "System" then
    name = apiInfo.Namespace
  elseif apiInfo.Type == "Function" then
    name = apiInfo:GetFullName()
  elseif apiInfo.Type == "Event" then
    name = apiInfo.LiteralName
  end
  self.data:Insert({ name = name, apiInfo = apiInfo })
end

---Search a word in documentation, set results in lib.data
---@param word string
---@param config Params
function lib:Search(word, config)
  self.data:Flush()
  if word and #word > 3 then
    local lowerWord = word:lower();
    local nsName, rest = lowerWord:match("^([%w%_]+)(.*)")
    local funcName = rest and rest:match("^%.([%w%_]+)")
    for _, systemInfo in ipairs(APIDocumentation.systems) do
      local systemMatch = (not config.disableSystems)
        and (nsName and #nsName >= 4)
        and (systemInfo.Namespace and systemInfo.Namespace:lower():match(nsName))

      if not config.disableFunctions then
        for _, apiInfo in ipairs(systemInfo.Functions) do
          if systemMatch then
            if funcName then
              if apiInfo:MatchesSearchString(funcName) then
                self:addLine(apiInfo)
              end
            else
              self:addLine(apiInfo)
            end
          else
            if apiInfo:MatchesSearchString(lowerWord) then
              self:addLine(apiInfo)
            end
          end
        end
      end

      if not config.disableEvents then
        if systemMatch and rest == "" then
          for _, apiInfo in ipairs(systemInfo.Events) do
            self:addLine(apiInfo)
          end
        else
          for _, apiInfo in ipairs(systemInfo.Events) do
            if apiInfo:MatchesSearchString(lowerWord) then
              self:addLine(apiInfo)
            end
          end
        end
      end
    end
  end
end

---set in lib.data the list of systems
function lib:ListSystems()
  self.data:Flush()
  for i, systemInfo in ipairs(APIDocumentation.systems) do
    if systemInfo.Namespace and #systemInfo.Functions > 0 then
      self:addLine(systemInfo)
    end
  end
end

---Hide, or Show and fill APIDoc widget, using lib.data data
---@param editbox EditBox
function lib:UpdateWidget(editbox)
  if self.data:IsEmpty() then
    self.scrollBox:Hide()
    self.scrollBar:Hide()
    self.editbox = nil
  else
    -- fix size
    local maxLinesShown = config[editbox].maxLinesShown
    local lines = self.data:GetSize()
    local height = math.min(lines, maxLinesShown) * 20
    local width = 0
    local hiddenString = editbox.APIDoc_hiddenString
    local fontPath = SharedMedia:Fetch("font", "Fira Mono Medium")
    hiddenString:SetFont(fontPath, 12, "")
    for _, elementData in self.data:Enumerate() do
      hiddenString:SetText(elementData.name)
      width = math.max(width, hiddenString:GetStringWidth())
    end
    self.scrollBox:SetSize(width, height)

    -- fix look
    local backgroundColor = config[editbox].backgroundColor
    self.scrollBox.background:SetColorTexture(unpack(backgroundColor))

    -- show
    self.scrollBox:SetParent(UIParent)
    self.scrollBar:SetParent(UIParent)
    self.scrollBox:SetFrameStrata("TOOLTIP")
    self.scrollBar:SetFrameStrata("TOOLTIP")
    self.scrollBox:Show()
    self.scrollBar:SetShown(lines > maxLinesShown)
    self.selectionBehaviour:SelectFirstElementData()
    self.editbox = editbox
  end
end

local function OnClickCallback(self)
  local name
  if IndentationLib then
    name = IndentationLib.stripWowColors(self.name)
  elseif WowLua and WowLua.indent then
    name = WowLua.indent.stripWowColors(self.name)
  end
  lib:SetWord(lib.editbox, name)
end

---@param editbox EditBox
---@return string currentWord
---@return integer startPosition
---@return integer endPosition
function lib:GetWord(editbox)
  -- get cursor position
  local cursorPosition = editbox:GetCursorPosition()
  local text = editbox:APIDoc_originalGetText()
  if IndentationLib then
    text, cursorPosition = IndentationLib.stripWowColorsWithPos(text, cursorPosition)
  end

  -- get start position of current word
  local startPosition = cursorPosition
  while startPosition - 1 > 0 and text:sub(startPosition - 1, startPosition - 1):find("[%w%.%_]") do
    startPosition = startPosition - 1
  end

  -- get end position of current word
  local endPosition = startPosition
  while endPosition + 1 < #text and text:sub(endPosition + 1, endPosition + 1):find("[%w%.%_]") do
    endPosition = endPosition + 1
  end

  local nextChar = text:sub(cursorPosition, cursorPosition)
  if nextChar ~= "" and nextChar ~= " " and nextChar ~= "\n" then
    return "", nil, nil
  end

  local currentWord = text:sub(startPosition, endPosition)
  return currentWord, startPosition, endPosition
end

---@param editbox EditBox
---@param word string
function lib:SetWord(editbox, word)
  -- get cursor position
  local cursorPosition = editbox:GetCursorPosition()
  local text = editbox:APIDoc_originalGetText()
  if IndentationLib then
    text, cursorPosition = IndentationLib.stripWowColorsWithPos(text, cursorPosition)
  end

  -- get start position of current word
  local startPosition = cursorPosition
  while startPosition > 0 and text:sub(startPosition - 1, startPosition - 1):find("[%w%.%_]") do
    startPosition = startPosition - 1
  end

  -- get end position of current word
  local endPosition = startPosition
  while endPosition + 1 < #text and text:sub(endPosition + 1, endPosition + 1):find("[%w%.%_]") do
    endPosition = endPosition + 1
  end

  -- check if replacement word looks like a function and has args
  local funcName, argsString = word:match("([%w%.%_]+)%(([%w%.%_,\"%s]*)%)")
  local funcArgs = {}
  if funcName and argsString then
    for arg in argsString:gmatch("([%w%.%_\"]+),?") do
      table.insert(funcArgs, arg)
    end
  end

  -- check if current word has parentheses and args
  local oldFuncArgs = {}
  if funcName then
    local currentWordArgs = text:sub(endPosition + 1, #text):match("^%(([%w%.%_,\"%s]*)%)")
    if currentWordArgs then
      for arg in currentWordArgs:gmatch("([%w%.%_\"]+),?") do
        table.insert(oldFuncArgs, arg)
      end
      -- move endPosition
      endPosition = endPosition + #currentWordArgs + 2
    end
  end

  -- replace replacement word's args with args from current word
  if funcName then
    local concatArgs = {}
    for i = 1, math.max(#funcArgs, #oldFuncArgs) do
      concatArgs[i] = oldFuncArgs[i] or funcArgs[i]
    end
    word = funcName .. "(" .. table.concat(concatArgs, ", ") .. ")"
  end

  -- replace word
  text = text:sub(1, startPosition - 1) .. word .. text:sub(endPosition + 1, #text)
  editbox:SetText(text)

  -- move cursor at end of word or start of parenthese
  local parenthesePosition = word:find("%(")
  editbox:SetCursorPosition(startPosition - 1 + (parenthesePosition or #word))
end

local function showTooltip(self)
  if self.apiInfo then
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT", 20, 20)
    GameTooltip:ClearLines()
    for _, line in ipairs(self.apiInfo:GetDetailedOutputLines()) do
      GameTooltip:AddLine(line)
    end
    GameTooltip:Show()
  end
end

local function hideTooltip(self)
  GameTooltip:Hide()
  GameTooltip:ClearLines()
end

APIAutoCompleteLineMixin = {}
function APIAutoCompleteLineMixin:Init(elementData)
  self.name = elementData.name
  self.apiInfo = elementData.apiInfo
  self:SetText(elementData.name)
  self:SetScript("OnClick", OnClickCallback)
  self:SetScript("OnEnter", showTooltip)
  self:SetScript("OnLeave", hideTooltip)
  local fontString = self:GetFontString()
  fontString:ClearAllPoints()
  local fontPath = SharedMedia:Fetch("font", "Fira Mono Medium")
  fontString:SetFont(fontPath, 12, "")
  fontString:SetPoint("LEFT")
  fontString:SetTextColor(0.973, 0.902, 0.581)
  if not self:GetHighlightTexture() then
    local texture = self:CreateTexture()
    texture:SetColorTexture(0.4,0.4,0.4,0.5)
    texture:SetAllPoints()
    self:SetHighlightTexture(texture)
  end
  self:SetSelected(false)
end

function APIAutoCompleteLineMixin:SetSelected(selected)
  self:SetHighlightLocked(selected)
end

function APIAutoCompleteLineMixin:Insert()
  OnClickCallback(self)
end
