--[[ Copyright (c) 2019 Optera
 * Part of Ghost Scanner
 *
 * See LICENSE.md in the project directory for license information.
--]]

-- local logger = require("__OpteraLib__.script.logger")
-- logger.settings.read_all_properties = false
-- logger.settings.max_depth = 6

-- logger.settings.class_dictionary.LuaEntity = {
--   backer_name = true,
--   name = true,
--   type = true,
--   unit_number = true,
--   force = true,
--   logistic_network = true,
--   logistic_cell = true,
--   item_requests = true,
--   ghost_prototype = true,
--  }
-- logger.settings.class_dictionary.LuaEntityPrototype = {
--   type = true,
--   name = true,
--   valid = true,
--   items_to_place_this = true,
--   next_upgrade = true,
--  }


-- constant prototypes names
local Scanner_Name = "ghost-scanner"

---- MOD SETTINGS ----

local UpdateInterval = settings.global["ghost-scanner-update-interval"].value
local MaxResults = settings.global["ghost-scanner-max-results"].value
if MaxResults == 0 then MaxResults = nil end
local ShowHidden = settings.global["ghost-scanner-show-hidden"].value
local InvertSign = settings.global["ghost-scanner-negative-output"].value
local RoundToStack = settings.global["ghost-scanner-round2stack"].value
local ShowCellCount = settings.global["ghost-scanner-cell-count"].value
local AreaReduction = settings.global["ghost-scanner-area-reduction"].value

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting == "ghost-scanner-update-interval" then
    UpdateInterval = settings.global["ghost-scanner-update-interval"].value
    UpdateEventHandlers()
  end
  if event.setting == "ghost-scanner-max-results" then
    MaxResults = settings.global["ghost-scanner-max-results"].value
    if MaxResults == 0 then MaxResults = nil end
  end
  if event.setting == "ghost-scanner-show-hidden" then
    ShowHidden = settings.global["ghost-scanner-show-hidden"].value
    storage.Lookup_items_to_place_this = {}
  end
  if event.setting == "ghost-scanner-negative-output" then
    InvertSign = settings.global["ghost-scanner-negative-output"].value
  end
  if event.setting == "ghost-scanner-round2stack" then
    RoundToStack = settings.global["ghost-scanner-round2stack"].value
  end
  if event.setting == "ghost-scanner-cell-count" then
    ShowCellCount = settings.global["ghost-scanner-cell-count"].value
  end
  if event.setting == "ghost-scanner-area-reduction" then
    AreaReduction = settings.global["ghost-scanner-area-reduction"].value
  end
end)


---- EVENTS ----

