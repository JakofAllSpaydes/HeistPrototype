--!strict
-- The house typefaces (Round 19o style pass: sharp, dark, condensed caps instead of the bubbly LuckiestGuy).
-- display: headings, numbers, names, buttons. body: descriptions and small labels. mono: number readouts.
-- Client UI reads them through Theme.Fonts; server-built signs and billboards require this directly.
-- Set them with `FontFace =` (they are Font objects, not Enum.Font).
return {
	display = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold),
	displayMedium = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Medium),
	body = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
	mono = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Medium),
}
