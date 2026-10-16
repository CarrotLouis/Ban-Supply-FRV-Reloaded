-- Reviewed against the retained Steam 25480438 capture. These RVAs are used
-- only after BOTH on-disk module hashes and the native function fingerprints match.
return {
    steam_build = '25480438',
    exe_sha256 = 'F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06',
    game_sha256 = '2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E',
    vehicle_resource = '9b2140378640432e',
    transport_resource = '75be82ed8592a6b3',
    avatar_resource = '4d1c334d294dfa97',
    transition = 27,
    reload_type = 21,
    reload_zones = {5, 6}, -- native, zero-based zone indices
    reload_mask = 0x60,
    -- IEEE-754 float32 1e20: ordinary frame deltas round to no change.
    -- Local runtime data only, never a shared definition or replicated timer.
    held_timer = string.char(0xec,0x78,0xad,0x60),
    default_timer = string.char(0,0,0x80,0xbf), -- StartEnabledDelay = -1
    delayed_property = 0x99901914,
    zone_types = {19, 19, 9, 19, 19, 21, 21},
    globals = {mission=0x33266a0, player=0x3326468, entities=0x346bf98,
               avatar=0x3326d20, seater=0x3326d78, collection=0x3326d88,
               interactable=0x3326d68, transport=0x3326518, user=0x347cef0},
    entity_map = 0xf22ec8,
    entity_records = 0xf32f18,
    functions = {}, -- filled by the reproducible profile generator
}
