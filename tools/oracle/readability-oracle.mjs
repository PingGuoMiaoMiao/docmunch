// Differential-test oracle: runs Mozilla Readability on the golden HTML fixtures
// and writes one JSON file per input. MoonBit-side extractor tests compare
// against these snapshots.
//
// Node is a TEST-TIME dependency only; it never ships with docmunch (D5).

import { readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs';
import { join, basename } from 'node:path';
import { JSDOM } from 'jsdom';
import { Readability } from '@mozilla/readability';

const htmlDir = process.argv[2] ?? 'fixtures/html';
const outDir = process.argv[3] ?? 'tools/oracle/out';

mkdirSync(outDir, { recursive: true });

const files = readdirSync(htmlDir).filter((f) => f.endsWith('.html')).sort();
if (files.length === 0) {
  console.error(`no .html fixtures under ${htmlDir}`);
  process.exit(1);
}

let failures = 0;
for (const file of files) {
  const html = readFileSync(join(htmlDir, file), 'utf8');
  try {
    const dom = new JSDOM(html, { url: 'https://example.invalid/' });
    const article = new Readability(dom.window.document).parse();
    const out = {
      fixture: file,
      ok: article !== null,
      title: article?.title ?? '',
      byline: article?.byline ?? '',
      siteName: article?.siteName ?? '',
      lang: article?.lang ?? '',
      length: article?.length ?? 0,
      excerpt: article?.excerpt ?? '',
      textContent: article?.textContent ?? '',
    };
    const target = join(outDir, basename(file, '.html') + '.json');
    writeFileSync(target, JSON.stringify(out, null, 2) + '\n', 'utf8');
    console.log(`ok   ${file} -> ${target} (${out.textContent.length} chars)`);
  } catch (err) {
    failures += 1;
    console.error(`fail ${file}: ${err.message}`);
  }
}

process.exit(failures === 0 ? 0 : 1);
