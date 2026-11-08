// Brief 8: rewrites a Roblox binary place with every chunk stored uncompressed (Lune 0.8.9 cannot read zstd) and drops
// PROP chunks Lune's reflection rejects (Tags, and any listed in argv[4] comma-separated).
// usage: node tools/rbxl-uncompress.js <in.rbxl> <out.rbxl> [dropProps]
// (Studio saves places zstd-compressed; tools/importhub.luau and exportnodes.luau need the output of this.)
const fs = require("fs");
const zlib = require("zlib");
const [, , inPath, outPath, extra] = process.argv;
const drop = new Set(["Tags", ...(extra ? extra.split(",") : [])]);
const buf = fs.readFileSync(inPath);
const HEADER = 32;
if (buf.toString("latin1", 0, 8) !== "<roblox!") throw new Error("not a binary place");

function lz4Decompress(src, outLen) {
	const out = Buffer.alloc(outLen);
	let i = 0, o = 0;
	while (i < src.length) {
		const token = src[i++];
		let lit = token >> 4;
		if (lit === 15) { let b; do { b = src[i++]; lit += b; } while (b === 255); }
		src.copy(out, o, i, i + lit); i += lit; o += lit;
		if (i >= src.length) break;
		const off = src[i] | (src[i + 1] << 8); i += 2;
		let len = token & 15;
		if (len === 15) { let b; do { b = src[i++]; len += b; } while (b === 255); }
		len += 4;
		for (let k = 0; k < len; k++) { out[o] = out[o - off]; o++; }
	}
	return out;
}

const parts = [buf.subarray(0, HEADER)];
let pos = HEADER;
const dropped = {};
while (pos < buf.length) {
	const name = buf.toString("latin1", pos, pos + 4);
	const clen = buf.readUInt32LE(pos + 4);
	const ulen = buf.readUInt32LE(pos + 8);
	const dataStart = pos + 16;
	let data;
	if (clen === 0) {
		data = buf.subarray(dataStart, dataStart + ulen);
		pos = dataStart + ulen;
	} else {
		const raw = buf.subarray(dataStart, dataStart + clen);
		pos = dataStart + clen;
		if (raw[0] === 0x28 && raw[1] === 0xb5 && raw[2] === 0x2f && raw[3] === 0xfd) data = zlib.zstdDecompressSync(raw);
		else data = lz4Decompress(raw, ulen);
	}
	if (name.startsWith("PROP")) {
		const nlen = data.readUInt32LE(4);
		const prop = data.toString("utf8", 8, 8 + nlen);
		if (drop.has(prop)) { dropped[prop] = (dropped[prop] || 0) + 1; continue; }
	}
	const head = Buffer.alloc(16);
	head.write(name, 0, "latin1");
	head.writeUInt32LE(0, 4);
	head.writeUInt32LE(data.length, 8);
	head.writeUInt32LE(0, 12);
	parts.push(head, data);
	if (name === "END\0") break;
}
fs.writeFileSync(outPath, Buffer.concat(parts));
console.log("wrote", outPath, "dropped", JSON.stringify(dropped));
