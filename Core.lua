local ADDON_NAME, ns = ...
local CALLER_ID = "AuctionatorOwnedMats"

ns.CALLER_ID = CALLER_ID
ns.LABEL_COLOR = "|cff66d9ef"
ns.COST_COLOR = "|cffffb84d"
ns.COLOR_END = "|r"

local initialized = false
local displayFrame = nil
local bestCraftsButton = nil
local hookedAucFrame = false

function ns.GetDB()
  if type(AuctionatorOwnedMatsDB) ~= "table" then
    AuctionatorOwnedMatsDB = {}
  end
  if AuctionatorOwnedMatsDB.enabled == nil then
    AuctionatorOwnedMatsDB.enabled = true
  end
  if AuctionatorOwnedMatsDB.filterMode == nil then
    AuctionatorOwnedMatsDB.filterMode = "have" -- "have", "ready", "all"
  end
  if AuctionatorOwnedMatsDB.onlyTrueProfit == nil then
    AuctionatorOwnedMatsDB.onlyTrueProfit = false
  end
  if AuctionatorOwnedMatsDB.sortKey == nil then
    AuctionatorOwnedMatsDB.sortKey = "cashProfit"
  end
  if AuctionatorOwnedMatsDB.sortDesc == nil then
    AuctionatorOwnedMatsDB.sortDesc = true
  end
  return AuctionatorOwnedMatsDB
end

function ns.GetBagCount(itemID)
  if type(itemID) ~= "number" then
    return 0
  end
  if C_Item and C_Item.GetItemCount then
    -- Bags only: includeBank=false, includeUses=false, includeReagentBank=false, includeAccountBank=false
    return C_Item.GetItemCount(itemID, false, false, false, false) or 0
  elseif GetItemCount then
    return GetItemCount(itemID, false, false, false) or 0
  end
  return 0
end

function ns.GetUnitPrice(itemID)
  if not (Auctionator and Auctionator.API and Auctionator.API.v1) then
    return 0
  end
  local vendorPrice = Auctionator.API.v1.GetVendorPriceByItemID(CALLER_ID, itemID)
  local auctionPrice = Auctionator.API.v1.GetAuctionPriceByItemID(CALLER_ID, itemID)

  local unitPrice = vendorPrice or auctionPrice
  if vendorPrice and auctionPrice and vendorPrice > 5 * auctionPrice then
    unitPrice = auctionPrice
  end

  return unitPrice or 0
end

local function IsBasicReagentSlot(reagentSlotSchematic)
  if Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic ~= nil then
    return reagentSlotSchematic.reagentType == Enum.CraftingReagentType.Basic
  end
  return reagentSlotSchematic.required ~= false
end

