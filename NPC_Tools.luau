--!strict
-- Can't set as first line bc of strict, but this was fully made by @israphaelgo on Discord and Roblox.

--// SERVICES // DEPENDENCIES

local _Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Npc_Types = require(ServerStorage.Default_Trees_Types.NPC_TREE)

local Velocity_Arrow = script.ArrowHead

-- // SETTINGS

local Visual_Raycast_Properties = {
	NoHitColor = Color3.new(0.94902, 1, 0), --# If nothing is hit
	HitColor = Color3.new(1, 0, 0), --# If something is hit
	Shape = Enum.PartType.Block, --# For now only block has good support
	Width = 0.025,
	Height = 0.025,
}

local Eye_Movement_Settings = {
	Max_Studs_Movement = 0.035, -- Default studs movement for the eyes
	ShrinkLimiter = 0.55, -- How close the ocular can be to the edge of the eye, 1 being on the edge, 0 being in the middle of the eye
}

-- // TYPE DEFINITIONS

type Obj = Npc_Types.Obj
type Last_Seen = Npc_Types.Last_Seen
type EyesData = Npc_Types.EyesInfo
type NPC_Info = Npc_Types.Npc_Info

type Model = typeof(workspace.R6) -- Temporary type, will be changed to a more specific type if needed
type ModelEye = typeof(workspace.R6.Head.EyeL)

-- // INIT

local module = {}

-- // INDEPENDENT METHODS

function module.Clean_Rays()
	for _, v in pairs(CollectionService:GetTagged("VisualRayCast")) do -- Get any visual raycast and cleans them up (could be replaced for a cache folder)
		v:Destroy()
	end
end

-- // DEPENDENT METHODS

