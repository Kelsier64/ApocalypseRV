-- 04: levels and automation (distance, drone filter, wind gusts, footstep loudness).
assert(H.project_file():find("SlenderSpeaker_FurElise", 1, true), "wrong project tab: " .. tostring(H.project_file()))

H.mix("Drone", { vol_db = -14 })
H.mix("Rust", { vol_db = -13 })
H.mix("Fog Wind", { vol_db = -24 })
H.mix("Speaker L", { vol_db = -2 })
H.mix("Speaker R", { vol_db = -2 })

local check = {}

-- The giant approaches through the fog, stands over you, then walks off.
check.distance_vol = H.automate_display("Distance", "Volume/Pan", "Volume", {
  { 1, -30 }, { 15, -26 }, { 17, -22 }, { 25, -15 }, { 33, -8 }, { 39, -2 }, { 46, 0 },
  { 47, 0 }, { 55, -6 }, { 63, -14 }, { 70, -20 }, { 88, -34 },
})
check.distance_air = H.automate_display("Distance", "ReaEQ", "Gain-High Shelf 4", {
  { 1, -16 }, { 15, -14 }, { 17, -12 }, { 25, -8 }, { 33, -4 }, { 39, -1 }, { 46, 0 },
  { 47, 0 }, { 55, -3 }, { 63, -8 }, { 70, -12 }, { 88, -18 },
})

check.drone_cutoff = H.automate_display("Drone", "Surge", "A Filter 1 Cutoff", {
  { 1, 220, 2 }, { 33, 320, 2 }, { 39, 650, 2 }, { 46, 800, 2 }, { 47, 400, 2 }, { 63, 260, 2 }, { 88, 180 },
})

local gusts, b, hi = {}, 1, false
while b <= 88 do
  gusts[#gusts + 1] = { b, hi and 1100 or 450, 2 }
  hi = not hi; b = b + 3
end
check.wind = H.automate_display("Fog Wind", "Surge", "A Filter 1 Cutoff", gusts)

H.fx("Footsteps", "JS: Volume/Pan Adjustment")
check.steps = H.automate_display("Footsteps", "Volume/Pan", "Volume", {
  { 16, -24 }, { 33, -10 }, { 39, -3 }, { 46, 0 }, { 48, 0 }, { 63, -12 }, { 80, -26 },
})

H.save()
return check
