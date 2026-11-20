local _, ns = ...

local WHITE_TEX = "Interface\\Buttons\\WHITE8x8"
local BACKDROP = { bgFile = WHITE_TEX, edgeFile = WHITE_TEX, edgeSize = 1 }

local VISIBLE_ROWS = 16
local ROW_HEIGHT = 24
local WINDOW_WIDTH = 660
local WINDOW_HEIGHT = 512

local scannerFrame = nil
local allEntries = {}
local filteredEntries = {}
local scrollOffset = 0
local liveScanRequestID = 0
local scanStats = { learned = 0, priced = 0, profName = "Profession", updatedAt = "", statusNote = nil }

local function IsAuctionHouseOpen()
  return (AuctionHouseFrame and AuctionHouseFrame:IsShown())
    or (AuctionFrame and AuctionFrame:IsShown())
end

local function FormatPriceAge(age)
  if age == nil then
    return "|cffffaa00Unknown|r"
  elseif age == 0 then
    return "|cff40ff40Today|r"
  elseif age == 1 then
    return "|cffffffff1 day ago|r"
  elseif age > 7 then
    return string.format("|cffff6644%d days ago (stale)|r", age)
  else
    return string.format("|cffffcc66%d days ago|r", age)
  end
end

local function SetFlatBackdrop(frame, bg, border)
  frame:SetBackdrop(BACKDROP)
  frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
  frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function GetCurrentProfessionName()
  if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
    local info = C_TradeSkillUI.GetBaseProfessionInfo()
    if type(info) == "table" then
      if info.professionName and info.professionName ~= "" then
        return info.professionName
      end
      if info.parentProfessionName and info.parentProfessionName ~= "" then
        return info.parentProfessionName
      end
    end
  end
  return "Profession"
end

local function ScanLearnedRecipes()
  allEntries = {}
  scanStats.learned = 0
  scanStats.priced = 0
  scanStats.profName = GetCurrentProfessionName()
  scanStats.updatedAt = date("%H:%M:%S")

  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo and T.GetRecipeSchematic) then
    return
  end

  local ids = T.GetAllRecipeIDs()
  if type(ids) ~= "table" then
    return
  end

  for _, recipeID in ipairs(ids) do
    local recipeInfo = T.GetRecipeInfo(recipeID)
    if type(recipeInfo) == "table" and recipeInfo.learned then
      scanStats.learned = scanStats.learned + 1

      local ok, recipeSchematic = pcall(T.GetRecipeSchematic, recipeID, false)
      if ok and type(recipeSchematic) == "table" and recipeSchematic.reagentSlotSchematics and #recipeSchematic.reagentSlotSchematics > 0 then
        local currentAH, age, anyPrice, exact, extraMissingCost, extraFullCost = ns.GetOutputAHInfo(recipeInfo, recipeSchematic, nil)
        if currentAH and currentAH > 0 then
          scanStats.priced = scanStats.priced + 1

          local missingCost, fullCost, breakdown, ownedUnits, totalUnits, hasUnknownMissingPrice, hasUnknownFullPrice = ns.CalculateCosts(recipeSchematic, nil)
          local effectiveMissing = missingCost + (extraMissingCost or 0)
          local effectiveFull = fullCost + (extraFullCost or 0)
          local count = recipeSchematic.quantityMin or 1
          local cashProfit = ns.CalculateProfit(currentAH, effectiveMissing, count)
          local trueProfit = ns.CalculateProfit(currentAH, effectiveFull, count)

          local hasAnyMat = ownedUnits > 0
          local isReady = (totalUnits > 0 and ownedUnits >= totalUnits and (extraMissingCost or 0) == 0)

          table.insert(allEntries, {
            recipeID = recipeID,
            recipeInfo = recipeInfo,
            name = recipeInfo.name or ("Recipe #" .. tostring(recipeID)),
            icon = recipeInfo.icon or recipeSchematic.icon,
            outputCount = count,
            ahPrice = currentAH,
            age = age,
            exact = exact,
            missingCost = effectiveMissing,
            fullCost = effectiveFull,
            cashProfit = cashProfit,
            trueProfit = trueProfit,
            ownedUnits = ownedUnits,
            totalUnits = totalUnits,
            hasAnyMat = hasAnyMat,
            isReady = isReady,
            hasUnknownMissingPrice = hasUnknownMissingPrice,
            hasUnknownFullPrice = hasUnknownFullPrice,
            breakdown = breakdown,
          })
        end
      end
    end
  end
