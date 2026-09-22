extends RefCounted

static var cache: Dictionary = {}
const PALETTE: Dictionary = {".": Color.TRANSPARENT, "#": Color("20353b"), "g": Color("55866a"), "l": Color("a3bc79"), "w": Color("e9d5a2"), "s": Color("e9b559"), "b": Color("926846"), "v": Color("88789d"), "p": Color("c3abd0"), "t": Color("70bbc1")}
const PATTERNS: Dictionary = {
	"monster": ["................", "......ll........", ".....lgl........", "....######......", "...#llgggg#.....", "..#llgggggg#....", "..#lggggggg#....", "..#gw#ggw#g#....", "..#gw#ggw#g#....", "..#gggggggg#....", "...#ggwwgg#.....", "....######......", "....bb..bb......", "...###..###.....", "................", "................"],
	"boss": ["....s..s..s.....", "....sssssss.....", "....#######.....", "...#ppvvvvv#....", "..#ppvvvvvvv#...", ".#ppvvvvvvvvv#..", ".#pvw#vvvw#vv#..", ".#vvw#vvvw#vv#..", ".#vvvvvvvvvvv#..", "..#vvvwwwvvv#...", "..#vvvvvvvvv#...", "...#########....", "...bb.....bb....", "..####...####...", "................", "................"],
	"cat": ["................", "...#......#.....", "..#w#....#w#....", "..#ww####ww#....", "..#wwwwwwww#....", "..#wbwwwwbw#....", "..#w#wwww#w#....", "..#wwwwwwww#....", "...#wwbbww#.....", "....#wwww#..#...", "...#wwwwww##w#..", "...#wbwwwbwww#..", "....#########...", "....bb...bb.....", "................", "................"],
	"chest": ["................", "................", "...##########...", "..#ssssssssss#..", "..#sbbbbbbbbs#..", "..#sbbbbbbbbs#..", "..############..", "..#ssssssssss#..", "..#sbbbbbbbbs#..", "..#sbbbssbbbs#..", "..#sbbbssbbbs#..", "..#sbbbbbbbbs#..", "..############..", "................", "................", "................"],
	"portal": [".....gggggg.....", "...gg######gg...", "..g##tttttt##g..", "..g#tt####tt#g..", ".g#tt######tt#g.", ".g#t########t#g.", ".g#t########t#g.", ".g#t##ssss##t#g.", ".g#t##ssss##t#g.", ".g#t###ss###t#g.", ".g#t###ss###t#g.", ".g#t########t#g.", ".g#tttttttttt#g.", "..############..", "...ssssssssss...", "................"],
	"relic": ["................", "......gg........", ".....glgg.......", ".....glglg......", ".....glglg......", ".....glglg......", "...ggglglg......", "..gllggllg......", "..gllglllg......", "...glllllg......", "....glllg.......", "....#sss#.......", "....#sss#.......", "....#####.......", "................", "................"]}

static func texture(key: String) -> Texture2D:
	if cache.has(key):
		return cache[key]
	var path: String = "res://assets/encounter/%s.png" % key
	if ResourceLoader.exists(path):
		cache[key] = load(path)
		return cache[key]
	var image: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var rows: Array = PATTERNS[key]
	for y: int in range(16):
		for x: int in range(16):
			image.set_pixel(x, y, PALETTE[rows[y][x]])
	image.resize(64, 64, Image.INTERPOLATE_NEAREST)
	var result: ImageTexture = ImageTexture.create_from_image(image)
	cache[key] = result
	return result
