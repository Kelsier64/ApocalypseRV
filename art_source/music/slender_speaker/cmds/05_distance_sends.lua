-- 05: v1 had far sections as loud as the climax because the reverb/echo sends left the Horn
-- before the distance automation. Move most of the send after Distance; keep a faint constant wash.
assert(H.project_file():find("SlenderSpeaker_FurElise", 1, true), "wrong project tab: " .. tostring(H.project_file()))

H.ensure_send("Horn", "Fog Reverb", -22)
H.ensure_send("Horn", "Forest Echo", -40)
H.ensure_send("Distance", "Fog Reverb", -5)
H.ensure_send("Distance", "Forest Echo", -14)

-- v1 leaned left by ~1.5 dB.
H.mix("Speaker L", { vol_db = -3 })
H.mix("Speaker R", { vol_db = -1.5 })

H.save()
return { horn = H.sends("Horn"), distance = H.sends("Distance") }
