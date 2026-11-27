// Builds the dispatch computer's word bank: one Kokoro call per word, silence trimmed,
// flattened to one pitch with a narrowband tone in Praat, then loudness-matched.
//
//   node scripts/audio/dispatch_voice/generate.mjs
//       Regenerates assets/audio/dispatch_voice/words/*.wav and word_bank.tres.
//   node scripts/audio/dispatch_voice/generate.mjs --audition am_michael,af_heart --text "unit kilo four seven"
//       Renders one joined sample per voice into .godot/dispatch_voice/audition/.
//
// Kokoro is installed outside the repo (KOKORO_DIR, default %USERPROFILE%/Apps/kokoro-tts,
// `npm install kokoro-js@1.2.1`); Praat is PRAAT_EXE, default %USERPROFILE%/Apps/praat/Praat.exe.
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, "../../..");
const HOME = process.env.USERPROFILE ?? process.env.HOME;
const KOKORO_DIR = process.env.KOKORO_DIR ?? join(HOME, "Apps", "kokoro-tts");
const PRAAT = process.env.PRAAT_EXE ?? join(HOME, "Apps", "praat", "Praat.exe");
const MODEL = "onnx-community/Kokoro-82M-v1.0-ONNX";
const WORK = join(ROOT, ".godot", "dispatch_voice");
const OUT = join(ROOT, "assets", "audio", "dispatch_voice");
const RATE = 16000;
const TARGET_RMS_DB = -20;
const PEAK_LIMIT = 0.95;
const AUDITION_GAP = 0.08;

const config = JSON.parse(readFileSync(join(HERE, "words.json"), "utf8"));
const args = process.argv.slice(2);
const option = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };

const { KokoroTTS } = await import(pathToFileURL(join(KOKORO_DIR, "node_modules", "kokoro-js", "dist", "kokoro.js")).href);
const tts = await KokoroTTS.from_pretrained(MODEL, { dtype: "fp32", device: "cpu" });

const audition = option("--audition");
if (audition) {
	const tokens = (option("--text") ?? "attention unit kilo four seven . proceed to relay station delta two . end of message").split(/\s+/);
	for (const voice of audition.split(",")) {
		const folder = join(WORK, "audition", voice);
		const words = await buildWords(voice, tokens.filter((t) => t !== "."), folder);
		writeWav(join(WORK, "audition", `${voice}.wav`), join_tokens(tokens, words), RATE);
		console.log(`audition ${voice}: ${join(WORK, "audition", voice + ".wav")}`);
	}
} else {
	const tokens = Object.keys(config.words);
	const folder = join(WORK, "bank");
	const words = await buildWords(config.voice, tokens, folder);
	const target = join(OUT, "words");
	mkdirSync(target, { recursive: true });
	for (const file of readdirSync(target)) if (file.endsWith(".wav") && !(file.slice(0, -4) in config.words)) {
		rmSync(join(target, file));
		rmSync(join(target, file + ".import"), { force: true });
	}
	for (const token of tokens) {
		const file = join(target, `${token}.wav`);
		writeWav(file, words[token], RATE);
		// WordBank.compose copies raw samples, so the words must import as uncompressed PCM.
		if (!existsSync(file + ".import")) writeFileSync(file + ".import", '[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\n\n[params]\n\ncompress/mode=0\n');
	}
	writeBank(tokens);
	console.log(`wrote ${tokens.length} words with ${config.voice}`);
}

async function buildWords(voice, tokens, folder) {
	const raw = join(folder, "raw");
	const flat = join(folder, "flat");
	for (const dir of [raw, flat]) { rmSync(dir, { recursive: true, force: true }); mkdirSync(dir, { recursive: true }); }
	for (const token of new Set(tokens)) {
		const text = config.words[token];
		if (!text) throw new Error(`No word '${token}' in words.json`);
		const audio = await tts.generate(text + ".", { voice, speed: config.speed });
		writeWav(join(raw, `${token}.wav`), trim(audio.audio), audio.sampling_rate);
	}
	const report = execFileSync(PRAAT, ["--run", "--FULL-TRUST", join(HERE, "flatten.praat"), raw, flat, String(config.pitch), String(RATE), "300", "3400", "2.5"], { encoding: "utf16le" });
	console.log(`${voice}: ${report.trim()}`);
	const words = {};
	for (const token of new Set(tokens)) words[token] = level(readWav(join(flat, `${token}.wav`)));
	return words;
}

