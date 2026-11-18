-- 10: tempo candidate 96 BPM (quarter note), tone A only. User: tone A closest, tempo is the main difference.
assert(H.project_file():find("SlenderSpeaker_FurElise", 1, true), "wrong project tab: " .. tostring(H.project_file()))
for _, n in ipairs({ "Tone A square", "Tone B music box", "Tone C pulse" }) do
  H.mix(n, { mute = (n ~= "Tone A square") })
end
H.set_tempo(96, 3, 8)
H.save()
local it = H.items("Tone A square")[1]
return { tempo = 96, item_start = it.start_bar, item_end = it.end_bar, end_s = H.bar_time(it.end_bar) }
