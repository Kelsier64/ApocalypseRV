-- 09: match the three candidates to about -18 dBFS RMS so the comparison is fair
-- (first renders: A -21.0, B -12.5 (hitting the limiter), C -19.1).
assert(H.project_file():find("SlenderSpeaker_FurElise", 1, true), "wrong project tab: " .. tostring(H.project_file()))
H.mix("Tone A square", { vol_db = 3 })
H.mix("Tone B music box", { vol_db = -6.5 })
H.mix("Tone C pulse", { vol_db = 1 })
H.save()
return "ok"
