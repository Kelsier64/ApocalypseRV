-- 01: tempo, sections, tracks, FX chains and routing for the Slender Speaker Für Elise.
assert(H.project_file():find("SlenderSpeaker_FurElise", 1, true), "wrong project tab: " .. tostring(H.project_file()))

H.set_tempo(56, 3, 8)

H.clear_markers()
H.region("Fog", 1, 16)
H.region("A far", 16, 33)
H.region("B closer", 33, 39)
H.region("A'' close", 39, 47)
H.region("Stuck", 47, 63)
H.region("Leaving", 63, 89)

local function T(name, o) return H.get_or_add_track(name, o) end

-- three loudspeakers of the giant
local spk = {
  { "Speaker C", 0.0, "#c8a040" },
  { "Speaker L", -0.65, "#b08a30" },
  { "Speaker R", 0.65, "#b08a30" },
}
for _, s in ipairs(spk) do
  local tr = T(s[1], { pan = s[2], color = s[3], master_send = false })
  H.fx(tr, "Surge XT")
end

local horn = T("Horn", { color = "#806020", master_send = false })
H.fx(horn, "JS: Saturation")
H.fx(horn, "ReaEQ")

local dist = T("Distance", { color = "#604818" })
H.fx(dist, "ReaEQ")
H.fx(dist, "JS: Volume/Pan Adjustment")

local verb = T("Fog Reverb", { color = "#405060" })
H.fx(verb, "ReaVerbate")
local echo = T("Forest Echo", { color = "#405060" })
H.fx(echo, "ReaDelay")

for _, n in ipairs({ "Drone", "Rust", "Footsteps", "Fog Wind" }) do
  local tr = T(n, { color = "#506070" })
  H.fx(tr, "Surge XT")
end

for _, s in ipairs(spk) do H.ensure_send(s[1], horn, 0) end
H.ensure_send(horn, dist, 0)
H.ensure_send(horn, verb, -8)
H.ensure_send(horn, echo, -16)
H.ensure_send("Drone", verb, -10)
H.ensure_send("Rust", verb, -4)
H.ensure_send("Footsteps", verb, -9)

local master = reaper.GetMasterTrack(0)
H.fx(master, "JS: Master Limiter")

H.save()
return H.dump({ sends = true })