end

local function ApplyFilterAndSort()
  local db = ns.GetDB()
  filteredEntries = {}

  for _, entry in ipairs(allEntries) do
    local keep = true
    if db.filterMode == "have" and not entry.hasAnyMat then
      keep = false
    elseif db.filterMode == "ready" and not entry.isReady then
      keep = false
    end

    if keep and db.onlyTrueProfit and (entry.hasUnknownFullPrice or entry.trueProfit <= 0) then
      keep = false
    end

    if keep then
      table.insert(filteredEntries, entry)
    end
  end

  local key = db.sortKey or "cashProfit"
  local desc = (db.sortDesc ~= false)

  table.sort(filteredEntries, function(a, b)
    local va = a[key]
    local vb = b[key]
    if va == vb then
      if a.cashProfit ~= b.cashProfit then
        return a.cashProfit > b.cashProfit
      end
      return a.name < b.name
    end
    if desc then
      return va > vb
    else
      return va < vb
    end
  end)

  local maxOffset = math.max(0, #filteredEntries - VISIBLE_ROWS)
  if scrollOffset > maxOffset then
    scrollOffset = maxOffset
  end
  if scrollOffset < 0 then
    scrollOffset = 0
  end
end

local function ShowRowTooltip(row, entry)
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:SetText(entry.name, 1, 0.82, 0)

  local afterCut = (Auctionator.Constants and Auctionator.Constants.AfterAHCut) or 0.95
  local netSale = math.floor(entry.ahPrice * entry.outputCount * afterCut + 0.5)

  if entry.outputCount > 1 then
    GameTooltip:AddDoubleLine(
      string.format("AH Sale (%dx, after 5%% cut):", entry.outputCount),
      ns.FormatMoney(netSale),
      0.85, 0.85, 0.85, 1, 1, 1
    )
  else
    GameTooltip:AddDoubleLine("AH Sale (after 5% cut):", ns.FormatMoney(netSale), 0.85, 0.85, 0.85, 1, 1, 1)
  end

  GameTooltip:AddDoubleLine("Full Craft Cost:", ns.FormatMoney(entry.fullCost), 0.85, 0.85, 0.85, 1, 1, 1)
  GameTooltip:AddDoubleLine("Price of missing mats:", ns.FormatMoney(entry.missingCost), 0.4, 0.85, 0.94, 1, 0.72, 0.3)
  GameTooltip:AddDoubleLine("Cash Profit:", ns.FormatSignedMoney(entry.cashProfit, GREEN_FONT_COLOR), 0.4, 0.85, 0.94, 1, 1, 1)
  GameTooltip:AddDoubleLine("True Profit (all mats):", ns.FormatSignedMoney(entry.trueProfit, WHITE_FONT_COLOR), 0.85, 0.85, 0.85, 1, 1, 1)
  GameTooltip:AddDoubleLine("AH Price Age:", FormatPriceAge(entry.age), 0.75, 0.75, 0.75, 1, 1, 1)

  if entry.breakdown and #entry.breakdown > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Reagents (bags only):", 1, 0.82, 0)
    for _, part in ipairs(entry.breakdown) do
      local itemName = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(part.itemID)) or ("Item #" .. tostring(part.itemID))
      local left = string.format("  %d/%d %s", part.usedFromBags, part.needed, itemName)
      local right
      if part.missing == 0 and part.unitPrice == 0 then
        right = "|cff40ff40In bags|r |cffffaa00(no price)|r"
      elseif part.missing == 0 then
        right = "|cff40ff40In bags|r"
      elseif part.unitPrice == 0 then
        right = "|cffffaa00No price|r"
      else
        right = string.format("Buy %d = %s", part.missing, ns.FormatMoney(part.missing * part.unitPrice))
      end
      GameTooltip:AddDoubleLine(left, right, 0.9, 0.9, 0.9, 1, 1, 1)
    end
  end

  if entry.hasUnknownMissingPrice then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Note: One or more missing reagents have no AH/vendor price in Auctionator.", 1, 0.65, 0.2, true)
  elseif entry.hasUnknownFullPrice then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Note: One or more owned reagents have no AH/vendor price in Auctionator; True Profit may be overstated.", 1, 0.65, 0.2, true)
  end

  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click to select this recipe in the Professions window.", 0.6, 0.85, 1)
  GameTooltip:Show()
