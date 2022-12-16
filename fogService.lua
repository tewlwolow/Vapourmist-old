local this = {}

local config = require("tew\\Vapourmist\\config")
local version = require("tew\\Vapourmist\\version")
local VERSION = version.version
local data = require("tew\\Vapourmist\\data")

local WtC = tes3.worldController.weatherController

-- The array holding cells and their fog data --
local currentFogs = {
	["cloud"] = {},
	["mist"] = {},
	["interior"] = {}
}

this.meshes = {
	["cloud"] = nil,
	["mist"] = nil,
	["interior"] = nil
}

-- Print debug messages --
function this.debugLog(message)
	if config.debugLogOn then
		if not message then message = "n/a" end
		message = tostring(message)
		local info = debug.getinfo(2, "Sl")
		local module = info.short_src:match("^.+\\(.+).lua$")
		local prepend = ("[Vapourmist.%s.%s:%s]:"):format(VERSION, module, info.currentline)
		local aligned = ("%-36s"):format(prepend)
		mwse.log(aligned .. " -- " .. string.format("%s", message))
	end
end

-- Remove all cached fog data for particular fog type --
function this.purgeCurrentFogs(fogType)
	currentFogs[fogType] = {}
end

-- Update cache --
function this.updateCurrentFogs(fogType, fog, cell)
	currentFogs[fogType][fog] = cell
end

-- Returns true if the cell is fogged --
function this.isCellFogged(activeCell, fogType)
	if not currentFogs or not currentFogs[fogType] then return false end
	return table.find(currentFogs[fogType], activeCell) ~= nil
end



-- Remove fog meshes one by one --
local function removeSelected(fog)
	local emitter = fog:getObjectByName("Mist Emitter")
	if not emitter.appCulled then
		emitter.appCulled = true
		emitter:update()
		this.debugLog("Appculling fog: " .. fog.name)
	end
end

-- Clean distant fog and remove appculled fog --
function this.cleanInactiveFog()
	local mp = tes3.mobilePlayer
	if not mp or not mp.position then return end

	local vfxRoot = tes3.game.worldSceneGraphRoot.children[9]

	for _, node in pairs(vfxRoot.children) do
		if node and string.startswith(node.name, "tew_") then
			local emitter = node:getObjectByName("Mist Emitter")
			if emitter and emitter.appCulled then
				vfxRoot:detachChild(node)
				this.debugLog("Found appculled fog. Detaching.")

				for fogType, fogList in pairs(currentFogs) do
					if fogList[node] then
						fogList[node] = nil
						this.debugLog("Removed fog: " .. node.name)
					end
				end
			end
		end
	end


	for _, fogType in pairs(currentFogs) do
		for fog, _ in pairs(fogType) do
			if fog and fog.appCulled then
				vfxRoot:detachChild(fog)
				this.debugLog("Found appculled fog. Detaching.")
				fogType[fog] = nil
				this.debugLog("Removed fog: " .. fog.name)
			elseif fog and mp.position:distance(fog.translation) > data.fogDistance then
				this.debugLog("Found distant fog. Appculling.")
				removeSelected(fog)
			end
		end
	end

end

-- Check whether fog is appculled --
function this.isFogAppculled(fogType)
	local vfxRoot = tes3.game.worldSceneGraphRoot.children[9]
	for _, node in pairs(vfxRoot.children) do
		if node and string.startswith(node.name, "tew_" .. fogType) then
			local emitter = node:getObjectByName("Mist Emitter")
			if emitter and emitter.appCulled then
				this.debugLog("Fog is appculled.")
				return true
			end
		end
	end
end

-- Determine fog position for exteriors --
local function getFogPosition(activeCell, height)
	local average = 0
	local denom = 0
	for stat in activeCell:iterateReferences() do
		average = average + stat.position.z
		denom = denom + 1
	end

	if average == 0 or denom == 0 then
		return height
	end

	local result = (average / denom) + height
	if result <= 0 then
		return height
	elseif result > height then
		return height + 100
	end

	return result
end


