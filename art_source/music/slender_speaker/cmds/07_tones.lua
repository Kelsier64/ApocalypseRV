-- 07: three electronic melody-IC tone candidates + a moderate horn loudspeaker. Dry: no reverb/delay
-- (the game positions the sound and adds the space).
assert(H.project_file():find("SlenderSpeaker_FurElise", 1, true), "wrong project tab: " .. tostring(H.project_file()))

local got = {}
local function S(track, fx, param, value)
  local ok, res = pcall(H.set, track, fx, param, value)
  got[#got + 1] = track .. " / " .. param .. " = " .. tostring(value) .. " -> " .. tostring(ok and res or ("ERROR " .. tostring(res)))
end

-- A: square-wave chip, mild decay to a sustain (classic melody IC).
local a = "Tone A square"
S(a, "Surge", "A Osc 1 Type", "Classic")
S(a, "Surge", "A Osc 1 Shape", 100)
S(a, "Surge", "A Osc 1 Width 1", 50)
S(a, "Surge", "A Osc Drift", 2)
S(a, "Surge", "A Amp EG Attack", 0)
S(a, "Surge", "A Amp EG Decay", 600)
S(a, "Surge", "A Amp EG Sustain", 40)
S(a, "Surge", "A Amp EG Release", 80)

-- B: music-box IC: sine + octave + twelfth, piano-like decay to silence.
local b = "Tone B music box"
S(b, "Surge", "A Osc 1 Type", "Sine")
S(b, "Surge", "A Osc 2 Type", "Sine")
S(b, "Surge", "A Osc 2 Octave", 1)
S(b, "Surge", "A Osc 2 Volume", -8)
S(b, "Surge", "A Osc 2 Mute", "Off")
S(b, "Surge", "A Osc 3 Type", "Sine")
S(b, "Surge", "A Osc 3 Octave", 1)
S(b, "Surge", "A Osc 3 Pitch", 7)
S(b, "Surge", "A Osc 3 Volume", -16)
S(b, "Surge", "A Osc 3 Mute", "Off")
S(b, "Surge", "A Amp EG Attack", 0)
S(b, "Surge", "A Amp EG Decay", 1100)
S(b, "Surge", "A Amp EG Sustain", 0)
S(b, "Surge", "A Amp EG Release", 400)

-- C: narrow pulse, nasal and buzzy, organ-like sustain.
local c = "Tone C pulse"
S(c, "Surge", "A Osc 1 Type", "Classic")
S(c, "Surge", "A Osc 1 Shape", 100)
S(c, "Surge", "A Osc 1 Width 1", 25)
S(c, "Surge", "A Osc Drift", 2)
S(c, "Surge", "A Amp EG Attack", 0)
S(c, "Surge", "A Amp EG Decay", 250)
S(c, "Surge", "A Amp EG Sustain", 75)
S(c, "Surge", "A Amp EG Release", 60)

-- Loudspeaker: moderate horn colour (band-limited, a little honk and grit).
local L = "Loudspeaker"
S(L, "Saturation", "Amount (%)", 40)
S(L, "ReaEQ", "Freq-High Pass 5", 400)
S(L, "ReaEQ", "Freq-Low Shelf", 200)
S(L, "ReaEQ", "Gain-Low Shelf", -6)
S(L, "ReaEQ", "Freq-Band 3", 1500)
S(L, "ReaEQ", "Gain-Band 3", 5)
S(L, "ReaEQ", "BW-Band 3", 1.5)
S(L, "ReaEQ", "Freq-High Shelf 4", 6000)
S(L, "ReaEQ", "Gain-High Shelf 4", -12)

local m = reaper.GetMasterTrack(0)
got[#got + 1] = "master limiter threshold -> " .. tostring(H.set(m, "Master Limiter", "Threshold", -1))

H.save()
return got