-- // RAYCASTS
function module.GetEyesConstraints(Object: Obj) -- Automatically set eye constraints, allows for any type of eyes to be used
	local Model = Object.Npc_Info.Model
	local Eyes = Model.Head:FindFirstChild("Eyes")
	local EyesInfo = Object.Npc_Info.EyesInfo

	if Eyes then
		for _, Eye: typeof(Eyes.EyeL) in pairs(Eyes:GetChildren()) do
			local EyeLetter = Eye.Name:sub(#Eye.Name) -- Get the last letter of the eye name, assuming it's either L or R
			local Ocular = Eye.Ocular

			if not Ocular then
				continue
			end

			local EyeMiddlePoint = Eye.Position --# Get the middle point of the eye

			local OcularMiddlePoint = Vector3.new(Ocular.Position.X, Ocular.Position.Y, EyeMiddlePoint.Z)
			local OcularEdgeX =
				Vector3.new(OcularMiddlePoint.X + Ocular.Size.X / 2, OcularMiddlePoint.Y, OcularMiddlePoint.Z)
			local EyeEdgeX = Vector3.new(EyeMiddlePoint.X + Eye.Size.X / 2, EyeMiddlePoint.Y, EyeMiddlePoint.Z)

			-- Getting the edge of the eye & ocular allows for a better calculation of the constraints

			local OcularEdgeY =
				Vector3.new(OcularMiddlePoint.X, OcularMiddlePoint.Y + Ocular.Size.Y / 2, OcularMiddlePoint.Z)
			local EyeEdgeY = Vector3.new(EyeMiddlePoint.X, EyeMiddlePoint.Y + Ocular.Size.Y / 2, EyeMiddlePoint.Z)

			local XLimit = (OcularEdgeX - EyeEdgeX).Magnitude * Eye_Movement_Settings.ShrinkLimiter
			local YLimit = (OcularEdgeY - EyeEdgeY).Magnitude * Eye_Movement_Settings.ShrinkLimiter

			-- We get the magnitude between both edges and shrink it using the shrink limiter, this allows for a more natural movement of the oculars

			EyesInfo.MoveConstraints[`{EyeLetter}Limit`] = {
				X = XLimit,
				Y = YLimit,
			}
		end
	end
end

function module.RayCastToDirection( -- Unused function I stored up, just wanted there to be more available raycast functions, might be useful for future use
	Origin: BasePart,
	Longitude: number,
	ExclusionList: {},
	XTilt: number,
	YTilt: number,
	ZTilt: number
): (Vector3?, RaycastResult?)
	if not Origin or not Longitude then
		return
	end

	local Params = RaycastParams.new()
	Params.FilterType = Enum.RaycastFilterType.Exclude
	Params.FilterDescendantsInstances = { unpack(ExclusionList), unpack(CollectionService:GetTagged("VisualRayCast")) }

	--# CFRAME VERSION: local Look_Point = Head.CFrame:ToWorldSpace(CFrame.new(CFrame.Angles(20, 0, 0).LookVector * Longitude))
	local Look_Point = (Origin.CFrame * CFrame.Angles(math.rad(XTilt or 0), math.rad(YTilt or 0), math.rad(ZTilt or 0))).LookVector
		* Longitude
	-- Edit the CFrame so it has the adjusted tilts as an angle and the elongate the tilted CFrame with out longitude from the lookvector

	local RayResult = workspace:Raycast(Origin.Position, Look_Point, Params)
	local HitPosition

	if not RayResult then
		HitPosition = Origin.Position + Look_Point -- Gets a point for reference as to how far the raycast went, even if it didn't hit anything
	else
		HitPosition = RayResult.Position
	end

	return HitPosition :: Vector3, RayResult :: RaycastResult?
end

function module.RayCastToTarget( -- Main raycast function, allows for vector3, parts and tables of parts to be used as targets, also allows for a max magnitude to be set, if the target is further than the max magnitude it will not raycast
	Origin: BasePart,
	Target: Vector3 | BasePart | { Instance },
	ExclusionList: {},
	MaxMagnitude: number?
): (Vector3?, RaycastResult?)
	if not Origin or not Target then
		return
	end

	MaxMagnitude = MaxMagnitude or 100 -- If no max magnitude is set, it will default to 100 studs

	local Params = RaycastParams.new()
	Params.FilterType = Enum.RaycastFilterType.Exclude
	Params.FilterDescendantsInstances =
		{ unpack(ExclusionList), unpack(CollectionService:GetTagged("VisualRayCast")), Origin }

	if typeof(Target) == "Instance" and Target:IsA("BasePart") then -- If the passed target was an instance then save its position as a vector3, saves the trouble
		Target = Target.Position
	end

	-- If target is a vector3 execute the code
	if typeof(Target) == "Vector3" then
		local Difference = (Target - Origin.Position)
		local RayResult: RaycastResult?
		local HitPosition: Vector3?

		-- If MaxMagnitude was passed and the magnitude betweent the target and the npc is less than MaxMagnitude then raycast
		if MaxMagnitude and Difference.Magnitude < MaxMagnitude then
			RayResult = workspace:Raycast(
				Origin.Position,
				Difference.Unit * (Difference.Magnitude + 10), --+10 Just in case, to make sure the raycast reaches the target
				Params
			)
		end

		if RayResult then
			HitPosition = RayResult.Position
		elseif MaxMagnitude and Difference.Magnitude < MaxMagnitude then
			HitPosition = Difference.Unit * Difference.Magnitude
		end

		return HitPosition :: Vector3?, RayResult :: RaycastResult?
	elseif typeof(Target) == "table" then -- Return the first part that is hit in the table, useful for characters
		for i, Part in Target do
			if typeof(Part) == "Instance" and Part:IsA("BasePart") then
				local Difference = (Part.Position - Origin.Position)
				local RayResult: RaycastResult?
				local HitPosition: Vector3?

				-- If MaxMagnitude was passed and the magnitude betweent the target and the npc is less than MaxMagnitude then raycast
				if MaxMagnitude and Difference.Magnitude < MaxMagnitude then
					RayResult = workspace:Raycast(
						Origin.Position,
						Difference.Unit * (Difference.Magnitude + 10), --+10 Just in case, to make sure the raycast reaches the target
						Params
					)
				end

				if RayResult then
					HitPosition = RayResult.Position

					return HitPosition :: Vector3, RayResult :: RaycastResult
				elseif i == #Target and MaxMagnitude and Difference.Magnitude < MaxMagnitude then -- If no parts were hit and the last part is being indexed then to return a reference point for the raycast
					HitPosition = Difference.Unit * Difference.Magnitude

					return HitPosition :: Vector3, RayResult :: RaycastResult?
				end
			end
		end
	end

	return
end

function module.Check_Visibility(NPC_Info: Npc_Types.Npc_Info, Target: Player)
	local Player_Character = Target and Target.Character
	local Player_HRP = Player_Character and Player_Character:FindFirstChild("HumanoidRootPart") :: BasePart

	--Sanity checks
	if not Player_Character or not NPC_Info or not Player_HRP or not Player_HRP:IsDescendantOf(workspace) then
		return false
	end

	local Model = NPC_Info.Model

	local ModelHRP = Model.HumanoidRootPart

	for _, Eye in pairs(Model.Head.Eyes:GetChildren()) do -- This allows for actual functionality to the eyes, instead of using the head as a fixed anchor to check the player's position I use the eyes
		Eye = Eye :: typeof(Model.Head.Eyes.EyeL) -- Just for the types
		local Ocular = Eye.Ocular

		if not Ocular then
			continue
		end

		local Difference = (Player_HRP.Position - Ocular.Position)
		local DirectionToEye = Difference.Unit
		local DotValue = ModelHRP.CFrame.LookVector:Dot(DirectionToEye)

		local RaycastTable: { Instance }
		local FilterTable = { Model }

		for _, Part in pairs(Player_Character:GetChildren()) do
			if Part:IsA("BasePart") then
				RaycastTable = RaycastTable or {}
				table.insert(RaycastTable, Part) -- We want to raycast to the parts of the character, so we add them to the raycast table
			elseif Part:IsA("Accessory") then
				local Handle = Part:FindFirstChild("Handle")
				if Handle and Handle:IsA("BasePart") then
					table.insert(FilterTable, Handle) -- We don't want to raycast to the handle of the accessory, so we add it to the filter table
				end
			end
		end

		--[[why >=? :dot is determining how close the direction to the character is to the
			model's lookvector, math.cos determines the limit of this, so if :dot returns 1 it
			means it's spot on the lookvector]]

		-- TL;DR: if the dot value is greater than or equal to the fov, then the character is within the fov of the npc
		if DotValue >= NPC_Info.Fov and Difference.Magnitude <= NPC_Info.VisualRange then
			local _Hit, RayCast = module.RayCastToTarget(Model.Head, RaycastTable, FilterTable, NPC_Info.VisualRange)

			if RayCast and RayCast.Instance:IsDescendantOf(Player_Character) then
				return true
			end
		end
	end

	return false
end
-- For visual raycast referencing
function module.VisualizeRaycast(RayResult: RaycastResult?, HitPosition: Vector3, Origin: BasePart)
	if not HitPosition then
		return
	end

	local Difference = HitPosition - Origin.Position -- Get the vector "line/difference" between the origin and the hit position, this will be used to determine the size of the visual raycast
	local Size_ZAxis = Difference.Magnitude -- Longitude
	local Position_MiddlePoint = Origin.Position + Difference / 2 -- This works smoothly because we take into account half of the "line/difference" vector, which is halfway of the desitnation of origin to the HitPosition and this allows for the Z axis size to have clear space to make a pointing effect
	local Position_CFrame = CFrame.lookAt(Position_MiddlePoint, HitPosition) -- Points towards the HitPosition

	local VisualRay = Instance.new("Part")
	VisualRay.CanCollide = false
	VisualRay.Anchored = true
	VisualRay.Shape = Visual_Raycast_Properties.Shape
	VisualRay.Size = Vector3.new(Visual_Raycast_Properties.Width, Visual_Raycast_Properties.Width, Size_ZAxis) -- Take settings into account
	VisualRay.CFrame = Position_CFrame
	VisualRay.Parent = workspace
	VisualRay:AddTag("VisualRayCast")

	if not RayResult then
		VisualRay.Color = Visual_Raycast_Properties.NoHitColor -- If there wasn't a Part hit, turn into no hit color
	else
		VisualRay.Color = Visual_Raycast_Properties.HitColor -- If there was a Part hit, turn into hit color
	end
end

-- // PREDICTION/NPC-RELATED
-- Predict position of the player based on their last seen position and velocity, and the time it takes for the NPC to reach the last seen position of the player. Returns the predicted CFrame, or nil if prediction is not possible.
function module.Predict(Object: Obj): CFrame | nil | boolean
	local Last_Target = Object.Short_Term_Memory.Last_Target
	local Long_Term_Memory, Last_Seen, Short_Term_Memory
	local Temp = Object.Blackboard.Temp

	if not Temp then
		Object.Blackboard.Temp = {}
		Temp = {}
	end

	if not Last_Target then
		warn("No last target to predict.")
		return
	end

	Long_Term_Memory = Object.Long_Term_Memory[Last_Target]
	Short_Term_Memory = Object.Short_Term_Memory[Last_Target]

	if not Long_Term_Memory or not Short_Term_Memory then
		warn("Target has not been recorded in the memory.")
		return
	end

	Last_Seen = Long_Term_Memory.Last_Seen

	if not Short_Term_Memory.Time_To_Reach or not Last_Seen or not Last_Seen.CFrame then
		warn("Insufficient information to predict.")
		return
	end
	-- Post Sanity checks

	if not Last_Seen.Velocity then
		Last_Seen.Velocity = Last_Seen.CFrame.LookVector * 5 --Set a default velocity if none was provided
	end

	local Velocity_CFrame = CFrame.lookAlong(Last_Seen.CFrame.Position, Last_Seen.Velocity.Unit) -- Referencing the direction the player was headed at using the velocity's unit
	local VelocityMagnitude = Last_Seen.Velocity.Magnitude
	-- D = V * T
	local ZIncrement = math.abs(VelocityMagnitude * Short_Term_Memory.Time_To_Reach) -- Ensures it's a positive number, it's the predicted studs the player moved

	local AppliedCFrame = Velocity_CFrame + (Velocity_CFrame.LookVector * ZIncrement) -- The predicted CFrame is taking the CFrame the player was last seen in as starting point and from then to point towards the predicted player position

	Short_Term_Memory.Predicted_CFrame = AppliedCFrame -- Save it onto the short term memory for external referencing

	local BallDisplay = Instance.new("Part")
	BallDisplay.Anchored = true
	BallDisplay.Shape = Enum.PartType.Ball
	BallDisplay.CanCollide = false
	BallDisplay.Size = Vector3.new(2.6, 2.6, 2.6)
	BallDisplay.CFrame = AppliedCFrame
	BallDisplay.Transparency = 0.7
	BallDisplay.Color = Color3.new(1, 1, 0)
	BallDisplay.Parent = workspace
	-- Create a visual reference
	-- If the temp table exists, destroy the previous ball display and set the new one
	if Temp then
		if Temp.BallDisplay then
			Temp.BallDisplay:Destroy()
		end

		Temp.BallDisplay = BallDisplay
	end

	return AppliedCFrame
end
-- Show the last seen position of the player, with a red ball and a blue line indicating the direction they were moving in
function module.Display_LastSeen(Last_CFrame: CFrame, Velocity: Vector3): Model
	if not Last_CFrame then
		return
	end
	if not Velocity then
		Velocity = Last_CFrame.LookVector * 5 -- Set a default velocity if none was provided
	end

	local AppliedCframe = CFrame.lookAlong(Last_CFrame.Position, Velocity.Unit) -- The ball will be facing the direction the player was moving in, using the velocity's unit to determine the direction
	local VelocityMagnitude = Velocity.Magnitude * 0.3 -- Get the overall speed and tone it down a bit so the arrow isn't 28 studs long

	local BallDisplay = Instance.new("Part")
	BallDisplay.Anchored = true
	BallDisplay.Shape = Enum.PartType.Ball
	BallDisplay.CanCollide = false
	BallDisplay.Size = Vector3.new(2.6, 2.6, 2.6)
	BallDisplay.CFrame = AppliedCframe
	BallDisplay.Transparency = 0.7
	BallDisplay.Color = Color3.new(1, 0, 0)

	local LookVector_Display = Instance.new("Part")
	LookVector_Display.Anchored = true
	LookVector_Display.CanCollide = false
	LookVector_Display.Size = Vector3.new(0.5, 0.5, VelocityMagnitude) -- Make it be as long as the player's Speed (toned down)
	LookVector_Display.CFrame = AppliedCframe + (AppliedCframe.LookVector * VelocityMagnitude / 2) -- Move it forward so the arrow is in front of the ball taking the dimensions in mind
	LookVector_Display.Transparency = 0.7
	LookVector_Display.Color = Color3.new(0.129412, 0.329412, 0.72549)

	local Arrow = Velocity_Arrow:Clone()
	Arrow.CFrame = (
		LookVector_Display.CFrame
		+ (LookVector_Display.CFrame.LookVector * (LookVector_Display.Size.Z / 2 + Arrow.Size.Z / 2))
	) -- * CFrame.Angles(0, 0, math.rad(90))

	-- Parent under a model for easier cleanup
	local Model = Instance.new("Model")
	Model.Parent = workspace

	Arrow.Parent = Model
	BallDisplay.Parent = Model
	LookVector_Display.Parent = Model

	return Model
end

--# Might be wise to make it a combined function to make it move the head aswell, should do later or sum
-- Moves the eyes (woooow insane system!11!)
function module.MoveOculars(Obj: Obj, Target: Vector3)
	if not Obj or not Target then
		return
	end

	local Model = Obj.Npc_Info.Model
	local ModelHRP = Model.HumanoidRootPart :: BasePart

	if not Model or not ModelHRP then
		return
	end
	-- Post sanity checks

	for _, Eye in pairs(Obj.Npc_Info.Model.Head.Eyes:GetChildren()) do -- Loop through the eyes of the NPC, and move them towards the target position`
		Eye = Eye :: typeof(Obj.Npc_Info.Model.Head.Eyes.EyeL) -- Purely for the type
		local EyeLetter = Eye.Name:sub(#Eye.Name) -- Get its letter
		local Ocular = Eye and Eye.Ocular
		local Limits = Obj.Npc_Info.EyesInfo.MoveConstraints[`{EyeLetter}Limit`] -- Get the respective limit with the Eye's letter

		if not Ocular or not Obj.Npc_Info.EyesInfo then
			continue
		end
		-- Post sanity checks

		local Weld = Ocular:FindFirstChildWhichIsA("Weld")

		local Offset = Eye.CFrame:PointToObjectSpace(Target) -- Get the target's position relative to the Eye, which could be considered as an offset
		local Unit = Offset.Unit -- Get the direction of the offset/player from the eye, so Eye --> player, we get that line and where it's pointing

		-- We get how much the line is pointing towards both the X and Y directions
		local UnitX = Unit.X * 0.13 -- The 0.13 is a soft limiter, so the stud movement of the eye was more fluid, so if the X was just 1 it wouldn't literally try to move 1 stud
		local UnitY = Unit.Y * 0.13

		local XLimit = Eye_Movement_Settings.Max_Studs_Movement
		local YLimit = Eye_Movement_Settings.Max_Studs_Movement -- Sets default limits (Not accurate)

		if Limits then
			XLimit = Limits["X"]
			YLimit = Limits["Y"] -- Sets dynamically adjusted limits if they're available (Accurate)
		end

		local ClampUnitX, ClampUnitY = math.clamp(UnitX, -XLimit, XLimit), math.clamp(UnitY, -YLimit, YLimit) -- Clamped values, so the oculars don't go overboard and look weird or clip outisde of the iris(in this case the eye)
		local _OverboardX = XLimit - UnitX --head movement, if negative then there's overboard
		local _OverboardY = YLimit - UnitY --head movement, if negative then there's overboard
		--The overboards are in case I want to add head movement, calculates whether there's overboard movement if it's a negative, and if so, it says how much

		local ClampedCFrame = CFrame.new(Vector3.new(ClampUnitX, ClampUnitY, 0)) -- Final result, must be used with a weld, since they're the perfect fit for this
		-- Tween the weld with the new CFrame, looks better
		TweenService:Create(Weld, TweenInfo.new(0.1), { C0 = ClampedCFrame }):Play()

		--[[If you ask why use a weld, it's because of their adjustable nature, they cling to the eye even unanchored, which is
		the safest optimization decision, since you wouldn't want to be running a constant hell loop that updates the eye's position constantly,
		the weld, unlike the weldconstraint allows for offests to be set, which is perfect for the eye movement, so we calculate how much to which
		side the player is compared to the ocular's position, we calculate the studs it must move in order to match that position and boom! working
		eyes]]
	end
end

return module

--[[ This module is the head and the necessity of my project, without it, nothing works since it provides all the core functions, I hoped to provide
-- something else to provide a more broad example of the overall code in my project but this was the only cohesive 200+ lines piece of code I could
find

Also, for the record, I use behavior trees for the npc]]
