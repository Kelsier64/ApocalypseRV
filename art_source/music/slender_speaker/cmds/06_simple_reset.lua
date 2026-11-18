-- 06: user feedback: not BGM. Plain electronic garbage-truck Für Elise played from the monster's head speaker.
-- Remove the ambient design (all tracks created by cmds 01-05), back to the original 75 BPM 3/8,
-- and set up three tone candidates (one track each, both hands) into one loudspeaker bus.
assert(H.project_file():find("SlenderSpeaker_FurElise", 1, true), "wrong project tab: " .. tostring(H.project_file()))

for _, n in ipairs({ "Speaker C", "Speaker L", "Speaker R", "Horn", "Distance", "Fog Reverb", "Forest Echo",
  "Drone", "Rust", "Footsteps", "Fog Wind" }) do
  if H.track(n) then H.delete_track(n) end
end

H.set_tempo(75, 3, 8)
H.clear_markers()
H.region("Pickup", 1, 2)
H.region("A", 2, 10)
H.region("A'", 10, 18)
H.region("B", 18, 24)
H.region("A''", 24, 32)

local src = dofile("C:/Users/evan4/Projects/ApocalypseRV/art_source/music/slender_speaker/furelise_notes.lua")

local speaker = H.get_or_add_track("Loudspeaker", { color = "#806020" })
H.fx(speaker, "JS: Saturation")
H.fx(speaker, "ReaEQ")

local tones = { { "Tone A square", false }, { "Tone B music box", true }, { "Tone C pulse", true } }
for _, t in ipairs(tones) do
  local tr = H.get_or_add_track(t[1], { master_send = false, mute = t[2], color = "#c8a040" })
  H.fx(tr, "Surge XT")
  H.ensure_send(tr, speaker, 0)
  H.delete_items(tr)
  local take = H.midi_item(tr, 1, 32, { name = "für elise" })
  local notes = {}
  for _, n in ipairs(src.rh) do notes[#notes + 1] = { p = n[3], s = n[1], l = n[2], v = 100 } end
  for _, n in ipairs(src.lh) do notes[#notes + 1] = { p = n[3], s = n[1], l = n[2], v = 85 } end
  H.add_notes(take, notes)
end

H.save()
return H.dump({ sends = true })