-- Determine fog position for interiors --
local function getInteriorCellPosition(cell)
	local pos = { x = 0, y = 0, z = 0 }
	local denom = 0

	for stat in cell:iterateReferences() do
		pos.x = pos.x + stat.position.x
		pos.y = pos.y + stat.position.y
		pos.z = pos.z + stat.position.z
		denom = denom + 1
	end

	return { x = pos.x / denom, y = pos.y / denom, z = pos.z / denom }
end

-- Appculling switch --
function this.cullFog(bool, type)
	local vfxRoot = tes3.game.worldSceneGraphRoot.children[9]
	for _, node in pairs(vfxRoot.children) do
		if node and node.name == "tew_" .. type then
			for _, fog in pairs(node.children) do
				if fog.name == "Mist Emitter" then
					if fog.appCulled ~= bool then
						fog.appCulled = bool
						fog:update()
						this.debugLog("Appculling switched to " .. tostring(bool) .. " for " .. type .. " fogs.")
					end
				end
			end
		end
	end
end

-- Calculate output colours from current fog colour --
function this.getOutputValues()
	local currentFogColor = WtC.currentFogColor:copy()
	local currentSkyColor = WtC.currentSkyColor:copy()
	local weatherColour = {
		r = math.lerp(currentFogColor.r, currentSkyColor.r, 0.1),
		g = math.lerp(currentFogColor.g, currentSkyColor.g, 0.1),
		b = math.lerp(currentFogColor.b, currentSkyColor.b, 0.1)
	}
	return {
		colours = {
			r = math.clamp(weatherColour.r - 0.03, 0.03, 0.72),
			g = math.clamp(weatherColour.g - 0.02, 0.03, 0.72),
			b = math.clamp(weatherColour.b - 0.03, 0.03, 0.72)
		},
		angle = WtC.windVelocityCurrWeather:normalized():copy().y * math.pi * 0.5,
		speed = math.max(WtC.currentWeather.cloudsSpeed * config.speedCoefficient, data.minimumSpeed)
	}
end

function this.reColour()
	if not currentFogs then return end
	local output = this.getOutputValues()
	local fogColour = output.colours
	local speed = output.speed
	local angle = output.angle

	for _, fogType in pairs(currentFogs) do
		if not fogType then return end
		if fogType ~= currentFogs["interior"] then
			for fog, _ in pairs(fogType) do
				if fog and fogType ~= "interior" then
					local particleSystem = fog:getObjectByName("MistEffect")
					local controller = particleSystem.controller
					local colorModifier = controller.particleModifiers

					if fogType == currentFogs["cloud"] then
						controller.speed = speed
						controller.planarAngle = angle
					end

					for _, key in pairs(colorModifier.colorData.keys) do
						key.color.r = fogColour.r
						key.color.g = fogColour.g
						key.color.b = fogColour.b
					end

					local materialProperty = particleSystem.materialProperty
					materialProperty.emissive = fogColour
					materialProperty.specular = fogColour
					materialProperty.diffuse = fogColour
					materialProperty.ambient = fogColour

					particleSystem:update()
					particleSystem:updateProperties()
					particleSystem:updateNodeEffects()
					fog:update()
					fog:updateProperties()
					fog:updateNodeEffects()
				end
			end
		end
	end
end


-- Add fogs to the active cells
function this.addFog(options)
	local type = options.type
	local height = options.height

	local vfxRoot = tes3.game.worldSceneGraphRoot.children[9]

	this.debugLog("Checking if we can add fog: " .. type)

	for _, activeCell in pairs(tes3.getActiveCells()) do
		if not this.isCellFogged(activeCell, type) and not activeCell.isInterior then
			this.debugLog("Cell is not fogged. Adding " .. type .. ".")

			local fogPosition = tes3vector3.new(
			8192 * activeCell.gridX + 4096,
			8192 * activeCell.gridY + 4096,
			getFogPosition(activeCell, height)
		)

		if tes3.player.position:copy():distance(fogPosition:copy()) <= data.fogDistance then
			local fogMesh = this.meshes[type]:clone()
			fogMesh:clearTransforms()
			fogMesh.translation = fogPosition

			vfxRoot:attachChild(fogMesh, true)

			for _, vfx in pairs(vfxRoot.children) do
				if vfx and vfx.name == "tew_" .. type then
					local particleSystem = vfx:getObjectByName("MistEffect")
					local controller = particleSystem.controller
					controller.initialSize = table.choice(data.fogTypes[type].initialSize)
					this.updateCurrentFogs(type, vfx, activeCell)
				end
			end

			fogMesh:update()
			fogMesh:updateProperties()
			fogMesh:updateNodeEffects()
		end
	end
