-- 08a: unmute only Tone A square (for rendering / A-B comparison).
assert(H.project_file():find("SlenderSpeaker_FurElise", 1, true), "wrong project tab: " .. tostring(H.project_file()))
for _, n in ipairs({ "Tone A square", "Tone B music box", "Tone C pulse" }) do
  H.mix(n, { mute = (n ~= "Tone A square") })
end
H.save()
return "Tone A square"
