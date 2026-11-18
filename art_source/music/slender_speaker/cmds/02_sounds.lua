-- 02: patches and effect settings.
assert(H.project_file():find("SlenderSpeaker_FurElise", 1, true), "wrong project tab: " .. tostring(H.project_file()))

local got = {}
local function S(track, fx, param, value)
  local ok, res = pcall(H.set, track, fx, param, value)
  got[#got + 1] = track .. " / " .. param .. " = " .. tostring(value) .. " -> " .. tostring(ok and res or ("ERROR " .. tostring(res)))
end

-- Three loudspeakers: cheap music-box square chip, each drifting / detuned differently.
local speakers = {
  { "Speaker C", 0.0, 6, 100 },
  { "Speaker L", -0.22, 14, 82 },
  { "Speaker R", 0.17, 10, 100 },
}
for _, s in ipairs(speakers) do
  local t = s[1]
  S(t, "Surge", "A Osc 1 Type", "Classic")
  S(t, "Surge", "A Osc 1 Shape", s[4])
  S(t, "Surge", "A Osc 1 Width 1", 50)
  S(t, "Surge", "A Osc 2 Type", "Classic")
  S(t, "Surge", "A Osc 2 Shape", 100)
  S(t, "Surge", "A Osc 2 Octave", 1)
  S(t, "Surge", "A Osc 2 Volume", -12)
  S(t, "Surge", "A Osc 2 Mute", "Off")
  S(t, "Surge", "A Pitch", s[2])
  S(t, "Surge", "A Osc Drift", s[3])
  S(t, "Surge", "A Amp EG Attack", 0)
  S(t, "Surge", "A Amp EG Decay", 450)
  S(t, "Surge", "A Amp EG Sustain", 50)
  S(t, "Surge", "A Amp EG Release", 140)
end

-- Horn: overdriven horn loudspeaker, band-limited with a honk.
S("Horn", "Saturation", "Amount (%)", 70)
S("Horn", "ReaEQ", "Freq-High Pass 5", 480)
S("Horn", "ReaEQ", "Freq-Low Shelf", 250)
S("Horn", "ReaEQ", "Gain-Low Shelf", -8)
S("Horn", "ReaEQ", "Freq-Band 2", 900)
S("Horn", "ReaEQ", "Gain-Band 2", 2)
S("Horn", "ReaEQ", "Freq-Band 3", 1700)
S("Horn", "ReaEQ", "Gain-Band 3", 8)
S("Horn", "ReaEQ", "BW-Band 3", 1.2)
S("Horn", "ReaEQ", "Freq-High Shelf 4", 4000)
S("Horn", "ReaEQ", "Gain-High Shelf 4", -20)

-- Distance: air loss shelf (automated later) + volume (automated later).
S("Distance", "ReaEQ", "Freq-High Shelf 4", 2500)

-- Fog reverb: huge, dark, 100% wet.
S("Fog Reverb", "ReaVerbate", "Wet", 0)
S("Fog Reverb", "ReaVerbate", "Dry", -200)
S("Fog Reverb", "ReaVerbate", "Room size", 100)
S("Fog Reverb", "ReaVerbate", "Dampening", 75)
S("Fog Reverb", "ReaVerbate", "Lowpass", 5000)
S("Fog Reverb", "ReaVerbate", "Hipass", 120)

-- Forest echo: one long reflection off the tree line.
S("Forest Echo", "ReaDelay", "Wet", 0)
S("Forest Echo", "ReaDelay", "Dry", -200)
S("Forest Echo", "ReaDelay", "1: Length (musical)", 0)
S("Forest Echo", "ReaDelay", "1: Length (time)", 620)
S("Forest Echo", "ReaDelay", "1: Feedback", -7)
S("Forest Echo", "ReaDelay", "1: Lowpass", 2500)
S("Forest Echo", "ReaDelay", "1: Hipass", 300)

-- Drone: detuned saw cluster, dark low-pass, slow swell.
local d = "Drone"
S(d, "Surge", "A Osc 1 Type", "Classic")
S(d, "Surge", "A Osc 1 Shape", 0)
S(d, "Surge", "A Osc 1 Unison Voices", "4 voices")
S(d, "Surge", "A Osc 1 Unison Detune", 25)
S(d, "Surge", "A Osc 2 Type", "Classic")
S(d, "Surge", "A Osc 2 Shape", 100)
S(d, "Surge", "A Osc 2 Octave", -1)
S(d, "Surge", "A Osc 2 Volume", -6)
S(d, "Surge", "A Osc 2 Mute", "Off")
S(d, "Surge", "A Osc Drift", 35)
S(d, "Surge", "A Filter 1 Type", "LP 24 dB")
S(d, "Surge", "A Filter 1 Cutoff", 260)
S(d, "Surge", "A Filter 1 Resonance", 30)
S(d, "Surge", "A Amp EG Attack", 4000)
S(d, "Surge", "A Amp EG Sustain", 100)
S(d, "Surge", "A Amp EG Release", 6000)

-- Rust: inharmonic FM clang (sheet metal / bridge girder).
local r = "Rust"
S(r, "Surge", "A Osc 1 Type", "Sine")
S(r, "Surge", "A Osc 2 Type", "Sine")
S(r, "Surge", "A Osc 2 Pitch", 6.37)
S(r, "Surge", "A Osc 2 Mute", "On")
S(r, "Surge", "A FM Routing", "2 > 1")
S(r, "Surge", "A FM Depth", 0)
S(r, "Surge", "A Amp EG Attack", 0)
S(r, "Surge", "A Amp EG Decay", 3000)
S(r, "Surge", "A Amp EG Sustain", 0)
S(r, "Surge", "A Amp EG Release", 3000)
S(r, "Surge", "A Filter 1 Type", "HP 12 dB")
S(r, "Surge", "A Filter 1 Cutoff", 150)

-- Footsteps: low sine + dark noise thud with a filter-envelope snap.
local f = "Footsteps"
S(f, "Surge", "A Osc 1 Type", "Sine")
S(f, "Surge", "A Noise Mute", "Off")
S(f, "Surge", "A Noise Volume", -4)
S(f, "Surge", "A Noise Color", -50)
S(f, "Surge", "A Filter 1 Type", "LP 24 dB")
S(f, "Surge", "A Filter 1 Cutoff", 70)
S(f, "Surge", "A Filter 1 FEG Mod Amount", 36)
S(f, "Surge", "A Filter EG Attack", 0)
S(f, "Surge", "A Filter EG Decay", 300)
S(f, "Surge", "A Filter EG Sustain", 0)
S(f, "Surge", "A Amp EG Attack", 3)
S(f, "Surge", "A Amp EG Decay", 1200)
S(f, "Surge", "A Amp EG Sustain", 0)
S(f, "Surge", "A Amp EG Release", 800)
S(f, "Surge", "A Waveshaper Type", "Soft")
S(f, "Surge", "A Waveshaper Drive", 6)

-- Fog wind: band-passed noise, cutoff gusts automated later.
local w = "Fog Wind"
S(w, "Surge", "A Osc 1 Mute", "On")
S(w, "Surge", "A Noise Mute", "Off")
S(w, "Surge", "A Noise Color", -30)
S(w, "Surge", "A Filter 1 Type", "BP 12 dB")
S(w, "Surge", "A Filter 1 Cutoff", 700)
S(w, "Surge", "A Filter 1 Resonance", 40)
S(w, "Surge", "A Amp EG Attack", 3000)
S(w, "Surge", "A Amp EG Sustain", 100)
S(w, "Surge", "A Amp EG Release", 4000)

H.set(reaper.GetMasterTrack(0), "Master Limiter", "Threshold", -3)
got[#got + 1] = "master limiter: " .. tostring(H.params(reaper.GetMasterTrack(0), "Master Limiter", "Threshold")[1].fmt)

H.save()
return got
