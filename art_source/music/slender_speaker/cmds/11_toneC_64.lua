-- 11: user asked to hear tone C at 64 BPM.
assert(H.project_file():find("SlenderSpeaker_FurElise", 1, true), "wrong project tab: " .. tostring(H.project_file()))
for _, n in ipairs({ "Tone A square", "Tone B music box", "Tone C pulse" }) do
  H.mix(n, { mute = (n ~= "Tone C pulse") })
end
H.set_tempo(64, 3, 8)
H.save()
return "tone C, 64 BPM"
