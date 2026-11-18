-- 03: notes for every track. Re-runnable: deletes this script's items first.
assert(H.project_file():find("SlenderSpeaker_FurElise", 1, true), "wrong project tab: " .. tostring(H.project_file()))

local src = dofile("C:/Users/evan4/Projects/ApocalypseRV/art_source/music/slender_speaker/furelise_notes.lua")
local LAST_BAR = 89
local function q(bar) return (bar - 1) * 1.5 end   -- bar -> QN from bar 1 (3/8)

local function fresh(track, name)
  H.delete_items(track)
  return (H.midi_item(track, 1, LAST_BAR - 1, { name = name }))
end

-- Speaker lag: speakers drift out of sync as the giant approaches.
-- returns QN lag for each speaker at a given QN.
local function lag(spk, at)
  local a = math.max(0, math.min(1, (at - q(16)) / (q(46) - q(16))))
  if spk == "Speaker C" then return 0 end
  if spk == "Speaker L" then return 0.02 + 0.10 * a end
  return 0.04 + 0.21 * a
end

local counts = {}
for _, spk in ipairs({ "Speaker C", "Speaker L", "Speaker R" }) do
  local take = fresh(spk, "für elise (" .. spk .. ")")
  local notes = {}
  local function add(p, s, l, v, extra_lag)
    notes[#notes + 1] = { p = p, s = s + lag(spk, s) + (extra_lag or 0), l = l, v = v }
  end

  -- Fog: two distant fragments, only the centre speaker, the second one breaks off.
  for _, n in ipairs(src.rh) do
    if n[1] >= 1 and n[1] <= 3 and spk == "Speaker C" then add(n[3], n[1] + q(6), n[2], 70) end
    if n[1] >= 1 and n[1] <= 2 and spk == "Speaker C" then add(n[3], n[1] + q(11), n[2], 60) end
  end

  -- Full piece: original bar 1 (pickup) -> bar 16. Ends on bar 46.
  for _, n in ipairs(src.rh) do add(n[3], n[1] + q(16), n[2], 100) end
  for _, n in ipairs(src.lh) do add(n[3], n[1] + q(16), n[2], 82) end

  -- Stuck: E-D# loops like a jammed chip, slowing, sagging in pitch, speakers smearing apart.
  local t, gap, k = q(47) + 0.5, 0.25, 0
  local extra = ({ ["Speaker C"] = 0, ["Speaker L"] = 0.3, ["Speaker R"] = 0.55 })[spk]
  while t < q(62) do
    local pitch = ((k % 2 == 0) and 76 or 75) - math.floor(k / 8)
    local v = math.floor(100 - 55 * (t - q(47)) / (q(62) - q(47)))
    notes[#notes + 1] = { p = pitch, s = t + extra * (t - q(47)) / (q(62) - q(47)), l = 0.23, v = v }
    t = t + gap; gap = gap * 1.06; k = k + 1
  end

  -- Leaving: the A phrase once more, far away, speakers badly out of step.
  local far_lag = ({ ["Speaker C"] = 0, ["Speaker L"] = 0.18, ["Speaker R"] = 0.4 })[spk]
  for _, n in ipairs(src.rh) do
    if n[1] < q(10) then notes[#notes + 1] = { p = n[3], s = n[1] + q(70) + far_lag, l = n[2], v = 75 } end
  end
  for _, n in ipairs(src.lh) do
    if n[1] < q(10) then notes[#notes + 1] = { p = n[3], s = n[1] + q(70) + far_lag, l = n[2], v = 60 } end
  end
  -- last call: E-D# far off.
  if spk ~= "Speaker L" then
    notes[#notes + 1] = { p = 76, s = q(84) + 1 + far_lag, l = 0.23, v = 60 }
    notes[#notes + 1] = { p = 75, s = q(84) + 1.25 + far_lag, l = 0.23, v = 60 }
  end
  H.add_notes(take, notes)
  counts[spk] = #notes
end

-- Drone: A pedal, dissonances in fog/climax/stuck.
do
  local take = fresh("Drone", "drone")
  local N = {}
  local function hold(p, b1, b2, v) N[#N + 1] = { p = p, s = q(b1), l = q(b2) - q(b1), v = v } end
  hold(33, 1, 33, 80); hold(40, 1, 33, 70)
  hold(34, 9, 15, 50)
  hold(36, 33, 39, 80); hold(43, 33, 39, 70)
  hold(33, 39, 47, 95); hold(40, 39, 47, 85); hold(41, 41, 47, 70)
  hold(34, 47, 63, 85); hold(40, 47, 63, 75)
  hold(33, 63, 88, 70); hold(40, 63, 88, 60)
  H.add_notes(take, N)
  counts.Drone = #N
end

-- Rust: sparse metal clangs.
do
  local take = fresh("Rust", "rust hits")
  local bars = { 4, 9.5, 14, 21, 27.33, 31, 36, 41, 44, 47, 50, 53.5, 57, 60, 66, 75, 83 }
  local pitches = { 37, 43, 39, 33 }
  local N = {}
  for i, b in ipairs(bars) do N[#N + 1] = { p = pitches[(i - 1) % #pitches + 1], s = q(b), l = 1.5, v = 90 } end
  H.add_notes(take, N)
  counts.Rust = #N
end

-- Footsteps: giant stride, every 2 bars, every bar when close.
do
  local take = fresh("Footsteps", "footsteps")
  local N = {}
  local function step(b) N[#N + 1] = { p = 28, s = q(b), l = 1.0, v = 110 } end
  for b = 18, 38, 2 do step(b) end
  for b = 39, 47 do step(b) end
  for b = 64, 80, 2 do step(b) end
  H.add_notes(take, N)
  counts.Footsteps = #N
end

-- Fog wind: one long noise note.
do
  local take = fresh("Fog Wind", "wind")
  H.add_notes(take, { { p = 60, s = 0, l = q(88), v = 100 } })
end

H.save()
return counts
