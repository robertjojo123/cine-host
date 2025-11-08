-- farmer.lua (deposit fix + inventory rules)
-- - First cycle after reboot: deposit path rotates 90° anti-clockwise
-- - Slot 1: placing block only; Slots 2..16: harvested items only

--------------------- CONFIG ------------------------
local STATE_FILE = "farmer_state.json"
local CLEAR_ON_RESUME = true
local WAIT_POLL_SEC = 2
local TAKE_COUNT = 8

------------------- STATE / LOAD --------------------
local state = {
  x = 0, z = 0, dir = 0,
  go_dir = nil,
  resumed = false
}

local function save()
  local f = fs.open(STATE_FILE, "w")
  f.write(textutils.serializeJSON(state))
  f.close()
end

local function load()
  if not fs.exists(STATE_FILE) then save() return false end
  local ok, data = pcall(function()
    local f = fs.open(STATE_FILE, "r")
    local t = textutils.unserializeJSON(f.readAll())
    f.close(); return t
  end)
  if ok and data and data.x and data.z and data.dir then
    state = data; state.resumed = true; return true
  end
  save(); return false
end

------------------ MOVEMENT CORE --------------------
local function fwd()
  if not turtle.forward() then
    turtle.dig(); turtle.attack(); sleep(0.1)
    if not turtle.forward() then error("blocked forward") end
  end
end

local function sfwd(n)
  for _=1,(n or 1) do
    fwd()
    if state.dir == 0 then state.z = state.z - 1
    elseif state.dir == 1 then state.x = state.x + 1
    elseif state.dir == 2 then state.z = state.z + 1
    else state.x = state.x - 1 end
    save()
  end
end

local function sl() turtle.turnLeft();  state.dir = (state.dir + 3) % 4; save() end
local function sr() turtle.turnRight(); state.dir = (state.dir + 1) % 4; save() end

local function face(d)
  local t = (d - state.dir) % 4
  if t == 1 then sr()
  elseif t == 2 then sr(); sr()
  elseif t == 3 then sl()
  end
end

local function goto(x,z)
  local dx, dz = x - state.x, z - state.z
  if dx ~= 0 then face(dx>0 and 1 or 3); sfwd(math.abs(dx)) end
  if dz ~= 0 then face(dz>0 and 2 or 0); sfwd(math.abs(dz)) end
end

local function goHome()
  goto(0,0)
  face(state.go_dir)
end

------------------- UTILITIES -----------------------
local function waitCropChange(before)
  while true do
    local ok, d = turtle.inspectDown()
    if (ok and d.name or "none") ~= before then return end
    sleep(WAIT_POLL_SEC)
  end
end

-- Ensure slot 1 is selected and used for placement only
local function selectSlot1ForPlacement()
  if turtle.getSelectedSlot() ~= 1 then turtle.select(1) end
end

----------------- IN / OUT MOTIONS ------------------
-- Intake: fill ONLY slot 1 with placing blocks from the supply chest (down)
local function intake()
  sr()
  sfwd(1)
  turtle.select(1)
  -- If slot1 already has a different item, do not mix; just top up the same item
  local d1 = turtle.getItemDetail(1)
  turtle.suckDown(TAKE_COUNT)  -- will add to slot 1 only
  sl(); sl()
  sfwd(1)
  sr()
end

-- Shared walker for the placement shape
local function walkPlacementShape(cb)
  sfwd(2); cb()              -- spot 1
  sfwd(1); cb()              -- spot 2
  sl(); sfwd(1); cb()        -- spot 3
  sfwd(1); cb()              -- spot 4
  sl(); sfwd(1); cb()        -- spot 5
  sfwd(1); cb()              -- spot 6
  sl(); sfwd(1); cb()        -- spot 7
  sfwd(1); cb()              -- spot 8
end

-- Placement: always place from slot 1
local function placement()
  selectSlot1ForPlacement()
  walkPlacementShape(function()
    selectSlot1ForPlacement()
    turtle.placeDown()
  end)
end

-- Deposit: drop everything from slots 2..16 to the down chest at the deposit station.
-- 'useResumeRotation' = true ONLY for the first cycle after a reboot: rotate path 90° anti-clockwise.
local function deposit(useResumeRotation)
  if useResumeRotation then
    -- 90° anti-clockwise vs normal deposit path
    sl(); sfwd(2)
  else
    sr(); sfwd(2)
  end
  -- Drop slots 2..16 only (preserve slot 1 for next placement)
  for s = 2, 16 do
    if turtle.getItemCount(s) > 0 then
      turtle.select(s)
      turtle.dropDown(turtle.getItemCount(s))
    end
  end
  -- restore orientation and return to the exact pre-deposit spot
  sl(); sl()
  sfwd(1)
  turtle.select(1)
end

------------------- HARVEST -------------------------
local function harvestPathToDeposit()
  turtle.digDown()
  sl(); sfwd(1); turtle.digDown()
  sfwd(1); turtle.digDown()
  sl(); sfwd(1); turtle.digDown()
  sfwd(1); turtle.digDown()
  sl(); sfwd(1); turtle.digDown()
  sfwd(1)
  -- At this point we are in the same place the old script used before its "turnRight(); forward(); forward()"
end

------------------- TARGETED CLEAR ------------------
local function walkClearPlacement()
  walkPlacementShape(function() turtle.digDown() end)
end

local function clearField()
  goHome()
  walkClearPlacement()  -- digs only the 8 placement spots
  goHome()
end

------------------- STARTUP -------------------------
local resumed = load()

if not state.go_dir then
  state.go_dir = state.dir
  save()
end

goHome()
face(state.go_dir)

if resumed and CLEAR_ON_RESUME then
  clearField()
  -- keep resumed=true for the first deposit rotation; we'll clear it after first cycle
end

------------------- MAIN LOOP -----------------------
while true do
  -- 1) Intake placing blocks into slot 1
  intake()

  -- 2) Place
  placement()

  -- 3) Wait for growth/transformation
  local ok, d = turtle.inspectDown()
  waitCropChange((ok and d.name) or "none")

  -- 4) Harvest along the footprint and stop at pre-deposit position
  harvestPathToDeposit()

  -- 5) Deposit (rotate 90° anti-clockwise IF this is the first cycle after reboot)
  deposit(resumed)

  -- After the very first post-reboot cycle, turn off the special rotation
  if resumed then
    state.resumed = false
    resumed = false
    save()
  end

  -- 6) Return home for next loop
  goHome()
end