function ns.CalculateCosts(recipeSchematic, transaction)
  local fullTotal = 0
  local missingTotal = 0
  local totalUnitsNeeded = 0
  local totalUnitsOwned = 0
  local hasUnknownMissingPrice = false
  local hasUnknownFullPrice = false
  local bagRemaining = {}
  local breakdown = {}

  local function ConsumeFromBags(itemID, needed)
    if needed <= 0 then
      return 0, 0
    end
    local have = bagRemaining[itemID]
    if have == nil then
      have = ns.GetBagCount(itemID)
    end
    local used = math.min(have, needed)
    bagRemaining[itemID] = have - used
    return needed - used, used
  end

  for slotIndex, reagentSlotSchematic in ipairs(recipeSchematic.reagentSlotSchematics or {}) do
    local reagents = reagentSlotSchematic.reagents
    if reagents and #reagents > 0 then
      local selected = 0
      local slotAllocations = transaction and transaction:GetAllocations(slotIndex)

      if slotAllocations ~= nil then
        selected = slotAllocations:Accumulate()
        for _, reagent in ipairs(reagents) do
          local itemID = reagent.itemID
          if itemID ~= nil then
            local allocation = slotAllocations:FindAllocationByReagent(reagent)
            local qty = allocation and allocation:GetQuantity() or 0
            if qty > 0 then
              local unitPrice = ns.GetUnitPrice(itemID)
              local missing, used = ConsumeFromBags(itemID, qty)
              fullTotal = fullTotal + qty * unitPrice
              missingTotal = missingTotal + missing * unitPrice
              totalUnitsNeeded = totalUnitsNeeded + qty
              totalUnitsOwned = totalUnitsOwned + used
              if unitPrice == 0 then
                hasUnknownFullPrice = true
                if missing > 0 then
                  hasUnknownMissingPrice = true
                end
              end
              table.insert(breakdown, {
                itemID = itemID,
                needed = qty,
                usedFromBags = used,
                missing = missing,
                unitPrice = unitPrice,
              })
            end
          end
        end
      end

      if IsBasicReagentSlot(reagentSlotSchematic) and selected < (reagentSlotSchematic.quantityRequired or 0) then
        local remainingNeeded = reagentSlotSchematic.quantityRequired - selected

        -- Match Auctionator's full-cost choice (cheapest priced option in the slot)
        local minUnitPrice = 0
        local chosenItemID = nil
        for _, entry in ipairs(reagents) do
          if entry.itemID ~= nil then
            local unitPrice = ns.GetUnitPrice(entry.itemID)
            if chosenItemID == nil then
              chosenItemID = entry.itemID
            end
            if unitPrice > 0 and (minUnitPrice == 0 or unitPrice < minUnitPrice) then
              minUnitPrice = unitPrice
              chosenItemID = entry.itemID
            end
          end
        end
        fullTotal = fullTotal + remainingNeeded * minUnitPrice

        -- Subtract any matching reagents already sitting in bags
        local stillMissing = remainingNeeded
        local totalUsed = 0
        for _, entry in ipairs(reagents) do
          if stillMissing <= 0 then
            break
          end
          if entry.itemID ~= nil then
            local afterMissing, used = ConsumeFromBags(entry.itemID, stillMissing)
            stillMissing = afterMissing
            totalUsed = totalUsed + used
          end
        end

        missingTotal = missingTotal + stillMissing * minUnitPrice
        totalUnitsNeeded = totalUnitsNeeded + remainingNeeded
        totalUnitsOwned = totalUnitsOwned + totalUsed
        if minUnitPrice == 0 then
          hasUnknownFullPrice = true
          if stillMissing > 0 then
            hasUnknownMissingPrice = true
          end
        end
        if chosenItemID ~= nil then
          table.insert(breakdown, {
            itemID = chosenItemID,
            needed = remainingNeeded,
            usedFromBags = totalUsed,
            missing = stillMissing,
            unitPrice = minUnitPrice,
          })
        end
      end
    end
  end

  return missingTotal, fullTotal, breakdown, totalUnitsOwned, totalUnitsNeeded, hasUnknownMissingPrice, hasUnknownFullPrice
end

local function GetItemIDByReagentQuality(possibleItemIDs, wantedQuality, allQualities)
  if #possibleItemIDs == 1 then
    return possibleItemIDs[1]
  end
  if not (allQualities and C_TradeSkillUI.GetItemReagentQualityByItemInfo) then
    return possibleItemIDs[1]
  end
  for _, itemID in ipairs(possibleItemIDs) do
    local quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(itemID)
    if allQualities[quality] == wantedQuality then
      return itemID
    end
  end
  return possibleItemIDs[1]
end

local function GetEnchantExtraCost()
  local extraMissingCost = 0
  local extraFullCost = 0
  local vellumID = Auctionator.Constants and Auctionator.Constants.EnchantingVellumID
  if vellumID then
    local vellumPrice = Auctionator.API.v1.GetVendorPriceByItemID(CALLER_ID, vellumID) or 0
    if vellumPrice > 0 then
      extraFullCost = vellumPrice
      if ns.GetBagCount(vellumID) < 1 then
        extraMissingCost = vellumPrice
      end
    end
  end
  return extraMissingCost, extraFullCost
end