end
end


-- Removes fog from view by appculling - with fade out
function this.removeFog(fogType)
	this.debugLog("Removing fog of type: " .. fogType)
	this.cullFog(true, fogType)
end

-- Removes fog from view by detaching - without fade out
function this.removeFogImmediate(fogType)
	this.debugLog("Immediately removing fog of type: " .. fogType)
	local vfxRoot = tes3.game.worldSceneGraphRoot.children[9]
	for _, node in pairs(vfxRoot.children) do
		if node and node.name == "tew_" .. fogType then
			vfxRoot:detachChild(node)
		end
	end
	this.purgeCurrentFogs(fogType)
end

-- Add fog to interior, a wee bit different func here --
function this.addInteriorFog(options)
	this.debugLog("Adding interior fog.")

	local vfxRoot = tes3.game.worldSceneGraphRoot.children[9]

	local fogType = data.interiorFog.name
	local height = options.height
	local cell = options.cell

	if not this.isCellFogged(cell, fogType) then
		this.debugLog("Interior cell is not fogged. Adding " .. fogType .. ".")
		local fogMesh = this.meshes["interior"]:clone()
		local pos = getInteriorCellPosition(cell)

		fogMesh:clearTransforms()
		fogMesh.translation = tes3vector3.new(
		pos.x,
		pos.y,
		pos.z + height
	)

		local originalInteriorFogColor = cell.fogColor
		local interiorFogColor = {
			r = math.clamp(math.lerp(originalInteriorFogColor.r, 1.0, 0.5), 0.3, 0.85),
			g = math.clamp(math.lerp(originalInteriorFogColor.r, 1.0, 0.46), 0.3, 0.85),
			b = math.clamp(math.lerp(originalInteriorFogColor.r, 1.0, 0.42), 0.3, 0.85)
		}

		local particleSystem = fogMesh:getObjectByName("MistEffect")
		local controller = particleSystem.controller
		controller.initialSize = table.choice(data.interiorFog.initialSize)
		local colorModifier = controller.particleModifiers
		for _, key in pairs(colorModifier.colorData.keys) do
			key.color.r = interiorFogColor.r
			key.color.g = interiorFogColor.g
			key.color.b = interiorFogColor.b
		end
		local materialProperty = particleSystem.materialProperty
		materialProperty.emissive = interiorFogColor
		materialProperty.specular = interiorFogColor
		materialProperty.diffuse = interiorFogColor
		materialProperty.ambient = interiorFogColor

		particleSystem:updateNodeEffects()
		this.updateCurrentFogs(fogType, fogMesh, cell)

		vfxRoot:attachChild(fogMesh, true)

		fogMesh:update()
		fogMesh:updateProperties()
		fogMesh:updateNodeEffects()
	end
end


-- Just remove them all --
function this.removeAll()
	local vfxRoot = tes3.game.worldSceneGraphRoot.children[9]
	for _, node in pairs(vfxRoot.children) do
		if node and string.startswith(node.name, "tew_") then
			vfxRoot:detachChild(node)
		end
	end

	currentFogs = {
		["cloud"] = {},
		["mist"] = {},
		["interior"] = {},
	}

	this.debugLog("All fog removed.")
end

-- Just remove exterior fogs. Useful for interiors --
function this.removeAllExterior()
	local vfxRoot = tes3.game.worldSceneGraphRoot.children[9]
	for _, node in pairs(vfxRoot.children) do
		if node and string.startswith(node.name, "tew_") and not (node.name == "tew_interior") then
			vfxRoot:detachChild(node)
		end
	end

	currentFogs["cloud"] = {}
	currentFogs["mist"] = {}

	this.debugLog("All exterior fog removed.")
end

return this
