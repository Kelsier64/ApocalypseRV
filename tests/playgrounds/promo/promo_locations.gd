extends RefCounted

static func bunkers(field: WorldField, distance: float, radius: float) -> Array[Dictionary]:
	var sites := field.sites_near_z(-distance, radius).filter(func(site):
		var definition := POIConfig.definition_for_site(site)
		return absf(site.s - distance) <= radius and definition != null and definition.interior_profile == &"bunker")
	sites.sort_custom(func(a, b): return absf(a.s - distance) < absf(b.s - distance))
	return sites
