#!/usr/bin/env node
/**
 * Fix for: "Error: Invalid or corrupt jarfile .../gradle-wrapper.jar" when
 * running `jac run --dev mobile`.
 *
 * Why this exists
 * ---------------
 * `expo prebuild` unpacks node_modules/expo/template.tgz with
 * @expo/cli/build/src/utils/tar.js, which hands an async iterable straight to
 * fs.writeFile(). Bun (the runtime `jac` uses to drive Expo) writes the leading
 * chunks of such a stream twice, so every file over ~16 KB in the template gets
 * junk appended: gradle-wrapper.jar grew from 46175 to 59487 bytes (13312 zero
 * bytes), and `java -jar gradle-wrapper.jar` then refuses to start. unzip,
 * Python's zipfile and java.util.zip all tolerate the trailing junk, which is
 * why the file looks fine everywhere except the JVM.
 *
 * What this script does
 * ---------------------
 * 1. Patches tar.js (idempotent) so each file is buffered and written with
 *    exactly the byte count declared by the tar header.
 * 2. Re-extracts template.tgz through the patched code and asserts the results
 *    are clean: gradle-wrapper.jar must end at its ZIP end-of-central-directory
 *    record and the splash PNG must end at its IEND chunk.
 *
 * The verification is run with jac's bundled Bun when available, because that
 * is the runtime where the corruption actually reproduces.
 *
 * Usage:
 *   node scripts/patch-expo-tar.mjs           # patch + verify
 *   node scripts/patch-expo-tar.mjs --verify  # verify only (exit 1 if unpatched)
 *
 * Run it once after .jac/mobile-rn exists (i.e. after the first
 * `jac run --dev mobile`, which is the run that fails).
 */

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const mobileRn = path.join(repoRoot, '.jac', 'mobile-rn');
const target = path.join(
  mobileRn,
  'node_modules',
  '@expo',
  'cli',
  'build',
  'src',
  'utils',
  'tar.js'
);
const template = path.join(mobileRn, 'node_modules', 'expo', 'template.tgz');

const PATCH_MARKER = 'exactly the bytes the tar header declares';

// Exact upstream code @expo/cli@57 ships for file entries.
const OLD_BLOCK = [
  '            case _multitars().TarTypeFlag.FILE:',
  '                debug(`write(${file.mode.toString(8)}): ${resolved}`);',
  '                await _nodefs().default.promises.writeFile(resolved, (0, _multitars().streamToAsyncIterable)(file.stream()), {',
  '                    mode: file.mode',
  '                });',
  '                break;',
].join('\n');

const NEW_BLOCK = [
  '            case _multitars().TarTypeFlag.FILE:',
  '                debug(`write(${file.mode.toString(8)}): ${resolved}`);',
  '                {',
  '                    // Local workaround: Bun (used by `jac` to run Expo CLI) can write',
  '                    // leading chunks twice when fs.writeFile() is given an async',
  '                    // iterable, which appends junk to extracted files (it turned',
  '                    // gradle-wrapper.jar into a 59487-byte file that the JVM rejects',
  '                    // with "Invalid or corrupt jarfile"). Buffer the entry and write',
  '                    // exactly the bytes the tar header declares instead.',
  '                    const chunks = [];',
  '                    for await (const chunk of (0, _multitars().streamToAsyncIterable)(file.stream())) {',
  '                        chunks.push(Buffer.from(chunk));',
  '                    }',
  '                    let data = Buffer.concat(chunks);',
  '                    if (typeof file.size === "number" && file.size >= 0 && file.size < data.length) {',
  '                        data = data.subarray(0, file.size);',
  '                    }',
  '                    await _nodefs().default.promises.writeFile(resolved, data, {',
  '                        mode: file.mode',
  '                    });',
  '                }',
  '                break;',
].join('\n');

const EOCD = Buffer.from([0x50, 0x4b, 0x05, 0x06]);

function fail(message) {
  console.error(`✖ ${message}`);
  process.exit(1);
}

function readTarget() {
  if (!fs.existsSync(target)) {
    fail(
      `${path.relative(repoRoot, target)} not found.\n` +
        '  Run `jac run --dev mobile` once first so .jac/mobile-rn is created\n' +
        '  (that first run is the one that fails), then re-run this script.'
    );
  }
  return fs.readFileSync(target, 'utf8');
}