function ns.GetOutputAHInfo(recipeInfo, recipeSchematic, transaction)
  local recipeID = recipeInfo.recipeID

  if recipeInfo.isEnchantingRecipe then
    local enchantMap = Auctionator.CraftingInfo and Auctionator.CraftingInfo.EnchantSpellsToItems
    local possibleOutputItemIDs = (enchantMap and enchantMap[recipeID]) or {}
    local itemID

    if recipeSchematic.hasCraftingOperationInfo and C_TradeSkillUI.GetCraftingOperationInfo and transaction then
      local ok, operationInfo = pcall(
        C_TradeSkillUI.GetCraftingOperationInfo,
        recipeID,
        transaction:CreateCraftingReagentInfoTbl(),
        transaction:GetAllocationItemGUID(),
        transaction:IsApplyingConcentration()
      )
      if ok and operationInfo ~= nil and C_TradeSkillUI.GetQualitiesForRecipe then
        itemID = GetItemIDByReagentQuality(
          possibleOutputItemIDs,
          operationInfo.guaranteedCraftingQualityID,
          C_TradeSkillUI.GetQualitiesForRecipe(recipeID)
        )
      end
    end

    if itemID == nil then
      itemID = possibleOutputItemIDs[1]
    end

    if itemID == nil then
      return nil
    end

    local currentAH = Auctionator.API.v1.GetAuctionPriceByItemID(CALLER_ID, itemID) or 0
    local age = Auctionator.API.v1.GetAuctionAgeByItemID(CALLER_ID, itemID)
    local exact = Auctionator.API.v1.IsAuctionDataExactByItemID(CALLER_ID, itemID)
    local extraMissingCost, extraFullCost = GetEnchantExtraCost()

    return currentAH, age, currentAH ~= 0, exact, extraMissingCost, extraFullCost
  end

  local qualityOverride
  if C_TradeSkillUI.GetCraftingOperationInfo and transaction then
    local ok, operationInfo = pcall(
      C_TradeSkillUI.GetCraftingOperationInfo,
      recipeID,
      transaction:CreateCraftingReagentInfoTbl(),
      transaction:GetAllocationItemGUID(),
      transaction:IsApplyingConcentration()
    )
    if ok and operationInfo and recipeInfo.qualityIDs then
      qualityOverride = recipeInfo.qualityIDs[operationInfo.craftingQuality]
    end
  end

  local qualitiesItemIDs = C_TradeSkillUI.GetRecipeQualityItemIDs and C_TradeSkillUI.GetRecipeQualityItemIDs(recipeID)
  local recipeLink

  if (not qualitiesItemIDs or #qualitiesItemIDs == 1) and C_TradeSkillUI.GetRecipeOutputItemData then
    local ok, outputData
    if transaction then
      ok, outputData = pcall(
        C_TradeSkillUI.GetRecipeOutputItemData,
        recipeID,
        transaction:CreateCraftingReagentInfoTbl(),
        transaction:GetAllocationItemGUID(),
        qualityOverride
      )
    else
      ok, outputData = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID)
    end
    if ok and outputData then
      recipeLink = outputData.hyperlink
    end
  elseif qualitiesItemIDs and C_TradeSkillUI.GetQualitiesForRecipe then
    local qualityIDs = C_TradeSkillUI.GetQualitiesForRecipe(recipeID)
    local idx = qualityIDs and tIndexOf(qualityIDs, qualityOverride)
    if idx and qualitiesItemIDs[idx] then
      recipeLink = select(2, C_Item.GetItemInfo(qualitiesItemIDs[idx]))
    end
  end

  if recipeLink ~= nil then
    local currentAH = Auctionator.API.v1.GetAuctionPriceByItemLink(CALLER_ID, recipeLink) or 0
    local age = Auctionator.API.v1.GetAuctionAgeByItemLink(CALLER_ID, recipeLink)
    local exact = Auctionator.API.v1.IsAuctionDataExactByItemLink(CALLER_ID, recipeLink)
    return currentAH, age, currentAH ~= 0, exact, 0, 0
  elseif recipeSchematic.outputItemID ~= nil then
    local currentAH = Auctionator.API.v1.GetAuctionPriceByItemID(CALLER_ID, recipeSchematic.outputItemID) or 0
    local age = Auctionator.API.v1.GetAuctionAgeByItemID(CALLER_ID, recipeSchematic.outputItemID)
    local exact = Auctionator.API.v1.IsAuctionDataExactByItemID(CALLER_ID, recipeSchematic.outputItemID)
    return currentAH, age, currentAH ~= 0, exact, 0, 0
  end

  return nil
end

function ns.CalculateProfit(currentAH, toCraft, count)
  local afterCut = (Auctionator.Constants and Auctionator.Constants.AfterAHCut) or 0.95
  local raw = currentAH * count * afterCut - toCraft
  if Auctionator.Constants and Auctionator.Constants.IsForever then
    return math.floor(raw + 0.5)
  end
  return math.floor(math.floor(raw) / 100) * 100
end

function ns.FormatMoney(amount)
  return GetMoneyString(math.max(0, math.floor(amount + 0.5)), true)
end

function ns.FormatSignedMoney(amount, positiveColor)
  local posColor = positiveColor or GREEN_FONT_COLOR
  if amount >= 0 then
    return posColor:WrapTextInColorCode(ns.FormatMoney(amount))
  else
    return RED_FONT_COLOR:WrapTextInColorCode("-" .. ns.FormatMoney(-amount))
  end
end

