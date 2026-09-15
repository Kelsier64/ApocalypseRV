extends RefCounted
class_name InstanceIds

static func create() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()
