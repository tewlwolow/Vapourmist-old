local this = {}

local config = require("tew.Vapourmist.config")
local version = require("tew.Vapourmist.version")
local VERSION = version.version
local data = require("tew.Vapourmist.data")

local CELL_SIZE = 8192

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
function this.updateCurrentFogs(fogType, fog, cellName)
	currentFogs[fogType][fog] = cellName
end

-- Returns true if the cell is fogged --
function this.isCellFogged(cellName, fogType)
	if table.empty(currentFogs) or table.empty(currentFogs[fogType]) then return false end
	return table.find(currentFogs[fogType], cellName)
end

-- Appculling switch --
function this.cullFog(bool, fogType)
	local vfxRoot = tes3.game.worldSceneGraphRoot.children[9]
	for _, node in pairs(vfxRoot.children) do
		if node and node.name == "tew_" .. fogType then
			local emitter = node:getObjectByName("Mist Emitter")
			if emitter.appCulled ~= bool then
				emitter.appCulled = bool
				emitter:update()
				node:update()
				this.debugLog("Appculling switched to " .. tostring(bool) .. " for " .. fogType .. " fog.")
			end
		end
	end
end

-- Remove fog meshes one by one --
local function removeSelected(fog)
	local emitter = fog:getObjectByName("Mist Emitter")
	if not emitter.appCulled then
		emitter.appCulled = true
		emitter:update()
		fog:update()
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

				for _, fogList in pairs(currentFogs) do
					for fog, _ in pairs(fogList) do
						if node == fog then
							fogList[fog] = nil
							this.debugLog("Removed fog: " .. node.name)
						end
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

local function getFogMix(fog, sky)
	return math.lerp(fog, sky, 0.17)
end

local function getLerpedComp(comp)
	return math.clamp(math.lerp(comp, 1.0, 0.03), 0.03, 0.88)
end

-- Calculate output colours from current fog colour --
function this.getOutputValues()
	local currentFogColor = WtC.currentFogColor:copy()
	local currentSkyColor = WtC.currentSkyColor:copy()
	local weatherColour = {
		r = getFogMix(currentFogColor.r, currentSkyColor.r),
		g = getFogMix(currentFogColor.g, currentSkyColor.g),
		b = getFogMix(currentFogColor.b, currentSkyColor.b)
	}
	return {
		colours = {
			r = getLerpedComp(weatherColour.r),
			g = getLerpedComp(weatherColour.g),
			b = getLerpedComp(weatherColour.b)
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
					local emitters = {
						fog:getObjectByName("FogLayer1"),
						fog:getObjectByName("FogLayer2"),
						fog:getObjectByName("FogLayer3")
					}

					for _, emitter in ipairs(emitters) do
						if not emitter then goto continue end

						local controller = emitter.controller
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

						local materialProperty = emitter.materialProperty
						materialProperty.emissive = fogColour
						materialProperty.specular = fogColour
						materialProperty.diffuse = fogColour
						materialProperty.ambient = fogColour

						emitter:update()
						emitter:updateProperties()
						emitter:updateNodeEffects()
						fog:update()
						fog:updateProperties()
						fog:updateNodeEffects()

						:: continue ::
					end
				end
			end
		end
	end
end

local function deployEmitter(vfx, particleSystem, cellName, fogType)
	if not particleSystem then return end
	local drawDistance = mge.distantLandRenderConfig.drawDistance
	local controller = particleSystem.controller
	local birthRate = (math.random(0.5, 1.5) * drawDistance) - CELL_SIZE
	controller.birthRate = birthRate
	controller.useBirthRate = true
	local lifespan = controller.lifespan * birthRate * 0.6
	controller.lifespan = lifespan * controller.birthRate
	controller.emitterWidth = CELL_SIZE * drawDistance
	controller.emitterHeight = CELL_SIZE * drawDistance
	controller.emitterDepth = math.random(700, 2400)
	local sizeArray = data.fogTypes[fogType].initialSize
	controller.initialSize = sizeArray[math.random(1, #sizeArray)]
	this.updateCurrentFogs(fogType, vfx, cellName)
end

-- Add fogs to the active cells
function this.addFog(options)
	local fogType = options.type
	local height = options.height

	local vfxRoot = tes3.game.worldSceneGraphRoot.children[9]

	this.debugLog("Checking if we can add fog: " .. fogType)

	local activeCell = tes3.getPlayerCell()
	local cellName = activeCell.editorName

	if not this.isCellFogged(cellName, fogType) and not activeCell.isInterior then
		this.debugLog("Cell is not fogged. Adding " .. fogType .. ".")

		local fogPosition = tes3vector3.new(
			CELL_SIZE * activeCell.gridX + CELL_SIZE/2,
			CELL_SIZE * activeCell.gridY + CELL_SIZE/2,
			getFogPosition(activeCell, height)
		)

		local fogMesh = this.meshes[fogType]:clone()
		fogMesh:clearTransforms()
		fogMesh.translation = fogPosition

		vfxRoot:attachChild(fogMesh, true)

		for _, vfx in pairs(vfxRoot.children) do
			if vfx and vfx.name == "tew_" .. fogType then
				deployEmitter(vfx, vfx:getObjectByName("FogLayer1"), cellName, fogType)
				deployEmitter(vfx, vfx:getObjectByName("FogLayer2"), cellName, fogType)
				deployEmitter(vfx, vfx:getObjectByName("FogLayer3"), cellName, fogType)
			end
		end

		fogMesh:update()
		fogMesh:updateProperties()
		fogMesh:updateNodeEffects()
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
	this.updateCurrentFogs(fogType, fogMesh, cell.editorName)

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