local function AnchorDisplayFrame(schematicForm)
  displayFrame:ClearAllPoints()

  local aucFrame = AuctionatorCraftingInfoProfessionsFrame
  if aucFrame and aucFrame:IsShown() and aucFrame.Total then
    displayFrame:SetPoint("TOPLEFT", aucFrame.Total, "BOTTOMLEFT", 0, -4)
    return
  end

  local reagents = schematicForm.Reagents
  if not reagents then
    return
  end

  local lowest = reagents
  local candidates = { schematicForm.OptionalReagents }
  if schematicForm.extraSlotFrames then
    for _, f in ipairs(schematicForm.extraSlotFrames) do
      table.insert(candidates, f)
    end
  end
  for _, f in ipairs(candidates) do
    if f and f:IsShown() and f:GetBottom() and lowest:GetBottom() and f:GetBottom() < lowest:GetBottom() then
      lowest = f
    end
  end

  displayFrame:SetPoint("LEFT", reagents, "LEFT", 0, -10)
  displayFrame:SetPoint("TOP", lowest, "BOTTOM", 0, -5)
end

function ns.UpdateDisplay()
  if not displayFrame or not ProfessionsFrame or not ProfessionsFrame.CraftingPage then
    return
  end

  local schematicForm = ProfessionsFrame.CraftingPage.SchematicForm
  if not schematicForm or not schematicForm:IsVisible() then
    displayFrame:Hide()
    return
  end

  if not ns.GetDB().enabled then
    displayFrame:Hide()
    return
  end

  if Auctionator.Config and Auctionator.Config.Options and Auctionator.Config.Options.CRAFTING_INFO_SHOW then
    if not Auctionator.Config.Get(Auctionator.Config.Options.CRAFTING_INFO_SHOW) then
      displayFrame:Hide()
      return
    end
  end

  local recipeInfo = schematicForm:GetRecipeInfo()
  if not recipeInfo or not recipeInfo.recipeID then
    displayFrame:Hide()
    return
  end

  local recipeLevel = schematicForm.GetCurrentRecipeLevel and schematicForm:GetCurrentRecipeLevel() or nil
  local recipeSchematic = C_TradeSkillUI.GetRecipeSchematic(recipeInfo.recipeID, false, recipeLevel)
  if not recipeSchematic or not recipeSchematic.reagentSlotSchematics or #recipeSchematic.reagentSlotSchematics == 0 then
    displayFrame:Hide()
    return
  end

  local transaction = schematicForm.GetTransaction and schematicForm:GetTransaction() or nil
  local missingCost, fullCost, _, totalUnitsOwned, totalUnitsNeeded, hasUnknownMissingPrice = ns.CalculateCosts(recipeSchematic, transaction)

  local lines = {}
  local showCost = true
  local showProfit = true
  if Auctionator.Config and Auctionator.Config.Options then
    if Auctionator.Config.Options.CRAFTING_INFO_SHOW_COST then
      showCost = Auctionator.Config.Get(Auctionator.Config.Options.CRAFTING_INFO_SHOW_COST)
    end
    if Auctionator.Config.Options.CRAFTING_INFO_SHOW_PROFIT then
      showProfit = Auctionator.Config.Get(Auctionator.Config.Options.CRAFTING_INFO_SHOW_PROFIT)
    end
  end

  local currentAH, age, anyPrice, exact, extraMissingCost, extraFullCost = ns.GetOutputAHInfo(recipeInfo, recipeSchematic, transaction)
  local effectiveMissingCost = missingCost + (extraMissingCost or 0)
  local allInBags = (not hasUnknownMissingPrice)
    and totalUnitsNeeded > 0
    and totalUnitsOwned >= totalUnitsNeeded
    and (extraMissingCost or 0) == 0

  if showCost then
    local costText
    if hasUnknownMissingPrice then
      if effectiveMissingCost == 0 then
        costText = ns.COST_COLOR .. "Unavailable (unpriced mat)" .. ns.COLOR_END
      else
        costText = ns.COST_COLOR .. ns.FormatMoney(effectiveMissingCost) .. " (+ unpriced)" .. ns.COLOR_END
      end
    elseif allInBags then
      costText = GREEN_FONT_COLOR:WrapTextInColorCode(ns.FormatMoney(0) .. " (All in bags)")
    else
      costText = ns.COST_COLOR .. ns.FormatMoney(effectiveMissingCost) .. ns.COLOR_END
    end
    table.insert(lines, ns.LABEL_COLOR .. "Price of missing mats:" .. ns.COLOR_END .. " " .. costText)
  end

  if showProfit and currentAH ~= nil then
    if not anyPrice then
      table.insert(lines, ns.LABEL_COLOR .. "Cash Profit:" .. ns.COLOR_END .. " " .. ns.COST_COLOR .. "Auction price unavailable" .. ns.COLOR_END)
    elseif hasUnknownMissingPrice then
      table.insert(lines, ns.LABEL_COLOR .. "Cash Profit:" .. ns.COLOR_END .. " " .. ns.COST_COLOR .. "Incomplete (unpriced mat)" .. ns.COLOR_END)
    else
      local count = (schematicForm.recipeSchematic and schematicForm.recipeSchematic.quantityMin) or recipeSchematic.quantityMin or 1
      local profit = ns.CalculateProfit(currentAH, effectiveMissingCost, count)
      local profitText = ns.FormatSignedMoney(profit, GREEN_FONT_COLOR)

      local warning = ""
      if Auctionator.CraftingInfo and Auctionator.CraftingInfo.GetProfitWarning then
        warning = Auctionator.CraftingInfo.GetProfitWarning(profit, age, anyPrice, exact) or ""
      end

      table.insert(lines, ns.LABEL_COLOR .. "Cash Profit:" .. ns.COLOR_END .. " " .. profitText .. warning)
    end
  end

  if #lines == 0 then
    displayFrame:Hide()
    return
  end

  AnchorDisplayFrame(schematicForm)
  displayFrame.Text:SetText(table.concat(lines, "\n"))
  displayFrame:SetHeight(16 * #lines)
  displayFrame:Show()
end

local function HookAuctionatorFrameIfPresent()
  if hookedAucFrame then
    return
  end
  if AuctionatorCraftingInfoProfessionsFrame then
    hookedAucFrame = true
    hooksecurefunc(AuctionatorCraftingInfoProfessionsFrame, "UpdateTotal", ns.UpdateDisplay)
    hooksecurefunc(AuctionatorCraftingInfoProfessionsFrame, "ShowIfRelevant", ns.UpdateDisplay)
  end
end

local refreshPending = false
local function RefreshAll()
  ns.UpdateDisplay()
  if ns.RefreshScannerIfShown then
    if not refreshPending then
      refreshPending = true
      C_Timer.After(0.2, function()
        refreshPending = false
        if ns.RefreshScannerIfShown then
          ns.RefreshScannerIfShown()
        end
      end)
    end
  end
end

local function InitializeProfessionsUI()
  if not (ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm) then
    return
  end

  HookAuctionatorFrameIfPresent()

  if initialized then
    RefreshAll()
    return
  end
  initialized = true

  local schematicForm = ProfessionsFrame.CraftingPage.SchematicForm

  displayFrame = CreateFrame("Frame", "AuctionatorOwnedMatsProfessionsFrame", schematicForm)
  displayFrame:SetSize(320, 32)
  displayFrame:SetFrameLevel(520)

  local text = displayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetJustifyH("LEFT")
  text:SetSpacing(1.5)
  text:SetPoint("TOPLEFT", displayFrame, "TOPLEFT", 0, 0)
  displayFrame.Text = text

  -- "Best Crafts" button in the top-right header bar of ProfessionsFrame
  bestCraftsButton = CreateFrame("Button", "AuctionatorOwnedMatsBestCraftsButton", ProfessionsFrame, "UIPanelButtonTemplate")
  bestCraftsButton:SetSize(96, 20)
  bestCraftsButton:SetText("Best Crafts")
  bestCraftsButton:SetPoint("TOPRIGHT", ProfessionsFrame, "TOPRIGHT", -32, -3)
  bestCraftsButton:SetFrameLevel(ProfessionsFrame:GetFrameLevel() + 20)
  bestCraftsButton:SetScript("OnClick", function()
    if ns.ToggleScannerWindow then
      ns.ToggleScannerWindow()
    end
  end)
  bestCraftsButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText("Auctionator: Owned Mats", 0.4, 0.85, 0.94)
    GameTooltip:AddLine("Scan all learned recipes in this profession and sort by Cash Profit using materials in your bags.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  bestCraftsButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  ProfessionsFrame:HookScript("OnHide", function()
    if ns.HideScannerWindow then
      ns.HideScannerWindow()
    end
  end)

  hooksecurefunc(schematicForm, "Init", function()
    HookAuctionatorFrameIfPresent()
    ns.UpdateDisplay()
  end)

  if schematicForm.statsChangedHandler then
    hooksecurefunc(schematicForm, "statsChangedHandler", ns.UpdateDisplay)
  end

  if ProfessionsRecipeSchematicFormMixin and ProfessionsRecipeSchematicFormMixin.Event then
    if ProfessionsRecipeSchematicFormMixin.Event.AllocationsModified then
      schematicForm:RegisterCallback(ProfessionsRecipeSchematicFormMixin.Event.AllocationsModified, ns.UpdateDisplay)
    end
    if ProfessionsRecipeSchematicFormMixin.Event.UseBestQualityModified then
      schematicForm:RegisterCallback(ProfessionsRecipeSchematicFormMixin.Event.UseBestQualityModified, ns.UpdateDisplay)
    end
  end

  if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.RegisterForDBUpdate then
    Auctionator.API.v1.RegisterForDBUpdate(CALLER_ID, RefreshAll)
  end

  RefreshAll()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("TRADE_SKILL_SHOW")
eventFrame:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
eventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_LOGIN" then
    ns.GetDB()
    if Auctionator and Auctionator.CraftingInfo and Auctionator.CraftingInfo.InitializeProfessionsFrame then
      hooksecurefunc(Auctionator.CraftingInfo, "InitializeProfessionsFrame", function()
        HookAuctionatorFrameIfPresent()
        InitializeProfessionsUI()
      end)
    end
    if ProfessionsFrame then
      InitializeProfessionsUI()
    end
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
    InitializeProfessionsUI()
    C_Timer.After(0, function()
      HookAuctionatorFrameIfPresent()
      RefreshAll()
    end)
  elseif event == "BAG_UPDATE_DELAYED" then
    if initialized and ProfessionsFrame and ProfessionsFrame:IsVisible() then
      RefreshAll()
    end
  elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
    if arg1 == Enum.PlayerInteractionType.Auctioneer and ns.UpdateScannerAHState then
      C_Timer.After(0, ns.UpdateScannerAHState)
    end
  end
end)