function patch() {
  const source = readTarget();
  if (source.includes(PATCH_MARKER)) {
    console.log('✔ tar.js is already patched.');
    return;
  }
  if (!source.includes(OLD_BLOCK)) {
    fail(
      'tar.js does not contain the expected upstream code, so it was not modified.\n' +
        '  The @expo/cli layout probably changed with an upgrade - please report this\n' +
        `  (file: ${target}).`
    );
  }
  fs.writeFileSync(target, source.replace(OLD_BLOCK, NEW_BLOCK));
  if (!fs.readFileSync(target, 'utf8').includes(PATCH_MARKER)) {
    fail('patch did not stick - tar.js was left in an inconsistent state.');
  }
  console.log(`✔ Patched ${path.relative(repoRoot, target)}`);
}

/** Re-extract the Expo template through the patched code and assert clean output. */
async function verifyExtraction() {
  const source = readTarget();
  if (!source.includes(PATCH_MARKER)) {
    fail('tar.js is NOT patched - run `node scripts/patch-expo-tar.mjs` first.');
  }
  if (!fs.existsSync(template)) {
    fail(`${path.relative(repoRoot, template)} not found - run \`jac run --dev mobile\` once first.`);
  }

  const req = createRequire(target);
  const tar = req('@expo/cli/build/src/utils/tar.js');
  const out = fs.mkdtempSync(path.join(os.tmpdir(), 'patch-expo-tar-'));
  try {
    await tar.extractAsync(template, out, { strip: 1 });

    const jarPath = path.join(out, 'android', 'gradle', 'wrapper', 'gradle-wrapper.jar');
    const jar = fs.readFileSync(jarPath);
    const eocd = jar.lastIndexOf(EOCD);
    if (eocd < 0) {
      fail(`gradle-wrapper.jar (${jar.length} bytes) has no ZIP end record - extraction is broken.`);
    }
    const trailing = jar.length - (eocd + 22);
    if (trailing !== 0) {
      fail(
        `gradle-wrapper.jar has ${trailing} trailing bytes (expected 0).\n` +
          '  The JVM will reject it with "Invalid or corrupt jarfile".'
      );
    }

    const pngPath = path.join(
      out,
      'android',
      'app',
      'src',
      'main',
      'res',
      'drawable-xhdpi',
      'splashscreen_logo.png'
    );
    const png = fs.readFileSync(pngPath);
    const iend = png.subarray(png.length - 8, png.length - 4).toString('latin1');
    if (iend !== 'IEND' || png[png.length - 1] !== 0x82) {
      fail(`splashscreen_logo.png (${png.length} bytes) is missing its IEND trailer - extraction is broken.`);
    }

    const runtime =
      typeof globalThis.Bun !== 'undefined'
        ? `Bun ${globalThis.Bun.version}`
        : `Node ${process.versions.node}`;
    console.log(`✔ Verified under ${runtime}: template extracted cleanly`);
    console.log(`    gradle-wrapper.jar      ${jar.length} bytes, ends at ZIP central directory`);
    console.log(`    splashscreen_logo.png   ${png.length} bytes, ends at IEND`);
  } finally {
    fs.rmSync(out, { recursive: true, force: true });
  }
}

/** Prefer jac's bundled Bun: that is the runtime where the bug reproduces. */
function verify() {
  if (typeof globalThis.Bun !== 'undefined' || process.env.PATCH_EXPO_TAR_UNDER_BUN === '1') {
    return verifyExtraction();
  }
  const rtRoot = path.join(os.homedir(), 'Library', 'Caches', 'jac', 'rt');
  let bun = null;
  try {
    for (const entry of fs.readdirSync(rtRoot)) {
      const candidate = path.join(rtRoot, entry, 'site', 'jaclang', 'client', '_bun', 'bun');
      if (fs.existsSync(candidate)) {
        bun = candidate;
        break;
      }
    }
  } catch {
    bun = null;
  }
  if (bun) {
    console.log(`  (verifying with jac's bundled Bun: ${bun})`);
    const res = spawnSync(bun, [fileURLToPath(import.meta.url), '--verify'], {
      stdio: 'inherit',
      env: { ...process.env, PATCH_EXPO_TAR_UNDER_BUN: '1' },
    });
    if (res.error) {
      console.warn(`  ! could not run bundled Bun (${res.error.message}); verifying with Node instead.`);
      return verifyExtraction();
    }
    process.exit(res.status ?? 1);
  }
  console.warn('  ! jac Bun not found; verifying under Node, which does not reproduce the bug.');
  return verifyExtraction();
}

const verifyOnly = process.argv.includes('--verify');
if (!verifyOnly) {
  patch();
}
await verify();
console.log('✔ Done - `jac run --dev mobile` should now build.');