end

local function SelectRecipeInProfessions(entry)
  if not (ProfessionsFrame and ProfessionsFrame:IsShown() and ProfessionsFrame.CraftingPage) then
    return
  end
  local craftingPage = ProfessionsFrame.CraftingPage
  if craftingPage.SelectRecipe and entry.recipeInfo then
    craftingPage:SelectRecipe(entry.recipeInfo)
  end
end

local function UpdateHeaderHighlights()
  if not scannerFrame then
    return
  end
  local db = ns.GetDB()
  local arrow = db.sortDesc and " (v)" or " (^)"

  for _, col in ipairs(scannerFrame.headerButtons) do
    local label = col.baseLabel
    if db.sortKey == col.sortKey then
      col.Text:SetText("|cff66d9ef" .. label .. arrow .. "|r")
    else
      col.Text:SetText("|cffcccccc" .. label .. "|r")
    end
  end

  for mode, btn in pairs(scannerFrame.filterButtons) do
    if db.filterMode == mode then
      SetFlatBackdrop(btn, { 0.14, 0.34, 0.44, 1 }, { 0.4, 0.85, 0.94, 1 })
      btn.Text:SetTextColor(1, 1, 1)
    else
      SetFlatBackdrop(btn, { 0.11, 0.12, 0.15, 1 }, { 0.25, 0.28, 0.32, 1 })
      btn.Text:SetTextColor(0.75, 0.78, 0.82)
    end
  end

  scannerFrame.trueProfitCheck:SetChecked(db.onlyTrueProfit)
end