SLASH_AUCTIONATOROWNEDMATS1 = "/aom"
SLASH_AUCTIONATOROWNEDMATS2 = "/ownedmats"
SlashCmdList["AUCTIONATOROWNEDMATS"] = function(msg)
  local cmd = (msg or ""):lower():match("^%s*(.-)%s*$")
  local db = ns.GetDB()

  if cmd == "list" or cmd == "scan" or cmd == "best" then
    if ns.ToggleScannerWindow then
      ns.ToggleScannerWindow()
    end
    return
  end

  if cmd == "toggle" or cmd == "on" or cmd == "off" then
    if cmd == "on" then
      db.enabled = true
    elseif cmd == "off" then
      db.enabled = false
    else
      db.enabled = not db.enabled
    end
    print("|cff66d9efAuctionatorOwnedMats:|r " .. (db.enabled and "Enabled" or "Disabled"))
    ns.UpdateDisplay()
    return
  end

  if cmd == "debug" then
    if not (ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm) then
      print("|cff66d9efAuctionatorOwnedMats:|r Open a profession window first.")
      return
    end
    local schematicForm = ProfessionsFrame.CraftingPage.SchematicForm
    local recipeInfo = schematicForm:GetRecipeInfo()
    if not recipeInfo then
      print("|cff66d9efAuctionatorOwnedMats:|r Select a recipe first.")
      return
    end
    local recipeLevel = schematicForm.GetCurrentRecipeLevel and schematicForm:GetCurrentRecipeLevel() or nil
    local recipeSchematic = C_TradeSkillUI.GetRecipeSchematic(recipeInfo.recipeID, false, recipeLevel)
    local transaction = schematicForm.GetTransaction and schematicForm:GetTransaction() or nil
    local missingCost, fullCost, breakdown = ns.CalculateCosts(recipeSchematic, transaction)
    print(string.format("|cff66d9efAuctionatorOwnedMats:|r %s (Full: %s, Missing: %s)", recipeInfo.name or "?", ns.FormatMoney(fullCost), ns.FormatMoney(missingCost)))
    for _, entry in ipairs(breakdown) do
      local itemName = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(entry.itemID)) or tostring(entry.itemID)
      print(string.format("  - %s: need %d, in bags %d, missing %d @ %s", itemName, entry.needed, entry.usedFromBags, entry.missing, ns.FormatMoney(entry.unitPrice)))
    end
    return
  end

  print("|cff66d9efAuctionatorOwnedMats:|r Commands: /aom list | /aom toggle | /aom on | /aom off | /aom debug")
end
