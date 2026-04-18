#!/usr/bin/env bun
// cli/index.ts — lute-jest CLI
// Usage:
//   bun cli/index.ts <spec.luau> [more.luau ...]
//   bun cli/index.ts examples/                  (runs all *.spec.luau under dir)
//   bun cli/index.ts examples-ts/               (auto-detects roblox-ts project: rbxtsc -> run out/)

import { spawnSync, spawn } from "node:child_process";
import { existsSync, readdirSync, statSync } from "node:fs";
import { resolve, join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, "..");
const RUNNER = join(ROOT, "runtime", "runner.luau");
const LUTE = process.env.LUTE_BIN || "/tmp/lute-bin/lute";

function isRobloxTsProject(dir: string): boolean {
	return existsSync(join(dir, "tsconfig.json")) && existsSync(join(dir, "package.json"));
}

function findSpecs(target: string): string[] {
	const abs = resolve(target);
	if (!existsSync(abs)) {
		console.error(`[lute-jest] not found: ${target}`);
		process.exit(2);
	}
	const s = statSync(abs);
	if (s.isFile()) return [abs];
	if (s.isDirectory()) {
		// roblox-ts project? compile first, then walk out/
		if (isRobloxTsProject(abs)) {
			console.log(`\x1b[2m[lute-jest] compiling roblox-ts project ${abs} ...\x1b[0m`);
			const r = spawnSync("bunx", ["rbxtsc", "-p", "."], { cwd: abs, stdio: "inherit" });
			if (r.status !== 0) {
				console.error("[lute-jest] rbxtsc failed");
				process.exit(2);
			}
			const outDir = join(abs, "out");
			if (!existsSync(outDir)) {
				console.error("[lute-jest] no out/ after compile");
				process.exit(2);
			}
			return findSpecs(outDir);
		}
		const out: string[] = [];
		for (const entry of readdirSync(abs)) {
			const p = join(abs, entry);
			const st = statSync(p);
			if (st.isDirectory()) out.push(...findSpecs(p));
			else if (entry.endsWith(".spec.luau") || entry.endsWith(".test.luau")) out.push(p);
		}
		return out;
	}
	return [];
}

function main() {
	const args = process.argv.slice(2);
	if (args.length === 0) {
		console.error("usage: lute-jest <spec.luau | dir> [...] [--workers N] [--bail]");
		process.exit(2);
	}

	let workers = Math.max(1, Math.min(8, navigator?.hardwareConcurrency || 4));
	let bail = false;
	const targets: string[] = [];
	for (let i = 0; i < args.length; i++) {
		if (args[i] === "--workers" && args[i + 1]) { workers = parseInt(args[++i]); continue; }
		if (args[i] === "--bail") { bail = true; continue; }
		targets.push(args[i]);
	}

	const specs = targets.flatMap(findSpecs);
	if (specs.length === 0) {
		console.error("[lute-jest] no .spec.luau files found");
		process.exit(2);
	}

	let failedFiles = 0;
	const start = Date.now();

	async function runOne(spec: string): Promise<{ rel: string; output: string; ok: boolean }> {
		return new Promise((res) => {
			const rel = spec.startsWith(ROOT) ? spec.slice(ROOT.length + 1) : spec;
			let output = "";
			const proc = spawn(LUTE, [RUNNER, spec], { cwd: ROOT });
			proc.stdout.on("data", (d) => (output += d.toString()));
			proc.stderr.on("data", (d) => (output += d.toString()));
			proc.on("close", (code) => res({ rel, output, ok: code === 0 }));
		});
	}

	(async () => {
		const queue = [...specs];
		const inflight: Promise<void>[] = [];
		const pump = async () => {
			while (queue.length > 0) {
				if (bail && failedFiles > 0) return;
				const spec = queue.shift()!;
				const { rel, output, ok } = await runOne(spec);
				console.log(`\x1b[1m\x1b[36m●\x1b[0m \x1b[1m${rel}\x1b[0m`);
				process.stdout.write(output);
				if (!ok) failedFiles++;
			}
		};
		for (let i = 0; i < workers; i++) inflight.push(pump());
		await Promise.all(inflight);

		const ms = Date.now() - start;
		console.log("");
		console.log(
			`\x1b[1mFiles: \x1b[32m${specs.length - failedFiles} passed\x1b[0m, ` +
			`\x1b[31m${failedFiles} failed\x1b[0m, ` +
			`\x1b[1m${specs.length} total\x1b[0m  (${ms}ms, ${workers} workers)`
		);
		process.exit(failedFiles > 0 ? 1 : 0);
	})();
}

main();