local function RenderRows()
  if not scannerFrame then
    return
  end

  local total = #filteredEntries
  local maxOffset = math.max(0, total - VISIBLE_ROWS)
  if scrollOffset > maxOffset then
    scrollOffset = maxOffset
  end

  -- Update scrollbar thumb
  local track = scannerFrame.scrollTrack
  local thumb = scannerFrame.scrollThumb
  if maxOffset <= 0 then
    thumb:Hide()
  else
    thumb:Show()
    local trackH = track:GetHeight()
    local thumbH = math.max(24, math.floor(trackH * (VISIBLE_ROWS / total)))
    thumb:SetHeight(thumbH)
    local travel = trackH - thumbH
    local yOffset = math.floor((scrollOffset / maxOffset) * travel + 0.5)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", track, "TOP", 0, -yOffset)
  end

  for i = 1, VISIBLE_ROWS do
    local row = scannerFrame.rows[i]
    local entry = filteredEntries[scrollOffset + i]
    if entry then
      row.entry = entry
      row.Icon:SetTexture(entry.icon or 134400)

      local badge = ""
      if entry.isReady then
        badge = " |cff40ff40[Ready]|r"
      elseif entry.hasAnyMat then
        badge = string.format(" |cff66d9ef[%d/%d]|r", entry.ownedUnits, entry.totalUnits)
      end

      local warn = (entry.hasUnknownMissingPrice or entry.hasUnknownFullPrice) and " |cffffaa00(?)|r" or ""
      row.Name:SetText(entry.name .. badge .. warn)

      if entry.hasUnknownMissingPrice and entry.missingCost == 0 then
        row.Missing:SetText(ns.COST_COLOR .. "Unpriced" .. ns.COLOR_END)
      elseif entry.isReady and entry.missingCost == 0 then
        row.Missing:SetText(GREEN_FONT_COLOR:WrapTextInColorCode(ns.FormatMoney(0)))
      else
        row.Missing:SetText(ns.COST_COLOR .. ns.FormatMoney(entry.missingCost) .. ns.COLOR_END)
      end

      row.CashProfit:SetText(ns.FormatSignedMoney(entry.cashProfit, GREEN_FONT_COLOR))
      row.TrueProfit:SetText(ns.FormatSignedMoney(entry.trueProfit, WHITE_FONT_COLOR))

      if (scrollOffset + i) % 2 == 0 then
        row.Bg:SetColorTexture(0.09, 0.10, 0.13, 0.9)
      else
        row.Bg:SetColorTexture(0.06, 0.07, 0.09, 0.9)
      end
      row:Show()
      if GameTooltip:IsOwned(row) then
        ShowRowTooltip(row, entry)
      end
    else
      row.entry = nil
      row:Hide()
      if GameTooltip:IsOwned(row) then
        GameTooltip:Hide()
      end
    end
  end

  if total == 0 then
    if scanStats.priced == 0 then
      scannerFrame.emptyText:SetText("No Auctionator prices found for learned recipes.\nRun an Auctionator Scan at the Auction House first.")
    elseif ns.GetDB().filterMode == "have" then
      scannerFrame.emptyText:SetText("No priced recipes match materials currently in your bags.\nClick 'All Recipes' to view every profitable craft.")
    elseif ns.GetDB().filterMode == "ready" then
      scannerFrame.emptyText:SetText("No priced recipes have 100% of their materials in your bags right now.")
    else
      scannerFrame.emptyText:SetText("No recipes match the current filters.")
    end
    scannerFrame.emptyText:Show()
  else
    scannerFrame.emptyText:Hide()
  end

  scannerFrame.titleText:SetText("Best Crafts - " .. scanStats.profName)
  if scanStats.statusNote then
    scannerFrame.footerText:SetText(scanStats.statusNote)
  else
    scannerFrame.footerText:SetText(string.format(
      "Showing %d recipes (%d priced / %d learned)  |  Updated %s  |  Click a recipe to select",
      total, scanStats.priced, scanStats.learned, scanStats.updatedAt
    ))
  end

  UpdateHeaderHighlights()
end

local function FullRescanAndRender()
  scanStats.statusNote = nil
  ScanLearnedRecipes()
  ApplyFilterAndSort()
  RenderRows()
end

local function UpdateScanButtonLabel()
  if not (scannerFrame and scannerFrame.scanBtn) then
    return
  end
  if IsAuctionHouseOpen() then
    scannerFrame.scanBtn:SetText("Scan AH")
  else
    scannerFrame.scanBtn:SetText("Refresh")
  end
end

