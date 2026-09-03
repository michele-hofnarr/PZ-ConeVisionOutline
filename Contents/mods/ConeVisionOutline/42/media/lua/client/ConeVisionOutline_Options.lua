-- Mod options for Cone Vision Outline (Settings -> Mods).
-- Color and intensity (alpha) for cone outline (zombies/animals in vision cone).
local MODULE_ID = "ConeVisionOutline"

ConeVisionOutlineOptions = ConeVisionOutlineOptions or {}
ConeVisionOutlineOptions.ConeOutlineColor = { r = 1, g = 1, b = 1 }  -- RGB from color picker
ConeVisionOutlineOptions.ConeOutlineAlpha = 0.3  -- intensity 0..1 from slider
ConeVisionOutlineOptions.LegacyOutlineMode = false  -- use the pre-v1.3 visibility check instead of the engine's own per-object signal
ConeVisionOutlineOptions.ScaleOutlineByLight = false  -- scale outline alpha by square light level (both modes)
ConeVisionOutlineOptions.ScaleOutlineByFog = false  -- scale outline alpha by world fog thickness at the target's distance (both modes)
ConeVisionOutlineOptions.OutlineAlwaysOn = false  -- show outlines at all times, not just while aiming (RMB) or driving
ConeVisionOutlineOptions.VehicleOutlineAlwaysOn = false  -- in vehicle: show outlines without holding RMB
ConeVisionOutlineOptions.OutlineAnimals = true  -- outline animals as well as zombies

local PZOptions

local function applyOptions()
    if not PZAPI or not PZAPI.ModOptions then return end
    local options = PZAPI.ModOptions:getOptions(MODULE_ID)
    if options then
        local optColor = options:getOption("ConeOutlineColor")
        if optColor then
            ConeVisionOutlineOptions.ConeOutlineColor = optColor:getValue()
        end
        local optAlpha = options:getOption("ConeOutlineAlpha")
        if optAlpha then
            ConeVisionOutlineOptions.ConeOutlineAlpha = optAlpha:getValue()
        end
        local optLegacyMode = options:getOption("LegacyOutlineMode")
        if optLegacyMode then
            ConeVisionOutlineOptions.LegacyOutlineMode = optLegacyMode:getValue()
        end
        local optScaleLight = options:getOption("ScaleOutlineByLight")
        if optScaleLight then
            ConeVisionOutlineOptions.ScaleOutlineByLight = optScaleLight:getValue()
        end
        local optScaleFog = options:getOption("ScaleOutlineByFog")
        if optScaleFog then
            ConeVisionOutlineOptions.ScaleOutlineByFog = optScaleFog:getValue()
        end
        local optAlwaysOn = options:getOption("OutlineAlwaysOn")
        if optAlwaysOn then
            ConeVisionOutlineOptions.OutlineAlwaysOn = optAlwaysOn:getValue()
        end
        local optVehicleAlways = options:getOption("VehicleOutlineAlwaysOn")
        if optVehicleAlways then
            ConeVisionOutlineOptions.VehicleOutlineAlwaysOn = optVehicleAlways:getValue()
        end
        local optOutlineAnimals = options:getOption("OutlineAnimals")
        if optOutlineAnimals then
            ConeVisionOutlineOptions.OutlineAnimals = optOutlineAnimals:getValue()
        end
    end
end

local function initConfig()
    if not PZAPI or not PZAPI.ModOptions then return end
    PZOptions = PZAPI.ModOptions:create(MODULE_ID, getText("UI_CVO_Options_Title"))

    local p = ConeVisionOutlineOptions.ConeOutlineColor
    PZOptions:addColorPicker(
        "ConeOutlineColor",
        getText("UI_CVO_Options_ConeOutlineColor"),
        p.r or 1, p.g or 1, p.b or 1, 1,
        getText("UI_CVO_Options_ConeOutlineColor_Tooltip")
    )
    PZOptions:addSlider(
        "ConeOutlineAlpha",
        getText("UI_CVO_Options_ConeOutlineAlpha"),
        0, 1, 0.05,
        ConeVisionOutlineOptions.ConeOutlineAlpha,
        getText("UI_CVO_Options_ConeOutlineAlpha_Tooltip")
    )
    PZOptions:addTickBox(
        "LegacyOutlineMode",
        getText("UI_CVO_Options_LegacyOutlineMode"),
        ConeVisionOutlineOptions.LegacyOutlineMode,
        getText("UI_CVO_Options_LegacyOutlineMode_Tooltip")
    )
    PZOptions:addTickBox(
        "ScaleOutlineByLight",
        getText("UI_CVO_Options_ScaleOutlineByLight"),
        ConeVisionOutlineOptions.ScaleOutlineByLight,
        getText("UI_CVO_Options_ScaleOutlineByLight_Tooltip")
    )
    PZOptions:addTickBox(
        "ScaleOutlineByFog",
        getText("UI_CVO_Options_ScaleOutlineByFog"),
        ConeVisionOutlineOptions.ScaleOutlineByFog,
        getText("UI_CVO_Options_ScaleOutlineByFog_Tooltip")
    )
    PZOptions:addTickBox(
        "OutlineAlwaysOn",
        getText("UI_CVO_Options_OutlineAlwaysOn"),
        ConeVisionOutlineOptions.OutlineAlwaysOn,
        getText("UI_CVO_Options_OutlineAlwaysOn_Tooltip")
    )
    PZOptions:addTickBox(
        "VehicleOutlineAlwaysOn",
        getText("UI_CVO_Options_VehicleOutlineAlwaysOn"),
        ConeVisionOutlineOptions.VehicleOutlineAlwaysOn,
        getText("UI_CVO_Options_VehicleOutlineAlwaysOn_Tooltip")
    )
    PZOptions:addTickBox(
        "OutlineAnimals",
        getText("UI_CVO_Options_OutlineAnimals"),
        ConeVisionOutlineOptions.OutlineAnimals,
        getText("UI_CVO_Options_OutlineAnimals_Tooltip")
    )

    PZOptions.apply = function()
        applyOptions()
    end
end

initConfig()

Events.OnMainMenuEnter.Add(function()
    applyOptions()
end)

Events.OnGameStart.Add(function()
    applyOptions()
end)

return ConeVisionOutlineOptions