do -- create & remove
function OnEntityCreated(event)
  local entity = event.created_entity or event.entity
  if entity and entity.valid then
    if entity.name == Scanner_Name then
      storage.GhostScanners = storage.GhostScanners or {}

      -- entity.operable = false
      -- entity.rotatable = false

      local ghostScanner = {}
      ghostScanner.ID = entity.unit_number
      ghostScanner.entity = entity
      storage.GhostScanners[#storage.GhostScanners+1] = ghostScanner

      UpdateEventHandlers()
    end

  end

end

function RemoveSensor(id)
  if not storage.GhostScanners then return end
  for i=#storage.GhostScanners, 1, -1 do
    if id == storage.GhostScanners[i].ID then
      table.remove(storage.GhostScanners,i)
    end
  end

  UpdateEventHandlers()
end

function OnEntityRemoved(event)
  if event.entity and event.entity.valid and event.entity.name == Scanner_Name then
    RemoveSensor(event.entity.unit_number)
  end
end
end

do -- tick handlers
function UpdateEventHandlers()
  -- unsubscribe tick handlers
  script.on_nth_tick(nil)
  script.on_event(defines.events.on_tick, nil)

  -- subcribe tick or nth_tick depending on number of scanners
  local entity_count = storage.GhostScanners and #storage.GhostScanners or 0
  if entity_count > 0 then
    local nth_tick = UpdateInterval / entity_count
    if nth_tick >= 2 then
      script.on_nth_tick(math.floor(nth_tick), OnNthTick)
    else
      script.on_event(defines.events.on_tick, OnTick)
    end

    script.on_event({defines.events.on_pre_player_mined_item, defines.events.on_robot_pre_mined, defines.events.on_entity_died}, OnEntityRemoved)
  else  -- all sensors removed
    script.on_event({defines.events.on_pre_player_mined_item, defines.events.on_robot_pre_mined, defines.events.on_entity_died}, nil)
  end
end

-- runs when #storage.GhostScanners > UpdateInterval/2
function OnTick(event)
  if not storage.GhostScanners or #storage.GhostScanners == 0 then return end
  local offset = event.tick % UpdateInterval
  for i=#storage.GhostScanners - offset, 1, -1 * UpdateInterval do
    local ghostScanner = storage.GhostScanners[i]
    if ghostScanner then
      if ghostScanner.entity and ghostScanner.entity.valid then
        UpdateSensor(ghostScanner)
      else
        RemoveSensor(ghostScanner.ID)
      end
    end
  end
end

-- runs when #storage.GhostScanners <= UpdateInterval/2
function OnNthTick(NthTickEvent)
  if not storage.GhostScanners or #storage.GhostScanners == 0 then return end
  if storage.UpdateIndex > #storage.GhostScanners then
    storage.UpdateIndex = 1
  end

  local ghostScanner = storage.GhostScanners[storage.UpdateIndex]
  if ghostScanner then
    if ghostScanner.entity and ghostScanner.entity.valid then
      UpdateSensor(ghostScanner)
    else
      RemoveSensor(ghostScanner.ID)
    end
  end

  storage.UpdateIndex = storage.UpdateIndex + 1
end

end



---- update Sensor ----
do
local signals
local signal_indexes

local function get_items_to_place(prototype)
  if ShowHidden then
    storage.Lookup_items_to_place_this[prototype.name] = prototype.items_to_place_this
  else
    -- filter items flagged as hidden
    local items_to_place_filtered = {}
    for _, v in pairs (prototype.items_to_place_this) do
      local item = v.name and prototypes.item[v.name]
      if item and not item.hidden then
        items_to_place_filtered[#items_to_place_filtered+1] = v
      end
    end
    storage.Lookup_items_to_place_this[prototype.name] = items_to_place_filtered
  end
  return storage.Lookup_items_to_place_this[prototype.name]
end

local function add_signal(signal_type, name, count, quality)
  local item_uid = name
  if quality then
    local prototype_name = type(quality) == "table" and quality.name or quality
    item_uid = name .. ":" .. prototype_name
  end

  local signal_index = signal_indexes[item_uid]
  local s
  if signal_index then
    s = signals[signal_index]
  else
    signal_index = #signals + 1
    signal_indexes[item_uid] = signal_index
    s = {
      value = {
        type = signal_type,
        name = name,
        quality = type(quality) == "table" and quality.name or quality
      },
      min = 0
    }
    signals[signal_index] = s
  end

  if InvertSign then
    s.min = s.min - count
  else
    s.min = s.min + count
  end
end

local function is_in_bbox(pos, area)
  if pos.x >= area.left_top.x and pos.x <= area.right_bottom.x
  and pos.y >= area.left_top.y and pos.y <= area.right_bottom.y then
    return true
  end
  return false
end

--- returns ghost requested items as signals or nil
local function get_ghosts_as_signals(logsiticNetwork)
  if not (logsiticNetwork and logsiticNetwork.valid) then
    return nil
  end

  local result_limit = MaxResults

  local search_areas = {}
  local found_entities ={} -- store found unit_numbers to prevent duplicate entries
  signals = {}
  signal_indexes = {}

  -- logistic networks don't have an id outside the gui, show the number of cells (roboports) to match the gui
  if ShowCellCount then
    add_signal("virtual", "ghost-scanner-cell-count", table_size(logsiticNetwork.cells))
  end

  for _,cell in pairs(logsiticNetwork.cells) do
    local pos = cell.owner.position
    local r = cell.construction_radius
    if r > 0 then
      local bounds = {
        left_top={ x=pos.x-r, y=pos.y-r, },
        right_bottom={ x=pos.x+r, y=pos.y+r }
      }
      local inner_bounds = { -- hack to skip checking if position is inside bounds for tiles
        left_top={ x=pos.x-r+AreaReduction, y=pos.y-r+AreaReduction },
        right_bottom={ x=pos.x+r-AreaReduction, y=pos.y+r-AreaReduction }
      }
      search_areas[#search_areas+1] = {
        bounds=bounds,
        inner_bounds=inner_bounds,
        force=logsiticNetwork.force,
        surface=cell.owner.surface
      }
    end
  end

  -- cliffs
  for _, search_area in pairs(search_areas) do
    local entities = search_area.surface.find_entities_filtered{area=search_area.inner_bounds, limit=result_limit, type="cliff"}
    local count_unique_entities = 0
    for _, e in pairs(entities) do
      local uid = e.unit_number or e.position
      if not found_entities[uid] and e.to_be_deconstructed() and e.prototype.cliff_explosive_prototype then
        found_entities[uid] = true
        add_signal("item", e.prototype.cliff_explosive_prototype, 1)
        count_unique_entities = count_unique_entities + 1
      end
    end
    if MaxResults then
      result_limit = result_limit - count_unique_entities
      if result_limit <= 0 then break end
    end
  end

  -- upgrade requests (requires 0.17.69)
  if MaxResults == nil or result_limit > 0 then
    for _, search_area in pairs(search_areas) do
      local entities = search_area.surface.find_entities_filtered{area=search_area.bounds, limit=result_limit, to_be_upgraded=true, force=search_area.force}
      local count_unique_entities = 0
      for _, e in pairs(entities) do
        local uid = e.unit_number
        local upgrade_target = {e.get_upgrade_target()}
        local upgrade_prototype = upgrade_target[1]
        local quality = upgrade_target[2]
        if not found_entities[uid] and upgrade_prototype and is_in_bbox(e.position, search_area.bounds) then
          found_entities[uid] = true
          local items_to_place = storage.Lookup_items_to_place_this[upgrade_prototype.name] or get_items_to_place(upgrade_prototype)
          for _, item_stack in pairs(items_to_place) do
            add_signal("item", item_stack.name, item_stack.count, quality)
            count_unique_entities = count_unique_entities + item_stack.count
          end
        end
      end
      if MaxResults then
        result_limit = result_limit - count_unique_entities
        if result_limit <= 0 then break end
      end
    end
  end

  -- entity-ghost knows items_to_place_this and item_requests (modules)
  if MaxResults == nil or result_limit > 0 then
    for _, search_area in pairs(search_areas) do
      local entities = search_area.surface.find_entities_filtered{area=search_area.bounds, limit=result_limit, type="entity-ghost", force=search_area.force}
      local count_unique_entities = 0
      for _, e in pairs(entities) do
        local uid = e.unit_number
        if not found_entities[uid] and is_in_bbox(e.position, search_area.bounds) then
          found_entities[uid] = true
          for _, item_stack in pairs(
            storage.Lookup_items_to_place_this[e.ghost_name] or
            get_items_to_place(e.ghost_prototype)
          ) do
            add_signal("item", item_stack.name, item_stack.count, e.quality)
            count_unique_entities = count_unique_entities + item_stack.count
          end

          for _, request_item in ipairs(e.item_requests) do
            add_signal("item", request_item.name, request_item.count, request_item.quality)
            count_unique_entities = count_unique_entities + request_item.count
          end
        end
      end
      if MaxResults then
        result_limit = result_limit - count_unique_entities
        if result_limit <= 0 then break end
      end
    end
  end

  -- item-request-proxy holds item_requests (modules) for built entities
  if MaxResults == nil or result_limit > 0 then
    for _, search_area in pairs(search_areas) do
      local entities = search_area.surface.find_entities_filtered{area=search_area.inner_bounds, limit=result_limit, type="item-request-proxy", force=search_area.force}
      local count_unique_entities = 0
      for _, e in pairs(entities) do
        local uid = script.register_on_object_destroyed(e)
        if not found_entities[uid] then
          found_entities[uid] = true
          for _, request_item in ipairs(e.item_requests) do
            add_signal("item", request_item.name, request_item.count, request_item.quality)
            count_unique_entities = count_unique_entities + request_item.count
          end
        end
      end
      if MaxResults then
        result_limit = result_limit - count_unique_entities
        if result_limit <= 0 then break end
      end
    end
  end

  -- tile-ghost knows only items_to_place_this
  if MaxResults == nil or result_limit > 0 then
    for _, search_area in pairs(search_areas) do
      local entities = search_area.surface.find_entities_filtered{area=search_area.inner_bounds, limit=result_limit, type="tile-ghost", force=search_area.force}
      local count_unique_entities = 0
      for _, e in pairs(entities) do
        local uid = e.unit_number
        if not found_entities[uid] then
          found_entities[uid] = true
          for _, item_stack in pairs(
            storage.Lookup_items_to_place_this[e.ghost_name] or
            get_items_to_place(e.ghost_prototype)
          ) do
            add_signal("item", item_stack.name, item_stack.count, item_stack.quality)
            count_unique_entities = count_unique_entities + item_stack.count
          end
        end
      end
      if MaxResults then
        result_limit = result_limit - count_unique_entities
        if result_limit <= 0 then break end
      end
    end
  end

  -- round signals to next stack size
  if RoundToStack then
    local round = math.ceil
    if InvertSign then round = math.floor end

    for _, signal in pairs(signals) do
      local prototype = prototypes.item[signal.value.name]
      if prototype then
        local stack_size = prototype.stack_size
        signal.min = round(signal.min / stack_size) * stack_size
      end
    end
  end

  return signals
end

local function set_combinator_signals(cb, signals)
  if not cb or not cb.valid then return end
  
  local section
  if cb.sections_count == 0 then
    section = cb.add_section()
  else
    section = cb.get_section(1)
  end

  if section then
    section.filters = signals or {}
  end
end

function UpdateSensor(ghostScanner)
  if not (ghostScanner and ghostScanner.entity and ghostScanner.entity.valid) then
    if ghostScanner and ghostScanner.ID then RemoveSensor(ghostScanner.ID) end
    return
  end

  local cb = ghostScanner.entity.get_control_behavior()
  if not cb then return end

  if not cb.enabled then
    set_combinator_signals(cb, nil)
    return
  end

  local logisticNetwork = ghostScanner.entity.surface.find_logistic_network_by_position(ghostScanner.entity.position, ghostScanner.entity.force)
  if not logisticNetwork then
    set_combinator_signals(cb, nil)
    return
  end

  local signals = get_ghosts_as_signals(logisticNetwork)
  set_combinator_signals(cb, signals)
end

end


---- INIT ----
do
local function init_events()
  script.on_event({
    defines.events.on_built_entity,
    defines.events.on_robot_built_entity,
    defines.events.script_raised_built,
    defines.events.script_raised_revive,
  }, OnEntityCreated)
  if storage.GhostScanners then
    UpdateEventHandlers()
  end
end

script.on_load(function()
  init_events()
end)

script.on_init(function()
  storage.GhostScanners = storage.GhostScanners or {}
  storage.UpdateIndex = storage.UpdateIndex or 1
  storage.Lookup_items_to_place_this = {}
  init_events()
end)

script.on_configuration_changed(function(data)
  storage.GhostScanners = storage.GhostScanners or {}
  storage.UpdateIndex = storage.UpdateIndex or 1
  storage.Lookup_items_to_place_this = {}
  init_events()
end)

end