local function TriggerLiveAHScan()
  liveScanRequestID = liveScanRequestID + 1
  local requestID = liveScanRequestID

  if not IsAuctionHouseOpen() then
    FullRescanAndRender()
    scanStats.statusNote = "Refreshed from cache (open the Auction House to scan live AH prices)"
    RenderRows()
    return
  end

  if not (Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.MultiSearchExact) then
    FullRescanAndRender()
    return
  end

  local T = C_TradeSkillUI
  if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo and T.GetRecipeSchematic) then
    return
  end

  local db = ns.GetDB()
  local ids = T.GetAllRecipeIDs()
  if type(ids) ~= "table" then
    return
  end

  local seenItemIDs = {}
  local itemsToLoad = {}
  local continuableContainer = ContinuableContainer:Create()

  local function AddItemID(itemID)
    if type(itemID) == "number" and itemID > 0 and not seenItemIDs[itemID] then
      seenItemIDs[itemID] = true
      table.insert(itemsToLoad, itemID)
      continuableContainer:AddContinuable(Item:CreateFromItemID(itemID))
    end
  end

  for _, recipeID in ipairs(ids) do
    local recipeInfo = T.GetRecipeInfo(recipeID)
    if type(recipeInfo) == "table" and recipeInfo.learned then
      local ok, recipeSchematic = pcall(T.GetRecipeSchematic, recipeID, false)
      if ok and type(recipeSchematic) == "table" and recipeSchematic.reagentSlotSchematics and #recipeSchematic.reagentSlotSchematics > 0 then
        local _, _, _, ownedUnits, totalUnits = ns.CalculateCosts(recipeSchematic, nil)
        local include = true
        if db.filterMode == "have" and ownedUnits <= 0 then
          include = false
        elseif db.filterMode == "ready" and (totalUnits <= 0 or ownedUnits < totalUnits) then
          include = false
        end

        if include then
          -- Output item
          if recipeInfo.isEnchantingRecipe then
            local enchantMap = Auctionator.CraftingInfo and Auctionator.CraftingInfo.EnchantSpellsToItems
            local outID = enchantMap and enchantMap[recipeID] and enchantMap[recipeID][1]
            AddItemID(outID)
          elseif recipeSchematic.outputItemID then
            AddItemID(recipeSchematic.outputItemID)
          end

          -- Basic reagents
          for _, slot in ipairs(recipeSchematic.reagentSlotSchematics) do
            local isBasic = (not (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic))
              or (slot.reagentType == Enum.CraftingReagentType.Basic)
            if isBasic and slot.reagents then
              for _, reagent in ipairs(slot.reagents) do
                AddItemID(reagent.itemID)
              end
            end
          end
        end
      end
    end
  end

  if #itemsToLoad == 0 then
    FullRescanAndRender()
    scanStats.statusNote = "No matching recipes to scan in current filter."
    RenderRows()
    return
  end

  scanStats.statusNote = string.format("|cff66d9efPreparing live AH scan for %d items...|r", #itemsToLoad)
  RenderRows()

  continuableContainer:ContinueOnLoad(function()
    if requestID ~= liveScanRequestID then
      return
    end
    if not IsAuctionHouseOpen() then
      FullRescanAndRender()
      return
    end

    local seenNames = {}
    local searchNames = {}
    for _, itemID in ipairs(itemsToLoad) do
      local itemInfo = { C_Item.GetItemInfo(itemID) }
      local name = itemInfo[1]
      local isBound = Auctionator.Utilities and Auctionator.Utilities.IsBound and Auctionator.Utilities.IsBound(itemInfo)
      if name and name ~= "" and not isBound and not seenNames[name] then
        if not name:match("[;^]") and not name:match('^%s*".*"%s*$') then
          seenNames[name] = true
          table.insert(searchNames, name)
        end
      end
    end

    if #searchNames == 0 then
      FullRescanAndRender()
      return
    end

    table.sort(searchNames)
    scanStats.statusNote = string.format("|cff66d9efScanning %d items live on AH via Auctionator...|r", #searchNames)
    RenderRows()

    local ok, err = pcall(Auctionator.API.v1.MultiSearchExact, "Best Crafts", searchNames)
    if not ok then
      scanStats.statusNote = "|cffff6644AH scan failed: " .. tostring(err) .. "|r"
      RenderRows()
    end
  end)
end

local function CreateFilterButton(parent, label, mode, width)
  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  btn:SetSize(width, 22)
  btn.Text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  btn.Text:SetPoint("CENTER")
  btn.Text:SetText(label)
  btn:SetScript("OnClick", function()
    local db = ns.GetDB()
    db.filterMode = mode
    scrollOffset = 0
    scanStats.statusNote = nil
    ApplyFilterAndSort()
    RenderRows()
  end)
  return btn
end

local function PositionWindowNearProfessions(win)
  win:ClearAllPoints()
  if ProfessionsFrame and ProfessionsFrame:IsShown() then
    local rightSpace = (UIParent:GetRight() or 1200) - (ProfessionsFrame:GetRight() or 800)
    if rightSpace >= WINDOW_WIDTH + 12 then
      win:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 6, 0)
      return
    end
    local leftSpace = ProfessionsFrame:GetLeft() or 0
    if leftSpace >= WINDOW_WIDTH + 12 then
      win:SetPoint("TOPRIGHT", ProfessionsFrame, "TOPLEFT", -6, 0)
      return
    end
  end
  win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

local function CreateScannerWindow()
  if scannerFrame then
    return scannerFrame
  end

  local win = CreateFrame("Frame", "AuctionatorOwnedMatsListFrame", UIParent, "BackdropTemplate")
  win:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
  win:SetFrameStrata("HIGH")
  win:SetClampedToScreen(true)
  win:SetMovable(true)
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self.userMoved = true
  end)
  win:SetScript("OnHide", function()
    liveScanRequestID = liveScanRequestID + 1
  end)
  SetFlatBackdrop(win, { 0.055, 0.065, 0.085, 0.97 }, { 0.25, 0.30, 0.36, 1 })

  table.insert(UISpecialFrames, "AuctionatorOwnedMatsListFrame")

  -- Title bar
  local header = CreateFrame("Frame", nil, win, "BackdropTemplate")
  header:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", win, "TOPRIGHT", -1, -1)
  header:SetHeight(30)
  SetFlatBackdrop(header, { 0.09, 0.11, 0.15, 1 }, { 0.2, 0.24, 0.3, 1 })

  local titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titleText:SetPoint("LEFT", header, "LEFT", 12, 0)
  titleText:SetTextColor(0.4, 0.85, 0.94)
  titleText:SetText("Best Crafts")
  win.titleText = titleText

  local closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButtonNoScripts")
  closeBtn:SetPoint("RIGHT", header, "RIGHT", -2, 0)
  closeBtn:SetScript("OnClick", function()
    win:Hide()
  end)

  local scanBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
  scanBtn:SetSize(82, 20)
  scanBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
  scanBtn:SetText(IsAuctionHouseOpen() and "Scan AH" or "Refresh")
  scanBtn:SetScript("OnClick", function()
    TriggerLiveAHScan()
  end)
  scanBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    if IsAuctionHouseOpen() then
      GameTooltip:SetText("Live AH Scan", 0.4, 0.85, 0.94)
      GameTooltip:AddLine("Queries the live Auction House via Auctionator for all recipes and reagents in your current filter (Have Mats / Ready / All) and updates profits in real time.", 1, 1, 1, true)
    else
      GameTooltip:SetText("Refresh from Cache", 1, 0.82, 0)
      GameTooltip:AddLine("Recalculates recipes from your bags and Auctionator's saved prices. Open the Auction House to run a live AH scan.", 1, 1, 1, true)
    end
    GameTooltip:Show()
  end)
  scanBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  win.scanBtn = scanBtn

  -- Filter bar
  local filterBar = CreateFrame("Frame", nil, win)
  filterBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 10, -8)
  filterBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -10, -8)
  filterBar:SetHeight(24)

  win.filterButtons = {}
  local btnHave = CreateFilterButton(filterBar, "Have Mats", "have", 86)
  btnHave:SetPoint("LEFT", filterBar, "LEFT", 0, 0)
  win.filterButtons["have"] = btnHave

  local btnReady = CreateFilterButton(filterBar, "Ready Only", "ready", 88)
  btnReady:SetPoint("LEFT", btnHave, "RIGHT", 6, 0)
  win.filterButtons["ready"] = btnReady

  local btnAll = CreateFilterButton(filterBar, "All Recipes", "all", 88)
  btnAll:SetPoint("LEFT", btnReady, "RIGHT", 6, 0)
  win.filterButtons["all"] = btnAll

  local trueProfitCheck = CreateFrame("CheckButton", nil, filterBar, "UICheckButtonTemplate")
  trueProfitCheck:SetSize(22, 22)
  trueProfitCheck:SetPoint("LEFT", btnAll, "RIGHT", 16, 0)
  trueProfitCheck:SetScript("OnClick", function(self)
    local db = ns.GetDB()
    db.onlyTrueProfit = self:GetChecked() and true or false
    scrollOffset = 0
    ApplyFilterAndSort()
    RenderRows()
  end)
  win.trueProfitCheck = trueProfitCheck

  local checkLabel = filterBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  checkLabel:SetPoint("LEFT", trueProfitCheck, "RIGHT", 2, 0)
  checkLabel:SetText("True Profit > 0 only")

  -- Column headers
  local colHeader = CreateFrame("Frame", nil, win, "BackdropTemplate")
  colHeader:SetPoint("TOPLEFT", filterBar, "BOTTOMLEFT", 0, -8)
  colHeader:SetPoint("TOPRIGHT", filterBar, "BOTTOMRIGHT", 0, -8)
  colHeader:SetHeight(22)
  SetFlatBackdrop(colHeader, { 0.11, 0.13, 0.17, 1 }, { 0.22, 0.26, 0.32, 1 })

  local columns = {
    { key = "name", label = "Recipe", x = 8, width = 266, justify = "LEFT" },
    { key = "missingCost", label = "Missing Mats", x = 278, width = 108, justify = "RIGHT" },
    { key = "cashProfit", label = "Cash Profit", x = 392, width = 112, justify = "RIGHT" },
    { key = "trueProfit", label = "True Profit", x = 510, width = 108, justify = "RIGHT" },
  }

  win.headerButtons = {}
  for _, col in ipairs(columns) do
    local hb = CreateFrame("Button", nil, colHeader)
    hb:SetPoint("LEFT", colHeader, "LEFT", col.x, 0)
    hb:SetSize(col.width, 22)
    hb.sortKey = col.key
    hb.baseLabel = col.label

    local t = hb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetAllPoints(hb)
    t:SetJustifyH(col.justify)
    hb.Text = t

    hb:SetScript("OnClick", function()
      local db = ns.GetDB()
      if db.sortKey == col.key then
        db.sortDesc = not db.sortDesc
      else
        db.sortKey = col.key
        db.sortDesc = (col.key ~= "name" and col.key ~= "missingCost")
      end
      scrollOffset = 0
      ApplyFilterAndSort()
      RenderRows()
    end)

    table.insert(win.headerButtons, hb)
  end

  -- List container
  local listBox = CreateFrame("Frame", nil, win, "BackdropTemplate")
  listBox:SetPoint("TOPLEFT", colHeader, "BOTTOMLEFT", 0, -2)
  listBox:SetPoint("TOPRIGHT", colHeader, "BOTTOMRIGHT", 0, -2)
  listBox:SetHeight(VISIBLE_ROWS * ROW_HEIGHT + 2)
  SetFlatBackdrop(listBox, { 0.045, 0.052, 0.068, 1 }, { 0.2, 0.24, 0.3, 1 })
  listBox:EnableMouseWheel(true)
  listBox:SetScript("OnMouseWheel", function(_, delta)
    local maxOffset = math.max(0, #filteredEntries - VISIBLE_ROWS)
    scrollOffset = math.max(0, math.min(maxOffset, scrollOffset - delta * 2))
    RenderRows()
  end)

  -- Scrollbar track + thumb
  local scrollTrack = CreateFrame("Frame", nil, listBox, "BackdropTemplate")
  scrollTrack:SetPoint("TOPRIGHT", listBox, "TOPRIGHT", -3, -3)
  scrollTrack:SetPoint("BOTTOMRIGHT", listBox, "BOTTOMRIGHT", -3, 3)
  scrollTrack:SetWidth(8)
  SetFlatBackdrop(scrollTrack, { 0.08, 0.09, 0.12, 1 }, { 0.16, 0.19, 0.24, 1 })
  win.scrollTrack = scrollTrack

  local scrollThumb = scrollTrack:CreateTexture(nil, "OVERLAY")
  scrollThumb:SetWidth(6)
  scrollThumb:SetColorTexture(0.4, 0.85, 0.94, 0.75)
  scrollThumb:Hide()
  win.scrollThumb = scrollThumb

  -- Empty state text
  local emptyText = listBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  emptyText:SetPoint("CENTER", listBox, "CENTER", 0, 0)
  emptyText:SetJustifyH("CENTER")
  emptyText:SetTextColor(0.7, 0.74, 0.8)
  emptyText:Hide()
  win.emptyText = emptyText

  -- Rows
  win.rows = {}
  for i = 1, VISIBLE_ROWS do
    local row = CreateFrame("Button", nil, listBox)
    row:SetPoint("TOPLEFT", listBox, "TOPLEFT", 1, -1 - (i - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", listBox, "TOPRIGHT", -14, -1 - (i - 1) * ROW_HEIGHT)
    row:SetHeight(ROW_HEIGHT)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    row.Bg = bg

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    hl:SetColorTexture(0.22, 0.48, 0.62, 0.35)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.Icon = icon

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    name:SetWidth(240)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    row.Name = name

    local missing = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    missing:SetPoint("LEFT", row, "LEFT", 277, 0)
    missing:SetWidth(108)
    missing:SetJustifyH("RIGHT")
    row.Missing = missing

    local cashProfit = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cashProfit:SetPoint("LEFT", row, "LEFT", 391, 0)
    cashProfit:SetWidth(112)
    cashProfit:SetJustifyH("RIGHT")
    row.CashProfit = cashProfit

    local trueProfit = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    trueProfit:SetPoint("LEFT", row, "LEFT", 509, 0)
    trueProfit:SetWidth(108)
    trueProfit:SetJustifyH("RIGHT")
    row.TrueProfit = trueProfit

    row:SetScript("OnEnter", function(self)
      if self.entry then
        ShowRowTooltip(self, self.entry)
      end
    end)
    row:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
      if self.entry then
        SelectRecipeInProfessions(self.entry)
      end
    end)

    row:Hide()
    win.rows[i] = row
  end

  -- Footer
  local footerText = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footerText:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 12, 8)
  footerText:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 8)
  footerText:SetJustifyH("LEFT")
  win.footerText = footerText

  win:Hide()
  scannerFrame = win
  return win
end

function ns.UpdateScannerAHState()
  UpdateScanButtonLabel()
end

function ns.RefreshScannerIfShown()
  if scannerFrame and scannerFrame:IsShown() then
    UpdateScanButtonLabel()
    FullRescanAndRender()
  end
end

function ns.HideScannerWindow()
  liveScanRequestID = liveScanRequestID + 1
  if scannerFrame and scannerFrame:IsShown() then
    scannerFrame:Hide()
  end
end

function ns.ToggleScannerWindow()
  if not (ProfessionsFrame and ProfessionsFrame:IsShown()) then
    print("|cff66d9efAuctionatorOwnedMats:|r Open a profession window first to scan its recipes.")
    return
  end

  local win = CreateScannerWindow()
  if win:IsShown() then
    win:Hide()
    return
  end

  if not win.userMoved then
    PositionWindowNearProfessions(win)
  end
  scrollOffset = 0
  UpdateScanButtonLabel()
  FullRescanAndRender()
  win:Show()
end