// Cut the leading and trailing silence Kokoro leaves around a single word.
function trim(samples) {
	let peak = 0;
	for (const s of samples) peak = Math.max(peak, Math.abs(s));
	// The onset keeps quiet consonants; the tail cuts the long sentence-final decay a single word gets.
	const onset = peak * 10 ** (-40 / 20), tail = peak * 10 ** (-30 / 20);
	const window = 240;
	const loud = (i, floor) => { let e = 0; for (let k = i; k < Math.min(samples.length, i + window); k++) e = Math.max(e, Math.abs(samples[k])); return e > floor; };
	let start = 0, end = samples.length;
	while (start < end && !loud(start, onset)) start += window / 2;
	while (end > start && !loud(Math.max(0, end - window), tail)) end -= window / 2;
	return samples.slice(Math.max(0, start - 480), Math.min(samples.length, end + 720));
}

// Match loudness across words, then fade the edges so joins never click.
function level(samples) {
	let sum = 0, peak = 0;
	for (const s of samples) { sum += s * s; peak = Math.max(peak, Math.abs(s)); }
	const rms = Math.sqrt(sum / samples.length);
	const gain = Math.min(10 ** (TARGET_RMS_DB / 20) / rms, PEAK_LIMIT / peak);
	const fade = Math.round(RATE * 0.006);
	return samples.map((s, i) => s * gain * Math.min(1, i / fade, (samples.length - 1 - i) / fade));
}

function join_tokens(tokens, words) {
	const gap = Math.round(AUDITION_GAP * RATE);
	const parts = [];
	for (const token of tokens) parts.push(token === "." ? new Float32Array(gap * 3) : words[token], new Float32Array(gap));
	const out = new Float32Array(parts.reduce((n, p) => n + p.length, 0));
	let at = 0;
	for (const p of parts) { out.set(p, at); at += p.length; }
	return out;
}

function writeBank(tokens) {
	const lines = ['[gd_resource type="Resource" script_class="WordBank" format=3]', "",
		'[ext_resource type="Script" path="res://core/audio/word_bank.gd" id="script"]'];
	for (const token of tokens) lines.push(`[ext_resource type="AudioStream" path="res://assets/audio/dispatch_voice/words/${token}.wav" id="${token}"]`);
	lines.push("", "[resource]", 'script = ExtResource("script")');
	lines.push(`words = Dictionary[StringName, AudioStreamWAV]({\n${tokens.map((t) => `&"${t}": ExtResource("${t}")`).join(",\n")}\n})`);
	writeFileSync(join(OUT, "word_bank.tres"), lines.join("\n") + "\n");
}

function writeWav(path, samples, rate) {
	mkdirSync(dirname(path), { recursive: true });
	const data = Buffer.alloc(samples.length * 2);
	samples.forEach((s, i) => data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, s)) * 32767), i * 2));
	const header = Buffer.alloc(44);
	header.write("RIFF", 0); header.writeUInt32LE(36 + data.length, 4); header.write("WAVE", 8);
	header.write("fmt ", 12); header.writeUInt32LE(16, 16); header.writeUInt16LE(1, 20); header.writeUInt16LE(1, 22);
	header.writeUInt32LE(rate, 24); header.writeUInt32LE(rate * 2, 28); header.writeUInt16LE(2, 32); header.writeUInt16LE(16, 34);
	header.write("data", 36); header.writeUInt32LE(data.length, 40);
	writeFileSync(path, Buffer.concat([header, data]));
}

function readWav(path) {
	const file = readFileSync(path);
	let at = 12, channels = 1, bits = 16;
	while (at < file.length) {
		const id = file.toString("ascii", at, at + 4), size = file.readUInt32LE(at + 4);
		if (id === "fmt ") { channels = file.readUInt16LE(at + 10); bits = file.readUInt16LE(at + 22); }
		if (id === "data") {
			if (channels !== 1 || bits !== 16) throw new Error(`${path}: expected 16-bit mono`);
			const out = new Float32Array(size / 2);
			for (let i = 0; i < out.length; i++) out[i] = file.readInt16LE(at + 8 + i * 2) / 32768;
			return out;
		}
		at += 8 + size + (size % 2);
	}
	throw new Error(`${path}: no data chunk`);
}
